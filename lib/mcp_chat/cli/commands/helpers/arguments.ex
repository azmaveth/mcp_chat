defmodule MCPChat.CLI.Commands.Helpers.Arguments do
  @moduledoc """
  Common argument parsing utilities for CLI commands.

  This module extracts duplicated argument parsing patterns from individual command modules
  to provide consistent argument handling across the CLI interface.
  """

  @doc """
  Parses the first argument as a subcommand, with an optional default.

  ## Examples

      iex> parse_subcommand(["list", "arg1", "arg2"])
      {"list", ["arg1", "arg2"]}

      iex> parse_subcommand([], "help")
      {"help", []}
  """
  def parse_subcommand(args, default \\ nil)

  def parse_subcommand([], default) do
    {default, []}
  end

  def parse_subcommand([subcommand | rest], _default) do
    {subcommand, rest}
  end

  @doc """
  Parses arguments as key=value pairs.

  ## Examples

      iex> parse_key_value_pairs(["name=John", "age=30", "city=NYC"])
      %{"name" => "John", "age" => "30", "city" => "NYC"}

      iex> parse_key_value_pairs(["invalid", "key=value"])
      {:error, "Invalid key=value format: 'invalid'"}
  """
  def parse_key_value_pairs(args) when is_list(args) do
    try do
      pairs =
        args
        |> Enum.map(&parse_single_key_value/1)
        |> Map.new()

      {:ok, pairs}
    rescue
      error -> {:error, error.message}
    end
  end

  @doc """
  Parses command line flags based on flag definitions.

  Flag definitions should be a map where keys are flag names and values
  are maps with `:type` and optional `:default` keys.

  ## Examples

      iex> flag_defs = %{verbose: %{type: :boolean, default: false}, count: %{type: :integer, default: 1}}
      iex> parse_flags(["--verbose", "--count", "5"], flag_defs)
      {:ok, %{verbose: true, count: 5}, []}
  """
  def parse_flags(args, flag_definitions) when is_list(args) and is_map(flag_definitions) do
    try do
      {flags, remaining} = do_parse_flags(args, flag_definitions, %{}, [])

      # Apply defaults for missing flags
      final_flags =
        flag_definitions
        |> Enum.reduce(flags, fn {name, def}, acc ->
          if Map.has_key?(acc, name) do
            acc
          else
            Map.put(acc, name, Map.get(def, :default))
          end
        end)

      {:ok, final_flags, Enum.reverse(remaining)}
    rescue
      error -> {:error, error.message}
    end
  end

  @doc """
  Parses a tool specification in the format "server:tool:arg1=value1,arg2=value2".

  ## Examples

      iex> parse_tool_spec("myserver:read_file:path=/tmp/file.txt,encoding=utf8")
      {:ok, {"myserver", "read_file", %{"path" => "/tmp/file.txt", "encoding" => "utf8"}}}

      iex> parse_tool_spec("server:tool")
      {:ok, {"server", "tool", %{}}}
  """
  def parse_tool_spec(spec) when is_binary(spec) do
    case String.split(spec, ":", parts: 3) do
      [server, tool] ->
        {:ok, {server, tool, %{}}}

      [server, tool, args_str] ->
        case parse_tool_arguments(args_str) do
          {:ok, args} -> {:ok, {server, tool, args}}
          error -> error
        end

      _ ->
        {:error, "Invalid tool spec format. Expected 'server:tool' or 'server:tool:args'"}
    end
  end

  @doc """
  Validates that the required number of arguments are present.

  ## Examples

      iex> validate_required_args(["arg1", "arg2"], 2, "command <arg1> <arg2>")
      :ok

      iex> validate_required_args(["arg1"], 2, "command <arg1> <arg2>")
      {:error, "Usage: command <arg1> <arg2>"}
  """
  def validate_required_args(args, required_count, usage_string) when is_list(args) do
    if length(args) >= required_count do
      :ok
    else
      {:error, "Usage: #{usage_string}"}
    end
  end

  @doc """
  Validates that the number of arguments is within an acceptable range.

  ## Examples

      iex> validate_arg_count(["a", "b"], 1..3, "command [arg1] [arg2] [arg3]")
      :ok

      iex> validate_arg_count(["a", "b", "c", "d"], 1..3, "command [arg1] [arg2] [arg3]")
      {:error, "Usage: command [arg1] [arg2] [arg3]"}
  """
  def validate_arg_count(args, range, usage_string) when is_list(args) do
    arg_count = length(args)

    if arg_count in range do
      :ok
    else
      {:error, "Usage: #{usage_string}"}
    end
  end

  @doc """
  Parses environment variable assignments from arguments.

  ## Examples

      iex> parse_env_vars(["API_KEY=secret", "DEBUG=true", "COUNT=42"])
      %{"API_KEY" => "secret", "DEBUG" => "true", "COUNT" => "42"}
  """
  def parse_env_vars(args) when is_list(args) do
    args
    |> Enum.filter(&String.contains?(&1, "="))
    |> Enum.map(&parse_single_key_value/1)
    |> Map.new()
  end

  @doc """
  Separates environment variables from other arguments.

  ## Examples

      iex> separate_env_vars(["command", "API_KEY=secret", "arg1", "DEBUG=true"])
      {%{"API_KEY" => "secret", "DEBUG" => "true"}, ["command", "arg1"]}
  """
  def separate_env_vars(args) when is_list(args) do
    {env_args, other_args} = Enum.split_with(args, &String.contains?(&1, "="))
    env_vars = parse_env_vars(env_args)
    {env_vars, other_args}
  end

  @doc """
  Parses boolean values from string arguments.

  Recognizes common boolean representations.

  ## Examples

      iex> parse_boolean("true")
      {:ok, true}

      iex> parse_boolean("false")
      {:ok, false}

      iex> parse_boolean("invalid")
      {:error, "Invalid boolean value: 'invalid'"}
  """
  def parse_boolean(value) when is_binary(value) do
    case String.downcase(value) do
      val when val in ["true", "t", "yes", "y", "1", "on"] -> {:ok, true}
      val when val in ["false", "f", "no", "n", "0", "off"] -> {:ok, false}
      _ -> {:error, "Invalid boolean value: '#{value}'"}
    end
  end

  @doc """
  Parses integer values with error handling.

  ## Examples

      iex> parse_integer("42")
      {:ok, 42}

      iex> parse_integer("not_a_number")
      {:error, "Invalid integer value: 'not_a_number'"}
  """
  def parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid integer value: '#{value}'"}
    end
  end

  @doc """
  Parses a comma-separated list of values.

  ## Examples

      iex> parse_list("a,b,c")
      ["a", "b", "c"]

      iex> parse_list("single")
      ["single"]

      iex> parse_list("")
      []
  """
  def parse_list(value) when is_binary(value) do
    if String.trim(value) == "" do
      []
    else
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end
  end

  # Private helper functions

  defp parse_single_key_value(pair) when is_binary(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] ->
        {String.trim(key), String.trim(value)}

      [key] ->
        {String.trim(key), ""}
    end
  end

  defp parse_tool_arguments(args_str) when is_binary(args_str) do
    if String.trim(args_str) == "" do
      {:ok, %{}}
    else
      try do
        args =
          args_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&parse_single_key_value/1)
          |> Map.new()

        {:ok, args}
      rescue
        ArgumentError -> {:error, "Invalid argument format in tool spec"}
      end
    end
  end

  defp do_parse_flags([], _flag_defs, flags, remaining) do
    {flags, remaining}
  end

  defp do_parse_flags([arg | rest], flag_defs, flags, remaining) do
    cond do
      String.starts_with?(arg, "--") ->
        flag_name = String.slice(arg, 2..-1//1) |> String.to_atom()

        case Map.get(flag_defs, flag_name) do
          nil ->
            # Unknown flag, treat as remaining argument
            do_parse_flags(rest, flag_defs, flags, [arg | remaining])

          %{type: :boolean} ->
            new_flags = Map.put(flags, flag_name, true)
            do_parse_flags(rest, flag_defs, new_flags, remaining)

          %{type: type} when type in [:string, :integer] ->
            case rest do
              [value | rest2] ->
                parsed_value = parse_flag_value(value, type)
                new_flags = Map.put(flags, flag_name, parsed_value)
                do_parse_flags(rest2, flag_defs, new_flags, remaining)

              [] ->
                raise ArgumentError, "Flag --#{flag_name} requires a value"
            end
        end

      String.starts_with?(arg, "-") ->
        # Single character flags not implemented yet, treat as remaining
        do_parse_flags(rest, flag_defs, flags, [arg | remaining])

      true ->
        # Regular argument
        do_parse_flags(rest, flag_defs, flags, [arg | remaining])
    end
  end

  defp parse_flag_value(value, :string), do: value

  defp parse_flag_value(value, :integer) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise ArgumentError, "Invalid integer value: '#{value}'"
    end
  end
end
