defmodule Grephql.ResponseDecoder do
  @moduledoc """
  Decodes GraphQL JSON response data into typed embedded schema structs.

  Uses `Ecto.embedded_load/3` to recursively convert plain maps (from
  `Jason.decode!/1`) into the generated embedded schema structs, automatically
  invoking custom `Ecto.Type.cast/2` callbacks for scalars and enums.

  ## Example

      json = %{"name" => "Alice", "posts" => [%{"title" => "Hello"}]}
      user = Grephql.ResponseDecoder.decode!(MyApp.GetUser.User, json)
      user.name #=> "Alice"
      hd(user.posts).title #=> "Hello"
  """

  @doc """
  Decodes a JSON map into the given embedded schema module.

  Raises on failure.
  """
  @spec decode!(module(), map()) :: struct()
  def decode!(module, data) when is_atom(module) and is_map(data) do
    Ecto.embedded_load(module, data, :json)
  end
end
