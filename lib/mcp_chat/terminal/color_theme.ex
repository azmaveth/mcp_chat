defmodule MCPChat.Terminal.ColorTheme do
  @moduledoc """
  Color theme management for terminal display.

  Provides predefined themes and custom theme support
  for consistent visual styling across the application.
  """

  use GenServer
  require Logger

  alias IO.ANSI

  # Theme state
  defstruct [
    # Active theme name
    :current_theme,
    # Available themes
    :themes,
    # User-defined themes
    :custom_themes,
    # Theme settings
    :settings
  ]

  # Default themes
  @default_themes %{
    default: %{
      primary: :cyan,
      secondary: :blue,
      accent: :magenta,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :blue,
      text: :white,
      text_dim: :light_black,
      text_bright: :light_white,
      background: :black,
      background_alt: :light_black,
      border: :blue,
      border_dim: :black,
      highlight: :yellow,
      selection: :cyan,
      prompt: :green,
      input: :white,
      code_keyword: :magenta,
      code_string: :yellow,
      code_number: :cyan,
      code_comment: :light_black,
      code_function: :green,
      code_variable: :white
    },
    monokai: %{
      primary: :magenta,
      secondary: :green,
      accent: :yellow,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :blue,
      text: :white,
      text_dim: :light_black,
      text_bright: :light_white,
      background: :black,
      background_alt: :light_black,
      border: :magenta,
      border_dim: :black,
      highlight: :yellow,
      selection: :light_black,
      prompt: :green,
      input: :white,
      code_keyword: :magenta,
      code_string: :yellow,
      code_number: :cyan,
      code_comment: :light_black,
      code_function: :green,
      code_variable: :white
    },
    solarized_dark: %{
      primary: :blue,
      secondary: :cyan,
      accent: :magenta,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :blue,
      text: :light_white,
      text_dim: :light_black,
      text_bright: :white,
      background: :black,
      background_alt: :light_black,
      border: :cyan,
      border_dim: :light_black,
      highlight: :yellow,
      selection: :blue,
      prompt: :green,
      input: :light_white,
      code_keyword: :green,
      code_string: :cyan,
      code_number: :magenta,
      code_comment: :light_black,
      code_function: :blue,
      code_variable: :yellow
    },
    dracula: %{
      primary: :magenta,
      secondary: :cyan,
      accent: :green,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :cyan,
      text: :white,
      text_dim: :light_black,
      text_bright: :light_white,
      background: :black,
      background_alt: :light_black,
      border: :magenta,
      border_dim: :light_black,
      highlight: :yellow,
      selection: :light_black,
      prompt: :green,
      input: :white,
      code_keyword: :magenta,
      code_string: :yellow,
      code_number: :blue,
      code_comment: :light_black,
      code_function: :green,
      code_variable: :white
    },
    nord: %{
      primary: :light_blue,
      secondary: :blue,
      accent: :cyan,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :light_blue,
      text: :white,
      text_dim: :light_black,
      text_bright: :light_white,
      background: :black,
      background_alt: :light_black,
      border: :blue,
      border_dim: :light_black,
      highlight: :yellow,
      selection: :light_blue,
      prompt: :green,
      input: :white,
      code_keyword: :blue,
      code_string: :green,
      code_number: :magenta,
      code_comment: :light_black,
      code_function: :cyan,
      code_variable: :white
    },
    gruvbox: %{
      primary: :yellow,
      secondary: :green,
      accent: :red,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :blue,
      text: :white,
      text_dim: :light_black,
      text_bright: :light_white,
      background: :black,
      background_alt: :light_black,
      border: :yellow,
      border_dim: :light_black,
      highlight: :yellow,
      selection: :blue,
      prompt: :green,
      input: :white,
      code_keyword: :red,
      code_string: :green,
      code_number: :magenta,
      code_comment: :light_black,
      code_function: :yellow,
      code_variable: :white
    },
    high_contrast: %{
      primary: :white,
      secondary: :light_white,
      accent: :yellow,
      success: :green,
      warning: :yellow,
      error: :red,
      info: :cyan,
      text: :white,
      text_dim: :light_white,
      text_bright: :white,
      background: :black,
      background_alt: :black,
      border: :white,
      border_dim: :light_white,
      highlight: :yellow,
      selection: :white,
      prompt: :white,
      input: :white,
      code_keyword: :white,
      code_string: :white,
      code_number: :white,
      code_comment: :light_white,
      code_function: :white,
      code_variable: :white
    }
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current theme.
  """
  def get_current_theme(pid \\ __MODULE__) do
    GenServer.call(pid, :get_current_theme)
  end

  @doc """
  Set the active theme.
  """
  def set_theme(pid \\ __MODULE__, theme_name) do
    GenServer.call(pid, {:set_theme, theme_name})
  end

  @doc """
  Get a specific color from the current theme.
  """
  def get_color(pid \\ __MODULE__, color_name) do
    GenServer.call(pid, {:get_color, color_name})
  end

  @doc """
  Apply a color from the current theme to text.
  """
  def colorize(pid \\ __MODULE__, text, color_name) do
    GenServer.call(pid, {:colorize, text, color_name})
  end

  @doc """
  List all available themes.
  """
  def list_themes(pid \\ __MODULE__) do
    GenServer.call(pid, :list_themes)
  end

  @doc """
  Register a custom theme.
  """
  def register_custom_theme(pid \\ __MODULE__, name, theme_definition) do
    GenServer.call(pid, {:register_custom_theme, name, theme_definition})
  end

  @doc """
  Get theme definition.
  """
  def get_theme_definition(pid \\ __MODULE__, theme_name) do
    GenServer.call(pid, {:get_theme_definition, theme_name})
  end

  @doc """
  Preview a theme with sample text.
  """
  def preview_theme(pid \\ __MODULE__, theme_name) do
    GenServer.call(pid, {:preview_theme, theme_name})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Color Theme Manager")

    settings = %{
      default_theme: Keyword.get(opts, :default_theme, :default),
      allow_custom_themes: Keyword.get(opts, :allow_custom_themes, true),
      auto_detect_terminal: Keyword.get(opts, :auto_detect_terminal, true),
      true_color: Keyword.get(opts, :true_color, false)
    }

    # Load custom themes from configuration
    custom_themes = load_custom_themes(opts)

    # Select initial theme
    initial_theme = select_initial_theme(settings, custom_themes)

    state = %__MODULE__{
      current_theme: initial_theme,
      themes: @default_themes,
      custom_themes: custom_themes,
      settings: settings
    }

    Logger.info("Color Theme Manager initialized",
      current_theme: state.current_theme,
      available_themes: map_size(state.themes) + map_size(state.custom_themes)
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_theme, _from, state) do
    {:reply, state.current_theme, state}
  end

  @impl true
  def handle_call({:set_theme, theme_name}, _from, state) do
    theme_atom = to_atom(theme_name)

    if theme_exists?(theme_atom, state) do
      new_state = %{state | current_theme: theme_atom}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :theme_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_color, color_name}, _from, state) do
    color = get_theme_color(state.current_theme, color_name, state)
    {:reply, color, state}
  end

  @impl true
  def handle_call({:colorize, text, color_name}, _from, state) do
    color = get_theme_color(state.current_theme, color_name, state)
    colored_text = apply_color(text, color)
    {:reply, colored_text, state}
  end

  @impl true
  def handle_call(:list_themes, _from, state) do
    default_themes = Map.keys(state.themes)
    custom_themes = Map.keys(state.custom_themes)
    all_themes = Enum.sort(default_themes ++ custom_themes)
    {:reply, all_themes, state}
  end

  @impl true
  def handle_call({:register_custom_theme, name, theme_definition}, _from, state) do
    if state.settings.allow_custom_themes do
      theme_atom = to_atom(name)
      validated_theme = validate_theme_definition(theme_definition)
      new_custom_themes = Map.put(state.custom_themes, theme_atom, validated_theme)
      new_state = %{state | custom_themes: new_custom_themes}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :custom_themes_disabled}, state}
    end
  end

  @impl true
  def handle_call({:get_theme_definition, theme_name}, _from, state) do
    theme_atom = to_atom(theme_name)
    definition = get_theme_def(theme_atom, state)
    {:reply, definition, state}
  end

  @impl true
  def handle_call({:preview_theme, theme_name}, _from, state) do
    theme_atom = to_atom(theme_name)

    case get_theme_def(theme_atom, state) do
      nil ->
        {:reply, {:error, :theme_not_found}, state}

      theme ->
        preview = generate_theme_preview(theme)
        {:reply, {:ok, preview}, state}
    end
  end

  # Private functions

  defp load_custom_themes(opts) do
    case Keyword.get(opts, :custom_themes) do
      nil ->
        %{}

      themes when is_map(themes) ->
        themes
        |> Enum.map(fn {name, definition} ->
          {to_atom(name), validate_theme_definition(definition)}
        end)
        |> Enum.into(%{})
    end
  end

  defp select_initial_theme(settings, custom_themes) do
    theme_atom = to_atom(settings.default_theme)

    cond do
      Map.has_key?(@default_themes, theme_atom) -> theme_atom
      Map.has_key?(custom_themes, theme_atom) -> theme_atom
      true -> :default
    end
  end

  defp theme_exists?(theme_name, state) do
    Map.has_key?(state.themes, theme_name) or
      Map.has_key?(state.custom_themes, theme_name)
  end

  defp get_theme_def(theme_name, state) do
    Map.get(state.themes, theme_name) ||
      Map.get(state.custom_themes, theme_name)
  end

  defp get_theme_color(theme_name, color_name, state) do
    case get_theme_def(theme_name, state) do
      # Fallback
      nil -> :white
      theme -> Map.get(theme, color_name, :white)
    end
  end

  defp apply_color(text, color) do
    color_code = apply(ANSI, color, [])
    color_code <> text <> ANSI.reset()
  end

  defp validate_theme_definition(definition) do
    # Ensure all required color keys are present
    required_keys = [:primary, :secondary, :text, :background, :error, :warning, :success]

    # Start with defaults
    base_theme = Map.get(@default_themes, :default)

    # Merge with provided definition
    validated = Map.merge(base_theme, definition)

    # Ensure required keys exist
    Enum.reduce(required_keys, validated, fn key, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        Map.put(acc, key, :white)
      end
    end)
  end

  defp generate_theme_preview(theme) do
    [
      "\n=== Theme Preview ===\n",
      apply_color("Primary Text", Map.get(theme, :primary, :white)),
      "\n",
      apply_color("Secondary Text", Map.get(theme, :secondary, :white)),
      "\n",
      apply_color("Success Message", Map.get(theme, :success, :green)),
      "\n",
      apply_color("Warning Message", Map.get(theme, :warning, :yellow)),
      "\n",
      apply_color("Error Message", Map.get(theme, :error, :red)),
      "\n",
      apply_color("Info Message", Map.get(theme, :info, :blue)),
      "\n\n",
      "Code Sample:\n",
      apply_color("def ", Map.get(theme, :code_keyword, :magenta)),
      apply_color("hello", Map.get(theme, :code_function, :green)),
      "(",
      apply_color("name", Map.get(theme, :code_variable, :white)),
      ") do\n",
      "  ",
      apply_color("# Greeting function", Map.get(theme, :code_comment, :light_black)),
      "\n",
      "  ",
      apply_color("\"Hello, \#{name}!\"", Map.get(theme, :code_string, :yellow)),
      "\n",
      "end\n",
      "\n",
      "Border: ",
      apply_color("┌─────────────┐", Map.get(theme, :border, :blue)),
      "\n",
      "        ",
      apply_color("│", Map.get(theme, :border, :blue)),
      " Sample Text ",
      apply_color("│", Map.get(theme, :border, :blue)),
      "\n",
      "        ",
      apply_color("└─────────────┘", Map.get(theme, :border, :blue)),
      "\n"
    ]
    |> Enum.join()
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Color Theme Manager shutting down")
    :ok
  end
end
