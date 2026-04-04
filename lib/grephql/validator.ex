defmodule Grephql.Validator do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Error
  alias Grephql.Validator.Rules

  @rules [
    Rules.Operations,
    Rules.Fields
  ]

  @spec validate(Document.t(), Schema.t()) :: :ok | {:error, [Error.t()]}
  def validate(%Document{} = document, %Schema{} = schema) do
    ctx = %Context{schema: schema}

    ctx =
      Enum.reduce(@rules, ctx, fn rule, acc ->
        rule.validate(document, acc)
      end)

    errors = Context.errors_by_severity(ctx, :error)
    warnings = Context.errors_by_severity(ctx, :warning)

    for warning <- warnings do
      IO.warn(warning.message)
    end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
