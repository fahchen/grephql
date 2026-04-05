defmodule Grephql.Validator.Rules.Arguments do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers
  alias Grephql.Validator.Traversal

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{schema: schema} = ctx) do
    Traversal.traverse_all(definitions, schema, ctx, &validate_field_args/3)
  end

  # nil type_name means upstream type couldn't be resolved — already reported
  defp validate_field_args(_field, nil, ctx), do: ctx

  defp validate_field_args(field, type_name, ctx) when is_binary(type_name) do
    case Schema.get_field(ctx.schema, type_name, field.name) do
      {:ok, schema_field} ->
        ctx
        |> check_arg_existence(field, schema_field)
        |> check_required_args(field, schema_field)
        |> check_arg_uniqueness(field)
        |> check_arg_types(field, schema_field)

      :error ->
        ctx
    end
  end

  defp check_arg_existence(ctx, field, schema_field) do
    Enum.reduce(field.arguments, ctx, fn arg, acc ->
      if Map.has_key?(schema_field.args, arg.name) do
        acc
      else
        Context.add_error(
          acc,
          "argument \"#{arg.name}\" is not defined on field \"#{field.name}\"",
          line: Helpers.loc_line(arg)
        )
      end
    end)
  end

  defp check_required_args(ctx, field, schema_field) do
    provided = MapSet.new(field.arguments, & &1.name)

    Enum.reduce(schema_field.args, ctx, fn {name, input_value}, acc ->
      if Helpers.required?(input_value) and not MapSet.member?(provided, name) do
        Context.add_error(
          acc,
          "required argument \"#{name}\" is missing on field \"#{field.name}\"",
          line: Helpers.loc_line(field)
        )
      else
        acc
      end
    end)
  end

  defp check_arg_uniqueness(ctx, field) do
    field.arguments
    |> Enum.group_by(& &1.name)
    |> Enum.reduce(ctx, fn
      {_name, [_single]}, acc ->
        acc

      {name, [_first | _rest]}, acc ->
        Context.add_error(
          acc,
          "duplicate argument \"#{name}\" on field \"#{field.name}\"",
          line: Helpers.loc_line(field)
        )
    end)
  end

  defp check_arg_types(ctx, field, schema_field) do
    Enum.reduce(field.arguments, ctx, fn arg, acc ->
      case Map.fetch(schema_field.args, arg.name) do
        {:ok, input_value} ->
          check_value_type(acc, arg, input_value.type, field.name)

        # Already reported by check_arg_existence
        :error ->
          acc
      end
    end)
  end

  defp check_value_type(ctx, arg, expected_type, field_name) do
    if variable?(arg.value) do
      ctx
    else
      named_type = Helpers.unwrap_type(expected_type)

      if named_type && !compatible_value?(arg.value, named_type.name) do
        Context.add_error(
          ctx,
          "type mismatch for argument \"#{arg.name}\" on field \"#{field_name}\"",
          line: Helpers.loc_line(arg)
        )
      else
        ctx
      end
    end
  end

  defp variable?(%Grephql.Language.Variable{}), do: true
  defp variable?(_value), do: false

  defp compatible_value?(%Grephql.Language.IntValue{}, name),
    do: name in ["Int", "Float", "ID"]

  defp compatible_value?(%Grephql.Language.FloatValue{}, name),
    do: name in ["Float"]

  defp compatible_value?(%Grephql.Language.StringValue{}, name),
    do: name in ["String", "ID"]

  defp compatible_value?(%Grephql.Language.BooleanValue{}, "Boolean"), do: true
  defp compatible_value?(%Grephql.Language.NullValue{}, _name), do: true
  defp compatible_value?(%Grephql.Language.EnumValue{}, _name), do: true
  defp compatible_value?(%Grephql.Language.ListValue{}, _name), do: true
  defp compatible_value?(%Grephql.Language.ObjectValue{}, _name), do: true
  defp compatible_value?(_value, _name), do: false
end
