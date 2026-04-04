defmodule Grephql.EmbeddedSchema do
  @moduledoc """
  Base module for generated GraphQL embedded schemas.

  Sets up `EctoTypedSchema` with `@primary_key false` so generated
  output/input types don't include an auto-generated `:id` field.

  ## Usage

      use Grephql.EmbeddedSchema
  """

  defmacro __using__(_opts) do
    quote do
      use EctoTypedSchema

      @primary_key false
    end
  end
end
