defmodule Grephql.Compiler do
  @moduledoc false

  alias Grephql.InputTypeGenerator
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

  # Dialyzer cannot trace callers of compile!/3 because it is only invoked
  # inside `quote` blocks at macro expansion time, not at runtime.
  @dialyzer [{:no_return, compile!: 3}, {:no_contracts, compile!: 3}]

  @doc """
  Compiles a GraphQL query string into a `%Query{}` struct.

  Runs the full compile pipeline: parse → validate → generate types.
  Raises `CompileError` on parse or validation failure.
  """
  @spec compile!(String.t(), Schema.t(), [option()]) :: Query.t()
  def compile!(query_string, schema, opts) do
    document = parse!(query_string)
    operation = extract_operation!(document)
    validate!(document, schema)

    client_module = Keyword.fetch!(opts, :client_module)

    generator_opts = [
      client_module: client_module,
      function_name: Keyword.fetch!(opts, :function_name),
      scalar_types: Keyword.get(opts, :scalar_types, %{})
    ]

    output_modules = TypeGenerator.generate(operation, schema, generator_opts)
    input_modules = InputTypeGenerator.generate(operation, schema, generator_opts)

    %Query{
      document: query_string,
      operation_name: operation.name,
      result_module: hd(output_modules),
      input_modules: input_modules,
      client_module: client_module,
      has_variables?: operation.variable_definitions != []
    }
  end

  defp parse!(query_string) do
    case Parser.parse(query_string) do
      {:ok, document} -> document
      {:error, reason} -> raise CompileError, description: "GraphQL parse error: #{reason}"
    end
  end

  defp extract_operation!(document) do
    operations =
      Enum.filter(document.definitions, &match?(%OperationDefinition{}, &1))

    case operations do
      [operation] ->
        operation

      [] ->
        raise CompileError, description: "no operation definition found in query"

      _multiple ->
        raise CompileError,
          description:
            "multiple operation definitions found; defgql supports exactly one operation per query"
    end
  end

  defp validate!(document, schema) do
    case Validator.validate(document, schema) do
      :ok ->
        :ok

      {:error, errors} ->
        messages = Enum.map_join(errors, "\n  ", & &1.message)

        raise CompileError,
          description: "GraphQL validation errors:\n  #{messages}"
    end
  end
end
