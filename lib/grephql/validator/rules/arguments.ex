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
          arg
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
          field
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
        Context.add_error(acc, "duplicate argument \"#{name}\" on field \"#{field.name}\"", field)
    end)
  end

  defp check_arg_types(ctx, field, schema_field) do
    Enum.reduce(field.arguments, ctx, fn arg, acc ->
      check_arg_value_type(acc, arg, schema_field, field.name)
    end)
  end

  defp check_arg_value_type(ctx, arg, schema_field, field_name) do
    with {:ok, input_value} <- Map.fetch(schema_field.args, arg.name),
         true <- Helpers.value_type_mismatch?(arg, input_value.type) do
      Context.add_error(
        ctx,
        "type mismatch for argument \"#{arg.name}\" on field \"#{field_name}\"",
        arg
      )
    else
      _no_mismatch -> ctx
    end
  end
end
