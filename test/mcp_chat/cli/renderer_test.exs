defmodule MCPChat.CLI.RendererTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias MCPChat.CLI.Renderer

  describe "show_welcome/0" do
    test "displays welcome message" do
      output = capture_io(fn -> Renderer.show_welcome() end)

      assert output =~ "Welcome to MCP Chat Client"
      assert output =~ "/help"
      assert output =~ "available commands"
    end
  end

  describe "show_goodbye/0" do
    test "displays goodbye message" do
      output = capture_io(fn -> Renderer.show_goodbye() end)

      assert output =~ "Goodbye! 👋"
    end
  end

  describe "format_prompt/0" do
    test "formats user prompt" do
      prompt = Renderer.format_prompt()

      assert prompt =~ "You"
      assert prompt =~ "›"
    end
  end

  describe "show_assistant_message/1" do
    test "displays simple text message" do
      output =
        capture_io(fn ->
          Renderer.show_assistant_message("Hello, world!")
        end)

      assert output =~ "Assistant"
      assert output =~ "›"
      assert output =~ "Hello, world!"
    end

    test "displays message with code block" do
      message = """
      Here's some code:
      ```elixir
      def hello do
        :world
      end
      ```
      """

      output =
        capture_io(fn ->
          Renderer.show_assistant_message(message)
        end)

      assert output =~ "Assistant"
      assert output =~ "def hello"
      assert output =~ ":world"
    end

    test "displays message with multiple paragraphs" do
      message = """
      First paragraph.

      Second paragraph.

      Third paragraph.
      """

      output =
        capture_io(fn ->
          Renderer.show_assistant_message(message)
        end)

      assert output =~ "First paragraph"
      assert output =~ "Second paragraph"
      assert output =~ "Third paragraph"
    end

    test "formats markdown headers" do
      message = """
      # Main Header
      ## Subheader
      ### Small Header
      Normal text
      """

      output =
        capture_io(fn ->
          Renderer.show_assistant_message(message)
        end)

      assert output =~ "# Main Header"
      assert output =~ "## Subheader"
      assert output =~ "### Small Header"
      assert output =~ "Normal text"
    end

    test "formats lists" do
      message = """
      - First item
      - Second item
      * Third item
      * Fourth item
      """

      output =
        capture_io(fn ->
          Renderer.show_assistant_message(message)
        end)

      assert output =~ "- First item"
      assert output =~ "- Second item"
      assert output =~ "* Third item"
      assert output =~ "* Fourth item"
    end

    test "formats quotes" do
      message = """
      > This is a quote
      > Continued quote
      Normal text
      """

      output =
        capture_io(fn ->
          Renderer.show_assistant_message(message)
        end)

      assert output =~ "> This is a quote"
      assert output =~ "> Continued quote"
      assert output =~ "Normal text"
    end
  end

  describe "show_thinking/0" do
    test "displays thinking message" do
      output =
        capture_io(fn ->
          Renderer.show_thinking()
        end)

      assert output =~ "Assistant"
      assert output =~ "›"
      assert output =~ "Thinking"
    end
  end

  describe "show_stream_chunk/1" do
    test "outputs stream chunk" do
      output =
        capture_io(fn ->
          Renderer.show_stream_chunk("Hello ")
          Renderer.show_stream_chunk("world!")
        end)

      assert output == "Hello world!"
    end
  end

  describe "end_stream/0" do
    test "ends stream with newline" do
      output =
        capture_io(fn ->
          Renderer.show_stream_chunk("Hello")
          Renderer.end_stream()
        end)

      assert output == "Hello\n"
    end
  end

  describe "show_error/1" do
    test "displays error message" do
      output =
        capture_io(fn ->
          Renderer.show_error("Something went wrong")
        end)

      assert output =~ "Error"
      assert output =~ "›"
      assert output =~ "Something went wrong"
    end

    test "displays multi-line error" do
      error = """
      Multiple things went wrong:
      - First error
      - Second error
      """

      output =
        capture_io(fn ->
          Renderer.show_error(error)
        end)

      assert output =~ "Error"
      assert output =~ "Multiple things went wrong"
      assert output =~ "First error"
      assert output =~ "Second error"
    end
  end

  describe "show_info/1" do
    test "displays info message" do
      output =
        capture_io(fn ->
          Renderer.show_info("Connection established")
        end)

      assert output =~ "Info"
      assert output =~ "›"
      assert output =~ "Connection established"
    end
  end

  describe "show_warning/1" do
    test "displays warning message" do
      output =
        capture_io(fn ->
          Renderer.show_warning("This might cause issues")
        end)

      assert output =~ "Warning"
      assert output =~ "›"
      assert output =~ "This might cause issues"
    end
  end

  describe "show_command_output/1" do
    test "displays command output in a box" do
      output =
        capture_io(fn ->
          Renderer.show_command_output("Command result")
        end)

      assert output =~ "Output"
      assert output =~ "Command result"
    end

    test "displays multi-line command output" do
      result = """
      Line 1
      Line 2
      Line 3
      """

      output =
        capture_io(fn ->
          Renderer.show_command_output(result)
        end)

      assert output =~ "Output"
      assert output =~ "Line 1"
      assert output =~ "Line 2"
      assert output =~ "Line 3"
    end
  end

  describe "show_table/2" do
    test "displays table with headers and data" do
      headers = ["Name", "Age", "City"]

      data = [
        %{"Name" => "Alice", "Age" => "30", "City" => "New York"},
        %{"Name" => "Bob", "Age" => "25", "City" => "San Francisco"},
        %{"Name" => "Charlie", "Age" => "35", "City" => "Seattle"}
      ]

      output =
        capture_io(fn ->
          Renderer.show_table(headers, data)
        end)

      # Check headers
      assert output =~ "Name"
      assert output =~ "Age"
      assert output =~ "City"

      # Check data
      assert output =~ "Alice"
      assert output =~ "30"
      assert output =~ "New York"
      assert output =~ "Bob"
      assert output =~ "25"
      assert output =~ "San Francisco"
    end

    test "handles varying column widths" do
      headers = ["Short", "Very Long Header Name"]

      data = [
        %{"Short" => "A", "Very Long Header Name" => "B"},
        %{"Short" => "Long content here", "Very Long Header Name" => "X"}
      ]

      output =
        capture_io(fn ->
          Renderer.show_table(headers, data)
        end)

      assert output =~ "Short"
      assert output =~ "Very Long Header Name"
      assert output =~ "Long content here"
    end
  end

  describe "show_code/1" do
    test "displays code in a box" do
      code = """
      def hello do
        :world
      end
      """

      output =
        capture_io(fn ->
          Renderer.show_code(code)
        end)

      assert output =~ "def hello"
      assert output =~ ":world"
      assert output =~ "end"
    end

    test "displays single line code" do
      output =
        capture_io(fn ->
          Renderer.show_code("IO.puts(\"Hello\")")
        end)

      assert output =~ "IO.puts(\"Hello\")"
    end
  end

  describe "show_text/1" do
    test "displays formatted text" do
      text = """
      # Header
      Normal text
      > Quote
      - List item
      """

      output =
        capture_io(fn ->
          Renderer.show_text(text)
        end)

      assert output =~ "# Header"
      assert output =~ "Normal text"
      assert output =~ "> Quote"
      assert output =~ "- List item"
    end
  end

  describe "clear_screen/0" do
    test "outputs clear screen sequence" do
      output =
        capture_io(fn ->
          Renderer.clear_screen()
        end)

      # Check for ANSI clear screen sequence
      assert output =~ "\e[2J"
      assert output =~ "\e[0;0H"
    end
  end
end
