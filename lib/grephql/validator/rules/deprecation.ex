defmodule Grephql.Validator.Rules.Deprecation do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.EnumValue
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
        |> check_deprecated_enum_args(field, schema_field)

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

  defp check_deprecated_enum_args(ctx, field, schema_field) do
    Enum.reduce(field.arguments, ctx, fn arg, acc ->
      case Map.fetch(schema_field.args, arg.name) do
        {:ok, input_value} ->
          check_deprecated_enum_value(acc, arg.value, input_value.type)

        :error ->
          acc
      end
    end)
  end

  defp check_deprecated_enum_value(ctx, %EnumValue{} = enum_val, type_ref) do
    named = Helpers.unwrap_type(type_ref)

    case named && Schema.get_type(ctx.schema, named.name) do
      {:ok, %{kind: :enum} = type} ->
        check_enum_value_deprecation(ctx, enum_val, type)

      _other ->
        ctx
    end
  end

  defp check_deprecated_enum_value(ctx, _value, _type_ref), do: ctx

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
