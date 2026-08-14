defmodule TestLayoutTest do
  use ExUnit.Case, async: true

  # ExUnit selects and reports by file, not by module: a second module in a file
  # cannot be run on its own, does not show up where you expect in a failure
  # trace, and silently inherits nothing from the first one's setup. Shared
  # helpers and fixtures belong in test/support instead, which is compiled via
  # elixirc_paths(:test).
  test "every *_test.exs file defines exactly one top-level module" do
    offenders =
      "test/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.map(fn path -> {path, top_level_modules(path)} end)
      |> Enum.reject(fn {_path, modules} -> length(modules) == 1 end)

    assert offenders == []
  end

  defp top_level_modules(path) do
    ~r/^defmodule\s+([\w.]+)/m
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
  end
end
