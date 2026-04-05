defmodule Grephql.Validator.Rules.Directives do
  @moduledoc false

  alias Grephql.Language.Directive
  alias Grephql.Language.Document
  alias Grephql.Language.Field
  alias Grephql.Language.Fragment
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    ctx =
      definitions
      |> Enum.filter(&match?(%OperationDefinition{}, &1))
      |> Enum.reduce(ctx, &validate_operation/2)

    definitions
    |> Enum.filter(&match?(%Fragment{}, &1))
    |> Enum.reduce(ctx, &validate_fragment_directives/2)
  end

  defp validate_operation(op, ctx) do
    ctx
    |> validate_directives(op.directives, op.operation, ctx.schema)
    |> validate_variable_definition_directives(op.variable_definitions, ctx.schema)
    |> validate_selection_set_directives(op.selection_set, ctx.schema)
  end

  defp validate_fragment_directives(frag, ctx) do
    ctx
    |> validate_directives(frag.directives, :fragment_definition, ctx.schema)
    |> validate_selection_set_directives(frag.selection_set, ctx.schema)
  end

  defp validate_variable_definition_directives(ctx, var_defs, schema) do
    Enum.reduce(var_defs, ctx, fn var_def, acc ->
      validate_directives(acc, var_def.directives, :variable_definition, schema)
    end)
  end

  defp validate_selection_set_directives(ctx, nil, _schema), do: ctx
  defp validate_selection_set_directives(ctx, %SelectionSet{selections: []}, _schema), do: ctx

  defp validate_selection_set_directives(ctx, %SelectionSet{selections: sels}, schema) do
    Enum.reduce(sels, ctx, fn sel, acc ->
      validate_selection_directives(acc, sel, schema)
    end)
  end

  defp validate_selection_directives(ctx, %Field{} = field, schema) do
    ctx
    |> validate_directives(field.directives, :field, schema)
    |> validate_selection_set_directives(field.selection_set, schema)
  end

  defp validate_selection_directives(ctx, %InlineFragment{} = frag, schema) do
    ctx
    |> validate_directives(frag.directives, :inline_fragment, schema)
    |> validate_selection_set_directives(frag.selection_set, schema)
  end

  defp validate_selection_directives(ctx, _selection, _schema), do: ctx

  defp validate_directives(ctx, directives, location, schema) do
    ctx =
      Enum.reduce(directives, ctx, fn %Directive{} = dir, acc ->
        validate_single_directive(acc, dir, location, schema)
      end)

    check_uniqueness(ctx, directives)
  end

  defp validate_single_directive(ctx, dir, location, schema) do
    case Schema.get_directive(schema, dir.name) do
      {:ok, schema_directive} ->
        ctx
        |> check_location(dir, location, schema_directive)
        |> check_arg_existence(dir, schema_directive)
        |> check_required_args(dir, schema_directive)

      :error ->
        Context.add_error(ctx, "unknown directive \"@#{dir.name}\"", line: Helpers.loc_line(dir))
    end
  end

  defp check_location(ctx, dir, location, schema_directive) do
    if location in schema_directive.locations do
      ctx
    else
      Context.add_error(
        ctx,
        "directive \"@#{dir.name}\" is not allowed on #{location_label(location)}",
        line: Helpers.loc_line(dir)
      )
    end
  end

  defp check_uniqueness(ctx, directives) do
    directives
    |> Enum.group_by(& &1.name)
    |> Enum.reduce(ctx, fn
      {_name, [_single]}, acc ->
        acc

      {name, [_first | _rest]}, acc ->
        Context.add_error(acc, "directive \"@#{name}\" is used more than once")
    end)
  end

  defp check_arg_existence(ctx, dir, schema_directive) do
    Enum.reduce(dir.arguments, ctx, fn arg, acc ->
      if Map.has_key?(schema_directive.args, arg.name) do
        acc
      else
        Context.add_error(
          acc,
          "argument \"#{arg.name}\" is not defined on directive \"@#{dir.name}\"",
          line: Helpers.loc_line(arg)
        )
      end
    end)
  end

  defp check_required_args(ctx, dir, schema_directive) do
    provided = MapSet.new(dir.arguments, & &1.name)

    Enum.reduce(schema_directive.args, ctx, fn {name, input_value}, acc ->
      if Helpers.required?(input_value) and not MapSet.member?(provided, name) do
        Context.add_error(
          acc,
          "required argument \"#{name}\" is missing on directive \"@#{dir.name}\"",
          line: Helpers.loc_line(dir)
        )
      else
        acc
      end
    end)
  end

  defp location_label(:query), do: "query operations"
  defp location_label(:mutation), do: "mutation operations"
  defp location_label(:subscription), do: "subscription operations"
  defp location_label(:field), do: "fields"
  defp location_label(:inline_fragment), do: "inline fragments"
  defp location_label(:fragment_definition), do: "fragment definitions"
  defp location_label(:variable_definition), do: "variable definitions"
end
