defmodule Grephql.Validator.Rules.Deprecation do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.EnumValue
  alias Grephql.Language.ListValue
  alias Grephql.Language.ObjectField
  alias Grephql.Language.ObjectValue
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers
  alias Grephql.Validator.Traversal

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    Traversal.traverse_operations(definitions, ctx.schema, ctx, &check_field/3)
  end

  defp check_field(_field, nil, ctx), do: ctx

  defp check_field(field, type_name, ctx) when is_binary(type_name) do
    case Schema.get_field(ctx.schema, type_name, field.name) do
      {:ok, schema_field} ->
        ctx
        |> check_deprecated_field(field, type_name, schema_field)
        |> check_args(field, schema_field)

      :error ->
        ctx
    end
  end

  defp check_deprecated_field(ctx, field, type_name, %{is_deprecated: true} = schema_field) do
    reason = deprecation_reason(schema_field.deprecation_reason)

    Context.add_error(
      ctx,
      "field \"#{field.name}\" on \"#{type_name}\" is deprecated#{reason}",
      severity: :warning,
      line: Helpers.loc_line(field)
    )
  end

  defp check_deprecated_field(ctx, _field, _type_name, _schema_field), do: ctx

  defp check_args(ctx, field, schema_field) do
    Enum.reduce(field.arguments, ctx, fn arg, acc ->
      case Map.fetch(schema_field.args, arg.name) do
        {:ok, input_value} ->
          acc
          |> check_deprecated_arg(arg, input_value)
          |> check_deprecated_value(arg.value, input_value.type)

        :error ->
          acc
      end
    end)
  end

  defp check_deprecated_arg(ctx, arg, %{is_deprecated: true} = input_value) do
    reason = deprecation_reason(input_value.deprecation_reason)

    Context.add_error(
      ctx,
      "argument \"#{arg.name}\" is deprecated#{reason}",
      severity: :warning,
      line: Helpers.loc_line(arg)
    )
  end

  defp check_deprecated_arg(ctx, _arg, _input_value), do: ctx

  # Walk values to find deprecated enum values and deprecated input object fields

  defp check_deprecated_value(ctx, %EnumValue{} = enum_val, type_ref) do
    named = Helpers.unwrap_type(type_ref)

    case named && Schema.get_type(ctx.schema, named.name) do
      {:ok, %{kind: :enum} = type} ->
        check_enum_value_deprecation(ctx, enum_val, type)

      _other ->
        ctx
    end
  end

  defp check_deprecated_value(ctx, %ObjectValue{} = obj, type_ref) do
    named = Helpers.unwrap_type(type_ref)

    case named && Schema.get_type(ctx.schema, named.name) do
      {:ok, %{kind: :input_object} = type} ->
        check_input_object_fields(ctx, obj, type)

      _other ->
        ctx
    end
  end

  defp check_deprecated_value(ctx, %ListValue{values: values}, type_ref) do
    inner_type = Helpers.unwrap_list_type(type_ref)

    if inner_type do
      Enum.reduce(values, ctx, fn val, acc ->
        check_deprecated_value(acc, val, inner_type)
      end)
    else
      ctx
    end
  end

  defp check_deprecated_value(ctx, _value, _type_ref), do: ctx

  defp check_input_object_fields(ctx, obj, type) do
    Enum.reduce(obj.fields, ctx, fn %ObjectField{} = field, acc ->
      case Map.fetch(type.input_fields, field.name) do
        {:ok, %{is_deprecated: true} = input_value} ->
          reason = deprecation_reason(input_value.deprecation_reason)

          message = ~s(input field "#{field.name}" on "#{type.name}" is deprecated#{reason})

          acc
          |> Context.add_error(message,
            severity: :warning,
            line: Helpers.loc_line(field)
          )
          |> check_deprecated_value(field.value, input_value.type)

        {:ok, input_value} ->
          check_deprecated_value(acc, field.value, input_value.type)

        :error ->
          acc
      end
    end)
  end

  defp check_enum_value_deprecation(ctx, enum_val, type) do
    case Enum.find(type.enum_values, &(&1.name == enum_val.value)) do
      %{is_deprecated: true} = ev ->
        reason = deprecation_reason(ev.deprecation_reason)

        Context.add_error(
          ctx,
          "enum value \"#{enum_val.value}\" is deprecated#{reason}",
          severity: :warning,
          line: Helpers.loc_line(enum_val)
        )

      _other ->
        ctx
    end
  end

  defp deprecation_reason(nil), do: ""
  defp deprecation_reason(""), do: ""
  defp deprecation_reason(reason), do: ": #{reason}"
end
