defmodule MCPChat.Terminal.InteractiveTutorial do
  @moduledoc """
  Interactive tutorial system for guiding users through features.

  Provides step-by-step walkthroughs with interactive
  demonstrations and progress tracking.
  """

  use GenServer
  require Logger

  # alias MCPChat.Terminal.{DisplayOverlay, InputInterceptor, ProgressIndicator}
  # These will be used for visual display integration in the future

  # Tutorial state
  defstruct [
    # Active tutorial
    :current_tutorial,
    # Current step index
    :current_step,
    # Available tutorials
    :tutorials,
    # User progress tracking
    :progress,
    # Display overlay reference
    :display_overlay,
    # Input interceptor reference
    :input_interceptor,
    # Tutorial settings
    :settings
  ]

  # Built-in tutorials
  @tutorials %{
    getting_started: %{
      id: :getting_started,
      name: "Getting Started with MCP Chat",
      description: "Learn the basics of using MCP Chat",
      steps: [
        %{
          title: "Welcome to MCP Chat!",
          content: """
          MCP Chat is a powerful tool for interacting with AI models and MCP servers.

          This tutorial will guide you through the basic features.
          Press ENTER to continue or ESC to exit at any time.
          """,
          action: :continue
        },
        %{
          title: "Basic Commands",
          content: """
          MCP Chat uses slash commands for special actions:

          • /help - Show available commands
          • /model - Switch AI models
          • /servers - List MCP servers
          • /context - Manage conversation context

          Try typing '/help' now:
          """,
          action: :wait_for_command,
          expected: "/help"
        },
        %{
          title: "Sending Messages",
          content: """
          To chat with the AI, simply type your message and press ENTER.

          Try asking a question:
          """,
          action: :wait_for_message,
          validation_type: :non_empty
        },
        %{
          title: "Using Autocomplete",
          content: """
          MCP Chat has intelligent autocomplete to help you type faster.

          Press TAB to see suggestions for:
          • Commands
          • File paths
          • MCP tools
          • Previous inputs

          Try typing '/' and pressing TAB:
          """,
          action: :wait_for_autocomplete
        },
        %{
          title: "Multi-line Input",
          content: """
          For longer messages, you can use multi-line input:

          • End a line with \\ to continue on the next line
          • Use Shift+Enter for a new line (in supported terminals)
          • Press Enter twice to send

          Try writing a multi-line message:
          """,
          action: :wait_for_multiline
        },
        %{
          title: "Tutorial Complete!",
          content: """
          Congratulations! You've completed the getting started tutorial.

          Explore more features:
          • /tutorial advanced - Advanced features
          • /tutorial mcp - Working with MCP servers
          • /tutorial shortcuts - Keyboard shortcuts

          Happy chatting!
          """,
          action: :complete
        }
      ]
    },
    advanced: %{
      id: :advanced,
      name: "Advanced Features",
      description: "Master advanced MCP Chat features",
      steps: [
        %{
          title: "Session Management",
          content: """
          MCP Chat saves your conversations in sessions:

          • /session list - View all sessions
          • /session new - Start a new session
          • /session load <id> - Resume a session
          • /session export - Export conversation

          Sessions auto-save your progress.
          """,
          action: :continue
        },
        %{
          title: "Context Management",
          content: """
          Control what the AI remembers:

          • /context show - View current context
          • /context clear - Clear conversation history
          • /context add <file> - Add file to context
          • /context remove <id> - Remove from context

          Manage token usage efficiently!
          """,
          action: :continue
        },
        %{
          title: "Aliases and Shortcuts",
          content: """
          Create custom shortcuts:

          • /alias add gpt "/model gpt-4"
          • /alias add code "/context add *.py"
          • /alias list - View all aliases

          Try creating an alias:
          """,
          action: :wait_for_command,
          expected_prefix: "/alias add"
        }
      ]
    },
    mcp: %{
      id: :mcp,
      name: "Working with MCP Servers",
      description: "Learn to use Model Context Protocol servers",
      steps: [
        %{
          title: "MCP Servers Overview",
          content: """
          MCP servers extend MCP Chat with tools and resources:

          • File system access
          • Database queries
          • API integrations
          • Custom tools

          Let's explore MCP features!
          """,
          action: :continue
        },
        %{
          title: "Listing Servers",
          content: """
          View available MCP servers:

          /servers - List all configured servers

          Try it now:
          """,
          action: :wait_for_command,
          expected: "/servers"
        },
        %{
          title: "Using MCP Tools",
          content: """
          MCP servers provide tools you can use:

          • /tools - List available tools
          • /tool <name> - Get tool details
          • Tools are automatically available to the AI

          The AI will use tools when needed to answer questions.
          """,
          action: :continue
        }
      ]
    },
    shortcuts: %{
      id: :shortcuts,
      name: "Keyboard Shortcuts",
      description: "Master keyboard shortcuts for efficiency",
      steps: [
        %{
          title: "Navigation Shortcuts",
          content: """
          Navigate efficiently with these shortcuts:

          • ↑/↓ - Browse command history
          • ←/→ - Move cursor
          • Ctrl+A - Beginning of line
          • Ctrl+E - End of line
          • Ctrl+←/→ - Move by word
          """,
          action: :continue
        },
        %{
          title: "Editing Shortcuts",
          content: """
          Edit text quickly:

          • Ctrl+U - Clear line
          • Ctrl+W - Delete word backward
          • Ctrl+K - Delete to end of line
          • Tab - Autocomplete
          • Ctrl+L - Clear screen
          """,
          action: :continue
        },
        %{
          title: "Special Actions",
          content: """
          Special action shortcuts:

          • Ctrl+C - Cancel current input/operation
          • Ctrl+D - Exit (when line is empty)
          • Ctrl+R - Search command history
          • Escape - Clear current input
          """,
          action: :continue
        }
      ]
    }
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a tutorial.
  """
  def start_tutorial(pid \\ __MODULE__, tutorial_id) do
    GenServer.call(pid, {:start_tutorial, tutorial_id})
  end

  @doc """
  Stop the current tutorial.
  """
  def stop_tutorial(pid \\ __MODULE__) do
    GenServer.call(pid, :stop_tutorial)
  end

  @doc """
  Advance to the next step.
  """
  def next_step(pid \\ __MODULE__) do
    GenServer.call(pid, :next_step)
  end

  @doc """
  Go back to the previous step.
  """
  def previous_step(pid \\ __MODULE__) do
    GenServer.call(pid, :previous_step)
  end

  @doc """
  Get current tutorial state.
  """
  def get_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Handle user input during tutorial.
  """
  def handle_input(pid \\ __MODULE__, input) do
    GenServer.call(pid, {:handle_input, input})
  end

  @doc """
  List available tutorials.
  """
  def list_tutorials(pid \\ __MODULE__) do
    GenServer.call(pid, :list_tutorials)
  end

  @doc """
  Get user's tutorial progress.
  """
  def get_progress(pid \\ __MODULE__) do
    GenServer.call(pid, :get_progress)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Interactive Tutorial")

    settings = %{
      auto_advance: Keyword.get(opts, :auto_advance, false),
      show_progress: Keyword.get(opts, :show_progress, true),
      highlight_actions: Keyword.get(opts, :highlight_actions, true),
      save_progress: Keyword.get(opts, :save_progress, true)
    }

    # Load saved progress
    progress = load_user_progress()

    state = %__MODULE__{
      current_tutorial: nil,
      current_step: 0,
      tutorials: @tutorials,
      progress: progress,
      settings: settings
    }

    Logger.info("Interactive Tutorial initialized",
      available_tutorials: map_size(@tutorials)
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:start_tutorial, tutorial_id}, _from, state) do
    tutorial_atom = to_atom(tutorial_id)

    case Map.get(state.tutorials, tutorial_atom) do
      nil ->
        {:reply, {:error, :tutorial_not_found}, state}

      tutorial ->
        new_state = %{state | current_tutorial: tutorial, current_step: 0}

        # Mark tutorial as started
        updated_state = update_progress(new_state, :started)

        # Return first step
        step = Enum.at(tutorial.steps, 0)
        {:reply, {:ok, format_step(step, 0, length(tutorial.steps))}, updated_state}
    end
  end

  @impl true
  def handle_call(:stop_tutorial, _from, state) do
    if state.current_tutorial do
      # Save progress before stopping
      save_user_progress(state.progress)

      new_state = %{state | current_tutorial: nil, current_step: 0}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :no_tutorial_active}, state}
    end
  end

  @impl true
  def handle_call(:next_step, _from, state) do
    case state.current_tutorial do
      nil ->
        {:reply, {:error, :no_tutorial_active}, state}

      tutorial ->
        next_index = state.current_step + 1

        if next_index < length(tutorial.steps) do
          step = Enum.at(tutorial.steps, next_index)
          new_state = %{state | current_step: next_index}

          {:reply, {:ok, format_step(step, next_index, length(tutorial.steps))}, new_state}
        else
          # Tutorial completed
          completed_state = update_progress(state, :completed)
          save_user_progress(completed_state.progress)

          final_state = %{completed_state | current_tutorial: nil, current_step: 0}

          {:reply, {:completed, tutorial.id}, final_state}
        end
    end
  end

  @impl true
  def handle_call(:previous_step, _from, state) do
    case state.current_tutorial do
      nil ->
        {:reply, {:error, :no_tutorial_active}, state}

      tutorial ->
        if state.current_step > 0 do
          prev_index = state.current_step - 1
          step = Enum.at(tutorial.steps, prev_index)
          new_state = %{state | current_step: prev_index}

          {:reply, {:ok, format_step(step, prev_index, length(tutorial.steps))}, new_state}
        else
          {:reply, {:error, :at_first_step}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    tutorial_state =
      if state.current_tutorial do
        %{
          tutorial_id: state.current_tutorial.id,
          tutorial_name: state.current_tutorial.name,
          current_step: state.current_step,
          total_steps: length(state.current_tutorial.steps),
          step: Enum.at(state.current_tutorial.steps, state.current_step)
        }
      else
        nil
      end

    {:reply, tutorial_state, state}
  end

  @impl true
  def handle_call({:handle_input, input}, _from, state) do
    case state.current_tutorial do
      nil ->
        {:reply, {:error, :no_tutorial_active}, state}

      tutorial ->
        step = Enum.at(tutorial.steps, state.current_step)
        result = validate_step_input(step, input)

        case result do
          :valid ->
            # Auto-advance if configured
            if state.settings.auto_advance and step.action != :complete do
              handle_call(:next_step, nil, state)
            else
              {:reply, {:ok, :input_accepted}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}

          {:hint, hint} ->
            {:reply, {:hint, hint}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_tutorials, _from, state) do
    tutorials =
      state.tutorials
      |> Enum.map(fn {id, tutorial} ->
        completed = get_in(state.progress, [id, :completed]) || false

        %{
          id: id,
          name: tutorial.name,
          description: tutorial.description,
          steps: length(tutorial.steps),
          completed: completed
        }
      end)
      |> Enum.sort_by(& &1.name)

    {:reply, tutorials, state}
  end

  @impl true
  def handle_call(:get_progress, _from, state) do
    {:reply, state.progress, state}
  end

  # Private functions

  defp format_step(step, index, total) do
    %{
      title: step.title,
      content: step.content,
      action: step.action,
      progress: "#{index + 1}/#{total}",
      percentage: round((index + 1) / total * 100)
    }
  end

  defp validate_message_input(input, validation_type) do
    case validation_type do
      :non_empty ->
        if String.length(String.trim(input)) > 0 do
          :valid
        else
          {:hint, "Please type a message or question"}
        end

      :any ->
        :valid

      _ ->
        :valid
    end
  end

  defp validate_step_input(step, input) do
    case step.action do
      :continue ->
        # Any input continues
        :valid

      :wait_for_command ->
        expected = Map.get(step, :expected)
        expected_prefix = Map.get(step, :expected_prefix)

        cond do
          expected && input == expected -> :valid
          expected_prefix && String.starts_with?(input, expected_prefix) -> :valid
          expected -> {:hint, "Try typing: #{expected}"}
          expected_prefix -> {:hint, "Start with: #{expected_prefix}"}
          true -> :valid
        end

      :wait_for_message ->
        validation_type = Map.get(step, :validation_type, :any)
        validate_message_input(input, validation_type)

      :wait_for_autocomplete ->
        # Check if TAB was pressed (would need input interceptor integration)
        :valid

      :wait_for_multiline ->
        # Check for multi-line input
        if String.contains?(input, "\n") or String.ends_with?(input, "\\") do
          :valid
        else
          {:hint, "Try ending your line with \\ to continue on the next line"}
        end

      :complete ->
        :valid

      _ ->
        :valid
    end
  end

  defp update_progress(state, event) do
    if state.settings.save_progress and state.current_tutorial do
      tutorial_id = state.current_tutorial.id

      progress_entry =
        Map.get(state.progress, tutorial_id, %{})
        |> Map.put(:last_step, state.current_step)
        |> Map.put(:last_updated, DateTime.utc_now())
        |> Map.put(event, true)

      new_progress = Map.put(state.progress, tutorial_id, progress_entry)
      %{state | progress: new_progress}
    else
      state
    end
  end

  defp load_user_progress() do
    # Load from persistent storage
    # This would integrate with the persistence system
    %{}
  end

  defp save_user_progress(_progress) do
    # Save to persistent storage
    # This would integrate with the persistence system
    :ok
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Interactive Tutorial shutting down")
    :ok
  end
end
