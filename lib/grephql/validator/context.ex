defmodule Grephql.Validator.Context do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema
  alias Grephql.Validator.Error
  alias Grephql.Validator.Helpers

  typed_structor do
    field :schema, Schema.t(), enforce: true
    field :errors, [Error.t()], default: []
  end

  @spec add_error(t(), String.t(), map() | keyword()) :: t()
  def add_error(ctx, message, node_or_opts \\ [])

  def add_error(%__MODULE__{} = ctx, message, %{} = node) do
    add_error(ctx, message, node, [])
  end

  def add_error(%__MODULE__{} = ctx, message, opts) when is_list(opts) do
    error = %Error{
      message: message,
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column),
      severity: Keyword.get(opts, :severity, :error)
    }

    %{ctx | errors: [error | ctx.errors]}
  end

  @spec add_error(t(), String.t(), map(), keyword()) :: t()
  def add_error(%__MODULE__{} = ctx, message, %{} = node, opts) do
    add_error(ctx, message, [
      {:line, Helpers.loc_line(node)},
      {:column, Helpers.loc_column(node)} | opts
    ])
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
