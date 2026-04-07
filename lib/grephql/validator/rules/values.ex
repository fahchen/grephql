defmodule Grephql.Validator.Rules.Values do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.EnumValue
  alias Grephql.Language.ListValue
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers
  alias Grephql.Validator.Traversal

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    Traversal.traverse_operations(definitions, ctx.schema, ctx, &validate_field_args/3)
  end

  defp validate_field_args(_field, nil, ctx), do: ctx

  defp validate_field_args(field, type_name, ctx) when is_binary(type_name) do
    Helpers.reduce_field_arg_types(field, type_name, ctx.schema, ctx, fn acc, value, type_ref ->
      validate_value(acc, value, type_ref, ctx.schema)
    end)
  end

  defp validate_value(ctx, %EnumValue{} = enum_val, type_ref, schema) do
    named = Helpers.unwrap_type(type_ref)

    case named && Schema.get_type(schema, named.name) do
      {:ok, %{kind: :enum} = type} ->
        check_enum_value(ctx, enum_val, type)

      _other ->
        ctx
    end
  end

  defp validate_value(ctx, %ListValue{values: values}, type_ref, schema) do
    inner_type = Helpers.unwrap_list_type(type_ref)

    if inner_type do
      Enum.reduce(values, ctx, fn val, acc ->
        validate_value(acc, val, inner_type, schema)
      end)
    else
      ctx
    end
  end

  defp validate_value(ctx, _value, _type_ref, _schema), do: ctx

  defp check_enum_value(ctx, enum_val, type) do
    valid_values = Enum.map(type.enum_values, & &1.name)

    if enum_val.value in valid_values do
      ctx
    else
      Context.add_error(
        ctx,
        "enum value \"#{enum_val.value}\" is not valid for type \"#{type.name}\"",
        enum_val
      )
    end
  end
end
