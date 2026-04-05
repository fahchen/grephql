| Term | Definition |
|------|------------|
| GQL sigil (~GQL) | Uppercase Elixir sigil that returns a plain GraphQL string. Used with `defgql`/`defgqlp` to enable `mix format` formatting via `Grephql.Formatter` plugin. Does not support interpolation |
| Client module | User-defined Elixir module that calls `use Grephql` to bind a schema source, compile-time options, and query definitions |
| Query struct | The compiled representation of a `defgql`/`defgqlp` definition, containing the GraphQL document string, result type information, and schema context |
| Union dispatch | GraphQL union/interface type mapping via direct struct matching (`%User{} \| %Post{}`). Response JSON is deserialized into the matching embedded schema based on `__typename` |
| Custom scalar mapping | User-defined configuration (in `use` options) that maps GraphQL custom scalar names to Ecto Type modules implementing `Ecto.Type` behaviour (`type/0`, `cast/1`, `dump/1`, `load/1`). Built-in Ecto Types under `Grephql.Types.*` are used as fallback when no explicit mapping is provided. Enum types also use Ecto Type for atom-string serialization |
| source | Compile-time option specifying where to load the GraphQL introspection schema from: a file path or inline JSON string. Use `mix grephql.download_schema` to fetch from a remote endpoint |
| Introspection schema | The GraphQL schema metadata obtained via the standard introspection query, in JSON format (`{"data": {"__schema": {...}}}`) |
| Field path naming | Struct naming convention for output types where module names are derived from the query's field path: `ClientModule.FunctionName.FieldName.NestedFieldName` — provides per-query isolation so different queries selecting different fields on the same GraphQL type get independent structs. Input types use schema-level naming instead: `ClientModule.InputTypeName` |
| Grephql.Error | Fixed struct representing a GraphQL error, with fields: `message` (string), `path` (list or nil), `locations` (list or nil), `extensions` (map or nil) — follows the GraphQL spec error format |
| EctoTypedSchema | Library used to define generated embedded schemas, providing automatic `@type t()` specs via `typed_embedded_schema` macro. Replaces TypedStructor for struct generation |
| build/1 | Function generated on input type modules that accepts a plain map, casts it via `Ecto.Changeset`, and returns `{:ok, struct}` or `{:error, changeset}`. Allows constructing input structs from untyped data with validation |
