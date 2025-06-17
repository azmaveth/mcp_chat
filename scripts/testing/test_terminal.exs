#!/usr/bin/env elixir

# Test terminal echo behavior

IO.puts("Testing terminal echo...")

# Save current settings
{settings, _} = System.cmd("stty", ["-g"])
settings = String.trim(settings)
IO.puts("Current settings saved: #{String.slice(settings, 0..20)}...")

# Try to disable echo
IO.puts("\nAttempting to disable echo...")
case System.cmd("stty", ["-echo"]) do
  {_, 0} -> 
    IO.puts("✓ stty -echo succeeded")
  {error, code} ->
    IO.puts("✗ stty -echo failed with code #{code}: #{error}")
end

# Also try with IO settings
old_io = :io.getopts(:standard_io)
IO.puts("Current IO opts: #{inspect(old_io)}")

:io.setopts(:standard_io, echo: false, binary: true)
IO.puts("Set echo: false on standard_io")

# Test reading
IO.puts("\nType 'test' and press Enter:")
IO.write("> ")

# Read character by character
chars = for _ <- 1..5 do
  case IO.getn("", 1) do
    :eof -> :eof
    char -> char
  end
end

IO.puts("\nRead chars: #{inspect(chars)}")

# Restore settings
System.cmd("stty", [settings])
:io.setopts(:standard_io, old_io)
IO.puts("\nSettings restored")