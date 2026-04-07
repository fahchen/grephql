defmodule Grephql.Validator do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Error
  alias Grephql.Validator.Helpers
  alias Grephql.Validator.Rules

  @rules [
    Rules.Operations,
    Rules.Fields,
    Rules.Arguments,
    Rules.Variables,
    Rules.Directives,
    Rules.Fragments,
    Rules.InputObjects,
    Rules.Values,
    Rules.Deprecation
  ]

  @spec validate(Document.t(), Schema.t(), Macro.Env.t() | nil) :: :ok | {:error, [Error.t()]}
  def validate(%Document{} = document, %Schema{} = schema, caller_env \\ nil) do
    ctx = %Context{schema: schema}

    ctx =
      Enum.reduce(@rules, ctx, fn rule, acc ->
        rule.validate(document, acc)
      end)

    finalize(ctx, caller_env)
  end

  @fragment_rules [
    Rules.Fragments,
    Rules.Fields,
    Rules.Arguments,
    Rules.Directives,
    Rules.Deprecation
  ]

  @spec validate_fragment(Document.t(), Schema.t(), Macro.Env.t() | nil) ::
          :ok | {:error, [Error.t()]}
  def validate_fragment(%Document{} = document, %Schema{} = schema, caller_env \\ nil) do
    ctx = %Context{schema: schema}

    ctx =
      Enum.reduce(@fragment_rules, ctx, fn rule, acc ->
        rule.validate(document, acc)
      end)

    finalize(ctx, caller_env)
  end

  defp finalize(ctx, caller_env) do
    line_offset = Helpers.caller_line_offset(caller_env)

    {errors, warnings} =
      ctx
      |> Context.errors()
      |> Enum.split_with(&(&1.severity == :error))

    for warning <- warnings do
      emit_warning(Error.format(warning, line_offset), caller_env)
    end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp emit_warning(message, %Macro.Env{} = env), do: IO.warn(message, env)
  defp emit_warning(message, _env), do: IO.warn(message)
end
