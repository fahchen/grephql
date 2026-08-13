defmodule TypedGql.Generation.Schema do
  @moduledoc """
  A node in the generated-schema tree, built by the resolve step before
  lowering to EctoTypedSchema AST.

  Two node shapes share this struct:

    * object node — `kind: :object`, carries `fields` and `children`
      (child nodes for embedded objects). Lowers to one
      `typed_embedded_schema` module.
    * union node — `kind: :union`, carries `union_module`,
      `typename_to_module`, and `children` (one object node per concrete
      type). Lowers to the concrete-type modules; the parameterized
      `TypedGql.Types.Union` type module is created eagerly during resolve
      because Ecto validates parameterized type modules exist at schema
      compile time.

  The full tree for an operation is built before any lowering happens, so
  lifecycle plugins see the complete structure.
  """
  use TypedStructor

  alias TypedGql.Generation.Field

  @type kind() :: :object | :union

  typed_structor do
    field :kind, kind(), enforce: true
    field :module, module(), enforce: true
    field :parent_type, String.t()
    field :fields, [Field.t()], default: []
    field :children, [t()], default: []
    field :union_module, module()
    field :typename_to_module, %{String.t() => module()}, default: %{}
  end

  @doc """
  Walks the whole tree applying `fun` to every `TypedGql.Generation.Field`.

  Lets directive plugins transform fields without recursion boilerplate.
  Recurses into both embedded-object children and union variants.
  """
  @spec map_fields(t(), (Field.t() -> Field.t())) :: t()
  def map_fields(%__MODULE__{} = node, fun) when is_function(fun, 1) do
    %{
      node
      | fields: Enum.map(node.fields, fun),
        children: Enum.map(node.children, &map_fields(&1, fun))
    }
  end
end
