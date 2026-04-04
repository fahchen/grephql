defmodule Grephql.TypeGenerator do
  @moduledoc """
  Generates EctoTypedSchema embedded schema modules from GraphQL query AST.

  Given an operation definition and a schema, generates per-query output type
  modules with proper nesting, nullability, and field alias support.

  ## Naming convention

  Output types follow per-query path naming:

      ClientModule.FunctionName.FieldName.NestedField...

  Field aliases override both struct field names and module path segments.
  """

  alias Grephql.Language.Field, as: QueryField
  alias Grephql.Schema
  alias Grephql.TypeMapper
  alias Grephql.Validator.Helpers

  @type option :: {:client_module, module()} | {:function_name, atom()} | {:scalar_types, map()}

  @doc """
  Generates embedded schema modules for an operation's output types.

  Returns a list of generated module names.

  ## Options

    - `:client_module` — the parent client module (e.g., `MyApp.UserService`)
    - `:function_name` — the defgql function name (e.g., `:get_user`)
    - `:scalar_types` — custom scalar type mappings (default: `%{}`)
  """
  @spec generate(Grephql.Language.OperationDefinition.t(), Schema.t(), [option()]) :: [module()]
  def generate(operation, schema, opts) do
    client_module = Keyword.fetch!(opts, :client_module)
    function_name = Keyword.fetch!(opts, :function_name)
    scalar_types = Keyword.get(opts, :scalar_types, %{})

    # Module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    base_module = Module.concat([client_module, camelize(function_name)])

    root_type_name = Helpers.root_type_name(schema, operation.operation)
    context = {schema, scalar_types}

    generate_selections(operation.selection_set.selections, root_type_name, base_module, context)
  end

  defp generate_selections(
         selections,
         parent_type_name,
         parent_module,
         {schema, scalar_types} = context
       ) do
    {field_defs, nested_modules} =
      Enum.reduce(selections, {[], []}, fn
        %QueryField{} = field, {defs_acc, mods_acc} ->
          field_name = field_name(field)

          # Field names from GraphQL schema, bounded set
          # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
          atom_name =
            field_name |> Macro.underscore() |> String.to_atom()

          {:ok, schema_field} = Schema.get_field(schema, parent_type_name, field.name)
          resolved = TypeMapper.resolve(schema_field.type, scalar_types)

          {field_def, new_modules} =
            build_field_def(field, atom_name, field_name, resolved, parent_module, context)

          {[field_def | defs_acc], [new_modules | mods_acc]}

        _non_field, acc ->
          acc
      end)

    field_defs = :lists.reverse(field_defs)
    create_embedded_schema(parent_module, field_defs)

    [parent_module | List.flatten(:lists.reverse(nested_modules))]
  end

  defp build_field_def(field, atom_name, field_name, resolved, parent_module, context) do
    case resolved.ecto_type do
      {:object, type_name} ->
        build_embed(
          :embeds_one,
          field,
          atom_name,
          field_name,
          type_name,
          resolved,
          parent_module,
          context
        )

      {:array, {:object, type_name}} ->
        build_embed(
          :embeds_many,
          field,
          atom_name,
          field_name,
          type_name,
          resolved,
          parent_module,
          context
        )

      ecto_type ->
        typed_opts = if resolved.nullable, do: [null: true], else: [null: false]
        {{:field, atom_name, ecto_type, [typed: typed_opts]}, []}
    end
  end

  defp build_embed(
         kind,
         field,
         atom_name,
         field_name,
         type_name,
         resolved,
         parent_module,
         context
       ) do
    # Nested module names from schema field paths
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    nested_module = Module.concat(parent_module, camelize(field_name))

    nested_modules =
      generate_selections(field.selection_set.selections, type_name, nested_module, context)

    typed_opts = embed_typed_opts(kind, resolved)
    {{kind, atom_name, nested_module, [typed: typed_opts]}, nested_modules}
  end

  defp embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  defp embed_typed_opts(_kind, _resolved), do: []

  defp create_embedded_schema(module_name, field_defs) do
    field_asts = Enum.map(field_defs, &field_def_to_ast/1)

    Module.create(
      module_name,
      quote do
        use Grephql.EmbeddedSchema

        typed_embedded_schema do
          (unquote_splicing(field_asts))
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp field_def_to_ast({kind, name, type_or_schema, opts}) do
    quote do: unquote(kind)(unquote(name), unquote(type_or_schema), unquote(opts))
  end

  defp field_name(%QueryField{alias: alias_name}) when is_binary(alias_name), do: alias_name
  defp field_name(%QueryField{name: name}), do: name

  defp camelize(name) when is_atom(name), do: name |> Atom.to_string() |> Macro.camelize()
  defp camelize(name) when is_binary(name), do: Macro.camelize(name)
end
