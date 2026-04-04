defmodule Grephql.Validator.Rules.Fields do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Schema
  alias Grephql.Schema.TypeRef
  alias Grephql.Validator.Context
  alias Grephql.Validator.Traversal

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    Traversal.traverse_operations(definitions, ctx.schema, ctx, &validate_field/3)
  end

  defp validate_field(field, type_name, ctx) do
    if introspection_field?(field.name) do
      ctx
    else
      check_field(ctx, field, type_name)
    end
  end

  defp check_field(ctx, field, type_name) when is_binary(type_name) do
    case Schema.get_type(ctx.schema, type_name) do
      {:ok, schema_type} ->
        case Map.fetch(schema_type.fields, field.name) do
          {:ok, schema_field} ->
            check_sub_selections(ctx, field, schema_field.type)

          :error ->
            Context.add_error(
              ctx,
              "field \"#{field.name}\" does not exist on type \"#{type_name}\"",
              line: loc_line(field)
            )
        end

      :error ->
        ctx
    end
  end

  defp check_field(ctx, _, _), do: ctx

  defp check_sub_selections(ctx, field, type_ref) do
    named_type = unwrap_type(type_ref)
    kind = resolve_type_kind(ctx.schema, named_type)
    has_sels = has_selections?(field.selection_set)

    check_kind(ctx, field, kind, has_sels)
  end

  defp check_kind(ctx, field, :scalar, true) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is a scalar and cannot have sub-selections",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, _, :scalar, false), do: ctx

  defp check_kind(ctx, field, :enum, true) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an enum and cannot have sub-selections",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, _, :enum, false), do: ctx

  defp check_kind(ctx, field, composite, false)
       when composite in [:object, :interface, :union] do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an object type and requires a sub-selection",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, _, composite, true)
       when composite in [:object, :interface, :union] do
    ctx
  end

  defp check_kind(ctx, _, _, _), do: ctx

  defp unwrap_type(%TypeRef{kind: kind, of_type: of_type})
       when kind in [:non_null, :list] and not is_nil(of_type) do
    unwrap_type(of_type)
  end

  defp unwrap_type(%TypeRef{} = ref), do: ref
  defp unwrap_type(nil), do: nil

  defp resolve_type_kind(%Schema{} = schema, %TypeRef{name: name}) when is_binary(name) do
    case Schema.get_type(schema, name) do
      {:ok, type} -> type.kind
      :error -> nil
    end
  end

  defp resolve_type_kind(_, _), do: nil

  defp has_selections?(%Grephql.Language.SelectionSet{selections: [_ | _]}), do: true
  defp has_selections?(_), do: false

  defp introspection_field?("__typename"), do: true
  defp introspection_field?("__type"), do: true
  defp introspection_field?("__schema"), do: true
  defp introspection_field?(_), do: false

  defp loc_line(%{loc: %{line: line}}) when is_integer(line), do: line
  defp loc_line(_), do: nil
end
