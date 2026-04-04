defmodule Grephql.Validator.Context do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema
  alias Grephql.Validator.Error

  typed_structor do
    field :schema, Schema.t(), enforce: true
    field :errors, [Error.t()], default: []
  end

  @spec add_error(t(), String.t(), keyword()) :: t()
  def add_error(%__MODULE__{} = ctx, message, opts \\ []) do
    error = %Error{
      message: message,
      line: Keyword.get(opts, :line),
      severity: Keyword.get(opts, :severity, :error)
    }

    %{ctx | errors: [error | ctx.errors]}
  end

  @spec errors(t()) :: [Error.t()]
  def errors(%__MODULE__{errors: errors}) do
    Enum.reverse(errors)
  end

  @spec errors_by_severity(t(), Error.severity()) :: [Error.t()]
  def errors_by_severity(%__MODULE__{} = ctx, severity) do
    ctx
    |> errors()
    |> Enum.filter(&(&1.severity == severity))
  end
end
