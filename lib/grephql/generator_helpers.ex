defmodule Grephql.GeneratorHelpers do
  @moduledoc false

  @doc false
  @spec field_def_to_ast({atom(), atom(), term(), keyword()}) :: Macro.t()
  def field_def_to_ast({kind, name, type_or_schema, opts}) do
    quote do: unquote(kind)(unquote(name), unquote(type_or_schema), unquote(opts))
  end

  @doc false
  @spec embed_typed_opts(:embeds_one | :embeds_many, Grephql.TypeMapper.resolve_result()) ::
          keyword()
  def embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  def embed_typed_opts(_kind, _resolved), do: []
end
