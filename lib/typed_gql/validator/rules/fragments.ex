defmodule TypedGql.Validator.Rules.Fragments do
  @moduledoc false

  alias TypedGql.Language.Document
  alias TypedGql.Language.Field
  alias TypedGql.Language.Fragment
  alias TypedGql.Language.FragmentSpread
  alias TypedGql.Language.InlineFragment
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.Schema
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions} = document, %Context{} = ctx) do
    fragments = Enum.filter(definitions, &match?(%Fragment{}, &1))
    # Registered fragments sit behind the document's own definitions, mirroring
    # the compiler's shadowing rule — a spread of either kind is checked where
    # it is spread.
    by_name = Map.merge(ctx.fragments, Document.fragments_by_name(document))

    ctx =
      definitions
      |> Enum.filter(&match?(%OperationDefinition{}, &1))
      |> Enum.reduce(ctx, fn op, acc ->
        root_type_name = Helpers.root_type_name(acc.schema, op.operation)
        validate_selection_set(acc, op.selection_set, root_type_name, by_name)
      end)

    ctx =
      Enum.reduce(fragments, ctx, fn frag, acc ->
        frag_type = frag.type_condition.name
        acc = validate_fragment_type_condition(acc, frag, frag_type)
        validate_selection_set(acc, frag.selection_set, frag_type, by_name)
      end)

    ctx
    |> check_cycles(fragments)
    |> check_unused(definitions, fragments)
  end

  # Spec 5.5.1.4: every fragment an executable document defines must be spread
  # somewhere in it, or a server rejects the whole document. A document with no
  # operation is not one we send — deffragment compiles a fragment on its own —
  # so the rule does not apply there.
  defp check_unused(ctx, definitions, fragments) do
    if Enum.any?(definitions, &match?(%OperationDefinition{}, &1)),
      do: reject_unused(ctx, definitions, fragments),
      else: ctx
  end

  # A use only counts when it is reachable from an operation — a spread inside
  # a fragment nothing spreads is not a use, or deleting one unused fragment
  # would surface the next on the following compile instead of both at once.
  defp reject_unused(ctx, definitions, fragments) do
    by_name = Map.new(fragments, &{&1.name, &1})

    reachable =
      definitions
      |> Enum.filter(&match?(%OperationDefinition{}, &1))
      |> Enum.flat_map(&spread_names(&1.selection_set))
      |> reach(by_name, %{})

    fragments
    |> Enum.reject(&is_map_key(reachable, &1.name))
    |> Enum.reduce(ctx, fn fragment, acc ->
      Context.add_error(acc, "fragment \"#{fragment.name}\" is defined but never used", fragment)
    end)
  end

  # `seen` is a map rather than a MapSet: dialyzer reads MapSet as opaque
  # across a recursive private call and rejects the accumulator.
  defp reach([], _by_name, seen), do: seen

  defp reach([name | rest], by_name, seen) do
    case {is_map_key(seen, name), by_name} do
      {true, _by_name} ->
        reach(rest, by_name, seen)

      {false, %{^name => fragment}} ->
        reach(spread_names(fragment.selection_set) ++ rest, by_name, Map.put(seen, name, true))

      # A spread of a registered fragment: not defined here, nothing to mark.
      {false, _by_name} ->
        reach(rest, by_name, Map.put(seen, name, true))
    end
  end

  # Spec 5.5.2.2: a cycle would make the document infinite. It also makes
  # TypeGenerator's spread expansion loop forever, so this has to be caught here
  # rather than left to fail somewhere downstream.
  defp check_cycles(ctx, fragments) do
    spreads = Map.new(fragments, &{&1.name, spread_names(&1.selection_set)})

    Enum.reduce(fragments, ctx, fn fragment, acc ->
      if cycles_back?(spreads, fragment.name, spreads[fragment.name], %{}) do
        Context.add_error(
          acc,
          "fragment \"#{fragment.name}\" spreads itself, directly or through another fragment",
          fragment
        )
      else
        acc
      end
    end)
  end

  # Whether a fragment reaches `start` does not depend on the route taken there,
  # so a fragment already walked can be skipped rather than walked again per
  # route. Enumerating routes instead is exponential: two fragments per layer,
  # each spreading both of the next layer, took 6.6s at 24 layers.
  # `seen` is a map rather than a MapSet: dialyzer reads MapSet as opaque across
  # a recursive private call and rejects the accumulator.
  defp cycles_back?(_spreads, _start, [], _seen), do: false

  defp cycles_back?(spreads, start, [current | rest], seen) do
    cond do
      current == start ->
        true

      Map.has_key?(seen, current) ->
        cycles_back?(spreads, start, rest, seen)

      true ->
        cycles_back?(
          spreads,
          start,
          Map.get(spreads, current, []) ++ rest,
          Map.put(seen, current, true)
        )
    end
  end

  defp spread_names(nil), do: []

  defp spread_names(%SelectionSet{selections: selections}) do
    Enum.flat_map(selections, fn
      %FragmentSpread{name: name} -> [name]
      %Field{} = field -> spread_names(field.selection_set)
      %InlineFragment{} = fragment -> spread_names(fragment.selection_set)
    end)
  end

  defp validate_fragment_type_condition(ctx, frag, type_name) do
    case Schema.get_type(ctx.schema, type_name) do
      {:ok, %{kind: kind}} when kind in [:object, :interface, :union] ->
        ctx

      {:ok, %{kind: kind}} ->
        Context.add_error(
          ctx,
          "fragment \"#{frag.name}\" cannot be defined on #{kind} type \"#{type_name}\"",
          frag
        )

      :error ->
        Context.add_error(
          ctx,
          "type \"#{type_name}\" in fragment \"#{frag.name}\" does not exist in the schema",
          frag
        )
    end
  end

  defp validate_selection_set(ctx, nil, _parent_type, _fragments), do: ctx

  defp validate_selection_set(ctx, %SelectionSet{selections: sels}, parent_type, fragments) do
    Enum.reduce(sels, ctx, fn sel, acc ->
      validate_selection(acc, sel, parent_type, fragments)
    end)
  end

  defp validate_selection(ctx, %Field{} = field, parent_type, fragments) do
    child_type = Helpers.resolve_field_type(ctx.schema, parent_type, field.name)
    validate_selection_set(ctx, field.selection_set, child_type, fragments)
  end

  defp validate_selection(
         ctx,
         %InlineFragment{type_condition: nil} = frag,
         parent_type,
         fragments
       ) do
    validate_selection_set(ctx, frag.selection_set, parent_type, fragments)
  end

  defp validate_selection(ctx, %InlineFragment{} = frag, parent_type, fragments) do
    frag_type = frag.type_condition.name

    ctx
    |> validate_type_condition(frag, frag_type, parent_type, ctx.schema)
    |> validate_selection_set(frag.selection_set, frag_type, fragments)
  end

  # A spread's type condition has to apply to where it is spread, exactly as an
  # inline fragment's does. Without this the generator resolves the fragment's
  # fields against the wrong type and dies on a bare MatchError. The definition's
  # own body is walked where it is defined, so only the condition is checked here.
  defp validate_selection(ctx, %FragmentSpread{} = spread, parent_type, fragments) do
    case Map.fetch(fragments, spread.name) do
      {:ok, fragment} ->
        validate_type_condition(
          ctx,
          spread,
          fragment.type_condition.name,
          parent_type,
          ctx.schema
        )

      :error ->
        ctx
    end
  end

  defp validate_type_condition(ctx, frag, type_name, parent_type, schema) do
    case Schema.get_type(schema, type_name) do
      {:ok, _type} ->
        check_type_applicability(ctx, frag, type_name, parent_type, schema)

      :error ->
        Context.add_error(
          ctx,
          "type \"#{type_name}\" in type condition does not exist in the schema",
          frag
        )
    end
  end

  defp check_type_applicability(ctx, _frag, _type_name, nil, _schema), do: ctx

  defp check_type_applicability(ctx, frag, type_name, parent_type, schema) do
    if types_applicable?(type_name, parent_type, schema) do
      ctx
    else
      Context.add_error(
        ctx,
        "type \"#{type_name}\" is not applicable to \"#{parent_type}\"",
        frag
      )
    end
  end

  defp types_applicable?(type_name, parent_type, schema) do
    type_name == parent_type or
      member_of_abstract_type?(type_name, parent_type, schema) or
      share_abstract_member?(type_name, parent_type, schema)
  end

  defp member_of_abstract_type?(type_name, parent_type, schema) do
    case Schema.get_type(schema, parent_type) do
      {:ok, parent} -> type_name in parent.possible_types
      :error -> false
    end
  end

  defp share_abstract_member?(type_name, parent_type, schema) do
    type_possible = possible_types_for(type_name, schema)
    parent_possible = possible_types_for(parent_type, schema)

    not MapSet.disjoint?(MapSet.new(type_possible), MapSet.new(parent_possible))
  end

  defp possible_types_for(type_name, schema) do
    case Schema.get_type(schema, type_name) do
      {:ok, %{kind: kind} = type} when kind in [:union, :interface] ->
        type.possible_types

      {:ok, _type} ->
        [type_name]

      :error ->
        []
    end
  end
end
