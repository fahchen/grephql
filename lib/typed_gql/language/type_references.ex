defmodule TypedGql.Language.NamedType do
  @moduledoc """
  A type referred to by name, such as `User`.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.ListType do
  @moduledoc """
  A list type, written `[Type]`.
  """
  use TypedStructor

  typed_structor do
    field :type, TypedGql.Language.type_reference_t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.NonNullType do
  @moduledoc """
  A non-null type, written `Type!`.
  """
  use TypedStructor

  typed_structor do
    field :type, TypedGql.Language.type_reference_t()
    field :loc, map(), default: %{line: nil}
  end
end
