---
id: BDR-0007
title: Use EctoTypedSchema embedded schemas and Changeset for type generation
status: accepted
date: 2026-04-04
summary: Generate Ecto embedded schemas via ecto_typed_schema for all output/input types; use Ecto.Changeset for response deserialization and input validation
---

**Feature**: client/features/type_generation.feature
**Rule**: Output types are generated as embedded schemas using EctoTypedSchema

## Decision

All generated GraphQL types (output and input) are Ecto embedded schemas defined
via `ecto_typed_schema` (`typed_embedded_schema` macro). This replaces
`typed_structor` and removes the `type_style` configuration — only struct mode exists.

**Output types:**
- Generated as embedded schemas with per-query field path naming
- Response JSON is deserialized via `Ecto.Changeset.cast/3` recursively into
  nested embedded schema structs

**Input types:**
- Generated as schema-level embedded schemas with a `build/1` function
- `build/1` accepts a plain map, casts via `Ecto.Changeset`, and returns
  `{:ok, struct}` or `{:error, changeset}`

**Removed:**
- `type_style` configuration (`:struct`, `:map`, `:query_shape`)
- `typed_structor` dependency
- Map mode for unions (only direct struct matching)

## Reason

1. **Ecto ecosystem alignment** — `embedded_schema` + `changeset` is the standard
   Elixir pattern for typed data without a database. Most developers already know it.
2. **Built-in validation** — Changeset provides required field validation, type casting,
   and error formatting out of the box. Input types get `build/1` with validation for free.
3. **Automatic typespecs** — `ecto_typed_schema` generates `@type t()` automatically,
   same as `typed_structor` but with Ecto schema integration.
4. **Simpler architecture** — One code generation path instead of three (struct/map/query_shape).

## Rejected Alternatives

- **TypedStructor** — Good for typespecs but no built-in casting/validation. Adding Ecto
  for scalars already brings the schema system — no reason to use two struct libraries.
- **type_style :map** — Maps lose struct pattern matching and have no enforceable keys.
  Embedded schemas are strictly better for type safety.
- **type_style :query_shape** — Same as struct mode with per-query field selection, which
  is already the default behaviour of field path naming. No need for a separate mode.
