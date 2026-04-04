# Grephql

Compile-time GraphQL client for Elixir using Ecto embedded schemas.

## Pre-commit

Run `mix precommit` before every commit. It runs:

- `compile --warnings-as-errors`
- `deps.unlock --unused`
- `format`
- `credo --strict`
- `dialyzer`
- `test`

Do not commit if `mix precommit` fails. Fix all issues first.

## Conventions

- Use `typed_structor` for internal data structs (AST, schema types)
- Use `ecto_typed_schema` (embedded schemas) for generated GraphQL types
- Use `Ecto.Type` for custom scalar and enum serialization
- Use `mimic` for mocking in tests
- Never use `any()` or `term()` in typespecs unless the value is genuinely unconstrained
- Semantic commit messages: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`
- Submit changes as PRs, not direct commits to main

## Dependencies

- `nimble_parsec` — lexer (compile-time only)
- `ecto` + `ecto_typed_schema` — embedded schemas, changesets, type system
- `typed_structor` — internal struct definitions with auto typespecs
- `req` — HTTP client for runtime query execution
- `jason` — JSON encoding/decoding
- `mimic` — test mocking
- `credo` — static analysis
- `dialyxir` — dialyzer integration
