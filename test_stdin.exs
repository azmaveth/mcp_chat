#!/usr/bin/env elixir

# Test basic stdin reading
IO.puts("Testing stdin reading...")

# Check stdin status
stdin_opts = :io.getopts(:standard_io)
IO.puts("Stdin options: #{inspect(stdin_opts)}")

# Try reading with IO.gets
IO.write("Type something and press Enter: ")
case IO.gets("") do
  :eof -> 
    IO.puts("\nGot EOF from IO.gets")
  {:error, reason} ->
    IO.puts("\nError from IO.gets: #{inspect(reason)}")
  data ->
    IO.puts("Got data from IO.gets: #{inspect(data)}")
end