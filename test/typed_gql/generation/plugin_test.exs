defmodule TypedGql.Generation.PluginTest do
  use ExUnit.Case, async: true

  alias TypedGql.Generation.Context
  alias TypedGql.Generation.Schema

  defmodule IdentityPlugin do
    @moduledoc false
    use TypedGql.Generation.Plugin
  end

  defmodule OverridePlugin do
    @moduledoc false
    use TypedGql.Generation.Plugin

    @impl TypedGql.Generation.Plugin
    def after_normalize(selections, _context), do: Enum.reverse(selections)
  end

  setup do
    %{context: %Context{schema: %TypedGql.Schema{}}}
  end

  describe "use TypedGql.Generation.Plugin identity defaults" do
    test "all four callbacks return their input unchanged", %{context: context} do
      selections = [:a, :b]
      tree = %Schema{kind: :object, module: Foo}
      module_asts = [{Foo, quote(do: :ok), [file: "foo.ex", line: 1]}]

      assert IdentityPlugin.before_normalize(selections, context) == selections
      assert IdentityPlugin.after_normalize(selections, context) == selections
      assert IdentityPlugin.after_resolve(tree, context) == tree
      assert IdentityPlugin.after_lower(module_asts, context) == module_asts
    end

    test "callbacks are overridable", %{context: context} do
      assert OverridePlugin.after_normalize([:a, :b], context) == [:b, :a]
      # Non-overridden callbacks keep identity behavior.
      assert OverridePlugin.before_normalize([:a, :b], context) == [:a, :b]
    end
  end
end
