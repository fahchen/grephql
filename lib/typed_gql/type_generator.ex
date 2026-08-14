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

  ## Lists of objects

  Only `[T!]!` becomes `embeds_many`: Ecto loads a null many-embed as `[]` and
  raises on a null element, so that is the one shape it models faithfully.
  Every other list of a composite — `[T]`, `[T]!`, `[T!]`, and any nesting such
  as `[[T]]` — becomes a plain field over the parameterized `Ecto.Embedded`
  type with `cardinality: :one`, which loads `nil` as `nil` at every level.

  A `[T!]!` carrying `@skip`/`@include` is a plain field too: the response can
  omit it entirely, and `embeds_many` pins `default: []`, which would report a
  list the server never sent as an empty one.

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
  alias TypedGql.Language.ObjectValue
  alias TypedGql.Schema
  alias TypedGql.TypeMapper
  alias TypedGql.Validator.Helpers

  @builtin_plugins [SkipInclude]

  @type option() ::
          {:client_module, module()}
          | {:function_name, atom()}
          | {:scalar_types, map()}
          | {:fragments, %{String.t() => TypedGql.Language.Fragment.t()}}
          | {:generation_plugins, [module()]}

  @doc """
  Generates embedded schema modules for an operation's output types.

  Returns a list of generated module names.

  ## Options

    - `:client_module` — the parent client module (e.g., `MyApp.UserService`)
    - `:function_name` — the defgql function name (e.g., `:get_user`)
    - `:scalar_types` — custom scalar type mappings (default: `%{}`)
    - `:fragments` — `TypedGql.Language.Fragment` definitions by name, for
      spread expansion; a spread naming one that is absent raises
      `CompileError` (default: `%{}`)
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
  Generates the result modules for a named fragment under
  `ClientModule.Fragments.FragmentName`.

  Takes the same options as `generate/3` except `:client_module` and
  `:function_name`, which the fragment's own name replaces.

  This was `generate_fragment/5` up to 0.12.2, taking `scalar_types` as a bare
  fourth argument and the plugin list as a fifth. Both are options now, so a
  caller passing `scalar_types` positionally has to wrap it:
  `generate_fragment(fragment, schema, client_module, scalar_types: types)`.

  Returns the module that stands for the fragment's result. For an object
  type condition — and for an abstract one whose selections every member
  shares — that is the embedded schema at `Fragments.FragmentName`. For a
  condition with per-member selections there is no single struct: the return
  is the `TypedGql.Types.Union` parameterized type at
  `Fragments.FragmentName.Union`, which dispatches on `__typename` to the
  per-member embedded schemas at `Fragments.FragmentName.MemberType`.
  """
  @spec generate_fragment(TypedGql.Language.Fragment.t(), Schema.t(), module(), [option()]) ::
          module()
  def generate_fragment(fragment, schema, client_module, opts \\ []) do
    # Fragment module names from schema, bounded set
    # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
    base_module =
      Module.concat([client_module, Fragments, GeneratorHelpers.camelize(fragment.name)])

    type_name = fragment.type_condition.name

    tree =
      run_pipeline(
        fragment.selection_set.selections,
        type_name,
        base_module,
        build_context(schema, opts),
        plugins(opts)
      )

    # base_module is the naming root the pipeline was given, not necessarily a
    # module it created: the union branch emits the variants and the dispatching
    # union type instead, so return what actually exists.
    case tree do
      %GenSchema{kind: :union, union_module: union_module} -> union_module
      %GenSchema{kind: :object, module: module} -> module
    end
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

      # The wrapper's directives now live on its members, so clear them: anything
      # left there afterwards was pushed down by a later merge and still has to
      # reach the members — see member_selections/3.
      [
        %{
          fragment
          | directives: [],
            selection_set: %{fragment.selection_set | selections: normalized}
        }
      ]
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
        [expand_spread(name, directives, context)]

      other ->
        [other]
    end)
  end

  # TypedGql.Validator.Rules.Fragments rejects a spread that reaches itself, so
  # the recursion here terminates on any document that went through validation.
  defp expand_spread(name, directives, context) do
    case Map.fetch(context.fragments, name) do
      {:ok, fragment} ->
        expanded = expand_spreads(fragment.selection_set.selections, context)

        %InlineFragment{
          type_condition: fragment.type_condition,
          directives: directives,
          selection_set: %{fragment.selection_set | selections: expanded}
        }

      # Dropping the spread would generate a struct missing every field it
      # selected, and the request would still ask the server for them.
      :error ->
        raise CompileError, description: "undefined fragment spread: ...#{name}"
    end
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

    # Selections can still carry inline fragments here: a field normalized under
    # an abstract type keeps them, and a covariant schema may then resolve that
    # field against a concrete member (`friend: Node` narrowing to `friend: User`
    # on User). Flattening against the type actually being resolved is what makes
    # the list the fields-only one the reducer below needs.
    fields =
      fields
      |> member_selections(parent_type_name, context)
      |> merge_fields()

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
      fields: gen_fields |> :lists.reverse() |> reject_colliding_names(),
      children: :lists.reverse(children)
    }
  end

  # Response keys are distinct but their struct field names may not be:
  # `typeName` and `type_name` both underscore to :type_name, and Ecto refuses
  # the second. Say so here rather than let it surface as a schema error.
  defp reject_colliding_names(gen_fields) do
    gen_fields
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn
      {_name, [_single]} ->
        :ok

      {name, colliding} ->
        keys = Enum.map_join(colliding, " and ", &~s("#{&1.original_name}"))

        raise CompileError,
          description: "response keys #{keys} both map to the struct field :#{name}"
    end)

    gen_fields
  end

  defp maybe_prepend(nil, acc), do: acc
  defp maybe_prepend(child, acc), do: [child | acc]

  # Two fragments may select the same field — `... on Node { id } ... on Named
  # { id }` where a member implements both — and a struct cannot declare it
  # twice. GraphQL treats them as one selection, so merge by response key,
  # keeping first-seen order.
  #
  # Every copy of a key is merged in one pass rather than folded pairwise: a
  # fold would feed the already-aggregated directives of the running result back
  # in, and a third copy would then re-prepend them to children that already
  # carry their own.
  defp merge_fields(selections) do
    # A child selection set under an abstract type still holds inline fragments.
    # They have no response key to merge on — resolve_union/5 turns them into
    # variants, where their fields merge per member — so they pass through.
    {fields, fragments} = Enum.split_with(selections, &match?(%QueryField{}, &1))

    merged =
      fields
      |> group_by_response_key()
      |> Enum.map(fn
        {_key, [single]} -> single
        {_key, copies} -> merge_copies(copies)
      end)

    merged ++ fragments
  end

  defp group_by_response_key(fields) do
    {order, by_key} =
      Enum.reduce(fields, {[], %{}}, fn field, {order, by_key} ->
        key = field_name(field)
        seen? = Map.has_key?(by_key, key)

        {if(seen?, do: order, else: [key | order]),
         Map.update(by_key, key, [field], &[field | &1])}
      end)

    order
    |> :lists.reverse()
    |> Enum.map(&{&1, by_key |> Map.fetch!(&1) |> :lists.reverse()})
  end

  defp merge_copies([first | rest] = copies) do
    Enum.each(rest, &check_mergeable!(first, &1))

    %{
      first
      | directives: merged_directives(copies),
        selection_set: merged_selection_set(copies)
    }
  end

  defp check_mergeable!(%QueryField{name: name} = first, %QueryField{name: name} = copy) do
    if not same_arguments?(first.arguments, copy.arguments) do
      raise CompileError,
        description:
          "conflicting selections for \"#{field_name(copy)}\": " <>
            "the same response key is selected with different arguments"
    end
  end

  # Same response key, different underlying field: the GraphQL spec forbids it
  # (FieldsInSetCanMerge) because a single response key cannot hold both.
  defp check_mergeable!(first, copy) do
    raise CompileError,
      description:
        "conflicting selections for \"#{field_name(copy)}\": " <>
          "it names both \"#{first.name}\" and \"#{copy.name}\""
  end

  # Selected unconditionally anywhere means always present, so one copy that
  # cannot be removed clears every other's @skip/@include.
  #
  # Deliberately not proven further: complementary conditions such as
  # `id @include(if: $x)` and `id @skip(if: $x)` also guarantee the field, but
  # deciding that in general means proving a boolean formula over the variables.
  # Keeping both directives marks the field nullable, which is the safe
  # direction — the value still decodes, only the typespec is wider than it has
  # to be, whereas guessing non-null would make the typespec lie.
  defp merged_directives(copies) do
    directives = Enum.flat_map(copies, & &1.directives)

    # An unconditional copy guarantees the field, which cancels the other
    # copies' @skip/@include — and only those: any other directive stays, or a
    # plugin reading the merged field's directives would silently lose it.
    if Enum.all?(copies, &SkipInclude.conditional?(&1.directives)),
      do: directives,
      else: Enum.reject(directives, &SkipInclude.skip_include?/1)
  end

  # Both copies are the same schema field, so either all are leaves or none is.
  defp merged_selection_set([%QueryField{selection_set: nil} | _rest]), do: nil

  defp merged_selection_set([first | _rest] = copies) do
    # Each copy's children were only selected under that copy's condition, so the
    # condition moves onto them before the lists become one. Without this a child
    # of a `@include(if: $a)` copy would look unconditional next to a child of
    # the `@include(if: $b)` copy, and be generated non-null.
    selections =
      Enum.flat_map(copies, &prepend_directives(&1.selection_set.selections, &1.directives))

    %{first.selection_set | selections: merge_fields(selections)}
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

  # Input object fields are unordered per the spec, unlike list values.
  defp without_locations(%ObjectValue{fields: fields}) do
    {ObjectValue, %{fields: fields |> Enum.sort_by(& &1.name) |> without_locations()}}
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

    case GeneratorHelpers.unwrap_list(resolved.ecto_type) do
      {{:object, type_name}, depth} ->
        resolve_embed(depth, base, type_name, parent_module, context)

      _scalar ->
        {base, nil}
    end
  end

  defp wrap_list(0, type), do: type
  defp wrap_list(depth, type), do: {:array, wrap_list(depth - 1, type)}

  defp resolve_embed(depth, %GenField{} = base, type_name, parent_module, context) do
    # Nested module names from schema field paths
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    nested_module = Module.concat(parent_module, GeneratorHelpers.camelize(base.original_name))

    child = resolve(base.query_field.selection_set.selections, type_name, nested_module, context)

    gen_field =
      case child do
        # Union/interface: lower to a plain field carrying the parameterized
        # TypedGql.Types.Union type instead of an embeds_one/embeds_many embed.
        %GenSchema{kind: :union, union_module: union_module} ->
          %{
            base
            | embed_module: union_module,
              resolved: %{
                base.resolved
                | ecto_type: wrap_list(depth, union_module),
                  enum_values: nil
              }
          }

        %GenSchema{kind: :object, module: object_module} ->
          resolve_object_embed(base, depth, object_module)
      end

    {gen_field, child}
  end

  defp resolve_object_embed(%GenField{} = base, 0, object_module) do
    %{base | kind: :embeds_one, embed_module: object_module}
  end

  # `embeds_many` pins `default: []` and raises on a nil element, so it models
  # only `[T!]!` faithfully. Every other list shape becomes a plain field over
  # `Ecto.Embedded` with `cardinality: :one`, which loads nil as nil at every
  # level and so nests to any depth.
  defp resolve_object_embed(%GenField{} = base, depth, object_module) do
    if depth == 1 and faithful_many?(base) do
      %{base | kind: :embeds_many, embed_module: object_module}
    else
      %{
        base
        | embed_module: object_module,
          resolved: %{base.resolved | ecto_type: wrap_list(depth, Ecto.Embedded)}
      }
    end
  end

  # A conditionally selected list can be absent from the response, and
  # embeds_many decodes an absent list as [] — "zero elements" where the truth is
  # "not requested" — so it is not faithful either, whatever the schema says.
  defp faithful_many?(%GenField{resolved: %{nullable: false, inner_nullable: false}} = field),
    do: not SkipInclude.conditional?(field.query_field.directives)

  defp faithful_many?(_field), do: false

  # A variant per possible type of the abstract parent, not per inline fragment:
  # the server may return any member, including one no fragment selected, and it
  # answers with a concrete typename even when the fragment condition was itself
  # abstract (`... on Node`). Members without a matching fragment still decode,
  # carrying the shared fields alone.
  defp resolve_union(shared_fields, inline_fragments, parent_type_name, parent_module, context) do
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
    reject_variant_collisions!(typename_to_module, union_module, parent_type_name)

    %GenSchema{
      kind: :union,
      module: parent_module,
      union_module: union_module,
      typename_to_module: typename_to_module,
      children: :lists.reverse(variants)
    }
  end

  # Every variant gets a module named after its camelized typename, and the
  # dispatcher takes "Union" — a member named Union, or two members whose names
  # camelize identically ("Foo_bar"/"FooBar"), would define two different
  # modules under one name and silently clobber whichever loads first.
  defp reject_variant_collisions!(typename_to_module, union_module, parent_type_name) do
    collided =
      typename_to_module
      |> Map.put("(union dispatcher)", union_module)
      |> Enum.group_by(fn {_name, module} -> module end, fn {name, _module} -> name end)
      |> Enum.filter(fn {_module, names} -> length(names) > 1 end)

    if collided != [] do
      details =
        Enum.map_join(collided, "; ", fn {module, names} ->
          "#{Enum.join(Enum.sort(names), " and ")} both name #{inspect(module)}"
        end)

      raise CompileError,
        description:
          "cannot generate variant modules for \"#{parent_type_name}\": #{details}"
    end
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
        if applies_to?(context.schema, fragment.type_condition.name, type_name) do
          fragment.selection_set.selections
          |> prepend_directives(fragment.directives)
          |> member_selections(type_name, context)
        else
          []
        end
    end)
  end

  defp applies_to?(_schema, type_name, type_name), do: true

  defp applies_to?(schema, condition, type_name) do
    case Schema.get_type(schema, condition) do
      {:ok, %{possible_types: possible_types}} -> type_name in possible_types
      :error -> false
    end
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
    TypedGql.Types.Union.define(node.union_module, node.typename_to_module)
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
    {type_opt, embedded_opts} = composite_opts(field)
    typed_opts = GeneratorHelpers.scalar_typed_opts(resolved) ++ type_opt
    source_opt = GeneratorHelpers.source_opt(field.name, field.original_name)
    enum_opts = GeneratorHelpers.enum_opts(resolved)
    typename_opts = GeneratorHelpers.typename_opts(resolved)

    opts =
      [{:typed, typed_opts} | source_opt] ++ enum_opts ++ typename_opts ++ embedded_opts

    {:field, field.name, resolved.ecto_type, opts}
  end

  defp lower_field(%GenField{kind: kind} = field) when kind in [:embeds_one, :embeds_many] do
    source_opt = GeneratorHelpers.source_opt(field.name, field.original_name)
    typed_opts = GeneratorHelpers.embed_typed_opts(kind, field.resolved)
    {kind, field.name, field.embed_module, [{:typed, typed_opts} | source_opt]}
  end

  # A composite leaf — a union dispatcher, or an object behind `Ecto.Embedded` —
  # takes its typespec from the GraphQL type, because the Ecto type says nothing
  # about which list levels and elements are nullable. `Ecto.Embedded` is itself
  # a parameterized type, so it also takes its target through field options
  # rather than through `embeds_one`/`embeds_many`.
  defp composite_opts(%GenField{embed_module: nil}), do: {[], []}

  defp composite_opts(%GenField{embed_module: module} = field) do
    leaf_ast = quote(do: unquote(module).t())
    type_opt = [type: TypeMapper.list_type_ast(field.schema_field.type, leaf_ast)]

    case GeneratorHelpers.unwrap_list(field.resolved.ecto_type) do
      {Ecto.Embedded, _depth} -> {type_opt, [cardinality: :one, related: module]}
      _other -> {type_opt, []}
    end
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
