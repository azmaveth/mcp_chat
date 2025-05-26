#!/usr/bin/env elixir
# Run with: elixir examples/notifications_demo.exs

# This example demonstrates the new MCP v0.2.0 features:
# - Progress notifications
# - Change notifications
# - Server-side LLM sampling

defmodule NotificationsDemo do
  @moduledoc """
  Demo of MCP Chat's notification features using ex_mcp v0.2.0.
  """
  
  def run() do
    IO.puts("\n🔔 MCP Notifications Demo\n")
    
    # Start required processes
    {:ok, _} = MCPChat.Config.start_link()
    {:ok, _} = MCPChat.MCP.NotificationRegistry.start_link()
    {:ok, _} = MCPChat.MCP.ProgressTracker.start_link()
    
    # Enable notifications
    enable_notifications()
    
    show_menu()
  end
  
  defp show_menu() do
    IO.puts("""
    
    Choose a demo:
    1. Progress Tracking Demo
    2. Change Notifications Demo
    3. Server-side LLM Sampling Demo
    4. Exit
    
    """)
    
    case IO.gets("Enter choice (1-4): ") |> String.trim() do
      "1" -> demo_progress()
      "2" -> demo_changes()
      "3" -> demo_sampling()
      "4" -> IO.puts("Goodbye!")
      _ -> 
        IO.puts("Invalid choice")
        show_menu()
    end
  end
  
  defp demo_progress() do
    IO.puts("\n📊 Progress Tracking Demo\n")
    
    # Simulate a long-running operation
    {:ok, token} = MCPChat.MCP.ProgressTracker.start_operation(
      "demo_server",
      "process_large_file",
      100
    )
    
    IO.puts("Started operation with token: #{token}")
    IO.puts("Simulating progress updates...\n")
    
    # Simulate progress updates
    for i <- 1..10 do
      progress = i * 10
      MCPChat.MCP.ProgressTracker.update_progress(token, progress, 100)
      
      # Show progress bar
      show_progress_bar(progress, 100)
      Process.sleep(500)
    end
    
    IO.puts("\n✅ Operation completed!")
    
    # Show final status
    case MCPChat.MCP.ProgressTracker.get_operation(token) do
      nil -> IO.puts("Operation not found")
      op -> 
        IO.puts("Final status: #{op.status}")
        IO.puts("Duration: #{DateTime.diff(op.updated_at, op.started_at)}s")
    end
    
    show_menu()
  end
  
  defp demo_changes() do
    IO.puts("\n🔄 Change Notifications Demo\n")
    
    # Create a test notification handler that prints changes
    defmodule DemoChangeHandler do
      @behaviour MCPChat.MCP.NotificationHandler
      
      def init(_args), do: {:ok, %{}}
      
      def handle_notification(server, type, params, state) do
        IO.puts("\n📢 Notification received!")
        IO.puts("   Server: #{server}")
        IO.puts("   Type: #{type}")
        IO.puts("   Params: #{inspect(params)}")
        {:ok, state}
      end
    end
    
    # Register the handler
    MCPChat.MCP.NotificationRegistry.register_handler(
      DemoChangeHandler,
      [:tools_list_changed, :resources_list_changed, :prompts_list_changed]
    )
    
    IO.puts("Handler registered. Simulating notifications...\n")
    
    # Simulate notifications
    notifications = [
      {"server1", "notifications/tools/list_changed", %{}},
      {"server2", "notifications/resources/list_changed", %{}},
      {"server1", "notifications/resources/updated", %{"uri" => "file:///example.txt"}},
      {"server3", "notifications/prompts/list_changed", %{}}
    ]
    
    Enum.each(notifications, fn {server, method, params} ->
      MCPChat.MCP.NotificationRegistry.dispatch_notification(server, method, params)
      Process.sleep(1000)
    end)
    
    # Cleanup
    MCPChat.MCP.NotificationRegistry.unregister_handler(DemoChangeHandler)
    
    show_menu()
  end
  
  defp demo_sampling() do
    IO.puts("\n🤖 Server-side LLM Sampling Demo\n")
    
    IO.puts("This demo would connect to an MCP server that supports sampling.")
    IO.puts("The server would use its own LLM to generate responses.\n")
    
    # Simulated sampling request
    params = %{
      messages: [
        %{
          role: "user",
          content: %{
            type: "text",
            text: "Write a haiku about Elixir programming"
          }
        }
      ],
      includeContext: "none",
      temperature: 0.7,
      maxTokens: 100
    }
    
    IO.puts("Request parameters:")
    IO.inspect(params, pretty: true)
    
    IO.puts("\nIn a real scenario, this would call:")
    IO.puts("MCPChat.MCP.NotificationClient.create_message(client, params)")
    
    # Simulated response
    IO.puts("\nSimulated response:")
    IO.puts("""
    
    Concurrent streams flow,
    Pattern matching guides the way,
    BEAM lights up the code.
    
    Model: claude-3-haiku
    Stop reason: max_tokens
    """)
    
    show_menu()
  end
  
  defp show_progress_bar(current, total) do
    percentage = round(current / total * 100)
    bar_width = 30
    filled = round(bar_width * current / total)
    empty = bar_width - filled
    
    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    IO.write("\r[#{bar}] #{percentage}%")
  end
  
  defp enable_notifications() do
    # Register handlers
    MCPChat.MCP.NotificationRegistry.register_handler(
      MCPChat.MCP.Handlers.ProgressHandler,
      [:progress]
    )
    
    IO.puts("✓ Notifications enabled")
  end
end

# Run the demo
NotificationsDemo.run()