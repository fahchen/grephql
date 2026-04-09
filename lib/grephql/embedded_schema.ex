defmodule Grephql.EmbeddedSchema do
  @moduledoc """
  Base module for generated GraphQL embedded schemas.

  Sets up `EctoTypedSchema` with `@primary_key false` so generated
  output/input types don't include an auto-generated `:id` field.

  Overrides `typed_embedded_schema/1` to automatically register
  `TypedStructor.Plugins.Access`, giving all generated schemas
  bracket-based field access (`schema[:field]`, `get_in/2`).

  ## Usage

      use Grephql.EmbeddedSchema
  """

  defmacro __using__(_opts) do
    quote do
      use EctoTypedSchema

      @primary_key false

      import EctoTypedSchema, only: []
      import Grephql.EmbeddedSchema, only: [typed_embedded_schema: 1]
    end
  end

  defmacro typed_embedded_schema(do: block) do
    quote do
      EctoTypedSchema.typed_embedded_schema do
        plugin TypedStructor.Plugins.Access

        unquote(block)
      end
    end
  end
end
