defmodule Grephql.Validator.Rules.InputObjects do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.ListValue
  alias Grephql.Language.ObjectField
  alias Grephql.Language.ObjectValue
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

  defp validate_value(ctx, %ObjectValue{} = obj, type_ref, schema) do
    named = Helpers.unwrap_type(type_ref)

    case named && Schema.get_type(schema, named.name) do
      {:ok, %{kind: :input_object} = type} ->
        ctx
        |> check_field_existence(obj, type)
        |> check_required_fields(obj, type)
        |> check_field_uniqueness(obj)
        |> validate_nested_fields(obj, type, schema)

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

  defp check_field_existence(ctx, obj, type) do
    Enum.reduce(obj.fields, ctx, fn %ObjectField{} = field, acc ->
      if Map.has_key?(type.input_fields, field.name) do
        acc
      else
        Context.add_error(
          acc,
          "field \"#{field.name}\" is not defined on input type \"#{type.name}\"",
          field
        )
      end
    end)
  end

  defp check_required_fields(ctx, obj, type) do
    provided = MapSet.new(obj.fields, & &1.name)

    Enum.reduce(type.input_fields, ctx, fn {name, input_value}, acc ->
      if Helpers.required?(input_value) and not MapSet.member?(provided, name) do
        Context.add_error(
          acc,
          "required field \"#{name}\" is missing on input type \"#{type.name}\"",
          obj
        )
      else
        acc
      end
    end)
  end

  defp check_field_uniqueness(ctx, obj) do
    obj.fields
    |> Enum.group_by(& &1.name)
    |> Enum.reduce(ctx, fn
      {_name, [_single]}, acc ->
        acc

      {name, [_first | _rest]}, acc ->
        Context.add_error(acc, "duplicate field \"#{name}\" in input object")
    end)
  end

  defp validate_nested_fields(ctx, obj, type, schema) do
    Enum.reduce(obj.fields, ctx, fn %ObjectField{} = field, acc ->
      case Map.fetch(type.input_fields, field.name) do
        {:ok, input_value} ->
          validate_value(acc, field.value, input_value.type, schema)

        :error ->
          acc
      end
    end)
  end
end
