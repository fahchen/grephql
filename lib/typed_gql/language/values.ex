defmodule TypedGql.Language.IntValue do
  @moduledoc """
  An integer literal.
  """
  use TypedStructor

  typed_structor do
    field :value, integer()
    field :loc, map()
  end
end

defmodule TypedGql.Language.FloatValue do
  @moduledoc """
  A float literal.
  """
  use TypedStructor

  typed_structor do
    field :value, float()
    field :loc, map()
  end
end

defmodule TypedGql.Language.StringValue do
  @moduledoc """
  A string literal, from either the quoted or the block-string form.
  """
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :loc, map()
  end
end

defmodule TypedGql.Language.BooleanValue do
  @moduledoc """
  A `true` or `false` literal.
  """
  use TypedStructor

  typed_structor do
    field :value, boolean()
    field :loc, map()
  end
end

defmodule TypedGql.Language.NullValue do
  @moduledoc """
  The `null` literal.
  """
  use TypedStructor

  typed_structor do
    field :loc, map()
  end
end

defmodule TypedGql.Language.EnumValue do
  @moduledoc """
  An unquoted enum member literal, such as `ACTIVE`.
  """
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :loc, map(), default: %{line: nil, column: nil}
  end
end

defmodule TypedGql.Language.ListValue do
  @moduledoc """
  A list literal, written `[...]`.
  """
  use TypedStructor

  typed_structor do
    field :values, [TypedGql.Language.value_t()], default: []
    field :loc, map()
  end
end

defmodule TypedGql.Language.ObjectValue do
  @moduledoc """
  An input object literal, written `{...}`.
  """
  use TypedStructor

  typed_structor do
    field :fields, [TypedGql.Language.ObjectField.t()], default: []
    field :loc, map()
  end
end

defmodule TypedGql.Language.ObjectField do
  @moduledoc """
  A single name/value pair inside an input object literal.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :value, TypedGql.Language.value_t()
    field :loc, map(), default: %{line: nil}
  end
end
