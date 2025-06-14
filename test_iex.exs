# Test script to check terminal detection in IEx
IO.puts("Testing terminal detection in IEx...")

# Check IO options
opts = :io.getopts(:standard_io)
IO.puts("IO options: #{inspect(opts)}")

# Check terminal status
terminal = Keyword.get(opts, :terminal, :undefined)
IO.puts("Terminal status: #{inspect(terminal)}")

# Check if it would be detected as escript
is_escript = terminal in [:ebadf, false]
IO.puts("Would be detected as escript: #{is_escript}")

# Test ExReadline detection
case :io.getopts(:standard_io) do
  opts when is_list(opts) ->
    terminal = Keyword.get(opts, :terminal, :undefined)
    IO.puts("\nDetected terminal: #{inspect(terminal)}")
    
    if terminal in [:ebadf, false] do
      IO.puts("Would use: :simple reader")
    else
      IO.puts("Would use: :advanced reader")
    end
  
  _ ->
    IO.puts("Failed to get IO opts")
end