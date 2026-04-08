# Used by "mix format"
grephql_locals = [
  deffragment: 1,
  defgql: 2,
  defgqlp: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ecto, :typed_structor, :ecto_typed_schema],
  locals_without_parens: grephql_locals,
  plugins: [Grephql.Formatter],
  export: [
    locals_without_parens: grephql_locals,
    plugins: [Grephql.Formatter]
  ]
]
