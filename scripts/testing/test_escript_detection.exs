IO.puts("Testing escript detection...")

# Test the detection logic
case :application.get_application() do
  {:ok, app} ->
    IO.puts("Running as application: #{inspect(app)}")
    IO.puts("Should use: advanced")
  :undefined ->
    IO.puts("Running as escript")
    IO.puts("Should use: simple")
end

# Test what's actually happening with ExReadline
processes = Process.list()
readline_processes = Enum.filter(processes, fn pid ->
  info = Process.info(pid, :registered_name)
  case info do
    {:registered_name, name} -> 
      String.contains?(to_string(name), "Readline") or
      String.contains?(to_string(name), "readline")
    _ -> false
  end
end)

IO.puts("\nReadline processes found: #{length(readline_processes)}")
Enum.each(readline_processes, fn pid ->
  IO.puts("  #{inspect(pid)} - #{inspect(Process.info(pid, :registered_name))}")
end)
