defmodule Grephql.Validator.Rules.Variables do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.Field
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Language.Variable
  alias Grephql.Language.VariableDefinition
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    definitions
    |> Enum.filter(&match?(%OperationDefinition{}, &1))
    |> Enum.reduce(ctx, &validate_operation/2)
  end

  defp validate_operation(op, ctx) do
    defined = collect_defined(op.variable_definitions)
    used = collect_used(op.selection_set)

    ctx
    |> check_unique_definitions(op.variable_definitions)
    |> check_unused_variables(defined, used)
    |> check_undefined_variables(defined, used)
    |> check_variable_types(op, defined, ctx.schema)
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
    check_variable_types_in_selections(ctx, op.selection_set, root_type_name, defined, schema)
  end

  defp check_variable_types_in_selections(ctx, nil, _type_name, _defined, _schema), do: ctx

  defp check_variable_types_in_selections(
         ctx,
         %SelectionSet{selections: []},
         _type_name,
         _defined,
         _schema
       ),
       do: ctx

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
    ctx = check_field_arg_var_types(ctx, field, type_name, defined, schema)

    child_type_name = Helpers.resolve_field_type(schema, type_name, field.name)
    check_variable_types_in_selections(ctx, field.selection_set, child_type_name, defined, schema)
  end

  defp check_selection_var_types(ctx, %Field{} = field, nil, defined, schema) do
    check_variable_types_in_selections(ctx, field.selection_set, nil, defined, schema)
  end

  defp check_selection_var_types(ctx, %InlineFragment{} = frag, _type_name, defined, schema) do
    frag_type = if frag.type_condition, do: frag.type_condition.name, else: nil
    check_variable_types_in_selections(ctx, frag.selection_set, frag_type, defined, schema)
  end

  defp check_selection_var_types(ctx, _selection, _type_name, _defined, _schema), do: ctx

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

    if compare_types(var_def.type, input_value.type) do
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

  defp compare_types(%Grephql.Language.NonNullType{type: inner}, %Grephql.Schema.TypeRef{
         kind: :non_null,
         of_type: of_type
       }) do
    compare_types(inner, of_type)
  end

  defp compare_types(%Grephql.Language.ListType{type: inner}, %Grephql.Schema.TypeRef{
         kind: :list,
         of_type: of_type
       }) do
    compare_types(inner, of_type)
  end

  # NonNull variable can satisfy nullable argument
  defp compare_types(%Grephql.Language.NonNullType{type: inner}, schema_type) do
    compare_types(inner, schema_type)
  end

  defp compare_types(%Grephql.Language.NamedType{name: name}, %Grephql.Schema.TypeRef{name: name}),
       do: true

  defp compare_types(_query_type, _schema_type), do: false

  defp collect_defined(var_defs) do
    Map.new(var_defs, fn %VariableDefinition{variable: var} = vd -> {var.name, vd} end)
  end

  defp collect_used(selection_set) do
    collect_used_vars(selection_set, [])
  end

  defp collect_used_vars(nil, acc), do: acc

  defp collect_used_vars(%SelectionSet{selections: sels}, acc) do
    Enum.reduce(sels, acc, &collect_selection_vars/2)
  end

  defp collect_selection_vars(%Field{} = field, acc) do
    acc = Enum.reduce(field.arguments, acc, &collect_arg_vars/2)
    collect_used_vars(field.selection_set, acc)
  end

  defp collect_selection_vars(%InlineFragment{} = frag, acc) do
    collect_used_vars(frag.selection_set, acc)
  end

  defp collect_selection_vars(_selection, acc), do: acc

  defp collect_arg_vars(arg, acc) do
    case arg.value do
      %Variable{} = var -> [var | acc]
      _other -> acc
    end
  end

  defp type_ref_to_string(%Grephql.Language.NonNullType{type: inner}),
    do: "#{type_ref_to_string(inner)}!"

  defp type_ref_to_string(%Grephql.Language.ListType{type: inner}),
    do: "[#{type_ref_to_string(inner)}]"

  defp type_ref_to_string(%Grephql.Language.NamedType{name: name}), do: name

  defp schema_type_ref_to_string(%Grephql.Schema.TypeRef{kind: :non_null, of_type: inner}),
    do: "#{schema_type_ref_to_string(inner)}!"

  defp schema_type_ref_to_string(%Grephql.Schema.TypeRef{kind: :list, of_type: inner}),
    do: "[#{schema_type_ref_to_string(inner)}]"

  defp schema_type_ref_to_string(%Grephql.Schema.TypeRef{name: name}), do: name
end
