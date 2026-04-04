defmodule Grephql.Language.NamedType do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.ListType do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :type, any()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.NonNullType do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :type, any()
    field :loc, map(), default: %{line: nil}
  end
end
