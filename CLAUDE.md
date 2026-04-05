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
- Always use parentheses in `@type` definitions: `@type foo() :: bar()`, not `@type foo :: bar`
- Function ordering: public functions above private. If a private function is only used by one public function, place it directly below that public function. In test files, private helpers go below test cases.
- Unused variables must have meaningful names: `_module` not `_`, `_rest` not `_`. The prefix `_` marks it unused; the name documents what it is
- Credo disables: never disable credo at file level or for an entire rule. Only use inline disables (`credo:disable-for-next-line` or `credo:disable-for-lines:N`) with a reason comment on the line above explaining why
- Run `/simplify` before every commit to review code for reuse, quality, and efficiency
- Semantic commit messages: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`
- Small commits: one logical change per commit, not multiple unrelated changes bundled together
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
