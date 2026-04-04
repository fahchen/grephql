defmodule Grephql.Validator.Helpers do
  @moduledoc false

  alias Grephql.Schema
  alias Grephql.Schema.TypeRef

  @spec unwrap_type(TypeRef.t() | nil) :: TypeRef.t() | nil
  def unwrap_type(%TypeRef{kind: kind, of_type: of_type})
      when kind in [:non_null, :list] and not is_nil(of_type) do
    unwrap_type(of_type)
  end

  def unwrap_type(%TypeRef{} = ref), do: ref
  def unwrap_type(nil), do: nil

  @spec loc_line(map()) :: non_neg_integer() | nil
  def loc_line(%{loc: %{line: line}}) when is_integer(line), do: line
  def loc_line(_), do: nil

  @spec root_type_name(Schema.t(), :query | :mutation | :subscription) :: String.t() | nil
  def root_type_name(%Schema{} = schema, :query), do: schema.query_type
  def root_type_name(%Schema{} = schema, :mutation), do: schema.mutation_type
  def root_type_name(%Schema{} = schema, :subscription), do: schema.subscription_type

  @spec resolve_field_type(Schema.t(), String.t() | nil, String.t()) :: String.t() | nil
  def resolve_field_type(_, nil, _), do: nil

  def resolve_field_type(schema, type_name, field_name) when is_binary(type_name) do
    case Schema.get_field(schema, type_name, field_name) do
      {:ok, schema_field} ->
        named = unwrap_type(schema_field.type)
        if named, do: named.name, else: nil

      :error ->
        nil
    end
  end
end
