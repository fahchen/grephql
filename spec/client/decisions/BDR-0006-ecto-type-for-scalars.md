---
id: BDR-0006
title: Use Ecto Type for scalar and enum serialization
status: accepted
date: 2026-04-04
summary: Use Ecto.Type behaviour for custom scalar and enum serialize/deserialize instead of a custom Grephql.Scalar behaviour
---

**Feature**: client/features/type_generation.feature
**Rule**: Custom scalar types use Ecto Type for casting, serialization, and deserialization

## Decision

Use `Ecto.Type` behaviour (`type/0`, `cast/1`, `dump/1`, `load/1`) for all custom scalar
and enum type conversions. This replaces the previously planned `Grephql.Scalar` behaviour
and shorthand `{type, serialize_fn, deserialize_fn}` tuple.

- `dump/1` — Elixir value → JSON-serializable value (for request variables)
- `load/1` — JSON value → Elixir value (for response deserialization)
- `cast/1` — External input → Elixir value (for user-facing input validation)
- `type/0` — Declares the underlying Ecto primitive type

Enum types also go through Ecto Type: atoms are dumped as uppercase strings, uppercase
strings are loaded as downcased atoms.

Built-in types are provided under `Grephql.Types.*` (e.g., `Grephql.Types.DateTime`).

## Reason

Ecto Type is a well-established Elixir convention. Reusing it means:

1. **Familiarity** — Most Elixir developers already know Ecto.Type callbacks
2. **Ecosystem compatibility** — Existing Ecto types (from libraries or user code) can be
   reused directly without wrapping
3. **No custom behaviour** — Eliminates the need to define and document `Grephql.Scalar`
4. **Unified pattern** — Both scalars and enums use the same mechanism

Ecto can be used standalone without a database — only the type system is needed.

## Rejected Alternatives

- **Custom `Grephql.Scalar` behaviour** — Would require users to learn a new API when
  Ecto.Type already covers the same use case. No advantage over Ecto.Type.
- **Shorthand `{type, ser_fn, deser_fn}` tuple** — Convenient but inconsistent with the
  Ecto Type approach. Users can define a simple Ecto Type module instead.
