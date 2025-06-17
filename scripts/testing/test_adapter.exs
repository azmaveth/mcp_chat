# Test the adapter behavior
alias MCPChat.CLI.ExReadlineAdapter

IO.puts("Starting adapter...")
{:ok, pid} = ExReadlineAdapter.start_link()
IO.puts("Adapter started: #{inspect(pid)}")

# Check which ExReadline implementation is running
IO.puts("\nChecking ExReadline processes:")
for name <- [ExReadline.SimpleReader, ExReadline.LineEditor, ExReadline] do
  case Process.whereis(name) do
    nil -> IO.puts("  #{name}: not running")
    pid -> IO.puts("  #{name}: running at #{inspect(pid)}")
  end
end

# Test reading a line
IO.puts("\nTesting read_line (type 'test' and press Enter):")
result = ExReadlineAdapter.read_line("Test> ")
IO.puts("Read result: #{inspect(result)}")
