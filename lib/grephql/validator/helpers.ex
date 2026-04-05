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
  def loc_line(_node), do: nil

  @spec root_type_name(Schema.t(), :query | :mutation | :subscription) :: String.t() | nil
  def root_type_name(%Schema{} = schema, :query), do: schema.query_type
  def root_type_name(%Schema{} = schema, :mutation), do: schema.mutation_type
  def root_type_name(%Schema{} = schema, :subscription), do: schema.subscription_type

  @spec resolve_field_type(Schema.t(), String.t() | nil, String.t()) :: String.t() | nil
  def resolve_field_type(_schema, nil, _field_name), do: nil

  def resolve_field_type(schema, type_name, field_name) when is_binary(type_name) do
    case Schema.get_field(schema, type_name, field_name) do
      {:ok, schema_field} ->
        named = unwrap_type(schema_field.type)
        if named, do: named.name, else: nil

      :error ->
        nil
    end
  end

  @doc """
  Iterates over a field's arguments, resolving each against the schema field's args.
  Calls `callback.(acc, arg_value, arg_type_ref)` for each known argument.
  Skips unknown args (already reported by Arguments rule).
  Returns the accumulated context.
  """
  @spec reduce_field_arg_types(
          Grephql.Language.Field.t(),
          String.t(),
          Schema.t(),
          Grephql.Validator.Context.t(),
          (Grephql.Validator.Context.t(), Grephql.Language.value_t(), TypeRef.t() ->
             Grephql.Validator.Context.t())
        ) :: Grephql.Validator.Context.t()
  def reduce_field_arg_types(field, type_name, schema, ctx, callback) do
    case Schema.get_field(schema, type_name, field.name) do
      {:ok, schema_field} ->
        reduce_known_args(field.arguments, schema_field.args, ctx, callback)

      :error ->
        ctx
    end
  end

  defp reduce_known_args(arguments, schema_args, ctx, callback) do
    Enum.reduce(arguments, ctx, fn arg, acc ->
      case Map.fetch(schema_args, arg.name) do
        {:ok, input_value} -> callback.(acc, arg.value, input_value.type)
        :error -> acc
      end
    end)
  end

  @spec variable?(Grephql.Language.value_t()) :: boolean()
  def variable?(%Grephql.Language.Variable{}), do: true
  def variable?(_value), do: false

  @spec compatible_value?(Grephql.Language.value_t(), String.t()) :: boolean()
  def compatible_value?(%Grephql.Language.IntValue{}, name), do: name in ["Int", "Float", "ID"]
  def compatible_value?(%Grephql.Language.FloatValue{}, name), do: name in ["Float"]
  def compatible_value?(%Grephql.Language.StringValue{}, name), do: name in ["String", "ID"]
  def compatible_value?(%Grephql.Language.BooleanValue{}, "Boolean"), do: true
  def compatible_value?(%Grephql.Language.NullValue{}, _name), do: true
  def compatible_value?(%Grephql.Language.EnumValue{}, _name), do: true
  def compatible_value?(%Grephql.Language.ListValue{}, _name), do: true
  def compatible_value?(%Grephql.Language.ObjectValue{}, _name), do: true
  def compatible_value?(_value, _name), do: false

  @spec value_type_mismatch?(Grephql.Language.Argument.t(), TypeRef.t()) :: boolean()
  def value_type_mismatch?(arg, expected_type) do
    if variable?(arg.value) do
      false
    else
      named_type = unwrap_type(expected_type)
      named_type != nil and not compatible_value?(arg.value, named_type.name)
    end
  end

  @spec required?(Schema.InputValue.t()) :: boolean()
  def required?(%{type: %TypeRef{kind: :non_null}, default_value: nil}), do: true
  def required?(_input_value), do: false

  @spec unwrap_list_type(TypeRef.t()) :: TypeRef.t() | nil
  def unwrap_list_type(%TypeRef{kind: :list, of_type: inner}), do: inner
  def unwrap_list_type(%TypeRef{kind: :non_null, of_type: inner}), do: unwrap_list_type(inner)
  def unwrap_list_type(_type_ref), do: nil
end
