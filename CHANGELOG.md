# Changelog

## v0.1.0

Initial release.

### Features

- **Compile-time validation** — GraphQL syntax errors and schema mismatches caught at `mix compile`
- **Typed responses** — Auto-generated Ecto embedded schemas for query results with nullability
- **Typed variables** — Input validation via Ecto changesets with generated `params()` type
- **Union/Interface support** — `__typename`-based dispatch via parameterized Ecto Type
- **Named fragments** — `deffragment` macro with auto-concatenation and nested dependency resolution
- **Custom scalars** — Map GraphQL scalars to Ecto types via `@grephql_scalars`
- **Deprecation warnings** — Compile-time warnings for deprecated fields, arguments, enum values, and input fields
- **`~GQL` sigil** — Formatter plugin for auto-formatting GraphQL in Elixir source files
- **Req integration** — Full access to Req's middleware/plugin system, including `Req.Test` for testing
- **`mix grephql.download_schema`** — Introspection-based schema download task
