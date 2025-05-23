defmodule MCPChat.CLI.Renderer do
  @moduledoc """
  Terminal UI rendering for the chat interface.
  """
  
  import Owl.IO, only: [puts: 1]
  
  @colors %{
    user: :cyan,
    assistant: :green,
    system: :yellow,
    error: :red,
    prompt: :blue,
    thinking: :magenta
  }
  
  def clear_screen do
    puts(IO.ANSI.clear())
    puts(IO.ANSI.cursor(0, 0))
  end
  
  def show_welcome do
    puts([
      Owl.Data.tag("╔════════════════════════════════════════╗", :cyan),
      "\n",
      Owl.Data.tag("║       Welcome to MCP Chat Client       ║", :cyan),
      "\n", 
      Owl.Data.tag("╚════════════════════════════════════════╝", :cyan),
      "\n\n",
      "Type ", 
      Owl.Data.tag("/help", :yellow),
      " for available commands or start chatting!\n"
    ])
  end
  
  def show_goodbye do
    puts([
      "\n",
      Owl.Data.tag("Goodbye! 👋", :cyan),
      "\n"
    ])
  end
  
  def format_prompt do
    [
      "\n",
      Owl.Data.tag("You", @colors.prompt),
      Owl.Data.tag(" › ", :light_black)
    ]
    |> Owl.Data.to_chardata()
    |> IO.ANSI.format()
    |> IO.iodata_to_binary()
  end
  
  def show_assistant_message(content) do
    puts([
      "\n",
      Owl.Data.tag("Assistant", @colors.assistant),
      Owl.Data.tag(" › ", :light_black),
      format_message_content(content)
    ])
  end
  
  def show_thinking do
    [
      "\n",
      Owl.Data.tag("Assistant", @colors.assistant),
      Owl.Data.tag(" › ", :light_black),
      Owl.Data.tag("Thinking", @colors.thinking),
      Owl.Data.tag("...", :light_black)
    ]
    |> Owl.Data.to_chardata()
    |> IO.write()
  end
  
  def show_stream_chunk(chunk) do
    IO.write(chunk)
  end
  
  def end_stream do
    puts("")
  end
  
  def show_error(message) do
    puts([
      "\n",
      Owl.Data.tag("Error", @colors.error),
      Owl.Data.tag(" › ", :light_black),
      Owl.Data.tag(message, @colors.error)
    ])
  end
  
  def show_info(message) do
    puts([
      "\n",
      Owl.Data.tag("Info", @colors.system),
      Owl.Data.tag(" › ", :light_black),
      message
    ])
  end
  
  def show_command_output(output) do
    puts([
      "\n",
      Owl.Box.new(output, 
        title: "Output",
        padding: 1,
        border_style: :solid_rounded,
        border_tag: :light_black
      )
    ])
  end
  
  def show_table(headers, rows) do
    puts([
      "\n",
      Owl.Table.new(rows,
        headers: headers,
        border_style: :solid_rounded
      )
    ])
  end
  
  def show_code(code) do
    puts([
      "\n",
      Owl.Box.new(code,
        padding: 1,
        border_style: :solid_rounded,
        border_tag: :light_black
      )
    ])
  end
  
  def show_text(text) do
    puts([
      "\n",
      format_message_content(text)
    ])
  end
  
  # Private Functions
  
  defp format_message_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&format_line/1)
    |> Enum.join("\n")
  end
  
  defp format_line(line) do
    cond do
      String.starts_with?(line, "```") ->
        Owl.Data.tag(line, :light_black)
      
      String.starts_with?(line, "#") ->
        Owl.Data.tag(line, :cyan)
      
      String.starts_with?(line, ">") ->
        Owl.Data.tag(line, :light_black)
      
      String.starts_with?(line, "-") or String.starts_with?(line, "*") ->
        Owl.Data.tag(line, :white)
      
      true ->
        line
    end
  end
end