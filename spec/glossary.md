| Term | Definition |
|------|------------|
| GQL sigil (~GQL) | Uppercase Elixir sigil that returns a plain GraphQL string. Used with `defgql`/`defgqlp` to enable `mix format` formatting via `TypedGql.Formatter` plugin. Does not support interpolation |
| Client module | User-defined Elixir module that calls `use TypedGql` to bind a schema source, compile-time options, and query definitions |
| Query struct | The compiled representation of a `defgql`/`defgqlp` definition, containing the GraphQL document string, the generated result/variables/input modules, and the originating client module |
| Union dispatch | GraphQL union/interface type mapping via direct struct matching (`%User{} \| %Post{}`). Response JSON is deserialized into the matching embedded schema based on `__typename` |
| Custom scalar mapping | The `:scalars` option, mapping a GraphQL scalar name to an Ecto type. See BDR-0006 |
| source | Compile-time option specifying where to load the GraphQL introspection schema from: a file path or inline JSON string. Use `mix typed_gql.download_schema` to fetch from a remote endpoint |
| Introspection schema | The GraphQL schema metadata obtained via the standard introspection query, in JSON format (`{"data": {"__schema": {...}}}`) |
| Field path naming | Struct naming convention for output types where module names are derived from the query's field path: `ClientModule.FunctionName.Result.FieldName.NestedFieldName` — provides per-query isolation so different queries selecting different fields on the same GraphQL type get independent structs. Input types use schema-level naming instead: `ClientModule.Inputs.InputTypeName` |
| TypedGql.Error | Fixed struct representing a GraphQL error, with fields: `message` (string), `path` (list or nil), `locations` (list or nil), `extensions` (map or nil) — follows the GraphQL spec error format |
| EctoTypedSchema | Library used to define generated embedded schemas, providing automatic `@type t()` specs via `typed_embedded_schema` macro. Replaces TypedStructor for struct generation |
| build/1 | Function generated on input type modules that validates a plain map and returns `{:ok, struct}` or `{:error, changeset}`. See BDR-0007 |
