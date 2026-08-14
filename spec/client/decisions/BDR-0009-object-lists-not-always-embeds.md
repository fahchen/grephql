---
id: BDR-0009
title: Only [T!]! object lists are embeds_many
status: accepted
date: 2026-08-14
summary: Lists of objects become embeds_many only when both the list and its elements are non-null; every other shape is a plain field over the parameterized Ecto.Embedded type
---

**Feature**: client/features/type_generation.feature
**Rule**: List types follow nullable composition

## Decision

A field whose GraphQL type is a list of an object, interface or union is
generated as `embeds_many` only when it is `[T!]!`. Every other shape —
`[T]`, `[T]!`, `[T!]`, and any nesting such as `[[T]]` — is generated as a
plain Ecto field whose type is `{:array, Ecto.Embedded}` (nested once per list
level), with `cardinality: :one` and `related:` naming the generated module.

This applies when the selection resolves to a single embedded schema: an
object type, or an abstract one whose selections every member shares. An
abstract selection with per-member inline fragments needs variant dispatch,
so it lowers to the parameterized `TypedGql.Types.Union` type behind
`{:array, ...}` wrappers instead — whatever the list shape, `[T!]!` included.

Its typespec is built from the GraphQL type reference
(`TypedGql.TypeMapper.list_type_ast/2`) rather than from the Ecto type, since
the Ecto type keeps none of the per-level nullability.

## Reason

1. **Ecto cannot represent a nullable many-embed.** `Ecto.Embedded.load/3` with
   `cardinality: :many` maps `nil` to `[]` and raises on a non-map element, and
   `ecto_typed_schema` pins `null: false, default: []`. So `posts: [Post]`
   returning `null` silently decoded to `[]`, and a null element — which any
   field error on an element produces — crashed decoding with an Ecto-internal
   message.
2. **`embeds_many` has no nesting.** `[[Post]]` had no representation at all and
   aborted compilation with `invalid or unknown composite {:object, "Post"}`.
3. **`Ecto.Embedded` is already a parameterized type**, so `cardinality: :one`
   gives exactly the needed semantics (`nil` → `nil`, map → struct) at every
   nesting depth, with no new type module to write and maintain.
4. **`[T!]!` keeps `embeds_many`** because that is the one shape it models
   faithfully, and it is what the common `posts: [Post!]!` schema looks like.

## Consequences

- For `[T]`, `[T]!` and `[T!]` fields the generated member is no longer an Ecto
  embed: it leaves `__schema__(:embeds)`, its struct default is `nil` rather
  than `[]`, and its typespec gains `| nil` on the list and/or its elements.
  Callers that relied on the `[]` coercion see `nil` instead — which is exactly
  the information the change restores.
- Decoding stays `Ecto.embedded_load/3` only, so `Ecto.Embedded.cast/2` (which
  rejects a list under `cardinality: :one`) is never on the decode path.
- A `[T!]!` field carrying `@skip`/`@include` is a plain field too: `embeds_many`
  pins `default: []`, which would report a list the response never carried as an
  empty one. Only an unconditional `[T!]!` keeps `embeds_many`.

## Rejected Alternatives

- **A new `TypedGql.Types.Embed` parameterized type** — three times the code of
  reusing `Ecto.Embedded`, plus a module-naming collision hazard, an eager
  module-creation ordering constraint, and a unit-test file existing only to
  cover clauses the generator never emits.
- **Keeping `embeds_many` everywhere and documenting the limitation** — a null
  list element is a legal GraphQL response, so this leaves valid responses
  undecodable.
- **Raising a `CompileError` for nested composite lists** — more code than the
  real fix, and `[[T]]` would stay unsupported.
