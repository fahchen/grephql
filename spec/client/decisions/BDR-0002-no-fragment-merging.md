---
id: BDR-0002
title: No sigil-level fragment merging
status: accepted
date: 2026-04-04
summary: Fragments reused via Elixir string interpolation instead of GraphQL fragment syntax
---

**Feature**: client/features/query_definition.feature
**Rule**: Fragments are reused via string interpolation in plain strings

## Reason

Implementing GraphQL fragment parsing and merging at the sigil level would add
significant complexity to the compiler for a feature that Elixir's string
interpolation already handles naturally. Users compose query strings using
standard Elixir mechanisms, keeping the sigil implementation focused on
validation and type generation.
