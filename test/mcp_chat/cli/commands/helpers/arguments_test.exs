defmodule MCPChat.CLI.Commands.Helpers.ArgumentsTest do
  use ExUnit.Case, async: true

  alias MCPChat.CLI.Commands.Helpers.Arguments

  @moduletag :unit

  describe "parse_subcommand/2" do
    test "parses subcommand from args with default" do
      result = Arguments.parse_subcommand(["list", "items"], "help")
      assert result == {"list", ["items"]}
    end

    test "parses subcommand with no remaining args" do
      result = Arguments.parse_subcommand(["add"], "help")
      assert result == {"add", []}
    end

    test "returns default when no args provided" do
      result = Arguments.parse_subcommand([], "help")
      assert result == {"help", []}
    end

    test "returns nil default when no args and no default" do
      result = Arguments.parse_subcommand([])
      assert result == {nil, []}
    end

    test "parses multiple remaining args" do
      result = Arguments.parse_subcommand(["command", "arg1", "arg2", "arg3"])
      assert result == {"command", ["arg1", "arg2", "arg3"]}
    end
  end

  describe "parse_key_value_pairs/1" do
    test "parses empty list" do
      result = Arguments.parse_key_value_pairs([])
      assert result == {:ok, %{}}
    end

    test "parses single key-value pair" do
      result = Arguments.parse_key_value_pairs(["key=value"])
      assert result == {:ok, %{"key" => "value"}}
    end

    test "parses multiple key-value pairs" do
      result = Arguments.parse_key_value_pairs(["key1=value1", "key2=value2"])
      assert result == {:ok, %{"key1" => "value1", "key2" => "value2"}}
    end

    test "parses key-value pairs with spaces in values" do
      result = Arguments.parse_key_value_pairs(["name=John Doe", "city=New York"])
      assert result == {:ok, %{"name" => "John Doe", "city" => "New York"}}
    end

    test "parses key-value pairs with equals in values" do
      result = Arguments.parse_key_value_pairs(["formula=x=y+z", "equation=a=b*c"])
      assert result == {:ok, %{"formula" => "x=y+z", "equation" => "a=b*c"}}
    end

    test "handles empty values" do
      result = Arguments.parse_key_value_pairs(["key=", "empty="])
      assert result == {:ok, %{"key" => "", "empty" => ""}}
    end

    test "handles keys without equals sign" do
      result = Arguments.parse_key_value_pairs(["validkey=value", "invalidkey"])
      assert result == {:ok, %{"validkey" => "value", "invalidkey" => ""}}
    end

    test "overwrites duplicate keys with last value" do
      result = Arguments.parse_key_value_pairs(["key=first", "key=second"])
      assert result == {:ok, %{"key" => "second"}}
    end
  end

  describe "validate_required_args/3" do
    test "validates sufficient args" do
      result = Arguments.validate_required_args(["arg1", "arg2"], 2, "command <arg1> <arg2>")
      assert result == :ok
    end

    test "validates more than required args" do
      result = Arguments.validate_required_args(["arg1", "arg2", "arg3"], 2, "command <arg1> <arg2>")
      assert result == :ok
    end

    test "rejects insufficient args" do
      result = Arguments.validate_required_args(["arg1"], 2, "command <arg1> <arg2>")
      assert result == {:error, "Usage: command <arg1> <arg2>"}
    end

    test "rejects empty args when required" do
      result = Arguments.validate_required_args([], 1, "command <arg>")
      assert result == {:error, "Usage: command <arg>"}
    end

    test "handles zero required args" do
      result = Arguments.validate_required_args([], 0, "command")
      assert result == :ok
    end

    test "handles zero required args with extra args" do
      result = Arguments.validate_required_args(["extra"], 0, "command")
      assert result == :ok
    end
  end

  describe "validate_arg_count/3" do
    test "validates args within range" do
      result = Arguments.validate_arg_count(["arg1", "arg2"], 1..3, "command [arg1] [arg2] [arg3]")
      assert result == :ok
    end

    test "validates single arg in range" do
      result = Arguments.validate_arg_count(["arg1"], 1..3, "command [arg1] [arg2] [arg3]")
      assert result == :ok
    end

    test "validates maximum args in range" do
      result = Arguments.validate_arg_count(["arg1", "arg2", "arg3"], 1..3, "command [arg1] [arg2] [arg3]")
      assert result == :ok
    end

    test "rejects too many args" do
      result = Arguments.validate_arg_count(["arg1", "arg2", "arg3", "arg4"], 1..3, "command [arg1] [arg2] [arg3]")
      assert result == {:error, "Usage: command [arg1] [arg2] [arg3]"}
    end

    test "rejects too few args" do
      result = Arguments.validate_arg_count([], 1..3, "command [arg1] [arg2] [arg3]")
      assert result == {:error, "Usage: command [arg1] [arg2] [arg3]"}
    end
  end

  describe "parse_flags/2" do
    test "parses empty flags from empty args" do
      flag_defs = %{verbose: %{type: :boolean, default: false}}
      result = Arguments.parse_flags([], flag_defs)
      assert result == {:ok, %{verbose: false}, []}
    end

    test "parses simple boolean flags" do
      flag_defs = %{verbose: %{type: :boolean, default: false}}
      result = Arguments.parse_flags(["--verbose", "arg1"], flag_defs)
      assert result == {:ok, %{verbose: true}, ["arg1"]}
    end

    test "parses multiple boolean flags" do
      flag_defs = %{
        verbose: %{type: :boolean, default: false},
        debug: %{type: :boolean, default: false}
      }

      result = Arguments.parse_flags(["--verbose", "--debug", "arg1"], flag_defs)
      assert result == {:ok, %{verbose: true, debug: true}, ["arg1"]}
    end

    test "parses string flags with values" do
      flag_defs = %{format: %{type: :string, default: "json"}}
      result = Arguments.parse_flags(["--format", "xml", "arg1"], flag_defs)
      assert result == {:ok, %{format: "xml"}, ["arg1"]}
    end

    test "parses integer flags with values" do
      flag_defs = %{count: %{type: :integer, default: 1}}
      result = Arguments.parse_flags(["--count", "5", "arg1"], flag_defs)
      assert result == {:ok, %{count: 5}, ["arg1"]}
    end

    test "handles unknown flags as remaining args" do
      flag_defs = %{verbose: %{type: :boolean, default: false}}
      result = Arguments.parse_flags(["--unknown", "arg1"], flag_defs)
      assert result == {:ok, %{verbose: false}, ["--unknown", "arg1"]}
    end

    test "applies default values for missing flags" do
      flag_defs = %{
        verbose: %{type: :boolean, default: false},
        format: %{type: :string, default: "json"}
      }

      result = Arguments.parse_flags(["--verbose"], flag_defs)
      assert result == {:ok, %{verbose: true, format: "json"}, []}
    end
  end

  describe "parse_tool_spec/1" do
    test "parses simple tool spec" do
      result = Arguments.parse_tool_spec("server:tool")
      assert result == {:ok, {"server", "tool", %{}}}
    end

    test "parses tool spec with arguments" do
      result = Arguments.parse_tool_spec("server:tool:arg1=value1,arg2=value2")
      assert result == {:ok, {"server", "tool", %{"arg1" => "value1", "arg2" => "value2"}}}
    end

    test "parses tool spec with single argument" do
      result = Arguments.parse_tool_spec("myserver:mytool:key=value")
      assert result == {:ok, {"myserver", "mytool", %{"key" => "value"}}}
    end

    test "parses tool spec with no arguments but colon" do
      result = Arguments.parse_tool_spec("server:tool:")
      assert result == {:ok, {"server", "tool", %{}}}
    end

    test "handles empty arguments in spec" do
      result = Arguments.parse_tool_spec("server:tool:key=,empty=")
      assert result == {:ok, {"server", "tool", %{"key" => "", "empty" => ""}}}
    end

    test "handles complex argument values" do
      result = Arguments.parse_tool_spec("server:tool:path=/usr/local/bin,url=https://example.com")

      expected_args = %{
        "path" => "/usr/local/bin",
        "url" => "https://example.com"
      }

      assert result == {:ok, {"server", "tool", expected_args}}
    end

    test "rejects invalid format - only server name" do
      result = Arguments.parse_tool_spec("server")
      assert result == {:error, "Invalid tool spec format. Expected 'server:tool' or 'server:tool:args'"}
    end

    test "handles arguments with equals in values" do
      result = Arguments.parse_tool_spec("server:tool:formula=x=y+z")
      assert result == {:ok, {"server", "tool", %{"formula" => "x=y+z"}}}
    end

    test "handles multiple equals in arguments" do
      result = Arguments.parse_tool_spec("server:tool:equation=a=b*c=d,simple=value")

      expected_args = %{
        "equation" => "a=b*c=d",
        "simple" => "value"
      }

      assert result == {:ok, {"server", "tool", expected_args}}
    end
  end

  describe "parse_env_vars/1" do
    test "parses empty list" do
      result = Arguments.parse_env_vars([])
      assert result == %{}
    end

    test "parses environment variables" do
      result = Arguments.parse_env_vars(["API_KEY=secret", "DEBUG=true", "COUNT=42"])
      assert result == %{"API_KEY" => "secret", "DEBUG" => "true", "COUNT" => "42"}
    end

    test "ignores non-env-var arguments" do
      result = Arguments.parse_env_vars(["command", "API_KEY=secret", "arg1"])
      assert result == %{"API_KEY" => "secret"}
    end

    test "handles empty values" do
      result = Arguments.parse_env_vars(["EMPTY=", "BLANK="])
      assert result == %{"EMPTY" => "", "BLANK" => ""}
    end
  end

  describe "separate_env_vars/1" do
    test "separates environment variables from other args" do
      args = ["command", "API_KEY=secret", "arg1", "DEBUG=true"]
      result = Arguments.separate_env_vars(args)

      expected_env = %{"API_KEY" => "secret", "DEBUG" => "true"}
      expected_args = ["command", "arg1"]

      assert result == {expected_env, expected_args}
    end

    test "handles all env vars" do
      args = ["API_KEY=secret", "DEBUG=true"]
      result = Arguments.separate_env_vars(args)

      expected_env = %{"API_KEY" => "secret", "DEBUG" => "true"}
      expected_args = []

      assert result == {expected_env, expected_args}
    end

    test "handles no env vars" do
      args = ["command", "arg1", "arg2"]
      result = Arguments.separate_env_vars(args)

      assert result == {%{}, ["command", "arg1", "arg2"]}
    end
  end

  describe "parse_boolean/1" do
    test "parses true values" do
      true_values = ["true", "t", "yes", "y", "1", "on", "TRUE", "True"]

      for value <- true_values do
        assert Arguments.parse_boolean(value) == {:ok, true}
      end
    end

    test "parses false values" do
      false_values = ["false", "f", "no", "n", "0", "off", "FALSE", "False"]

      for value <- false_values do
        assert Arguments.parse_boolean(value) == {:ok, false}
      end
    end

    test "rejects invalid boolean values" do
      invalid_values = ["invalid", "maybe", "2", "", "null"]

      for value <- invalid_values do
        assert {:error, "Invalid boolean value: '" <> ^value <> "'"} = Arguments.parse_boolean(value)
      end
    end
  end

  describe "parse_integer/1" do
    test "parses valid integers" do
      assert Arguments.parse_integer("42") == {:ok, 42}
      assert Arguments.parse_integer("-10") == {:ok, -10}
      assert Arguments.parse_integer("0") == {:ok, 0}
    end

    test "rejects invalid integers" do
      invalid_values = ["not_a_number", "42.5", "42abc", "", "abc123"]

      for value <- invalid_values do
        assert {:error, "Invalid integer value: '" <> ^value <> "'"} = Arguments.parse_integer(value)
      end
    end
  end

  describe "parse_list/1" do
    test "parses comma-separated list" do
      result = Arguments.parse_list("a,b,c")
      assert result == ["a", "b", "c"]
    end

    test "parses single item" do
      result = Arguments.parse_list("single")
      assert result == ["single"]
    end

    test "handles empty string" do
      result = Arguments.parse_list("")
      assert result == []
    end

    test "handles whitespace-only string" do
      result = Arguments.parse_list("   ")
      assert result == []
    end

    test "trims whitespace around items" do
      result = Arguments.parse_list(" a , b , c ")
      assert result == ["a", "b", "c"]
    end

    test "handles empty items" do
      result = Arguments.parse_list("a,,b")
      assert result == ["a", "b"]
    end

    test "handles trailing comma" do
      result = Arguments.parse_list("a,b,")
      assert result == ["a", "b"]
    end
  end
end
