defmodule Grephql.Language.IntValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, integer()
    field :loc, map()
  end
end

defmodule Grephql.Language.FloatValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, float()
    field :loc, map()
  end
end

defmodule Grephql.Language.StringValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :loc, map()
  end
end

defmodule Grephql.Language.BooleanValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, boolean()
    field :loc, map()
  end
end

defmodule Grephql.Language.NullValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :loc, map()
  end
end

defmodule Grephql.Language.EnumValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.ListValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :values, [Grephql.Language.value_t()], default: []
    field :loc, map()
  end
end

defmodule Grephql.Language.ObjectValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :fields, [Grephql.Language.ObjectField.t()], default: []
    field :loc, map()
  end
end

defmodule Grephql.Language.ObjectField do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :value, Grephql.Language.value_t()
    field :loc, map(), default: %{line: nil}
  end
end
