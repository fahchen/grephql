defmodule TypedGql.Test.NodeLocationPlugin do
  @moduledoc false
  use TypedGql.Generation.Plugin

  alias TypedGql.Generation.Schema

  # `Module.create/3` records a line and no column, so the docs chunk a location
  # test reads can only ever prove half the mapping. A plugin is the documented
  # reader of the other half: it sees the `TypedGql.Language` nodes themselves.
  # This one records what it was handed, under the module the tree is rooted at,
  # so a test can assert positions no generated module carries.
  @key {__MODULE__, :locations}

  @impl TypedGql.Generation.Plugin
  def after_resolve(%Schema{} = tree, _context) do
    :persistent_term.put({@key, tree.module}, collect(tree, %{}))
    tree
  end

  @doc """
  Everything recorded so far, by root module then field name.

  Read at compile time by the module whose documents produced it: the compiler's
  memory is gone by the time a test runs.
  """
  @spec captured() :: %{module() => %{atom() => map()}}
  def captured do
    captured =
      Map.new(:persistent_term.get(), fn
        {{@key, module}, locations} -> {module, locations}
        _other -> {nil, nil}
      end)

    Map.delete(captured, nil)
  end

  defp collect(%Schema{} = node, acc) do
    acc =
      Enum.reduce(node.fields, acc, fn field, acc ->
        Map.put(acc, field.name, field.query_field.loc)
      end)

    Enum.reduce(node.children, acc, &collect/2)
  end
end
