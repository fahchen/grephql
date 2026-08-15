# Mapping Custom Scalars

GraphQL lets a schema declare scalars beyond the five the spec defines, and
every API invents its own: `GitObjectID`, `Money`, `PageInfoCursor`. TypedGql
has to know what Elixir value each one becomes, or it cannot generate a field
for it.

Most schemas need little or no configuration — TypedGql ships mappings for the
scalars that recur across APIs (listed below). Configure the `:scalars` option
for the ones that are specific to your schema.

## Configuring a scalar

`:scalars` is a compile-time option on `use TypedGql`, mapping the scalar's
name in the schema to an Ecto type:

```elixir
defmodule MyApp.GitHub do
  use TypedGql,
    otp_app: :my_app,
    source: "priv/schemas/github.json",
    scalars: %{
      "GitObjectID" => :string,
      "GitTimestamp" => :string,
      "Money" => MyApp.Types.Money
    }
end
```

The value is either a plain Ecto type (`:string`, `:integer`, `:float`,
`:boolean`, `:map`, `:date`, `:decimal`, …) or a module implementing the
`Ecto.Type` behaviour. A plain type is enough whenever the wire value is
already the Elixir value you want; write a module when it needs converting.

A scalar the schema uses but neither TypedGql nor you have mapped fails the
build rather than the request:

```
** (CompileError) unknown scalar type "Money", configure it via scalar_types
```

## Built-in mappings

These are applied automatically, so a schema using them needs no `:scalars`
entry:

| Scalar | Elixir type |
|--------|-------------|
| `String`, `ID` | `:string` |
| `Int` | `:integer` |
| `Float` | `:float` |
| `Boolean` | `:boolean` |
| `DateTime` | `TypedGql.Types.DateTime` (ISO 8601 string ↔ `%DateTime{}`) |
| `Date` | `:date` |
| `JSON`, `JSONObject` | `:map` |
| `URI`, `URL` | `:string` |
| `BigInt`, `Long` | `:integer` |
| `UnsignedInt64` | `:integer` |
| `HTML`, `Base64String` | `:string` |

`String`, `Int`, `Float`, `Boolean` and `ID` are the spec's own scalars; the
rest are conventions common enough across public APIs to be worth a default.

## Your mapping always wins

The lookup checks `:scalars` first and only then the built-in table, so
configuring a name that already has a default replaces it — for the whole
client, in both directions, for every field of that type.

Keep the built-in `DateTime`:

```elixir
# createdAt decodes to %DateTime{}
scalars: %{}
```

Or take the raw string instead:

```elixir
# createdAt stays "2025-06-01T12:00:00Z"
scalars: %{"DateTime" => :string}
```

The same applies to enums: mapping an enum's name in `:scalars` overrides the
atom conversion TypedGql would otherwise generate for it.

## Writing a scalar type

An `Ecto.Type` module converts between the JSON on the wire and the Elixir
value you want. The shortest useful one implements `type/0` and `cast/1`:

```elixir
defmodule MyApp.Types.Money do
  use Ecto.Type

  # The Ecto primitive the value is stored as.
  def type, do: :decimal

  # Runs on a variable you pass in, and on the value the server sent.
  def cast(%Decimal{} = amount), do: {:ok, amount}
  def cast(amount) when is_binary(amount), do: parse(amount)
  def cast(_other), do: :error

  def dump(%Decimal{} = amount), do: {:ok, Decimal.to_string(amount)}
  def dump(_other), do: :error

  def load(amount) when is_binary(amount), do: parse(amount)
  def load(_other), do: :error

  defp parse(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> {:ok, decimal}
      _other -> :error
    end
  end
end
```

### Which callback actually runs

This is worth knowing before you write the module, because the answer depends
on one callback you probably will not write.

`use Ecto.Type` defaults `embed_as/1` to `:self`, and TypedGql moves values in
and out of embedded schemas — so with that default **`cast/1` is the only
callback that runs, in both directions**:

- a variable is `cast/1` on the way in, and the cast value goes into the
  request JSON untouched — `dump/1` is not called
- a response value is `cast/1` on the way out of the JSON — `load/1` is not
  called

So a scalar whose wire form and Elixir form differ needs a `cast/1` that
accepts both: the Elixir value the caller passes, and the JSON value the
server sends. `Money` above does exactly that.

Declare `embed_as/1` as `:dump` when you want the conventional pair instead:

```elixir
def embed_as(_format), do: :dump
```

Then `dump/1` runs on the way into the request and `load/1` on the way out of
the response, and `cast/1` handles caller input only. TypedGql's own enum,
union and `__typename` types are written this way; `TypedGql.Types.DateTime`
keeps the `:self` default, which is why its `cast/1` and `load/1` parse the
same string.

Returning `:error` decides what a bad value costs:

- from the variable path, the call fails with an `Ecto.Changeset` error and no
  HTTP request is made
- from the response path, the call returns `{:error, %TypedGql.DecodeError{}}`
  rather than raising

## Where the mapping shows up

A configured scalar reaches every generated artifact for that client:

```elixir
defgql :get_repository, ~GQL"""
query GetRepository($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    createdAt   # DateTime  -> %DateTime{}
    url         # URI       -> String.t()
    diskUsage   # Int       -> integer()
  }
}
"""
```

- the generated struct field carries the Elixir type
- its `@type t()` names that type, so Dialyzer sees it
- the response decoder converts the value through the type
- so does a variable of that type, on its way into the request
