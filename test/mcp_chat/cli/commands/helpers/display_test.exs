defmodule MCPChat.CLI.Commands.Helpers.DisplayTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias MCPChat.CLI.Commands.Helpers.Display

  @moduletag :unit

  describe "format_time_ago/1" do
    test "formats recent time correctly" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -30, :second)

      assert Display.format_time_ago(past) == "30 seconds ago"
    end

    test "formats minutes correctly" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -120, :second)

      assert Display.format_time_ago(past) == "2 minutes ago"
    end

    test "formats hours correctly" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -7_200, :second)

      assert Display.format_time_ago(past) == "2 hours ago"
    end

    test "formats days correctly" do
      now = DateTime.utc_now()
      # 2 days
      past = DateTime.add(now, -172_800, :second)

      assert Display.format_time_ago(past) == "2 days ago"
    end

    test "formats months correctly" do
      now = DateTime.utc_now()
      # 2 months
      past = DateTime.add(now, -5_184_000, :second)

      assert Display.format_time_ago(past) == "2 months ago"
    end

    test "formats years correctly" do
      now = DateTime.utc_now()
      # 2 years
      past = DateTime.add(now, -63_072_000, :second)

      assert Display.format_time_ago(past) == "2 years ago"
    end

    test "handles singular forms correctly" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -1, :second)

      assert Display.format_time_ago(past) == "1 second ago"
    end

    test "handles nil input" do
      assert Display.format_time_ago(nil) == "Never"
    end

    test "handles invalid input" do
      assert Display.format_time_ago("invalid") == "Unknown"
    end
  end

  describe "format_bytes/1" do
    test "formats bytes correctly" do
      assert Display.format_bytes(512) == "512 B"
      assert Display.format_bytes(0) == "0 B"
    end

    test "formats kilobytes correctly" do
      assert Display.format_bytes(1_024) == "1.0 KB"
      assert Display.format_bytes(1_536) == "1.5 KB"
    end

    test "formats megabytes correctly" do
      assert Display.format_bytes(1_048_576) == "1.0 MB"
      assert Display.format_bytes(2_097_152) == "2.0 MB"
    end

    test "formats gigabytes correctly" do
      assert Display.format_bytes(1_073_741_824) == "1.0 GB"
      assert Display.format_bytes(2_147_483_648) == "2.0 GB"
    end

    test "formats terabytes correctly" do
      assert Display.format_bytes(1_099_511_627_776) == "1.0 TB"
    end

    test "handles nil input" do
      assert Display.format_bytes(nil) == "0 B"
    end

    test "handles invalid input" do
      assert Display.format_bytes("invalid") == "Unknown"
    end
  end

  describe "format_number/2" do
    test "formats default numbers with commas" do
      assert Display.format_number(1_234) == "1,234"
      assert Display.format_number(1_234_567) == "1,234,567"
      assert Display.format_number(123) == "123"
    end

    test "formats compact numbers" do
      assert Display.format_number(1_500, :compact) == "1.5K"
      assert Display.format_number(1_500_000, :compact) == "1.5M"
      assert Display.format_number(1_500_000_000, :compact) == "1.5B"
      assert Display.format_number(1_500_000_000_000, :compact) == "1.5T"
      assert Display.format_number(500, :compact) == "500"
    end

    test "formats percentages" do
      assert Display.format_number(0.75, :percentage) == "75.0%"
      assert Display.format_number(0.1, :percentage) == "10.0%"
      assert Display.format_number(1.0, :percentage) == "100.0%"
    end

    test "handles float numbers" do
      assert Display.format_number(12.34, :default) == "12.34"
    end

    test "handles nil input" do
      assert Display.format_number(nil, :any) == "0"
    end

    test "handles invalid input" do
      assert Display.format_number("invalid", :compact) == "\"invalid\""
    end
  end

  describe "format_duration/1" do
    test "formats seconds only" do
      assert Display.format_duration(30) == "30s"
      assert Display.format_duration(0) == "0s"
    end

    test "formats minutes and seconds" do
      assert Display.format_duration(90) == "1m 30s"
      assert Display.format_duration(120) == "2m"
    end

    test "formats hours, minutes, and seconds" do
      assert Display.format_duration(3_661) == "1h 1m 1s"
      assert Display.format_duration(7_200) == "2h"
      assert Display.format_duration(7_260) == "2h 1m"
    end

    test "handles float input" do
      assert Display.format_duration(90.5) == "1m 31s"
    end

    test "handles invalid input" do
      assert Display.format_duration("invalid") == "0s"
    end
  end

  describe "show_table/3" do
    test "displays basic table" do
      headers = ["Name", "Age", "City"]

      rows = [
        ["Alice", "30", "NYC"],
        ["Bob", "25", "LA"]
      ]

      output =
        capture_io(fn ->
          Display.show_table(headers, rows)
        end)

      assert output =~ "Name"
      assert output =~ "Age"
      assert output =~ "City"
      assert output =~ "Alice"
      assert output =~ "Bob"
      assert output =~ "30"
      assert output =~ "25"
      # Should contain separator lines
      assert output =~ "---"
    end

    test "handles empty rows" do
      headers = ["Name", "Age"]
      rows = []

      output =
        capture_io(fn ->
          Display.show_table(headers, rows)
        end)

      assert output =~ "Name"
      assert output =~ "Age"
      assert output =~ "---"
    end

    test "handles custom separator" do
      headers = ["A", "B"]
      rows = [["1", "2"]]

      output =
        capture_io(fn ->
          Display.show_table(headers, rows, separator: " :: ")
        end)

      assert output =~ "::"
    end

    test "truncates long content" do
      headers = ["Long Content"]
      very_long_text = String.duplicate("A", 100)
      rows = [[very_long_text]]

      output =
        capture_io(fn ->
          Display.show_table(headers, rows, max_width: 20)
        end)

      assert output =~ "..."
    end
  end

  describe "show_key_value_table/2" do
    test "displays map data" do
      data = %{
        name: "Alice",
        age: 30,
        city: "NYC"
      }

      output =
        capture_io(fn ->
          Display.show_key_value_table(data)
        end)

      assert output =~ "name: Alice"
      assert output =~ "age : 30"
      assert output =~ "city: NYC"
    end

    test "displays list data" do
      data = [
        {"name", "Alice"},
        {"age", 30},
        {"city", "NYC"}
      ]

      output =
        capture_io(fn ->
          Display.show_key_value_table(data)
        end)

      assert output =~ "name: Alice"
      assert output =~ "age : 30"
      assert output =~ "city: NYC"
    end

    test "handles custom separator" do
      data = %{key: "value"}

      output =
        capture_io(fn ->
          Display.show_key_value_table(data, separator: " => ")
        end)

      assert output =~ "key => value"
    end

    test "handles complex values" do
      data = %{
        list: [1, 2, 3],
        map: %{nested: "value"},
        long_list: Enum.to_list(1..10)
      }

      output =
        capture_io(fn ->
          Display.show_key_value_table(data)
        end)

      assert output =~ "list     : [1, 2, 3]"
      # Small maps are displayed inline
      assert output =~ "map      : %{nested: \"value\"}"
      # Should show summary for long lists
      assert output =~ "long_list: [10 items]"
    end
  end

  describe "show_numbered_list/1" do
    test "displays numbered list" do
      items = ["First item", "Second item", "Third item"]

      output =
        capture_io(fn ->
          Display.show_numbered_list(items)
        end)

      assert output =~ "1. First item"
      assert output =~ "2. Second item"
      assert output =~ "3. Third item"
    end

    test "handles empty list" do
      output =
        capture_io(fn ->
          Display.show_numbered_list([])
        end)

      assert output == ""
    end
  end

  describe "show_bulleted_list/2" do
    test "displays bulleted list with default bullet" do
      items = ["First item", "Second item"]

      output =
        capture_io(fn ->
          Display.show_bulleted_list(items)
        end)

      assert output =~ "  • First item"
      assert output =~ "  • Second item"
    end

    test "displays bulleted list with custom bullet" do
      items = ["First item", "Second item"]

      output =
        capture_io(fn ->
          Display.show_bulleted_list(items, bullet: "-")
        end)

      assert output =~ "  - First item"
      assert output =~ "  - Second item"
    end

    test "handles custom indentation" do
      items = ["Item"]

      output =
        capture_io(fn ->
          Display.show_bulleted_list(items, indent: 4)
        end)

      assert output =~ "    • Item"
    end

    test "handles empty list" do
      output =
        capture_io(fn ->
          Display.show_bulleted_list([])
        end)

      assert output == ""
    end
  end

  describe "show_progress_bar/3" do
    test "displays progress bar" do
      output =
        capture_io(fn ->
          Display.show_progress_bar(7, 10, 20)
        end)

      assert output =~ "["
      assert output =~ "]"
      assert output =~ "70%"
      # Filled character
      assert output =~ "█"
      # Empty character
      assert output =~ "▒"
    end

    test "handles completed progress" do
      output =
        capture_io(fn ->
          Display.show_progress_bar(10, 10)
        end)

      assert output =~ "100%"
      # Check that it includes newline when complete
      assert String.contains?(output, "\n")
    end

    test "handles zero total" do
      output =
        capture_io(fn ->
          Display.show_progress_bar(5, 0)
        end)

      assert output =~ "0%"
    end
  end

  describe "show_status_with_icon/2" do
    test "displays success status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:success, "Operation completed")
        end)

      assert output =~ "✅ Operation completed"
    end

    test "displays error status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:error, "Something failed")
        end)

      assert output =~ "❌ Something failed"
    end

    test "displays warning status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:warning, "Be careful")
        end)

      assert output =~ "⚠️ Be careful"
    end

    test "displays info status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:info, "Information")
        end)

      assert output =~ "ℹ️ Information"
    end

    test "displays pending status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:pending, "Waiting")
        end)

      assert output =~ "⏳ Waiting"
    end

    test "displays running status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:running, "Processing")
        end)

      assert output =~ "🔄 Processing"
    end

    test "handles unknown status" do
      output =
        capture_io(fn ->
          Display.show_status_with_icon(:unknown, "Message")
        end)

      assert output =~ "• Message"
    end
  end
end
