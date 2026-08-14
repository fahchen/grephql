defmodule TypedGql.Generation.Context do
  @moduledoc """
  Read-only context passed to `TypedGql.Generation.Plugin` callbacks.

  Carries the schema and compile-time options the engine has available
  at every pipeline juncture. Per-node information (parent type, target
  module) lives on `TypedGql.Generation.Schema` nodes, not here.

  `:fragments` maps a fragment name to the parsed
  `TypedGql.Language.Fragment` itself. Up to 0.12.2 the value was a map
  wrapping it (`%{source:, fragment:, result_module:}`); a plugin reading
  `context.fragments[name].fragment` has to read `context.fragments[name]`
  now. The wrapper's other keys were never usable from a plugin — generation
  is what produces the result module.
  """
  use TypedStructor

  alias TypedGql.Schema

  typed_structor do
    field :schema, Schema.t(), enforce: true
    field :scalar_types, %{String.t() => module()}, default: %{}
    field :fragments, %{String.t() => TypedGql.Language.Fragment.t()}, default: %{}
  end
end
