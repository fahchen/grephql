defmodule Grephql.Schema.Type do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema.EnumValue
  alias Grephql.Schema.Field
  alias Grephql.Schema.InputValue

  @type kind ::
          :scalar
          | :object
          | :interface
          | :union
          | :enum
          | :input_object
          | :list
          | :non_null

  typed_structor do
    field :kind, kind(), enforce: true
    field :name, String.t()
    field :description, String.t()
    field :fields, %{String.t() => Field.t()}, default: %{}
    field :input_fields, %{String.t() => InputValue.t()}, default: %{}
    field :interfaces, [String.t()], default: []
    field :enum_values, [EnumValue.t()], default: []
    field :possible_types, [String.t()], default: []
    field :of_type, Grephql.Schema.TypeRef.t()
  end

  @spec get_field(t(), String.t()) :: {:ok, Field.t()} | :error
  def get_field(%__MODULE__{fields: fields}, name) do
    Map.fetch(fields, name)
  end
end
