defmodule TypedGql.Language.OperationDefinition do
  @moduledoc """
  A query, mutation or subscription operation, whether written with the
  operation keyword or in the shorthand selection-set form.
  """
  use TypedStructor

  typed_structor do
    field :operation, atom()
    field :name, String.t()
    field :description, String.t()
    field :variable_definitions, [TypedGql.Language.VariableDefinition.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :selection_set, TypedGql.Language.SelectionSet.t()
    field :shorthand, boolean()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.SelectionSet do
  @moduledoc """
  A braced block of selections requested from one type.
  """
  use TypedStructor

  typed_structor do
    field :selections, [TypedGql.Language.selection_t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.Field do
  @moduledoc """
  A field selection: a name, optional alias, arguments, directives and
  sub-selections.
  """
  use TypedStructor

  typed_structor do
    field :alias, String.t()
    field :name, String.t()
    field :arguments, [TypedGql.Language.Argument.t()], default: []
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :selection_set, TypedGql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.Argument do
  @moduledoc """
  A single argument supplied to a field or a directive.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :value, TypedGql.Language.value_t()
    field :loc, map() | tuple(), default: {}
  end
end

defmodule TypedGql.Language.Variable do
  @moduledoc """
  A use of an operation variable, written `$name`.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.VariableDefinition do
  @moduledoc """
  A variable declared in an operation's signature, with the type it must
  satisfy and the default it falls back to.
  """
  use TypedStructor

  typed_structor do
    field :variable, TypedGql.Language.Variable.t()
    field :type, TypedGql.Language.type_reference_t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :default_value, TypedGql.Language.value_t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.Directive do
  @moduledoc """
  A directive applied to a node, written `@name(...)`.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :arguments, [TypedGql.Language.Argument.t()], default: []
    field :loc, map()
  end
end

defmodule TypedGql.Language.Fragment do
  @moduledoc """
  A named fragment definition: a type condition and the selections it
  contributes wherever it is spread.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :type_condition, TypedGql.Language.NamedType.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :selection_set, TypedGql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.FragmentSpread do
  @moduledoc """
  A spread of a named fragment into a selection set, written `...Name`.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule TypedGql.Language.InlineFragment do
  @moduledoc """
  An inline fragment: an optional type condition and the selections it guards.
  """
  use TypedStructor

  typed_structor do
    field :type_condition, TypedGql.Language.NamedType.t()
    field :directives, [TypedGql.Language.Directive.t()], default: []
    field :selection_set, TypedGql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end
