defmodule MCPChat.CLI.HelpersTest do
  use ExUnit.Case, async: true

  alias MCPChat.CLI.Helpers

  describe "parse_subcommand/2" do
    test "parses first argument as subcommand" do
      assert {"list", ["arg1", "arg2"]} = Helpers.parse_subcommand(["list", "arg1", "arg2"])
    end

    test "returns default when no arguments" do
      assert {"help", []} = Helpers.parse_subcommand([], "help")
    end

    test "returns nil default when not specified" do
      assert {nil, []} = Helpers.parse_subcommand([])
    end
  end

  describe "validate_required_args/2" do
    test "validates sufficient arguments" do
      assert :ok = Helpers.validate_required_args(["arg1", "arg2"], 2)
      assert :ok = Helpers.validate_required_args(["arg1", "arg2", "arg3"], 2)
    end

    test "rejects insufficient arguments" do
      assert {:error, "Missing required arguments"} = Helpers.validate_required_args(["arg1"], 2)
      assert {:error, "Missing required arguments"} = Helpers.validate_required_args([], 1)
    end
  end

  describe "format_time_ago/1" do
    test "formats recent times" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -30, :second)
      assert "30 seconds ago" = Helpers.format_time_ago(past)
    end

    test "formats minutes ago" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -90, :second)
      assert "1 minute ago" = Helpers.format_time_ago(past)
    end

    test "formats hours ago" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600, :second)
      assert "1 hour ago" = Helpers.format_time_ago(past)
    end

    test "formats days ago" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -86400, :second)
      assert "1 day ago" = Helpers.format_time_ago(past)
    end
  end

  describe "format_file_size/1" do
    test "formats bytes" do
      assert "512 B" = Helpers.format_file_size(512)
    end

    test "formats kilobytes" do
      assert "1.5 KB" = Helpers.format_file_size(1536)
    end

    test "formats megabytes" do
      assert "2.0 MB" = Helpers.format_file_size(2_097_152)
    end

    test "formats gigabytes" do
      assert "1.0 GB" = Helpers.format_file_size(1_073_741_824)
    end
  end

  describe "format_number/1" do
    test "formats numbers with thousands separators" do
      assert "1,000" = Helpers.format_number(1_000)
      assert "10,000" = Helpers.format_number(10_000)
      assert "1,000,000" = Helpers.format_number(1_000_000)
    end

    test "formats small numbers without separators" do
      assert "100" = Helpers.format_number(100)
      assert "50" = Helpers.format_number(50)
    end
  end

  describe "format_number/2" do
    test "formats percentages" do
      assert "50.0%" = Helpers.format_number(0.5, :percentage)
      assert "75.5%" = Helpers.format_number(0.755, :percentage)
    end

    test "formats currency" do
      assert "$1.5" = Helpers.format_number(1.5, :currency)
      assert "$0.005" = Helpers.format_number(0.005, :currency)
    end
  end

  describe "get_session_property/2" do
    test "returns backend for known property" do
      assert :anthropic = Helpers.get_session_property(:backend)
    end

    test "returns default for unknown property" do
      assert "default" = Helpers.get_session_property(:unknown, "default")
      assert nil == Helpers.get_session_property(:unknown)
    end
  end

  describe "validate_session/1" do
    test "validates non-empty session ID" do
      assert :ok = Helpers.validate_session("session123")
    end

    test "rejects empty session ID" do
      assert {:error, "Invalid session ID"} = Helpers.validate_session("")
    end
  end
end
