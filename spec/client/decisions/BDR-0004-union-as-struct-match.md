---
id: BDR-0004
title: Union and interface types as direct struct match
status: accepted
date: 2026-04-04
summary: GraphQL unions/interfaces map to direct struct union with pattern matching on embedded schema structs
---

**Feature**: client/features/type_generation.feature
**Rule**: GraphQL unions and interfaces map to direct struct union

## Context

GraphQL union types need an Elixir representation that supports safe dispatching.
Since we only generate embedded schema structs (no map mode), the dispatch
mechanism is straightforward struct pattern matching.

## Behaviours Considered

### Option A: Direct struct union
`%User{} | %Post{}` — match on struct. Response JSON is deserialized into the
correct embedded schema based on the `__typename` field in the response.

### Option B: Tagged tuple
`{:user, User.t()} | {:post, Post.t()}` — explicit tag wrapper.

## Decision

Chose Option A. Direct struct matching is the most natural pattern in Elixir —
no extra wrapper layer. The `__typename` field from the GraphQL response is used
internally during deserialization to select the correct embedded schema, but the
user-facing API is simply struct pattern matching.

## Rejected Alternatives

**Option B** — Tagged tuples add an extra layer of wrapping that makes nested
pattern matching more verbose. Direct struct matching is more idiomatic.
