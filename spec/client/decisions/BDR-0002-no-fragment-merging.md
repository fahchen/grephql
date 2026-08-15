---
id: BDR-0002
title: The ~GQL sigil performs no fragment merging
status: superseded
date: 2026-04-04
summary: The sigil returns its string unchanged; fragment reuse and merging moved into deffragment and the generation pipeline
---

**Feature**: client/features/query_definition.feature
**Rule**: Fragments are reused via string interpolation or deffragment

## Decision

`~GQL` returns its contents unchanged. Being an uppercase sigil it does not
interpolate, and it parses nothing, so it merges nothing: composing a document
out of Elixir strings is the caller's business — with an ordinary interpolated
string, not through the sigil — and `~GQL` exists only as a hook for
`mix format`.

## Reason

Implementing GraphQL fragment parsing and merging at the sigil level would add
significant complexity to the compiler for a feature that Elixir's string
interpolation already handles naturally. Users compose query strings using
standard Elixir mechanisms, keeping the sigil implementation focused on
validation and type generation.

## Superseded

The original decision went further and kept fragments out of the library
entirely. That no longer holds:

- `deffragment` parses, validates and registers a named fragment on the client
  module, and resolves spreads transitively at compile time.
- The `normalize` step expands every spread against its parent type, so a
  fragment's fields land on the generated struct like any other selection.
- The generator implements FieldsInSetCanMerge: one response key selected from
  several places — direct fields, named fragments, repeated root fields —
  collapses into a single merged selection.

Only the statement about the sigil itself survives. See BDR-0009 for how merged
list selections lower, and the `deffragment` scenarios in
`query_definition.feature` for the reuse rules.
