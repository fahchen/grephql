defmodule Grephql.Compiler do
  @moduledoc false

  alias Grephql.InputTypeGenerator
  alias Grephql.Language.Fragment
  alias Grephql.Language.ListType
  alias Grephql.Language.NamedType
  alias Grephql.Language.NonNullType
  alias Grephql.Language.OperationDefinition
  alias Grephql.Parser
  alias Grephql.Query
  alias Grephql.Schema
  alias Grephql.TypeGenerator
  alias Grephql.Validator

  @type option() ::
          {:client_module, module()}
          | {:function_name, atom()}
          | {:scalar_types, map()}
          | {:caller_env, Macro.Env.t()}
          | {:fragments, %{String.t() => fragment_entry()}}

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
  @spec compile_document!(Grephql.Language.Document.t(), String.t(), Schema.t(), [option()]) ::
          Query.t()
  def compile_document!(document, query_string, schema, opts) do
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

    fragments = Keyword.get(opts, :fragments, %{})

    generator_opts = [
      client_module: client_module,
      function_name: Keyword.fetch!(opts, :function_name),
      scalar_types: Keyword.get(opts, :scalar_types, %{}),
      fragments: fragments
    ]

    output_modules = TypeGenerator.generate(operation, schema, generator_opts)
    input_modules = InputTypeGenerator.generate(operation, schema, generator_opts)
    variables_module = InputTypeGenerator.generate_variables(operation, schema, generator_opts)

    %Query{
      document: query_string,
      operation_name: operation.name,
      operation_type: Atom.to_string(operation.operation),
      result_module: hd(output_modules),
      result_modules: output_modules,
      variables_module: variables_module,
      input_modules: input_modules,
      client_module: client_module,
      has_variables?: operation.variable_definitions != [],
      variable_docs: build_variable_docs(operation.variable_definitions)
    }
  end

  @doc """
  Compiles a GraphQL fragment string into a fragment entry map.

  Parses the fragment, validates it, and generates a result struct module
  under `ClientModule.Fragments.FragmentName`. Returns a map with `:source`,
  `:fragment`, and `:result_module` keys.

  Raises `CompileError` on parse or validation failure.
  """
  @spec compile_fragment!(String.t(), Schema.t(), [option()]) :: fragment_entry()
  def compile_fragment!(fragment_string, schema, opts) do
    document = parse!(fragment_string)

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
    scalar_types = Keyword.get(opts, :scalar_types, %{})

    result_module = TypeGenerator.generate_fragment(fragment, schema, client_module, scalar_types)

    %{
      source: String.trim(fragment_string),
      fragment: fragment,
      result_module: result_module
    }
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
    line_offset = Grephql.Validator.Helpers.caller_line_offset(caller_env)
    messages = Enum.map_join(errors, "\n  ", &Grephql.Validator.Error.format(&1, line_offset))
    raise CompileError, description: "#{label}:\n  #{messages}"
  end
end
