#!/usr/bin/env elixir

# Simple script to test ExReadline behavior
IO.puts("Starting ExReadline test...")

# Start ExReadline
{:ok, _pid} = ExReadline.start_link()

IO.puts("ExReadline started. Type /help and press Enter:")

# Read a line
case ExReadline.read_line("Test › ") do
  :eof ->
    IO.puts("Got EOF")
  line ->
    IO.puts("Got line: #{inspect(line)}")
end

IO.puts("Test complete.")