---
id: BDR-0004
title: Union and interface types as direct struct match with __typename
status: accepted
date: 2026-04-04
summary: GraphQL unions/interfaces map to direct struct union (struct mode) or __typename-keyed map (map mode)
---

**Feature**: client/features/type_generation.feature
**Rule**: GraphQL unions and interfaces map to direct type union

## Context

GraphQL union types need an Elixir representation that supports safe dispatching.

## Behaviours Considered

### Option A: Direct union type
`:struct` mode: `%User{} | %Post{}` — match on struct.
`:map` mode: `%{__typename: :user, ...} | %{__typename: :post, ...}` — match on `__typename` key.

### Option B: Tagged tuple
`{:user, User.t()} | {:post, Post.t()}` — explicit tag for all modes.

## Decision

Chose Option A. Direct struct matching is more natural in Elixir — no extra
wrapper layer. For `:map` mode, `__typename` as a map key provides the same
discriminator. The result is flatter code and more idiomatic pattern matching.

## Rejected Alternatives

**Option B** — Tagged tuples add an extra layer of wrapping that makes nested
pattern matching more verbose. Since we fork the parser and have access to
`__typename` from the response, we can use it directly as a discriminator
in map mode without needing a tuple tag.
