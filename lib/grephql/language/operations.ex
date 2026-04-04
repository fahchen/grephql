defmodule Grephql.Language.OperationDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :operation, atom()
    field :name, String.t()
    field :description, String.t()
    field :variable_definitions, [Grephql.Language.VariableDefinition.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :selection_set, Grephql.Language.SelectionSet.t()
    field :shorthand, boolean()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.SelectionSet do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :selections, [any()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.Field do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :alias, String.t()
    field :name, String.t()
    field :arguments, [Grephql.Language.Argument.t()], default: []
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :selection_set, Grephql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.Argument do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :value, any()
    field :loc, map() | tuple(), default: {}
  end
end

defmodule Grephql.Language.Variable do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.VariableDefinition do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :variable, Grephql.Language.Variable.t()
    field :type, any()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :default_value, any()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.Directive do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :arguments, [Grephql.Language.Argument.t()], default: []
    field :loc, map()
  end
end

defmodule Grephql.Language.Fragment do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :description, String.t()
    field :type_condition, Grephql.Language.NamedType.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :selection_set, Grephql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.FragmentSpread do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :loc, map(), default: %{line: nil}
  end
end

defmodule Grephql.Language.InlineFragment do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :type_condition, Grephql.Language.NamedType.t()
    field :directives, [Grephql.Language.Directive.t()], default: []
    field :selection_set, Grephql.Language.SelectionSet.t()
    field :loc, map(), default: %{line: nil}
  end
end
