defmodule Grephql.GeneratorHelpers do
  @moduledoc false

  @doc false
  @spec field_def_to_ast({atom(), atom(), term(), keyword()}) :: Macro.t()
  def field_def_to_ast({kind, name, type_or_schema, opts}) do
    quote do: unquote(kind)(unquote(name), unquote(type_or_schema), unquote(opts))
  end

  @doc false
  @spec camelize(atom()) :: String.t()
  def camelize(name) when is_atom(name), do: name |> Atom.to_string() |> Macro.camelize()

  @doc false
  @spec camelize(String.t()) :: String.t()
  def camelize(name) when is_binary(name), do: Macro.camelize(name)

  @doc false
  @spec embed_typed_opts(:embeds_one | :embeds_many, Grephql.TypeMapper.resolve_result()) ::
          keyword()
  def embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  def embed_typed_opts(_kind, _resolved), do: []

  @doc """
  Reverses accumulated field definitions and extracts cast field names.

  Takes the reversed accumulators from a reduce pass and returns
  `{field_defs, cast_fields, embed_names, required_names}` ready
  for `create_input_schema/5`.
  """
  @spec prepare_schema_fields(list(), list(), list()) ::
          {list(), [atom()], list(), list()}
  def prepare_schema_fields(field_defs, embed_names, required_names) do
    field_defs = :lists.reverse(field_defs)
    embed_names = :lists.reverse(embed_names)
    required_names = :lists.reverse(required_names)
    cast_fields = for {:field, name, _type, _opts} <- field_defs, do: name

    {field_defs, cast_fields, embed_names, required_names}
  end
end
