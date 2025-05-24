defmodule MCPChat.CLI.SimpleLineReaderTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias MCPChat.CLI.SimpleLineReader

  describe "read_line/1" do
    test "reads a simple line of input" do
      input = "Hello, world!\n"

      output =
        capture_io(input, fn ->
          result = SimpleLineReader.read_line("> ")
          send(self(), {:result, result})
        end)

      assert output =~ "> "
      assert_receive {:result, "Hello, world!"}
    end

    test "handles empty input" do
      input = "\n"

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("> ")
        send(self(), {:result, result})
      end)

      assert_receive {:result, ""}
    end

    test "handles EOF" do
      input = ""

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("> ")
        send(self(), {:result, result})
      end)

      assert_receive {:result, :eof}
    end

    test "handles multi-word input" do
      input = "This is a test\n"

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("$ ")
        send(self(), {:result, result})
      end)

      assert_receive {:result, "This is a test"}
    end
  end

  describe "set_completion_fn/1" do
    test "sets custom completion function" do
      # Define a simple completion function
      completion_fn = fn prefix ->
        commands = ["/help", "/hello", "/history"]
        Enum.filter(commands, &String.starts_with?(&1, prefix))
      end

      # Since this uses GenServer, we can't directly test the state
      # Just ensure it doesn't crash
      assert :ok = SimpleLineReader.set_completion_fn(completion_fn)
    end

    test "can clear completion function" do
      SimpleLineReader.set_completion_fn(fn _ -> [] end)
      assert :ok = SimpleLineReader.set_completion_fn(nil)
    end
  end

  describe "integration" do
    test "handles special characters in input" do
      input = "Test with $pecial ch@rs!\n"

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("> ")
        send(self(), {:result, result})
      end)

      assert_receive {:result, "Test with $pecial ch@rs!"}
    end

    test "preserves whitespace" do
      input = "  spaced   input  \n"

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("> ")
        send(self(), {:result, result})
      end)

      # Note: trailing whitespace is trimmed including from end
      assert_receive {:result, "  spaced   input  "}
    end

    test "handles unicode characters" do
      input = "Hello 世界 🌍\n"

      capture_io(input, fn ->
        result = SimpleLineReader.read_line("> ")
        send(self(), {:result, result})
      end)

      assert_receive {:result, "Hello 世界 🌍"}
    end
  end
end
