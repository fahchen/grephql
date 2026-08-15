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
value you want. `Ecto.Type` requires four callbacks, and the next section
explains which value reaches each one:

> #### Which callbacks run is not obvious {: .tip}
>
> Read [Which value reaches which callback](#which-value-reaches-which-callback)
> before writing one. `dump/1` receives the value `cast/1` returned rather than
> the caller's input, the response path never runs `cast/1`, and one line —
> `embed_as/1` — decides whether `dump/1` and `load/1` run at all.

```elixir
defmodule MyApp.Types.Money do
  use Ecto.Type

  # Run dump/1 and load/1 rather than routing everything through cast/1.
  def embed_as(_format), do: :dump

  # The Ecto primitive the value is stored as.
  def type, do: :decimal

  # The caller's value, in any shape you choose to accept.
  def cast(%Decimal{} = amount), do: {:ok, amount}
  def cast(amount) when is_binary(amount), do: parse(amount)
  def cast(_other), do: :error

  # The Elixir value, on its way into the request.
  def dump(%Decimal{} = amount), do: {:ok, Decimal.to_string(amount)}
  def dump(_other), do: :error

  # The server's value, on its way into the result struct.
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

### Which value reaches which callback

A value crosses your type three times, and each crossing hands it to a
different callback:

```
              caller's value        Elixir value         wire value
                     │                    │                   │
   request           ├──── cast/1 ───────▶├──── dump/1 ──────▶├───▶  server
                     │                    │                   │
   response          │                    ├◀─── load/1 ───────┤◀───  server
                     │                    │                   │
                     ╵                    ╵                   ╵
                                  kept in the struct
```

Read it column by column: the request crosses two callbacks, the response
crosses one, and nothing on the way back ever reaches the caller's-value
column.

| Callback | Receives | Returns | Runs when |
|----------|----------|---------|-----------|
| `cast/1` | whatever the caller passed as a variable | the Elixir value kept in the variables struct | `Variables.build/1`, while the changeset validates |
| `dump/1` | **that Elixir value**, not the caller's | the value put into the request JSON | while the request body is serialized |
| `load/1` | the value the server sent | the Elixir value kept in the result struct | while the response is decoded |

Two consequences are easy to get wrong:

- **The request path runs two callbacks, the response path one.** Outbound a
  value goes `cast/1` then `dump/1`; inbound it goes through `load/1` alone,
  with no `cast/1` afterwards. So `load/1` has to finish the conversion by
  itself.
- **`dump/1` never sees the caller's input.** Write its clauses against your
  own Elixir representation. The lenient "accept a string, a struct, an
  integer…" matching belongs in `cast/1`, which is the only one facing
  arbitrary caller input.

Returning `:error` costs something different from each callback:

- from `cast/1`, the call returns `{:error, %Ecto.Changeset{}}` and no HTTP
  request is made
- from `load/1`, the call returns `{:error, %TypedGql.DecodeError{}}` rather
  than raising
- from `dump/1`, the call **raises** `ArgumentError` — the value has already
  passed `cast/1` by then, so a type that accepts a value on the way in and
  rejects it on the way out is treating it as a bug in itself rather than as
  bad input. Keep `dump/1` total over whatever `cast/1` can return.

### `embed_as/1` decides whether `dump/1` and `load/1` run at all

The table above describes a type that declares

```elixir
def embed_as(_format), do: :dump
```

> #### Declare `embed_as: :dump` {: .warning}
>
> `use Ecto.Type` defaults `embed_as/1` to `:self`. Under that default TypedGql
> never calls the `dump/1` and `load/1` that `Ecto.Type` requires you to
> implement, and whatever `cast/1` returns is handed to the JSON encoder as it
> is — so a value with no encoder fails the request with a
> `Protocol.UndefinedError` that never mentions scalars.

`use Ecto.Type` does **not** default to that. It defaults `embed_as/1` to
`:self`, and TypedGql moves every value in and out of an embedded schema, so
under the default the picture collapses:

| | `embed_as: :dump` | `embed_as: :self` (the default) |
|---|---|---|
| caller's value → struct | `cast/1` | `cast/1` |
| struct → request JSON | `dump/1` | *nothing* — the value is handed to the JSON encoder as it is |
| response JSON → struct | `load/1` | `cast/1` |

So with the default, `cast/1` does all the work and the `dump/1` and `load/1`
that `Ecto.Type` requires you to implement are never called. Two things follow:

- `cast/1` receives values from **both** sources — the caller and the server —
  and cannot tell them apart, so it has to accept both shapes and cannot be
  strict about one and lenient about the other.
- whatever `cast/1` returns is what gets JSON-encoded. That is fine for a
  string or a number, and fine for `%DateTime{}` because the JSON libraries
  encode it; a struct of your own with no encoder fails the request with a
  `Protocol.UndefinedError` that says nothing about scalars.

Prefer `:dump` unless your Elixir value *is* the wire value, in which case the
required `dump/1` and `load/1` are one-liners either way. Every type TypedGql
ships declares `:dump` — its enum, union, `__typename` and `DateTime` types.

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
