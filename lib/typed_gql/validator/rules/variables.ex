defmodule TypedGql.Validator.Rules.Variables do
  @moduledoc false

  alias TypedGql.Language.Document
  alias TypedGql.Language.Field
  alias TypedGql.Language.FragmentSpread
  alias TypedGql.Language.InlineFragment
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.Language.Variable
  alias TypedGql.Language.VariableDefinition
  alias TypedGql.Schema
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    definitions
    |> Enum.filter(&match?(%OperationDefinition{}, &1))
    |> Enum.reduce(ctx, &validate_operation/2)
  end

  defp validate_operation(op, ctx) do
    defined = collect_defined(op.variable_definitions)
    used = collect_used(op)

    ctx
    |> check_unique_definitions(op.variable_definitions)
    |> check_unused_variables(defined, used)
    |> check_undefined_variables(defined, used)
    |> check_null_defaults(op.variable_definitions)
    |> check_variable_types(op, defined, ctx.schema)
  end

  # Spec 5.8.2: a default has to be usable as the variable's type, and null
  # never is for a non-null one — the declaration promises a value it cannot
  # supply, and generation would go on to treat the variable as optional.
  defp check_null_defaults(ctx, var_defs) do
    Enum.reduce(var_defs, ctx, fn var_def, acc ->
      case {var_def.type, var_def.default_value} do
        {%TypedGql.Language.NonNullType{}, %TypedGql.Language.NullValue{}} ->
          Context.add_error(
            acc,
            "variable \"$#{var_def.variable.name}\" of non-null type " <>
              "\"#{type_ref_to_string(var_def.type)}\" cannot default to null",
            var_def
          )

        _usable_or_absent ->
          acc
      end
    end)
  end

  defp check_unique_definitions(ctx, var_defs) do
    var_defs
    |> Enum.group_by(& &1.variable.name)
    |> Enum.reduce(ctx, fn
      {_name, [_single]}, acc ->
        acc

      {name, [_first | _rest]}, acc ->
        Context.add_error(acc, "duplicate variable \"$#{name}\"")
    end)
  end

  defp check_unused_variables(ctx, defined, used) do
    used_names = MapSet.new(used, & &1.name)

    Enum.reduce(defined, ctx, fn {name, var_def}, acc ->
      if MapSet.member?(used_names, name) do
        acc
      else
        Context.add_error(
          acc,
          "variable \"$#{name}\" is defined but not used",
          var_def
        )
      end
    end)
  end

  defp check_undefined_variables(ctx, defined, used) do
    Enum.reduce(used, ctx, fn var, acc ->
      if Map.has_key?(defined, var.name) do
        acc
      else
        Context.add_error(
          acc,
          "variable \"$#{var.name}\" is used but not defined",
          var
        )
      end
    end)
  end

  defp check_variable_types(ctx, op, defined, schema) do
    root_type_name = Helpers.root_type_name(schema, op.operation)

    ctx
    |> check_directive_arg_var_types(op.directives, defined, schema)
    |> check_variable_types_in_selections(op.selection_set, root_type_name, defined, schema)
  end

  defp check_variable_types_in_selections(ctx, nil, _type_name, _defined, _schema), do: ctx

  defp check_variable_types_in_selections(
         ctx,
         %SelectionSet{selections: sels},
         type_name,
         defined,
         schema
       ) do
    Enum.reduce(sels, ctx, fn sel, acc ->
      check_selection_var_types(acc, sel, type_name, defined, schema)
    end)
  end

  defp check_selection_var_types(ctx, %Field{} = field, type_name, defined, schema)
       when is_binary(type_name) do
    ctx =
      ctx
      |> check_field_arg_var_types(field, type_name, defined, schema)
      |> check_directive_arg_var_types(field.directives, defined, schema)

    child_type_name = Helpers.resolve_field_type(schema, type_name, field.name)
    check_variable_types_in_selections(ctx, field.selection_set, child_type_name, defined, schema)
  end

  defp check_selection_var_types(ctx, %Field{} = field, nil, defined, schema) do
    ctx
    |> check_directive_arg_var_types(field.directives, defined, schema)
    |> check_variable_types_in_selections(field.selection_set, nil, defined, schema)
  end

  # A condition-less inline fragment selects on the enclosing type, so the
  # parent type carries through — dropping it to nil would skip argument
  # checking for everything inside the fragment.
  defp check_selection_var_types(ctx, %InlineFragment{} = frag, type_name, defined, schema) do
    frag_type = if frag.type_condition, do: frag.type_condition.name, else: type_name

    ctx
    |> check_directive_arg_var_types(frag.directives, defined, schema)
    |> check_variable_types_in_selections(frag.selection_set, frag_type, defined, schema)
  end

  defp check_selection_var_types(ctx, %FragmentSpread{} = spread, _type_name, defined, schema) do
    check_directive_arg_var_types(ctx, spread.directives, defined, schema)
  end

  defp check_field_arg_var_types(ctx, field, type_name, defined, schema) do
    case Schema.get_field(schema, type_name, field.name) do
      {:ok, schema_field} ->
        Enum.reduce(field.arguments, ctx, fn arg, acc ->
          check_arg_var_type(acc, arg, schema_field.args, defined)
        end)

      :error ->
        ctx
    end
  end

  defp check_directive_arg_var_types(ctx, directives, defined, schema) do
    Enum.reduce(directives, ctx, fn directive, acc ->
      case Schema.get_directive(schema, directive.name) do
        {:ok, schema_directive} ->
          check_directive_args(acc, directive.arguments, schema_directive.args, defined)

        :error ->
          acc
      end
    end)
  end

  defp check_directive_args(ctx, arguments, schema_args, defined) do
    Enum.reduce(arguments, ctx, fn arg, acc ->
      check_arg_var_type(acc, arg, schema_args, defined)
    end)
  end

  defp check_arg_var_type(ctx, arg, schema_args, defined) do
    case {arg.value, Map.fetch(schema_args, arg.name)} do
      {%Variable{name: var_name}, {:ok, input_value}} ->
        check_var_type_match(ctx, arg, var_name, input_value, defined)

      _other ->
        ctx
    end
  end

  defp check_var_type_match(ctx, _arg, var_name, _input_value, defined)
       when not is_map_key(defined, var_name) do
    # Undefined variable — already reported by check_undefined_variables
    ctx
  end

  defp check_var_type_match(ctx, arg, var_name, input_value, defined) do
    var_def = Map.fetch!(defined, var_name)

    if usage_allowed?(var_def, input_value) do
      ctx
    else
      var_type_str = type_ref_to_string(var_def.type)
      arg_type_str = schema_type_ref_to_string(input_value.type)

      Context.add_error(
        ctx,
        "variable \"$#{var_name}\" of type \"#{var_type_str}\" is not compatible with argument \"#{arg.name}\" of type \"#{arg_type_str}\"",
        arg
      )
    end
  end

  # Spec 5.8.5: a nullable variable may still be used where a non-null value is
  # expected, as long as one side carries a default the server falls back to —
  # so the location can never actually receive null.
  defp usage_allowed?(%VariableDefinition{type: %TypedGql.Language.NonNullType{}} = var_def, %{
         type: location_type
       }) do
    compare_types(var_def.type, location_type)
  end

  defp usage_allowed?(
         var_def,
         %{type: %TypedGql.Schema.TypeRef{kind: :non_null, of_type: inner}} = input_value
       ) do
    default_supplied?(var_def, input_value) and compare_types(var_def.type, inner)
  end

  defp usage_allowed?(var_def, %{type: location_type}) do
    compare_types(var_def.type, location_type)
  end

  defp default_supplied?(%VariableDefinition{default_value: variable_default}, input_value) do
    TypedGql.Language.usable_default?(variable_default) or not is_nil(input_value.default_value)
  end

  defp compare_types(%TypedGql.Language.NonNullType{type: inner}, %TypedGql.Schema.TypeRef{
         kind: :non_null,
         of_type: of_type
       }) do
    compare_types(inner, of_type)
  end

  defp compare_types(%TypedGql.Language.ListType{type: inner}, %TypedGql.Schema.TypeRef{
         kind: :list,
         of_type: of_type
       }) do
    compare_types(inner, of_type)
  end

  # NonNull variable can satisfy nullable argument
  defp compare_types(%TypedGql.Language.NonNullType{type: inner}, schema_type) do
    compare_types(inner, schema_type)
  end

  defp compare_types(%TypedGql.Language.NamedType{name: name}, %TypedGql.Schema.TypeRef{
         name: name
       }),
       do: true

  defp compare_types(_query_type, _schema_type), do: false

  defp collect_defined(var_defs) do
    Map.new(var_defs, fn %VariableDefinition{variable: var} = vd -> {var.name, vd} end)
  end

  defp collect_used(%OperationDefinition{} = op) do
    op.selection_set
    |> collect_used_vars([])
    |> collect_directive_vars(op.directives)
  end

  defp collect_used_vars(nil, acc), do: acc

  defp collect_used_vars(%SelectionSet{selections: sels}, acc) do
    Enum.reduce(sels, acc, &collect_selection_vars/2)
  end

  defp collect_selection_vars(%Field{} = field, acc) do
    acc =
      field.arguments
      |> Enum.reduce(acc, &collect_arg_vars/2)
      |> collect_directive_vars(field.directives)

    collect_used_vars(field.selection_set, acc)
  end

  defp collect_selection_vars(%InlineFragment{} = frag, acc) do
    acc = collect_directive_vars(acc, frag.directives)
    collect_used_vars(frag.selection_set, acc)
  end

  defp collect_selection_vars(%FragmentSpread{} = spread, acc) do
    collect_directive_vars(acc, spread.directives)
  end

  defp collect_arg_vars(arg, acc) do
    case arg.value do
      %Variable{} = var -> [var | acc]
      _other -> acc
    end
  end

  defp collect_directive_vars(acc, directives) do
    Enum.reduce(directives, acc, fn directive, directive_acc ->
      Enum.reduce(directive.arguments, directive_acc, &collect_arg_vars/2)
    end)
  end

  defp type_ref_to_string(%TypedGql.Language.NonNullType{type: inner}),
    do: "#{type_ref_to_string(inner)}!"

  defp type_ref_to_string(%TypedGql.Language.ListType{type: inner}),
    do: "[#{type_ref_to_string(inner)}]"

  defp type_ref_to_string(%TypedGql.Language.NamedType{name: name}), do: name

  defp schema_type_ref_to_string(%TypedGql.Schema.TypeRef{kind: :non_null, of_type: inner}),
    do: "#{schema_type_ref_to_string(inner)}!"

  defp schema_type_ref_to_string(%TypedGql.Schema.TypeRef{kind: :list, of_type: inner}),
    do: "[#{schema_type_ref_to_string(inner)}]"

  defp schema_type_ref_to_string(%TypedGql.Schema.TypeRef{name: name}), do: name
end
