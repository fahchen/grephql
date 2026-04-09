defmodule Grephql.Error do
  @moduledoc """
  Represents a GraphQL error from the response.

  Follows the GraphQL spec error format with `message`, `locations`,
  `path`, and `extensions` fields. Use `from_json/1` to parse from
  a raw response error map.
  """

  use Grephql.EmbeddedSchema

  @type location() :: %{line: non_neg_integer(), column: non_neg_integer()}

  typed_embedded_schema do
    plugin TypedStructor.Plugins.Access

    field :message, :string, typed: [null: false]
    field :locations, {:array, :map}, typed: [null: true]
    field :path, {:array, Grephql.Types.PathSegment}, typed: [null: true]
    field :extensions, :map, typed: [null: true]
  end

  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    Ecto.embedded_load(__MODULE__, json, :json)
  end
end
