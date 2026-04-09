defmodule TypedStructor.Plugins.Access do
  @moduledoc """
  A `TypedStructor` plugin that implements the `Access` behaviour for structs.

  This allows bracket-based field access on generated schemas:

      schema[:field_name]
      get_in(schema, [:nested, :field])

  Deleting keys via `pop/2` is not supported — structs have a fixed set of
  fields — so `pop/2` raises an error.

  ## Usage

  Register the plugin inside a `typed_structor` or `typed_embedded_schema` block:

      typed_embedded_schema do
        plugin TypedStructor.Plugins.Access

        field :name, :string
      end

  Or register it globally in config:

      config :typed_structor, plugins: [TypedStructor.Plugins.Access]
  """

  use TypedStructor.Plugin

  @impl TypedStructor.Plugin
  defmacro after_definition(_definition, _opts) do
    quote do
      @behaviour Access

      @impl Access
      defdelegate fetch(struct, key), to: Map

      @impl Access
      def get_and_update(struct, key, fun) do
        Map.get_and_update(struct, key, fun)
      end

      @impl Access
      def pop(_struct, _key) do
        raise UndefinedFunctionError,
          module: __MODULE__,
          function: :pop,
          arity: 2,
          reason: "structs do not allow removing keys"
      end
    end
  end
end
