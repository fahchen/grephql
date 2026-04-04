defmodule Grephql.Schema do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema.Directive
  alias Grephql.Schema.Type

  typed_structor do
    field :query_type, String.t()
    field :mutation_type, String.t()
    field :subscription_type, String.t()
    field :types, %{String.t() => Type.t()}, default: %{}
    field :directives, [Directive.t()], default: []
  end

  @spec get_type(t(), String.t()) :: {:ok, Type.t()} | :error
  def get_type(%__MODULE__{types: types}, name) do
    Map.fetch(types, name)
  end

  @spec get_field(t(), String.t(), String.t()) ::
          {:ok, Grephql.Schema.Field.t()} | :error
  def get_field(%__MODULE__{} = schema, type_name, field_name) do
    with {:ok, type} <- get_type(schema, type_name) do
      Type.get_field(type, field_name)
    end
  end
end
