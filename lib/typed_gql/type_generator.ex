defmodule TypedGql.TypeGenerator do
  @moduledoc """
  Generates EctoTypedSchema embedded schema modules from GraphQL query AST.

  Given an operation definition and a schema, generates per-query output type
  modules with proper nesting, nullability, and field alias support.

  ## Generation pipeline

  Generation runs as four named steps. Lifecycle plugins
  (`TypedGql.Generation.Plugin`) hook the first three via `after_normalize`,
  `after_resolve`, and `after_lower` (plus `before_normalize` for the raw
  entry); the terminal `create` step compiles modules and is not hookable:

    1. `normalize` — raw selections to canonical selections: expands fragment
       spreads, flattens inline fragments on object types, and propagates
       ancestor (inline-fragment / fragment-spread) directives down onto each
       field's `directives`.
    2. `resolve` — canonical selections + schema to a
       `TypedGql.Generation.Schema` tree. The whole tree is built before any
       lowering.
    3. `lower` — tree to `{module, quoted_ast}` pairs.
    4. `create` — `{module, ast}` pairs to BEAM modules.

  TypedGql always runs its built-in plugins (currently
  `TypedGql.Generation.Plugins.SkipInclude` for `@include`/`@skip`) before any
  user plugins supplied via the `:generation_plugins` option.

  ## Naming convention

  Output types follow per-query path naming under a `Result` namespace:

      ClientModule.FunctionName.Result.FieldName.NestedField...

  Field aliases override both struct field names and module path segments.

  ## Union/Interface support

  When a field's type is a union or interface, inline fragments determine
  which concrete types to generate. Shared fields (outside fragments) are
  merged into each concrete type's struct. A parameterized `TypedGql.Types.Union`
  Ecto Type handles `__typename`-based dispatch during deserialization.
  """

  alias TypedGql.Generation.Context
  alias TypedGql.Generation.Field, as: GenField
  alias TypedGql.Generation.Plugins.SkipInclude
  alias TypedGql.Generation.Schema, as: GenSchema
  alias TypedGql.GeneratorHelpers
  alias TypedGql.Language.Field, as: QueryField
  alias TypedGql.Language.FragmentSpread
  alias TypedGql.Language.InlineFragment
  alias TypedGql.Schema
  alias TypedGql.TypeMapper
  alias TypedGql.Validator.Helpers

  @builtin_plugins [SkipInclude]

  @type option() ::
          {:client_module, module()}
          | {:function_name, atom()}
          | {:scalar_types, map()}
          | {:fragments, map()}
          | {:generation_plugins, [module()]}

  @doc """
  Generates embedded schema modules for an operation's output types.

  Returns a list of generated module names.

  ## Options

    - `:client_module` — the parent client module (e.g., `MyApp.UserService`)
    - `:function_name` — the defgql function name (e.g., `:get_user`)
    - `:scalar_types` — custom scalar type mappings (default: `%{}`)
    - `:fragments` — named fragment entries for spread expansion (default: `%{}`)
    - `:generation_plugins` — user `TypedGql.Generation.Plugin` modules,
      appended after the built-in plugins (default: `[]`)
  """
  @spec generate(TypedGql.Language.OperationDefinition.t(), Schema.t(), [option()]) :: [module()]
  def generate(operation, schema, opts) do
    client_module = Keyword.fetch!(opts, :client_module)
    function_name = Keyword.fetch!(opts, :function_name)

    # Module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    base_module = Module.concat([client_module, GeneratorHelpers.camelize(function_name), Result])

    root_type_name = Helpers.root_type_name(schema, operation.operation)

    operation.selection_set.selections
    |> run_pipeline(root_type_name, base_module, build_context(schema, opts), plugins(opts))
    |> unwrap_module_names()
  end

  @doc """
  Generates an embedded schema module for a named fragment under
  `ClientModule.Fragments.FragmentName`.
  """
  @spec generate_fragment(TypedGql.Language.Fragment.t(), Schema.t(), module(), map(), [module()]) ::
          module()
  def generate_fragment(fragment, schema, client_module, scalar_types, generation_plugins \\ []) do
    # Fragment module names from schema, bounded set
    # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
    base_module =
      Module.concat([client_module, Fragments, GeneratorHelpers.camelize(fragment.name)])

    type_name = fragment.type_condition.name
    context = build_context(schema, scalar_types: scalar_types)

    run_pipeline(
      fragment.selection_set.selections,
      type_name,
      base_module,
      context,
      plugins(generation_plugins: generation_plugins)
    )

    base_module
  end

  defp build_context(schema, opts) do
    %Context{
      schema: schema,
      scalar_types: Keyword.get(opts, :scalar_types, %{}),
      fragments: Keyword.get(opts, :fragments, %{})
    }
  end

  defp plugins(opts) do
    @builtin_plugins ++ Keyword.get(opts, :generation_plugins, [])
  end

  # Runs the full generation pipeline and returns the tree's module result.
  defp run_pipeline(selections, parent_type_name, parent_module, context, plugins) do
    canonical =
      selections
      |> run_after(plugins, :before_normalize, context)
      |> normalize(parent_type_name, context)
      |> run_after(plugins, :after_normalize, context)

    tree =
      canonical
      |> resolve(parent_type_name, parent_module, context)
      |> run_after(plugins, :after_resolve, context)

    create_union_modules(tree)

    tree
    |> lower()
    |> run_after(plugins, :after_lower, context)
    |> GeneratorHelpers.create_modules()

    tree
  end

  defp run_after(value, plugins, callback, context) do
    Enum.reduce(plugins, value, fn plugin, acc ->
      apply(plugin, callback, [acc, context])
    end)
  end

  # ── normalize ──────────────────────────────────────────────────────────

  # Produces canonical selections: fragment spreads expanded, inline fragments
  # on object types flattened, and ancestor fragment directives propagated onto
  # each field. For union/interface parents, inline fragments are kept (so the
  # resolve step can build per-variant modules) with their directives already
  # propagated onto member fields.
  defp normalize(selections, parent_type_name, context) do
    selections = expand_spreads(selections, context)

    if union_or_interface?(context.schema, parent_type_name) do
      normalize_union_selections(selections, parent_type_name, context)
    else
      normalize_object_selections(selections, parent_type_name, context)
    end
  end

  defp normalize_object_selections(selections, parent_type_name, context) do
    Enum.flat_map(selections, fn
      %QueryField{} = field ->
        [normalize_field(field, parent_type_name, context)]

      %InlineFragment{} = fragment ->
        # Object parents resolve to a single concrete type, so an inline
        # fragment's members merge into the parent (resolved against
        # parent_type_name) rather than producing union variants. Recursing in
        # object mode keeps the result flat — only QueryFields — which
        # resolve_object/5 requires.
        fragment.selection_set.selections
        |> prepend_directives(fragment.directives)
        |> normalize(parent_type_name, context)
    end)
  end

  defp normalize_union_selections(selections, parent_type_name, context) do
    Enum.flat_map(selections, fn
      %QueryField{} = field ->
        [normalize_field(field, parent_type_name, context)]

      %InlineFragment{} = fragment ->
        normalize_union_fragment(fragment, parent_type_name, context)
    end)
  end

  defp normalize_union_fragment(fragment, parent_type_name, context) do
    condition = fragment.type_condition && fragment.type_condition.name

    if shared_condition?(context.schema, condition, parent_type_name) do
      fragment.selection_set.selections
      |> prepend_directives(fragment.directives)
      |> normalize(parent_type_name, context)
    else
      normalized =
        fragment.selection_set.selections
        |> prepend_directives(fragment.directives)
        |> normalize(condition, context)

      [%{fragment | selection_set: %{fragment.selection_set | selections: normalized}}]
    end
  end

  # A fragment with no type condition, or on the parent itself, selects fields
  # every member shares. So does one on an interface the parent implements —
  # directly or through another interface — provided that interface covers every
  # member, or the fields would be shared with a member they do not apply to.
  # Hoisting keeps such fragments out of resolve_union/5, which would otherwise
  # invent a __typename dispatch the response has no reason to satisfy.
  defp shared_condition?(_schema, nil, _parent_type_name), do: true

  defp shared_condition?(schema, condition, parent_type_name) do
    condition == parent_type_name or
      (condition in implemented_interfaces(schema, parent_type_name) and
         covers_every_member?(schema, condition, parent_type_name))
  end

  defp implemented_interfaces(schema, type_name, seen \\ []) do
    interfaces = type_name |> fetch_type(schema) |> Map.fetch!(:interfaces)
    fresh = interfaces -- seen

    Enum.reduce(fresh, seen ++ fresh, fn interface, acc ->
      implemented_interfaces(schema, interface, acc)
    end)
  end

  defp covers_every_member?(schema, condition, parent_type_name) do
    covered = condition |> fetch_type(schema) |> Map.fetch!(:possible_types)
    members = parent_type_name |> fetch_type(schema) |> Map.fetch!(:possible_types)

    members -- covered == []
  end

  defp fetch_type(type_name, schema) do
    {:ok, type} = Schema.get_type(schema, type_name)
    type
  end

  # Normalizes a field's own sub-selection set under its child type. A field's
  # own directives are NOT propagated into its sub-selections — only fragment
  # directives propagate to their members.
  defp normalize_field(%QueryField{selection_set: nil} = field, _parent_type_name, _context),
    do: field

  # child_type is nil only for a field the schema does not declare or whose type
  # it does not define; Rules.Fields rejects both before generation runs. Callers
  # of generate/3 that skip validation get a crash further down either way — the
  # old nil guard here only moved where it happened.
  defp normalize_field(%QueryField{} = field, parent_type_name, context) do
    child_type = Helpers.resolve_field_type(context.schema, parent_type_name, field.name)
    normalized = normalize(field.selection_set.selections, child_type, context)
    %{field | selection_set: %{field.selection_set | selections: normalized}}
  end

  # A spread becomes an inline fragment rather than being spliced in: its type
  # condition decides which concrete type the members belong to, which matters
  # under a union or interface parent. Under an object parent the inline
  # fragment is flattened right back, so nothing changes there.
  defp expand_spreads(selections, context) do
    Enum.flat_map(selections, fn
      %FragmentSpread{name: name, directives: directives} ->
        case Map.fetch(context.fragments, name) do
          {:ok, entry} ->
            expanded = expand_spreads(entry.fragment.selection_set.selections, context)

            [
              %InlineFragment{
                type_condition: entry.fragment.type_condition,
                directives: directives,
                selection_set: %{entry.fragment.selection_set | selections: expanded}
              }
            ]

          :error ->
            []
        end

      other ->
        [other]
    end)
  end

  defp prepend_directives(selections, []), do: selections

  defp prepend_directives(selections, directives) do
    Enum.map(selections, fn selection ->
      Map.update!(selection, :directives, &(directives ++ &1))
    end)
  end

  defp union_or_interface?(schema, type_name) do
    match?(
      {:ok, %{kind: kind}} when kind in [:union, :interface],
      Schema.get_type(schema, type_name)
    )
  end

  # ── resolve ────────────────────────────────────────────────────────────

  # Builds the generated-schema tree from canonical selections.
  defp resolve(selections, parent_type_name, parent_module, context) do
    if union_or_interface?(context.schema, parent_type_name) do
      {shared_fields, inline_fragments} =
        Enum.split_with(selections, &match?(%QueryField{}, &1))

      case inline_fragments do
        [] ->
          resolve_abstract_fields(shared_fields, parent_type_name, parent_module, context)

        _fragments ->
          resolve_union(shared_fields, inline_fragments, parent_type_name, parent_module, context)
      end
    else
      resolve_object(selections, parent_type_name, parent_module, context)
    end
  end

  # Only fields common to every possible type were selected, so no per-variant
  # struct is needed — but `__typename` can still be any of the possible types.
  defp resolve_abstract_fields(fields, parent_type_name, parent_module, context) do
    {:ok, parent} = Schema.get_type(context.schema, parent_type_name)

    resolve_object(fields, parent_type_name, parent_module, context,
      typename_values: parent.possible_types
    )
  end

  defp resolve_object(fields, parent_type_name, parent_module, context, opts \\ []) do
    # On a concrete object type `__typename` can only ever be that type's name;
    # abstract parents override this with their possible types.
    opts = Keyword.put_new(opts, :typename_values, [parent_type_name])
    fields = merge_fields(fields)

    {gen_fields, children} =
      Enum.reduce(fields, {[], []}, fn %QueryField{} = field, {fields_acc, children_acc} ->
        {gen_field, child} =
          resolve_field(field, parent_type_name, parent_module, context, opts)

        {[gen_field | fields_acc], maybe_prepend(child, children_acc)}
      end)

    %GenSchema{
      kind: :object,
      module: parent_module,
      parent_type: parent_type_name,
      fields: :lists.reverse(gen_fields),
      children: :lists.reverse(children)
    }
  end

  defp maybe_prepend(nil, acc), do: acc
  defp maybe_prepend(child, acc), do: [child | acc]

  # Two fragments may select the same field — `... on Node { id } ... on Named
  # { id }` where a member implements both — and a struct cannot declare it
  # twice. GraphQL treats them as one selection, so merge by response key,
  # keeping first-seen order.
  defp merge_fields(fields) do
    {order, by_key} =
      Enum.reduce(fields, {[], %{}}, fn field, {order, by_key} ->
        key = field_name(field)

        case Map.fetch(by_key, key) do
          {:ok, existing} -> {order, Map.put(by_key, key, merge_field(existing, field))}
          :error -> {[key | order], Map.put(by_key, key, field)}
        end
      end)

    order |> :lists.reverse() |> Enum.map(&Map.fetch!(by_key, &1))
  end

  defp merge_field(%QueryField{name: name} = existing, %QueryField{name: name} = field) do
    if not same_arguments?(existing.arguments, field.arguments) do
      raise CompileError,
        description:
          "conflicting selections for \"#{field_name(field)}\": " <>
            "the same response key is selected with different arguments"
    end

    %{
      existing
      | directives: merge_directives(existing.directives, field.directives),
        selection_set: merge_selection_sets(existing.selection_set, field.selection_set)
    }
  end

  # Same response key, different underlying field: the GraphQL spec forbids it
  # (FieldsInSetCanMerge) because a single response key cannot hold both.
  defp merge_field(existing, field) do
    raise CompileError,
      description:
        "conflicting selections for \"#{field_name(field)}\": " <>
          "it names both \"#{existing.name}\" and \"#{field.name}\""
  end

  # Two argument lists are the same when they name the same values, whatever the
  # order they were written in and wherever in the source they came from — the
  # nodes carry a `loc`, so comparing them as-is would call every second
  # occurrence a conflict.
  defp same_arguments?(arguments, other) do
    comparable_arguments(arguments) == comparable_arguments(other)
  end

  defp comparable_arguments(arguments) do
    arguments |> Enum.sort_by(& &1.name) |> without_locations()
  end

  defp without_locations(%struct{} = node) do
    fields =
      node
      |> Map.from_struct()
      |> Map.delete(:loc)
      |> Map.new(fn {key, value} -> {key, without_locations(value)} end)

    {struct, fields}
  end

  defp without_locations(values) when is_list(values), do: Enum.map(values, &without_locations/1)
  defp without_locations(other), do: other

  # Selected unconditionally anywhere means always present, so a copy that
  # cannot be removed clears the other's @skip/@include.
  defp merge_directives(directives, other) do
    if SkipInclude.conditional?(directives) and SkipInclude.conditional?(other),
      do: directives ++ other,
      else: []
  end

  # Both copies are the same schema field, so either both are leaves or neither is.
  defp merge_selection_sets(nil, _other), do: nil

  defp merge_selection_sets(selection_set, other) do
    %{selection_set | selections: merge_fields(selection_set.selections ++ other.selections)}
  end

  defp resolve_field(%QueryField{} = field, parent_type_name, parent_module, context, opts) do
    field_name = field_name(field)

    # Field names from GraphQL schema, bounded set
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    atom_name = field_name |> Macro.underscore() |> String.to_atom()

    schema_field = get_field!(context.schema, parent_type_name, field.name)

    resolved =
      schema_field.type
      |> TypeMapper.resolve(context.schema, context.scalar_types)
      |> override_typename_type(field.name, opts)

    base = %GenField{
      kind: :field,
      name: atom_name,
      original_name: field_name,
      resolved: resolved,
      query_field: field,
      schema_field: schema_field
    }

    case resolved.ecto_type do
      {:object, type_name} ->
        resolve_embed(:embeds_one, base, type_name, parent_module, context)

      {:array, {:object, type_name}} ->
        resolve_embed(:embeds_many, base, type_name, parent_module, context)

      _scalar ->
        {base, nil}
    end
  end

  defp resolve_embed(kind, %GenField{} = base, type_name, parent_module, context) do
    # Nested module names from schema field paths
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    nested_module = Module.concat(parent_module, GeneratorHelpers.camelize(base.original_name))

    child = resolve(base.query_field.selection_set.selections, type_name, nested_module, context)

    gen_field =
      case child do
        # Union/interface: lower to a plain field carrying the parameterized
        # TypedGql.Types.Union type instead of an embeds_one/embeds_many embed.
        %GenSchema{kind: :union, union_module: union_module} ->
          ecto_type = if kind == :embeds_many, do: {:array, union_module}, else: union_module
          %{base | resolved: %{base.resolved | ecto_type: ecto_type, enum_values: nil}}

        %GenSchema{kind: :object, module: object_module} ->
          %{base | kind: kind, embed_module: object_module}
      end

    {gen_field, child}
  end

  # A variant per possible type of the abstract parent, not per inline fragment:
  # the server may return any member, including one no fragment selected, and it
  # answers with a concrete typename even when the fragment condition was itself
  # abstract (`... on Node`). Members without a matching fragment still decode,
  # carrying the shared fields alone.
  defp resolve_union(shared_fields, inline_fragments, parent_type_name, parent_module, context) do
    shared_fields = ensure_typename(shared_fields)
    typename_key = typename_key(shared_fields)
    {:ok, parent} = Schema.get_type(context.schema, parent_type_name)
    typename_values = parent.possible_types

    {typename_to_module, variants} =
      Enum.reduce(typename_values, {%{}, []}, fn type_name, {type_map, variants_acc} ->
        merged_selections =
          shared_fields ++ member_selections(inline_fragments, type_name, context)

        # Member type names from schema, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        variant_module = Module.concat(parent_module, GeneratorHelpers.camelize(type_name))

        variant =
          resolve_object(merged_selections, type_name, variant_module, context,
            typename_values: typename_values
          )

        {Map.put(type_map, type_name, variant_module), [variant | variants_acc]}
      end)

    # Union type module names derived from schema at compile time
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    union_module = Module.concat(parent_module, "Union")

    %GenSchema{
      kind: :union,
      module: parent_module,
      union_module: union_module,
      typename_key: typename_key,
      typename_to_module: typename_to_module,
      children: :lists.reverse(variants)
    }
  end

  # Flattens the fragments that apply to `type_name` down to plain fields.
  # A fragment applies when its condition names the member, or is an abstract
  # type the member belongs to (`... on Node` over a union of Nodes). Recursing
  # is what handles a fragment nested inside an abstract one, whose members were
  # normalized against the abstract type and so are still inline fragments —
  # resolve_object/5 only accepts fields.
  defp member_selections(selections, type_name, context) do
    Enum.flat_map(selections, fn
      %QueryField{} = field ->
        [field]

      %InlineFragment{} = fragment ->
        if applies_to?(context.schema, fragment.type_condition.name, type_name),
          do: member_selections(fragment.selection_set.selections, type_name, context),
          else: []
    end)
  end

  defp applies_to?(_schema, type_name, type_name), do: true

  defp applies_to?(schema, condition, type_name) do
    case Schema.get_type(schema, condition) do
      {:ok, %{possible_types: possible_types}} -> type_name in possible_types
      :error -> false
    end
  end

  # Dispatch reads one key out of the raw response before any variant is known,
  # so it has to be a selection every member shares. Prefer an unaliased
  # __typename: an aliased one can also carry @skip, and the response then has
  # neither key.
  defp typename_key(shared_fields) do
    typename_fields = Enum.filter(shared_fields, &(&1.name == "__typename"))
    # A copy carrying @skip/@include may be absent from the response, so it can
    # only be the key when it is the only copy there is.
    unconditional = Enum.filter(typename_fields, &(&1.directives == []))

    preferred =
      Enum.find(unconditional, &is_nil(&1.alias)) || List.first(unconditional) ||
        hd(typename_fields)

    field_name(preferred)
  end

  # __typename is a meta-field available on all object types per the GraphQL spec,
  # but introspection JSON often omits it from the type's fields. Provide a
  # synthetic NonNull String! field when Schema.get_field returns :error.
  @typename_field %TypedGql.Schema.Field{
    name: "__typename",
    type: %TypedGql.Schema.TypeRef{
      kind: :non_null,
      of_type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"}
    }
  }

  defp get_field!(schema, type_name, "__typename") do
    case Schema.get_field(schema, type_name, "__typename") do
      {:ok, field} -> field
      :error -> @typename_field
    end
  end

  defp get_field!(schema, type_name, field_name) do
    {:ok, field} = Schema.get_field(schema, type_name, field_name)
    field
  end

  defp ensure_typename(shared_fields) do
    if Enum.any?(shared_fields, &(&1.name == "__typename")) do
      shared_fields
    else
      [%QueryField{name: "__typename"} | shared_fields]
    end
  end

  defp override_typename_type(resolved, "__typename", opts) do
    values = Keyword.fetch!(opts, :typename_values)

    resolved
    |> Map.put(:ecto_type, TypedGql.Types.Typename)
    |> Map.put(:typename_values, values)
  end

  defp override_typename_type(resolved, _field_name, _opts), do: resolved

  # ── create (union types) ─────────────────────────────────────────────────

  # Union/interface parameterized type modules must be created eagerly because
  # Ecto's __field__ validates parameterized type modules exist at schema
  # compile time, before lowered embedded-schema modules are created.
  defp create_union_modules(%GenSchema{kind: :union} = node) do
    TypedGql.Types.Union.define(node.union_module, node.typename_to_module, node.typename_key)
    Enum.each(node.children, &create_union_modules/1)
  end

  defp create_union_modules(%GenSchema{kind: :object} = node) do
    Enum.each(node.children, &create_union_modules/1)
  end

  # ── lower ──────────────────────────────────────────────────────────────

  # Lowers the tree into {module, quoted_ast} pairs, rebuilding each field's
  # tuple/AST from its Generation.Field, so plugin nullability changes flow
  # through naturally.
  defp lower(%GenSchema{} = tree), do: lower(tree, [])

  defp lower(%GenSchema{kind: :union} = node, acc) do
    Enum.reduce(node.children, acc, &lower/2)
  end

  defp lower(%GenSchema{kind: :object} = node, acc) do
    field_defs = Enum.map(node.fields, &lower_field/1)
    ast = build_embedded_schema_ast(node.module, field_defs)
    Enum.reduce(node.children, [ast | acc], &lower/2)
  end

  defp lower_field(%GenField{kind: :field} = field) do
    resolved = field.resolved
    typed_opts = GeneratorHelpers.scalar_typed_opts(resolved)
    source_opt = GeneratorHelpers.source_opt(field.name, field.original_name)
    enum_opts = GeneratorHelpers.enum_opts(resolved)
    typename_opts = GeneratorHelpers.typename_opts(resolved)
    opts = [{:typed, typed_opts} | source_opt] ++ enum_opts ++ typename_opts
    {:field, field.name, resolved.ecto_type, opts}
  end

  defp lower_field(%GenField{kind: kind} = field) when kind in [:embeds_one, :embeds_many] do
    source_opt = GeneratorHelpers.source_opt(field.name, field.original_name)
    typed_opts = GeneratorHelpers.embed_typed_opts(kind, field.resolved)
    {kind, field.name, field.embed_module, [{:typed, typed_opts} | source_opt]}
  end

  defp build_embedded_schema_ast(module_name, field_defs) do
    field_asts = Enum.map(field_defs, &GeneratorHelpers.field_def_to_ast/1)

    ast =
      quote do
        use TypedGql.EmbeddedSchema

        typed_embedded_schema do
          (unquote_splicing(field_asts))
        end
      end

    {module_name, ast}
  end

  # Extracts the module name list from the generated tree, root-first and
  # depth-first. The first entry is the operation's `Result` module, which the
  # compiler uses as the response decode root.
  defp unwrap_module_names(%GenSchema{} = tree) do
    tree |> collect_module_names() |> List.flatten()
  end

  defp collect_module_names(%GenSchema{kind: :union} = node) do
    Enum.map(node.children, &collect_module_names/1)
  end

  defp collect_module_names(%GenSchema{kind: :object} = node) do
    [node.module | Enum.map(node.children, &collect_module_names/1)]
  end

  defp field_name(%QueryField{alias: alias_name}) when is_binary(alias_name), do: alias_name
  defp field_name(%QueryField{name: name}), do: name
end
