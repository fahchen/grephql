defmodule Grephql.Validator.Helpers do
  @moduledoc false

  alias Grephql.Schema.TypeRef

  @spec unwrap_type(TypeRef.t() | nil) :: TypeRef.t() | nil
  def unwrap_type(%TypeRef{kind: kind, of_type: of_type})
      when kind in [:non_null, :list] and not is_nil(of_type) do
    unwrap_type(of_type)
  end

  def unwrap_type(%TypeRef{} = ref), do: ref
  def unwrap_type(nil), do: nil

  @spec loc_line(map()) :: non_neg_integer() | nil
  def loc_line(%{loc: %{line: line}}) when is_integer(line), do: line
  def loc_line(_), do: nil
end
