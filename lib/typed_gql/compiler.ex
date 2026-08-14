defmodule TypedGql.Compiler do
  @moduledoc false

  alias TypedGql.EnsureTypename
  alias TypedGql.InputTypeGenerator
  alias TypedGql.Language.Fragment
  alias TypedGql.Language.ListType
  alias TypedGql.Language.NamedType
  alias TypedGql.Language.NonNullType
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Parser
  alias TypedGql.Printer
  alias TypedGql.Query
  alias TypedGql.Schema
  alias TypedGql.TypeGenerator
  alias TypedGql.Validator

  @type option() ::
          {:client_module, module()}
          | {:function_name, atom()}
          | {:scalar_types, map()}
          | {:caller_env, Macro.Env.t()}
          | {:fragments, %{String.t() => fragment_entry()}}
          | {:generation_plugins, [module()]}

  @type fragment_entry() :: %{
          source: String.t(),
          fragment: Fragment.t(),
          result_module: module()
        }

  # Dialyzer cannot trace callers of compile!/3 because it is only invoked
  # inside `quote` blocks at macro expansion time, not at runtime.
  @dialyzer [
    {:no_return, compile!: 3, compile_document!: 4, compile_fragment!: 3},
    {:no_contracts, compile!: 3, compile_document!: 4, compile_fragment!: 3}
  ]

  @doc """
  Compiles a GraphQL query string into a `%Query{}` struct.

  Runs the full compile pipeline: parse → validate → generate types.
  Raises `CompileError` on parse or validation failure.
  """
  @spec compile!(String.t(), Schema.t(), [option()]) :: Query.t()
  def compile!(query_string, schema, opts) do
    document = parse!(query_string)
    compile_document!(document, query_string, schema, opts)
  end

  @doc """
  Compiles a pre-parsed document into a `%Query{}` struct.

  Same as `compile!/3` but accepts an already-parsed document,
  avoiding a redundant parse when the caller has already parsed the query.
  """
  @spec compile_document!(TypedGql.Language.Document.t(), String.t(), Schema.t(), [option()]) ::
          Query.t()
  def compile_document!(document, _query_string, schema, opts) do
    reject_type_system_definitions!(document)

    operation =
      extract_single!(
        document,
        &match?(%OperationDefinition{}, &1),
        "no operation definition found in query",
        "multiple operation definitions found; defgql supports exactly one operation per query"
      )

    caller_env = Keyword.get(opts, :caller_env)

    raise_on_errors!(
      Validator.validate(document, schema, caller_env),
      "GraphQL validation errors",
      caller_env
    )

    client_module = Keyword.fetch!(opts, :client_module)

    generator_opts = [
      client_module: client_module,
      function_name: Keyword.fetch!(opts, :function_name),
      scalar_types: Keyword.get(opts, :scalar_types, %{}),
      fragments: opts |> registered_fragments() |> Map.merge(document_fragments(document)),
      generation_plugins: Keyword.get(opts, :generation_plugins, [])
    ]

    output_modules = TypeGenerator.generate(operation, schema, generator_opts)
    input_modules = InputTypeGenerator.generate(operation, schema, generator_opts)
    variables_module = InputTypeGenerator.generate_variables(operation, schema, generator_opts)

    %Query{
      # Only the transmitted document gains __typename. Dispatch reads it off the
      # raw response and the decoded variant is told apart by its module, so
      # injecting it into the generated struct would expose a field the query
      # never asked for — see TypedGql.EnsureTypename.
      document: document |> EnsureTypename.transform(schema) |> Printer.print(),
      operation_name: operation.name,
      operation_type: Atom.to_string(operation.operation),
      function_name: Keyword.fetch!(opts, :function_name),
      result_module: hd(output_modules),
      result_modules: output_modules,
      variables_module: variables_module,
      input_modules: input_modules,
      client_module: client_module,
      has_variables?: operation.variable_definitions != [],
      variable_docs: build_variable_docs(operation.variable_definitions)
    }
  end

  # The generator only ever needs the fragment definition, so the registry's
  # entries are unwrapped here — that is what makes a fragment defined in the
  # query string itself interchangeable with a registered one.
  defp registered_fragments(opts) do
    opts
    |> Keyword.get(:fragments, %{})
    |> Map.new(fn {name, entry} -> {name, entry.fragment} end)
  end

  # A fragment defined in the document shadows a registered one of the same
  # name: it is the definition the server will see.
  defp document_fragments(%{definitions: definitions}) do
    definitions
    |> Enum.filter(&match?(%Fragment{}, &1))
    |> Map.new(&{&1.name, &1})
  end

  @doc """
  Compiles a GraphQL fragment string into a fragment entry map.

  Parses the fragment, validates it, and generates its result modules under
  `ClientModule.Fragments.FragmentName`. Returns a map with `:source`,
  `:fragment`, and `:result_module` keys — see
  `TypedGql.TypeGenerator.generate_fragment/4` for which module
  `:result_module` names.

  Raises `CompileError` on parse or validation failure.
  """
  @spec compile_fragment!(String.t(), Schema.t(), [option()]) :: fragment_entry()
  def compile_fragment!(fragment_string, schema, opts) do
    document = parse!(fragment_string)
    reject_type_system_definitions!(document)

    fragment =
      extract_single!(
        document,
        &match?(%Fragment{}, &1),
        "no fragment definition found",
        "multiple fragment definitions found; deffragment supports exactly one fragment per call"
      )

    caller_env = Keyword.get(opts, :caller_env)

    raise_on_errors!(
      Validator.validate_fragment(document, schema, caller_env),
      "GraphQL fragment validation errors",
      caller_env
    )

    client_module = Keyword.fetch!(opts, :client_module)

    generator_opts = [
      scalar_types: Keyword.get(opts, :scalar_types, %{}),
      generation_plugins: Keyword.get(opts, :generation_plugins, []),
      # The fragment's own definition is deliberately left out: a body may only
      # spread fragments registered before it, so it can never spread itself.
      fragments: registered_fragments(opts)
    ]

    result_module =
      TypeGenerator.generate_fragment(fragment, schema, client_module, generator_opts)

    %{
      source: String.trim(fragment_string),
      fragment: fragment,
      result_module: result_module
    }
  end

  # The document is printed and sent, and a request carries executable
  # definitions only — Printer has no clause for the rest either.
  defp reject_type_system_definitions!(%{definitions: definitions}) do
    executable? = &(match?(%OperationDefinition{}, &1) or match?(%Fragment{}, &1))

    case Enum.reject(definitions, executable?) do
      [] ->
        :ok

      [definition | _rest] ->
        raise CompileError,
          description:
            "type system definitions cannot be sent in a request, found: " <>
              inspect(definition.__struct__)
    end
  end

  defp parse!(query_string) do
    case Parser.parse(query_string) do
      {:ok, document} -> document
      {:error, reason} -> raise CompileError, description: "GraphQL parse error: #{reason}"
    end
  end

  defp extract_single!(document, predicate, none_message, multiple_message) do
    case Enum.filter(document.definitions, predicate) do
      [single] ->
        single

      [] ->
        raise CompileError, description: none_message

      _multiple ->
        raise CompileError, description: multiple_message
    end
  end

  defp build_variable_docs(variable_definitions) do
    Enum.map(variable_definitions, fn var_def ->
      %{
        name: var_def.variable.name,
        type: type_to_string(var_def.type),
        required: match?(%NonNullType{}, var_def.type)
      }
    end)
  end

  defp type_to_string(%NamedType{name: name}), do: name
  defp type_to_string(%ListType{type: inner}), do: "[#{type_to_string(inner)}]"
  defp type_to_string(%NonNullType{type: inner}), do: "#{type_to_string(inner)}!"

  defp raise_on_errors!(:ok, _label, _caller_env), do: :ok

  defp raise_on_errors!({:error, errors}, label, caller_env) do
    line_offset = TypedGql.Validator.Helpers.caller_line_offset(caller_env)
    messages = Enum.map_join(errors, "\n  ", &TypedGql.Validator.Error.format(&1, line_offset))
    raise CompileError, description: "#{label}:\n  #{messages}"
  end
end
