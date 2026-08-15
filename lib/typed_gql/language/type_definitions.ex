defmodule TypedGql.Language.ScalarTypeDefinition do
  @moduledoc """
  A `scalar` definition, introducing a leaf type whose representation the
  service decides.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.ObjectTypeDefinition do
  @moduledoc """
  A `type` definition: a concrete object type, the interfaces it implements
  and the fields it exposes.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :interfaces, [TypedGql.Language.NamedType.t()], default: []
    field :fields, [TypedGql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.InterfaceTypeDefinition do
  @moduledoc """
  An `interface` definition: the fields every implementing type must provide.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :fields, [TypedGql.Language.FieldDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :interfaces, [TypedGql.Language.NamedType.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.UnionTypeDefinition do
  @moduledoc """
  A `union` definition: the set of object types a value of this type may be.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :types, [TypedGql.Language.NamedType.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.EnumTypeDefinition do
  @moduledoc """
  An `enum` definition: the set of named values the type admits.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :values, [TypedGql.Language.EnumValueDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.InputObjectTypeDefinition do
  @moduledoc """
  An `input` definition: an object type usable only as an argument or
  variable value.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :fields, [TypedGql.Language.InputValueDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.FieldDefinition do
  @moduledoc """
  A field declared on an object or interface type, with the arguments it
  accepts and the type it returns.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :arguments, [TypedGql.Language.InputValueDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :type, TypedGql.Language.type_reference_t()
    field :complexity, non_neg_integer()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.InputValueDefinition do
  @moduledoc """
  An input position — an argument or an input object field — with the type it
  accepts and the default it falls back to.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :type, TypedGql.Language.type_reference_t()
    field :description, String.t()
    field :default_value, TypedGql.Language.value_t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.EnumValueDefinition do
  @moduledoc """
  A single member declared by an enum type definition.
  """
  use TypedStructor

  typed_structor do
    field :value, String.t()
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil, column: nil}
  end
end
