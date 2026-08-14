defmodule TypedGql.VariablesDumper do
  @moduledoc """
  Dumps a variables struct to wire JSON, keeping only the keys the caller
  actually provided.

  `Ecto.embedded_dump/2` emits every schema field, which turns an omitted
  optional input field into an explicit `null` on the wire. GraphQL
  distinguishes the two: absent means "not given", while `null` can mean
  "clear this value" in an update mutation. Pruning the dump against the
  original params preserves the distinction — a key the caller passed
  (even as `nil`) is sent, a key they omitted is not.
  """

  @spec dump(struct(), map()) :: map()
  def dump(%module{} = variables, params) do
    variables
    |> Ecto.embedded_dump(:json)
    |> prune(module, params)
  end

  defp prune(dumped, module, params) do
    embeds = module.__schema__(:embeds)

    Enum.reduce(module.__schema__(:fields), dumped, fn field, acc ->
      prune_field(acc, module, field, field in embeds, fetch_param(params, field))
    end)
  end

  defp prune_field(dumped, module, field, _embed?, :error),
    do: Map.delete(dumped, module.__schema__(:field_source, field))

  defp prune_field(dumped, _module, _field, false = _embed?, {:ok, _param_value}), do: dumped

  defp prune_field(dumped, module, field, true = _embed?, {:ok, param_value}) do
    %{related: related, cardinality: cardinality} = module.__schema__(:embed, field)
    source = module.__schema__(:field_source, field)

    Map.update!(dumped, source, &prune_embed(&1, cardinality, related, param_value))
  end

  defp prune_embed(nil, _cardinality, _related, _param_value), do: nil

  defp prune_embed(dumped, :one, related, param_value), do: prune(dumped, related, param_value)

  defp prune_embed(dumped, :many, related, param_values) do
    Enum.zip_with(dumped, param_values, &prune(&1, related, &2))
  end

  # Params reach the changeset with atom or string keys; accept both here too.
  defp fetch_param(params, field) do
    with :error <- Map.fetch(params, field) do
      Map.fetch(params, Atom.to_string(field))
    end
  end
end
