defmodule Grephql.Validator.Error do
  @moduledoc false
  use TypedStructor

  @type severity() :: :error | :warning

  typed_structor do
    field :message, String.t(), enforce: true
    field :line, non_neg_integer()
    field :column, non_neg_integer()
    field :severity, severity(), default: :error
  end

  @spec format(t(), non_neg_integer()) :: String.t()
  def format(error, line_offset \\ 0)

  def format(%__MODULE__{message: message, line: line, column: column}, line_offset)
      when is_integer(line) and is_integer(column) do
    "(#{line + line_offset}:#{column}) #{message}"
  end

  def format(%__MODULE__{message: message, line: line}, line_offset) when is_integer(line) do
    "(#{line + line_offset}) #{message}"
  end

  def format(%__MODULE__{message: message}, _line_offset) do
    message
  end
end
