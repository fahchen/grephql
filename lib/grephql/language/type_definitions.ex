defmodule Grephql.Language.ScalarTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.ObjectTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :interfaces, [Grephql.Language.NamedType.t()], default: []
    field :fields, [Grephql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.InterfaceTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :fields, [Grephql.Language.FieldDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :interfaces, [Grephql.Language.NamedType.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.UnionTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :types, [Grephql.Language.NamedType.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.EnumTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :values, [Grephql.Language.EnumValueDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.InputObjectTypeDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :fields, [Grephql.Language.InputValueDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.FieldDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :arguments, [Grephql.Language.InputValueDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :type, Grephql.Language.type_reference_t()
    field :complexity, non_neg_integer()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.InputValueDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :type, Grephql.Language.type_reference_t()
    field :description, String.t()
    field :default_value, Grephql.Language.value_t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.EnumValueDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :description, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil, column: nil}
  end
end
