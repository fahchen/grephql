defmodule TypedGql.Generation.Field do
  @moduledoc """
  A single generated schema field, before lowering to EctoTypedSchema AST.

  Promotes the inputs of the type generator's field building into a struct
  so lifecycle plugins can read GraphQL context (`query_field`/`schema_field`)
  and mutate generation intent (e.g. set `resolved.nullable` to `true`).

  Lowering rebuilds the field definition from `resolved` plus the names, so a
  plugin mutating `resolved` flows through naturally.
  """
  use TypedStructor

  alias TypedGql.Language.Field, as: QueryField
  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.TypeMapper

  @type kind() :: :field | :embeds_one | :embeds_many

  typed_structor do
    field :kind, kind(), enforce: true
    field :name, atom(), enforce: true
    field :original_name, String.t(), enforce: true
    field :resolved, TypeMapper.resolve_result(), enforce: true
    field :embed_module, module()
    field :query_field, QueryField.t(), enforce: true
    field :schema_field, SchemaField.t(), enforce: true
  end

  @doc """
  Sets the field's nullability, mutating `resolved.nullable`.
  """
  @spec put_nullable(t(), boolean()) :: t()
  def put_nullable(%__MODULE__{resolved: resolved} = field, nullable)
      when is_boolean(nullable) do
    %{field | resolved: %{resolved | nullable: nullable}}
  end
end
