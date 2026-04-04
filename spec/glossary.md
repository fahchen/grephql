| Term | Definition |
|------|------------|
| GQL sigil (~GQL) | Elixir sigil containing a GraphQL operation string; triggers compile-time validation against the introspection schema and returns a typed query struct |
| Client module | User-defined Elixir module that calls `use Grephql` to bind a schema source, compile-time options, and query definitions |
| Query struct | The compiled representation of a ~GQL sigil, containing the GraphQL document string, result type information, and schema context |
| type_style | Compile-time configuration option controlling the form of generated Elixir types: `:struct` (nested structs), `:map` (typed maps), or `:query_shape` (struct shaped by the query's selected fields) |
| Union dispatch | GraphQL union/interface type mapping: in `:struct` mode, direct struct matching (`%User{} \| %Post{}`); in `:map` mode, `__typename` key matching (`%{__typename: :user} \| %{__typename: :post}`) |
| Custom scalar mapping | User-defined configuration (in `use` options) that maps GraphQL custom scalar names to either a `Grephql.Scalar` behaviour module or a shorthand `{type, serialize_fn, deserialize_fn}` tuple. Built-in scalars are used as fallback when no explicit mapping is provided |
| Grephql.Scalar | Behaviour defining callbacks for custom scalar type mapping: `type/0` (Elixir typespec), `serialize/1` (Elixir → JSON), `deserialize/1` (JSON → Elixir) |
| source | Compile-time option specifying where to load the GraphQL introspection schema from: a file path or inline JSON string. Use `mix grephql.download_schema` to fetch from a remote endpoint |
| Introspection schema | The GraphQL schema metadata obtained via the standard introspection query, in JSON format (`{"data": {"__schema": {...}}}`) |
| Field path naming | Struct naming convention for output types where module names are derived from the query's field path: `ClientModule.FunctionName.FieldName.NestedFieldName` — provides per-query isolation so different queries selecting different fields on the same GraphQL type get independent structs. Input types use schema-level naming instead: `ClientModule.InputTypeName` |
| Grephql.Error | Fixed struct representing a GraphQL error, with fields: `message` (string), `path` (list or nil), `locations` (list or nil), `extensions` (map or nil) — follows the GraphQL spec error format |
| TypedStructor | Library used to define generated structs, providing automatic `@type t()` specs, enforced keys for non-null fields, and nullable handling for optional fields |
