defmodule Grephql.TypeGenerator do
  @moduledoc """
  Generates EctoTypedSchema embedded schema modules from GraphQL query AST.

  Given an operation definition and a schema, generates per-query output type
  modules with proper nesting, nullability, and field alias support.

  ## Naming convention

  Output types follow per-query path naming under a `Result` namespace:

      ClientModule.FunctionName.Result.FieldName.NestedField...

  Field aliases override both struct field names and module path segments.

  ## Union/Interface support

  When a field's type is a union or interface, inline fragments determine
  which concrete types to generate. Shared fields (outside fragments) are
  merged into each concrete type's struct. A parameterized `Grephql.Types.Union`
  Ecto Type handles `__typename`-based dispatch during deserialization.
  """

  alias Grephql.GeneratorHelpers
  alias Grephql.Language.Field, as: QueryField
  alias Grephql.Language.FragmentSpread
  alias Grephql.Schema
  alias Grephql.TypeMapper
  alias Grephql.Validator.Helpers

  @type option() ::
          {:client_module, module()}
          | {:function_name, atom()}
          | {:scalar_types, map()}
          | {:fragments, map()}

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
    fragments = Keyword.get(opts, :fragments, %{})

    # Module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    base_module = Module.concat([client_module, GeneratorHelpers.camelize(function_name), Result])

    root_type_name = Helpers.root_type_name(schema, operation.operation)
    context = {schema, scalar_types, fragments}

    {result, module_asts} =
      collect_selections(operation.selection_set.selections, root_type_name, base_module, context)

    GeneratorHelpers.create_modules(module_asts)

    unwrap_module_names(result)
  end

  @doc """
  Generates an embedded schema module for a named fragment under
  `ClientModule.Fragments.FragmentName`.
  """
  @spec generate_fragment(Grephql.Language.Fragment.t(), Schema.t(), module(), map()) :: module()
  def generate_fragment(fragment, schema, client_module, scalar_types) do
    # Fragment module names from schema, bounded set
    # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
    base_module =
      Module.concat([client_module, Fragments, GeneratorHelpers.camelize(fragment.name)])

    type_name = fragment.type_condition.name
    context = {schema, scalar_types, %{}}

    {_result, module_asts} =
      collect_selections(fragment.selection_set.selections, type_name, base_module, context)

    GeneratorHelpers.create_modules(module_asts)

    base_module
  end

  # Collects module ASTs without creating them. Returns:
  #   - For objects: {[module_name, ...], [{mod, ast}, ...]}
  #   - For unions:  {{union_module, [module_name, ...]}, [{mod, ast}, ...]}
  defp collect_selections(selections, parent_type_name, parent_module, context) do
    selections = expand_fragment_spreads(selections, context)
    {shared_fields, inline_fragments} = Enum.split_with(selections, &match?(%QueryField{}, &1))

    case inline_fragments do
      [] ->
        collect_object_schema(shared_fields, parent_type_name, parent_module, context)

      _fragments ->
        collect_union_schemas(shared_fields, inline_fragments, parent_module, context)
    end
  end

  defp expand_fragment_spreads(selections, {_schema, _scalar_types, fragments} = context) do
    Enum.flat_map(selections, fn
      %FragmentSpread{name: name} ->
        case Map.fetch(fragments, name) do
          {:ok, entry} ->
            expand_fragment_spreads(entry.fragment.selection_set.selections, context)

          :error ->
            []
        end

      other ->
        [other]
    end)
  end

  defp collect_object_schema(
         fields,
         parent_type_name,
         parent_module,
         {schema, scalar_types, _fragments} = context
       ) do
    {field_defs, nested_modules, nested_asts} =
      Enum.reduce(fields, {[], [], []}, fn %QueryField{} = field,
                                           {defs_acc, mods_acc, asts_acc} ->
        field_name = field_name(field)

        # Field names from GraphQL schema, bounded set
        # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
        atom_name =
          field_name |> Macro.underscore() |> String.to_atom()

        {:ok, schema_field} = Schema.get_field(schema, parent_type_name, field.name)
        resolved = TypeMapper.resolve(schema_field.type, schema, scalar_types)

        {field_def, new_modules, new_asts} =
          build_field_def(field, atom_name, field_name, resolved, parent_module, context)

        {[field_def | defs_acc], [new_modules | mods_acc], [new_asts | asts_acc]}
      end)

    field_defs = :lists.reverse(field_defs)
    parent_ast = build_embedded_schema_ast(parent_module, field_defs)

    module_names = [parent_module | List.flatten(:lists.reverse(nested_modules))]
    all_asts = [parent_ast | List.flatten(:lists.reverse(nested_asts))]

    {module_names, all_asts}
  end

  defp collect_union_schemas(shared_fields, inline_fragments, parent_module, context) do
    shared_fields = ensure_typename(shared_fields)

    {typename_to_module, all_modules, all_asts} =
      Enum.reduce(inline_fragments, {%{}, [], []}, fn fragment, {type_map, mods_acc, asts_acc} ->
        type_name = fragment.type_condition.name
        merged_selections = shared_fields ++ fragment.selection_set.selections

        # Fragment type names from schema, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        fragment_module = Module.concat(parent_module, GeneratorHelpers.camelize(type_name))

        {fragment_modules, fragment_asts} =
          collect_object_schema(merged_selections, type_name, fragment_module, context)

        {Map.put(type_map, type_name, fragment_module), [fragment_modules | mods_acc],
         [fragment_asts | asts_acc]}
      end)

    # Union type module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    union_module = Module.concat(parent_module, "Union")

    # Union modules must be created eagerly because Ecto's __field__
    # validates parameterized type modules exist at schema compile time.
    Grephql.Types.Union.define(union_module, typename_to_module)

    flat_modules = List.flatten(:lists.reverse(all_modules))
    flat_asts = List.flatten(:lists.reverse(all_asts))

    {{union_module, flat_modules}, flat_asts}
  end

  defp ensure_typename(shared_fields) do
    if Enum.any?(shared_fields, &(&1.name == "__typename")) do
      shared_fields
    else
      [%QueryField{name: "__typename"} | shared_fields]
    end
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
        source_opt = GeneratorHelpers.source_opt(atom_name, field_name)
        enum_opts = GeneratorHelpers.enum_opts(resolved)
        opts = [{:typed, typed_opts} | source_opt] ++ enum_opts
        {{:field, atom_name, ecto_type, opts}, [], []}
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
    nested_module = Module.concat(parent_module, GeneratorHelpers.camelize(field_name))

    {result, nested_asts} =
      collect_selections(field.selection_set.selections, type_name, nested_module, context)

    source_opt = GeneratorHelpers.source_opt(atom_name, field_name)

    case result do
      # Union/interface: use parameterized type field instead of embed
      {union_module, nested_modules} ->
        ecto_type = if kind == :embeds_many, do: {:array, union_module}, else: union_module
        typed_opts = if resolved.nullable, do: [null: true], else: [null: false]

        {{:field, atom_name, ecto_type, [{:typed, typed_opts} | source_opt]}, nested_modules,
         nested_asts}

      # Regular object: use embeds_one/embeds_many
      [_nested_module | _rest] = nested_modules ->
        typed_opts = GeneratorHelpers.embed_typed_opts(kind, resolved)

        {{kind, atom_name, nested_module, [{:typed, typed_opts} | source_opt]}, nested_modules,
         nested_asts}
    end
  end

  defp build_embedded_schema_ast(module_name, field_defs) do
    field_asts = Enum.map(field_defs, &GeneratorHelpers.field_def_to_ast/1)

    ast =
      quote do
        use Grephql.EmbeddedSchema

        typed_embedded_schema do
          (unquote_splicing(field_asts))
        end
      end

    {module_name, ast}
  end

  # Extracts module name list from collect result
  defp unwrap_module_names({_union_module, modules}), do: modules
  defp unwrap_module_names(modules) when is_list(modules), do: modules

  defp field_name(%QueryField{alias: alias_name}) when is_binary(alias_name), do: alias_name
  defp field_name(%QueryField{name: name}), do: name
end
