defmodule TypedGql.Language.SchemaDefinition do
  @moduledoc """
  A schema definition: the root operation types a service exposes.

  The parser emits `TypedGql.Language.SchemaDeclaration` for the `schema { ... }`
  block; this node stays in the definition union for compatibility.
  """
  use TypedStructor

  typed_structor do
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :fields, [TypedGql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.SchemaDeclaration do
  @moduledoc """
  A `schema { ... }` block declaring which types serve as the query, mutation
  and subscription roots.
  """
  use TypedStructor

  typed_structor do
    field :description, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :fields, [TypedGql.Language.FieldDefinition.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.DirectiveDefinition do
  @moduledoc """
  A `directive @name on ...` definition: where a custom directive may be
  applied and whether it may repeat.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :arguments, [TypedGql.Language.InputValueDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :locations, [atom()], default: []
    field :repeatable, boolean(), default: false
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.TypeExtensionDefinition do
  @moduledoc """
  An `extend` definition, adding members to a type declared elsewhere.
  """
  use TypedStructor

  typed_structor do
    field :definition, TypedGql.Language.ObjectTypeDefinition.t()
    field :loc, map(), default: %{line: nil}
  end
end
