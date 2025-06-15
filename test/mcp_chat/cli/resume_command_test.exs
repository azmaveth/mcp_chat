defmodule MCPChat.CLI.ResumeCommandTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Commands.Utility
  alias ExLLMAdapter
  alias MCPChat.Session

  alias MCPChat.CLI.ResumeCommandTest

  setup do
    # Start session if not already started
    case Process.whereis(MCPChat.Session) do
      nil -> {:ok, _} = Session.start_link()
      _ -> :ok
    end

    # Clear any existing recovery ID
    Session.clear_last_recovery_id()

    # Mock ExLLM.StreamRecovery
    :meck.new(ExLLM.StreamRecovery, [:non_strict])

    on_exit(fn ->
      :meck.unload(ExLLM.StreamRecovery)
      Session.clear_last_recovery_id()
    end)

    :ok
  end

  describe "/resume command" do
    test "shows error when no interrupted response exists" do
      output =
        capture_io(fn ->
          Utility.handle_command("resume", [])
        end)

      assert output =~ "No interrupted response to resume"
    end

    test "shows error when recovery ID is no longer available" do
      # Set a recovery ID
      Session.set_last_recovery_id("test_recovery_123")

      # Mock empty list of recoverable streams
      :meck.expect(ExLLM.StreamRecovery, :list_recoverable_streams, fn -> [] end)

      output =
        capture_io(fn ->
          Utility.handle_command("resume", [])
        end)

      assert output =~ "Previous response is no longer recoverable"

      # Verify recovery ID was cleared
      assert Session.get_last_recovery_id() == nil
    end

    test "successfully resumes an interrupted stream" do
      recovery_id = "test_recovery_123"
      Session.set_last_recovery_id(recovery_id)

      # Mock recoverable stream info
      stream_info = %{
        id: recovery_id,
        provider: :anthropic,
        model: "claude-3-sonnet",
        chunks_received: 5,
        token_count: 100,
        error: {:network_error, "Connection lost"},
        last_chunk_at: DateTime.utc_now()
      }

      :meck.expect(ExLLM.StreamRecovery, :list_recoverable_streams, fn -> [stream_info] end)

      # Mock partial response
      chunks = [
        %{content: "This is a partial"},
        %{content: " response that was"},
        %{content: " interrupted"}
      ]

      :meck.expect(ExLLM.StreamRecovery, :get_partial_response, fn ^recovery_id ->
        {:ok, chunks}
      end)

      # Mock successful resume
      :meck.expect(ExLLM.StreamRecovery, :resume_stream, fn ^recovery_id, _opts ->
        {:ok, Stream.map([%{delta: " and now continues."}], & &1)}
      end)

      result = Utility.handle_command("resume", [])

      # Should return resume_stream tuple
      assert {:resume_stream, stream} = result

      # Verify the stream works
      chunks = Enum.to_list(stream)
      assert [%{delta: " and now continues."}] = chunks
    end

    test "shows partial content before resuming" do
      recovery_id = "test_recovery_123"
      Session.set_last_recovery_id(recovery_id)

      stream_info = %{
        id: recovery_id,
        provider: :openai,
        model: "gpt-4",
        chunks_received: 3,
        token_count: 50,
        error: {:timeout, "Request timeout"},
        last_chunk_at: DateTime.utc_now()
      }

      :meck.expect(ExLLM.StreamRecovery, :list_recoverable_streams, fn -> [stream_info] end)

      chunks = [
        %{content: "Here is the answer"},
        %{content: " to your question"}
      ]

      :meck.expect(ExLLM.StreamRecovery, :get_partial_response, fn ^recovery_id ->
        {:ok, chunks}
      end)

      :meck.expect(ExLLM.StreamRecovery, :resume_stream, fn ^recovery_id, _opts ->
        {:ok, Stream.map([%{delta: ": 42"}], & &1)}
      end)

      output =
        capture_io(fn ->
          Utility.handle_command("resume", [])
        end)

      # Should show resume info
      assert output =~ "Resuming interrupted response"
      assert output =~ "Provider: openai"
      assert output =~ "Model: gpt-4"
      assert output =~ "Chunks received: 3"
      assert output =~ "Tokens processed: 50"

      # Should show partial content
      assert output =~ "--- Partial response ---"
      assert output =~ "Here is the answer to your question"
      assert output =~ "--- Continuing... ---"
    end

    test "handles resume failure gracefully" do
      recovery_id = "test_recovery_123"
      Session.set_last_recovery_id(recovery_id)

      stream_info = %{
        id: recovery_id,
        provider: :anthropic,
        model: "claude-3-sonnet",
        chunks_received: 10,
        token_count: 200,
        error: {:api_error, %{status: 500}},
        last_chunk_at: DateTime.utc_now()
      }

      :meck.expect(ExLLM.StreamRecovery, :list_recoverable_streams, fn -> [stream_info] end)

      :meck.expect(ExLLM.StreamRecovery, :get_partial_response, fn ^recovery_id ->
        {:ok, [%{content: "Partial content"}]}
      end)

      # Mock resume failure
      :meck.expect(ExLLM.StreamRecovery, :resume_stream, fn ^recovery_id, _opts ->
        {:error, "Model no longer available"}
      end)

      output =
        capture_io(fn ->
          Utility.handle_command("resume", [])
        end)

      assert output =~ "Failed to resume: \"Model no longer available\""
    end
  end
end
