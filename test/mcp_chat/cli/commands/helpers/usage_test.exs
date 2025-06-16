defmodule MCPChat.CLI.Commands.Helpers.UsageTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias MCPChat.CLI.Commands.Helpers.Usage

  @moduletag :unit

  describe "show_command_help/3" do
    test "displays basic command help" do
      output =
        capture_io(fn ->
          Usage.show_command_help("test", "A test command")
        end)

      assert output =~ "A test command"
      assert output =~ "Usage: /test <subcommand>"
      assert output =~ "Available subcommands:"
      assert output =~ "Use '/test help' for more information"
    end

    test "displays command help with subcommands" do
      subcommands = [
        %{name: "list", description: "List items"},
        %{name: "add", description: "Add new item"},
        %{name: "remove", description: "Remove item"}
      ]

      output =
        capture_io(fn ->
          Usage.show_command_help("manage", "Manage items", subcommands)
        end)

      assert output =~ "Manage items"
      assert output =~ "Usage: /manage <subcommand>"
      assert output =~ "list"
      assert output =~ "List items"
      assert output =~ "add"
      assert output =~ "Add new item"
      assert output =~ "remove"
      assert output =~ "Remove item"
    end

    test "handles empty subcommands list" do
      output =
        capture_io(fn ->
          Usage.show_command_help("simple", "Simple command", [])
        end)

      assert output =~ "Simple command"
      assert output =~ "Usage: /simple <subcommand>"
      assert output =~ "Available subcommands:"
    end
  end

  describe "show_usage_error/1" do
    test "displays usage error message" do
      output =
        capture_io(fn ->
          Usage.show_usage_error("command <arg>")
        end)

      assert output =~ "Usage: command <arg>"
    end

    test "handles multi-line usage messages" do
      usage_msg = "command <subcommand> [options]\n\nAvailable subcommands:\n  list - List items"

      output =
        capture_io(fn ->
          Usage.show_usage_error(usage_msg)
        end)

      assert output =~ "Usage: command <subcommand> [options]"
      assert output =~ "Available subcommands:"
    end
  end

  describe "show_subcommand_list/1" do
    test "displays list of subcommands" do
      subcommands = [
        %{name: "list", description: "List items"},
        %{name: "add", description: "Add new item"},
        %{name: "remove", description: "Remove item"}
      ]

      output =
        capture_io(fn ->
          Usage.show_subcommand_list(subcommands)
        end)

      assert output =~ "list"
      assert output =~ "List items"
      assert output =~ "add"
      assert output =~ "Add new item"
      assert output =~ "remove"
      assert output =~ "Remove item"
    end

    test "displays subcommands with usage information" do
      subcommands = [
        %{name: "list", description: "List items", usage: "list [options]"},
        %{name: "add", description: "Add item", usage: "add <name>"}
      ]

      output =
        capture_io(fn ->
          Usage.show_subcommand_list(subcommands)
        end)

      assert output =~ "list"
      assert output =~ "List items"
      assert output =~ "Usage: list [options]"
      assert output =~ "add"
      assert output =~ "Add item"
      assert output =~ "Usage: add <name>"
    end

    test "handles empty subcommand list" do
      output =
        capture_io(fn ->
          Usage.show_subcommand_list([])
        end)

      assert output =~ "No subcommands available"
    end
  end

  describe "format_usage_line/3" do
    test "formats usage line with default width" do
      result = Usage.format_usage_line("list", "List all items")
      assert result == "  list            - List all items"
    end

    test "formats usage line with custom width" do
      result = Usage.format_usage_line("list", "List all items", 10)
      assert result == "  list       - List all items"
    end

    test "handles long command names" do
      result = Usage.format_usage_line("very-long-command", "Description", 20)
      assert result == "  very-long-command    - Description"
    end
  end

  describe "show_flag_help/1" do
    test "displays empty flag help" do
      output =
        capture_io(fn ->
          Usage.show_flag_help([])
        end)

      # Should not output anything for empty flags
      assert output == ""
    end

    test "displays single flag help" do
      flags = [%{name: "--verbose", description: "Enable verbose output", type: :boolean}]

      output =
        capture_io(fn ->
          Usage.show_flag_help(flags)
        end)

      assert output =~ "Options:"
      assert output =~ "--verbose"
      assert output =~ "Enable verbose output"
    end

    test "displays multiple flags with proper alignment" do
      flags = [
        %{name: "--verbose", description: "Enable verbose output", type: :boolean},
        %{name: "--quiet", description: "Suppress output", type: :boolean},
        %{name: "--format", description: "Output format", type: :string, default: "json"},
        %{name: "--count", description: "Number of items", type: :integer, default: 10}
      ]

      output =
        capture_io(fn ->
          Usage.show_flag_help(flags)
        end)

      assert output =~ "Options:"
      assert output =~ "--verbose"
      assert output =~ "--quiet"
      assert output =~ "--format"
      assert output =~ "--count"
      assert output =~ "Enable verbose output"
      assert output =~ "(string)"
      assert output =~ "[default: json]"
      assert output =~ "(integer)"
      assert output =~ "[default: 10]"
    end

    test "handles flags with no descriptions" do
      flags = [
        %{name: "--verbose", description: "Enable verbose output", type: :boolean},
        %{name: "--debug", type: :boolean},
        %{name: "--quiet", description: "", type: :boolean}
      ]

      output =
        capture_io(fn ->
          Usage.show_flag_help(flags)
        end)

      assert output =~ "--verbose"
      assert output =~ "--debug"
      assert output =~ "--quiet"
      assert output =~ "Enable verbose output"
    end
  end

  describe "show_examples/1" do
    test "displays empty examples" do
      output =
        capture_io(fn ->
          Usage.show_examples([])
        end)

      # Should not output anything for empty examples
      assert output == ""
    end

    test "displays single example" do
      examples = ["command list"]

      output =
        capture_io(fn ->
          Usage.show_examples(examples)
        end)

      assert output =~ "Examples:"
      assert output =~ "/command list"
    end

    test "displays multiple examples" do
      examples = [
        "command list",
        "command add item1",
        "command remove --force item2"
      ]

      output =
        capture_io(fn ->
          Usage.show_examples(examples)
        end)

      assert output =~ "Examples:"
      assert output =~ "/command list"
      assert output =~ "/command add item1"
      assert output =~ "/command remove --force item2"
    end
  end

  describe "show_comprehensive_help/1" do
    test "displays comprehensive help with all sections" do
      help_config = %{
        command: "manage",
        description: "Manages items in the system",
        usage: "manage <subcommand> [options]",
        subcommands: [
          %{name: "list", description: "List items"},
          %{name: "add", description: "Add item"}
        ],
        flags: [
          %{name: "--verbose", description: "Enable verbose output", type: :boolean}
        ],
        examples: [
          "manage list --verbose",
          "manage add item1"
        ],
        notes: "Additional notes about usage"
      }

      output =
        capture_io(fn ->
          Usage.show_comprehensive_help(help_config)
        end)

      assert output =~ "Manages items in the system"
      assert output =~ "Usage: /manage <subcommand> [options]"
      assert output =~ "Subcommands:"
      assert output =~ "list"
      assert output =~ "Options:"
      assert output =~ "--verbose"
      assert output =~ "Examples:"
      assert output =~ "/manage list --verbose"
      assert output =~ "Notes:"
      assert output =~ "Additional notes about usage"
    end

    test "displays minimal help with defaults" do
      help_config = %{
        command: "simple"
      }

      output =
        capture_io(fn ->
          Usage.show_comprehensive_help(help_config)
        end)

      assert output =~ "No description available"
      assert output =~ "Usage: /simple [options]"
    end
  end

  describe "show_command_not_found/2" do
    test "displays command not found with suggestions" do
      output =
        capture_io(fn ->
          Usage.show_command_not_found("lst", ["list", "last", "lost"])
        end)

      assert output =~ "Unknown subcommand: 'lst'"
      assert output =~ "Did you mean:"
      assert output =~ "Available commands:"
    end

    test "displays command not found without suggestions" do
      output =
        capture_io(fn ->
          Usage.show_command_not_found("xyz", ["list", "add", "remove"])
        end)

      assert output =~ "Unknown subcommand: 'xyz'"
      assert output =~ "Available commands: list, add, remove"
      # Should not suggest anything for very different commands
    end

    test "handles empty available commands" do
      output =
        capture_io(fn ->
          Usage.show_command_not_found("unknown", [])
        end)

      assert output =~ "Unknown subcommand: 'unknown'"
      # Should not show available commands section
    end
  end

  describe "show_invalid_argument/2" do
    test "displays invalid argument error" do
      output =
        capture_io(fn ->
          Usage.show_invalid_argument("badarg")
        end)

      assert output =~ "Invalid argument: 'badarg'"
    end

    test "displays invalid argument error with context" do
      output =
        capture_io(fn ->
          Usage.show_invalid_argument("badarg", "expected integer")
        end)

      assert output =~ "Invalid argument: 'badarg' (expected integer)"
    end
  end

  describe "show_operation_success/2" do
    test "displays success message" do
      output =
        capture_io(fn ->
          Usage.show_operation_success("create")
        end)

      assert output =~ "create completed successfully"
    end

    test "displays success message with details" do
      output =
        capture_io(fn ->
          Usage.show_operation_success("create", "Item created with ID 123")
        end)

      assert output =~ "create completed successfully: Item created with ID 123"
    end
  end

  describe "show_operation_failure/2" do
    test "displays failure message" do
      output =
        capture_io(fn ->
          Usage.show_operation_failure("create", "Invalid input")
        end)

      assert output =~ "create failed: Invalid input"
    end

    test "handles error atoms" do
      output =
        capture_io(fn ->
          Usage.show_operation_failure("connect", :timeout)
        end)

      assert output =~ "connect failed: timeout"
    end

    test "handles complex error structures" do
      error = %{code: 404, message: "Not found"}

      output =
        capture_io(fn ->
          Usage.show_operation_failure("fetch", inspect(error))
        end)

      assert output =~ "fetch failed:"
      assert output =~ "404"
      assert output =~ "Not found"
    end
  end
end
