defmodule MCPChat.Terminal.KeyboardHandler do
  @moduledoc """
  Advanced keyboard input handling for terminal enhancements.

  Manages keyboard shortcuts, key mapping, and input modes
  including Vi/Emacs emulation and custom key bindings.
  """

  use GenServer
  require Logger

  # Key constants
  @escape "\e"
  @ctrl_key_offset 64

  # Keyboard handler state
  defstruct [
    # Current input mode (:normal, :insert, :command, :search)
    :mode,
    # Active key bindings
    :key_bindings,
    # Keys waiting for sequence completion
    :pending_keys,
    # Macro recording state
    :macro_recording,
    # Recent key buffer for sequences
    :key_buffer,
    # Handler settings
    :settings,
    # Map of key -> handler_pid for event routing
    :registered_handlers
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process a key input and return the appropriate action.
  """
  def process_key(pid \\ __MODULE__, key_data) do
    GenServer.call(pid, {:process_key, key_data})
  end

  @doc """
  Set the input mode (normal, insert, etc.).
  """
  def set_mode(pid \\ __MODULE__, mode) do
    GenServer.call(pid, {:set_mode, mode})
  end

  @doc """
  Get current input mode.
  """
  def get_mode(pid \\ __MODULE__) do
    GenServer.call(pid, :get_mode)
  end

  @doc """
  Register a custom key binding.
  """
  def bind_key(pid \\ __MODULE__, key_sequence, action) do
    GenServer.call(pid, {:bind_key, key_sequence, action})
  end

  @doc """
  Start/stop macro recording.
  """
  def toggle_macro_recording(pid \\ __MODULE__, register \\ "q") do
    GenServer.call(pid, {:toggle_macro_recording, register})
  end

  @doc """
  Execute a recorded macro.
  """
  def execute_macro(pid \\ __MODULE__, register) do
    GenServer.call(pid, {:execute_macro, register})
  end

  @doc """
  Register a handler for specific key events.
  """
  def register_handler(pid \\ __MODULE__, handler_pid, key_mappings) do
    GenServer.call(pid, {:register_handler, handler_pid, key_mappings})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Keyboard Handler")

    settings = %{
      vim_mode: Keyword.get(opts, :vim_mode, false),
      emacs_mode: Keyword.get(opts, :emacs_mode, true),
      custom_bindings_enabled: Keyword.get(opts, :custom_bindings_enabled, true),
      key_timeout: Keyword.get(opts, :key_timeout, 500),
      enable_macros: Keyword.get(opts, :enable_macros, true)
    }

    initial_mode =
      cond do
        settings.vim_mode -> :normal
        settings.emacs_mode -> :emacs
        true -> :simple
      end

    state = %__MODULE__{
      mode: initial_mode,
      key_bindings: load_key_bindings(initial_mode, settings),
      pending_keys: [],
      macro_recording: nil,
      key_buffer: [],
      settings: settings,
      registered_handlers: %{}
    }

    Logger.info("Keyboard Handler initialized",
      mode: state.mode,
      settings: settings
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:process_key, key_data}, _from, state) do
    # Add to key buffer
    new_buffer = add_to_buffer(state.key_buffer, key_data)

    # Record macro if active
    new_state =
      if state.macro_recording do
        record_macro_key(state, key_data)
      else
        state
      end
      |> Map.put(:key_buffer, new_buffer)

    # Check if any registered handlers want this key
    handled = notify_registered_handlers(key_data, new_state)

    if handled do
      {:reply, :handled, new_state}
    else
      # Process the key based on current mode
      case process_key_in_mode(key_data, new_state) do
        {:action, action, final_state} ->
          {:reply, {:action, action}, final_state}

        {:pending, pending_state} ->
          # Start timeout for key sequence
          schedule_key_timeout(state.settings.key_timeout)
          {:reply, :pending, pending_state}

        {:mode_change, new_mode, final_state} ->
          mode_state = change_mode(final_state, new_mode)
          {:reply, {:mode_change, new_mode}, mode_state}

        {:passthrough, final_state} ->
          {:reply, :passthrough, final_state}
      end
    end
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_state = change_mode(state, mode)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_mode, _from, state) do
    {:reply, state.mode, state}
  end

  @impl true
  def handle_call({:bind_key, key_sequence, action}, _from, state) do
    if state.settings.custom_bindings_enabled do
      new_bindings = add_key_binding(state.key_bindings, key_sequence, action)
      new_state = %{state | key_bindings: new_bindings}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :custom_bindings_disabled}, state}
    end
  end

  @impl true
  def handle_call({:toggle_macro_recording, register}, _from, state) do
    if state.settings.enable_macros do
      case state.macro_recording do
        nil ->
          # Start recording
          new_state = %{state | macro_recording: %{register: register, keys: []}}
          {:reply, {:started, register}, new_state}

        %{register: ^register} ->
          # Stop recording
          save_macro(register, state.macro_recording.keys)
          new_state = %{state | macro_recording: nil}
          {:reply, {:stopped, register}, new_state}

        _ ->
          {:reply, {:error, :already_recording}, state}
      end
    else
      {:reply, {:error, :macros_disabled}, state}
    end
  end

  @impl true
  def handle_call({:execute_macro, register}, _from, state) do
    case load_macro(register) do
      {:ok, keys} ->
        # Return the keys to be replayed
        {:reply, {:ok, keys}, state}

      :error ->
        {:reply, {:error, :no_macro}, state}
    end
  end

  @impl true
  def handle_call({:register_handler, handler_pid, key_mappings}, _from, state) do
    # Register handlers for specific keys
    new_handlers =
      Enum.reduce(key_mappings, state.registered_handlers, fn {key, event_type}, acc ->
        Map.update(acc, key, [{handler_pid, event_type}], fn handlers ->
          [{handler_pid, event_type} | handlers]
        end)
      end)

    new_state = %{state | registered_handlers: new_handlers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:key_timeout, state) do
    # Timeout waiting for key sequence completion
    if length(state.pending_keys) > 0 do
      # Process incomplete sequence
      new_state = %{state | pending_keys: []}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp load_key_bindings(mode, settings) do
    base_bindings =
      case mode do
        :vim -> load_vim_bindings()
        # Vi normal mode
        :normal -> load_vim_bindings()
        :emacs -> load_emacs_bindings()
        _ -> %{}
      end

    # Load custom bindings from configuration
    custom_bindings =
      if settings.custom_bindings_enabled do
        load_custom_bindings()
      else
        %{}
      end

    Map.merge(base_bindings, custom_bindings)
  end

  defp load_vim_bindings do
    %{
      # Normal mode navigation
      "h" => {:move, :left},
      "j" => {:move, :down},
      "k" => {:move, :up},
      "l" => {:move, :right},
      "w" => {:move, :word_forward},
      "b" => {:move, :word_backward},
      "e" => {:move, :word_end},
      "0" => {:move, :line_start},
      "$" => {:move, :line_end},
      "gg" => {:move, :buffer_start},
      "G" => {:move, :buffer_end},

      # Mode changes
      "i" => {:mode, :insert},
      "I" => {:mode, :insert_line_start},
      "a" => {:mode, :append},
      "A" => {:mode, :append_line_end},
      "o" => {:edit, :open_below},
      "O" => {:edit, :open_above},

      # Editing
      "x" => {:delete, :char},
      "dd" => {:delete, :line},
      "dw" => {:delete, :word},
      "D" => {:delete, :to_line_end},
      "cc" => {:change, :line},
      "cw" => {:change, :word},
      "C" => {:change, :to_line_end},
      "u" => {:undo},
      ctrl("r") => {:redo},

      # Copy/paste
      "yy" => {:yank, :line},
      "yw" => {:yank, :word},
      "p" => {:paste, :after},
      "P" => {:paste, :before},

      # Search
      "/" => {:search, :forward},
      "?" => {:search, :backward},
      "n" => {:search, :next},
      "N" => {:search, :previous},

      # Visual mode
      "v" => {:mode, :visual},
      "V" => {:mode, :visual_line},
      ctrl("v") => {:mode, :visual_block}
    }
  end

  defp load_emacs_bindings do
    %{
      # Movement
      ctrl("f") => {:move, :right},
      ctrl("b") => {:move, :left},
      ctrl("n") => {:move, :down},
      ctrl("p") => {:move, :up},
      ctrl("a") => {:move, :line_start},
      ctrl("e") => {:move, :line_end},
      alt("f") => {:move, :word_forward},
      alt("b") => {:move, :word_backward},
      alt("<") => {:move, :buffer_start},
      alt(">") => {:move, :buffer_end},

      # Editing
      ctrl("d") => {:delete, :char},
      ctrl("k") => {:delete, :to_line_end},
      ctrl("w") => {:delete, :word_backward},
      alt("d") => {:delete, :word_forward},
      ctrl("y") => {:yank},
      alt("w") => {:copy},
      ctrl("_") => {:undo},

      # Search
      ctrl("s") => {:search, :forward},
      ctrl("r") => {:search, :backward},

      # Misc
      ctrl("g") => {:cancel},
      ctrl("x") => {:prefix, "C-x"},
      ctrl("c") => {:prefix, "C-c"}
    }
  end

  defp load_custom_bindings do
    # Load from configuration file or defaults
    %{
      # Custom shortcuts
      ctrl("t") => {:action, :fuzzy_find},
      ctrl("p") => {:action, :command_palette},
      alt("enter") => {:action, :execute_in_new_pane}
    }
  end

  defp process_key_in_mode(key_data, state) do
    case state.mode do
      :normal -> process_vim_normal_key(key_data, state)
      :insert -> process_vim_insert_key(key_data, state)
      :emacs -> process_emacs_key(key_data, state)
      :simple -> {:passthrough, state}
      _ -> {:passthrough, state}
    end
  end

  defp process_vim_normal_key(key_data, state) do
    # Build potential key sequence
    sequence = build_key_sequence(state.pending_keys ++ [key_data])

    # Check for exact match
    case Map.get(state.key_bindings, sequence) do
      nil ->
        # Check if it could be a prefix
        if is_key_prefix?(sequence, state.key_bindings) do
          {:pending, %{state | pending_keys: state.pending_keys ++ [key_data]}}
        else
          # Not a valid sequence
          {:passthrough, %{state | pending_keys: []}}
        end

      {:mode, new_mode} ->
        {:mode_change, new_mode, %{state | pending_keys: []}}

      action ->
        {:action, action, %{state | pending_keys: []}}
    end
  end

  defp process_vim_insert_key(key_data, state) do
    case key_data do
      # ESC to normal mode
      "\e" -> {:mode_change, :normal, state}
      _ -> {:passthrough, state}
    end
  end

  defp process_emacs_key(key_data, state) do
    # Similar to vim processing but for Emacs bindings
    sequence = build_key_sequence(state.pending_keys ++ [key_data])

    case Map.get(state.key_bindings, sequence) do
      nil ->
        if is_key_prefix?(sequence, state.key_bindings) do
          {:pending, %{state | pending_keys: state.pending_keys ++ [key_data]}}
        else
          {:passthrough, %{state | pending_keys: []}}
        end

      {:prefix, _prefix} ->
        {:pending, %{state | pending_keys: state.pending_keys ++ [key_data]}}

      action ->
        {:action, action, %{state | pending_keys: []}}
    end
  end

  defp build_key_sequence(keys) do
    Enum.join(keys, "")
  end

  defp is_key_prefix?(sequence, bindings) do
    Enum.any?(bindings, fn {key, _action} ->
      String.starts_with?(key, sequence) and key != sequence
    end)
  end

  defp change_mode(state, new_mode) do
    new_bindings = load_key_bindings(new_mode, state.settings)
    %{state | mode: new_mode, key_bindings: new_bindings, pending_keys: []}
  end

  defp add_to_buffer(buffer, key_data) do
    # Keep last 100 keys
    [key_data | buffer]
    |> Enum.take(100)
  end

  defp add_key_binding(bindings, sequence, action) do
    Map.put(bindings, sequence, action)
  end

  defp record_macro_key(state, key_data) do
    case state.macro_recording do
      %{keys: keys} = recording ->
        new_recording = %{recording | keys: keys ++ [key_data]}
        %{state | macro_recording: new_recording}

      _ ->
        state
    end
  end

  defp save_macro(register, keys) do
    # Store macro in persistent storage
    :persistent_term.put({:macro, register}, keys)
  end

  defp load_macro(register) do
    case :persistent_term.get({:macro, register}, nil) do
      nil -> :error
      keys -> {:ok, keys}
    end
  end

  defp schedule_key_timeout(timeout) do
    Process.send_after(self(), :key_timeout, timeout)
  end

  defp notify_registered_handlers(key_data, state) do
    # Check if any handlers are registered for this key
    case Map.get(state.registered_handlers, key_data) do
      nil ->
        false

      handlers ->
        # Notify all handlers
        Enum.each(handlers, fn {handler_pid, event_type} ->
          if Process.alive?(handler_pid) do
            send(handler_pid, {:keyboard_event, {event_type, key_data}})
          end
        end)

        true
    end
  end

  # Helper functions for key combinations
  defp ctrl(key) when is_binary(key) do
    <<char::utf8>> = key

    if char >= ?a and char <= ?z do
      <<char - @ctrl_key_offset>>
    else
      key
    end
  end

  defp alt(key) do
    @escape <> key
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Keyboard Handler shutting down")
    :ok
  end
end
