defmodule MCPChat.Terminal.SyntaxHighlighter do
  @moduledoc """
  Syntax highlighting for terminal input and output.

  Provides language-aware syntax highlighting for various
  programming languages and command formats.
  """

  use GenServer
  require Logger

  alias IO.ANSI

  # Highlighter state
  defstruct [
    # Syntax rules for languages
    :language_rules,
    # Color theme
    :theme,
    # Highlighted text cache
    :cache,
    # Highlighter settings
    :settings
  ]

  # Token types
  @token_types [
    :keyword,
    :string,
    :number,
    :comment,
    :operator,
    :function,
    :variable,
    :constant,
    :type,
    :punctuation,
    :error,
    :warning,
    :builtin,
    :command,
    :flag,
    :path,
    :url
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Highlight text with automatic language detection.
  """
  def highlight(pid \\ __MODULE__, text, language \\ :auto) do
    GenServer.call(pid, {:highlight, text, language})
  end

  @doc """
  Highlight command line input.
  """
  def highlight_command(pid \\ __MODULE__, command) do
    GenServer.call(pid, {:highlight_command, command})
  end

  @doc """
  Get highlighted diff output.
  """
  def highlight_diff(pid \\ __MODULE__, diff_text) do
    GenServer.call(pid, {:highlight_diff, diff_text})
  end

  @doc """
  Set color theme.
  """
  def set_theme(pid \\ __MODULE__, theme) do
    GenServer.call(pid, {:set_theme, theme})
  end

  @doc """
  Clear highlighting cache.
  """
  def clear_cache(pid \\ __MODULE__) do
    GenServer.call(pid, :clear_cache)
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Syntax Highlighter")

    settings = %{
      cache_enabled: Keyword.get(opts, :cache_enabled, true),
      cache_size: Keyword.get(opts, :cache_size, 100),
      auto_detect: Keyword.get(opts, :auto_detect, true),
      highlight_urls: Keyword.get(opts, :highlight_urls, true),
      highlight_paths: Keyword.get(opts, :highlight_paths, true)
    }

    theme_name = Keyword.get(opts, :theme, :monokai)

    state = %__MODULE__{
      language_rules: load_language_rules(),
      theme: load_theme(theme_name),
      cache: %{},
      settings: settings
    }

    Logger.info("Syntax Highlighter initialized",
      theme: theme_name,
      languages: Map.keys(state.language_rules)
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:highlight, text, language}, _from, state) do
    # Check cache first
    cache_key = {text, language}

    highlighted =
      if state.settings.cache_enabled do
        case Map.get(state.cache, cache_key) do
          nil ->
            result = perform_highlighting(text, language, state)
            new_cache = update_cache(state.cache, cache_key, result, state.settings.cache_size)
            {:reply, result, %{state | cache: new_cache}}

          cached ->
            {:reply, cached, state}
        end
      else
        result = perform_highlighting(text, language, state)
        {:reply, result, state}
      end
  end

  @impl true
  def handle_call({:highlight_command, command}, _from, state) do
    highlighted = highlight_command_line(command, state)
    {:reply, highlighted, state}
  end

  @impl true
  def handle_call({:highlight_diff, diff_text}, _from, state) do
    highlighted = highlight_diff_content(diff_text, state)
    {:reply, highlighted, state}
  end

  @impl true
  def handle_call({:set_theme, theme_name}, _from, state) do
    new_theme = load_theme(theme_name)
    new_state = %{state | theme: new_theme, cache: %{}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    {:reply, :ok, %{state | cache: %{}}}
  end

  # Private functions

  defp load_language_rules do
    %{
      elixir: load_elixir_rules(),
      javascript: load_javascript_rules(),
      python: load_python_rules(),
      shell: load_shell_rules(),
      json: load_json_rules(),
      markdown: load_markdown_rules()
    }
  end

  defp load_elixir_rules do
    %{
      keywords: ~w[
        def defp defmodule defmacro defmacrop defstruct defprotocol
        defimpl defexception defoverridable defdelegate defguard
        do end fn case cond if unless when in and or not
        try catch rescue after raise throw
        import require use alias
        true false nil self
        __MODULE__ __DIR__ __ENV__ __CALLER__ __STACKTRACE__
      ],
      operators: ~w[
        = == != === !== < > <= >= + - * / ++ -- <> :: | || && ! ^ @ ~
        -> <- => |> <<< >>> <<~ ~>> <~ ~> <~> <|>
      ],
      builtins: ~w[
        spawn spawn_link send receive
        length hd tl elem put_elem tuple_size
        is_atom is_binary is_bitstring is_boolean is_float
        is_function is_integer is_list is_map is_nil is_number
        is_pid is_port is_reference is_tuple
        abs div rem round trunc
        inspect to_string to_atom
      ],
      patterns: %{
        string: ~r/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/,
        atom: ~r/(:[a-zA-Z_]\w*[?!]?|:"(?:[^"\\]|\\.)*")/,
        number: ~r/\b\d+(\.\d+)?([eE][+-]?\d+)?\b/,
        comment: ~r/#.*/,
        module: ~r/\b[A-Z]\w*(\.[A-Z]\w*)*/,
        function_call: ~r/\b\w+[?!]?\s*(?=\()/,
        sigil:
          ~r/~[a-zA-Z](?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\((?:[^)]|\\.)*\)|\[(?:[^\]]|\\.)*\]|\{(?:[^}]|\\.)*\}|<(?:[^>]|\\.)*>|\|(?:[^|]|\\.)*\||\/(?:[^\/]|\\.)*\/)/
      }
    }
  end

  defp load_javascript_rules do
    %{
      keywords: ~w[
        async await break case catch class const continue debugger
        default delete do else export extends finally for function
        if import in instanceof let new return super switch this
        throw try typeof var void while with yield
      ],
      operators: ~w[
        = == === != !== < > <= >= + - * / % ++ -- 
        && || ! & | ^ ~ << >> >>> ?: => ... ?? ?.
      ],
      builtins: ~w[
        console Object Array String Number Boolean Date Math JSON
        Promise Set Map WeakSet WeakMap Symbol RegExp Error
        parseInt parseFloat isNaN isFinite undefined null
      ],
      patterns: %{
        string: ~r/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)/,
        number: ~r/\b\d+(\.\d+)?([eE][+-]?\d+)?\b/,
        comment: ~r/(\/\/.*|\/\*[\s\S]*?\*\/)/,
        regex: ~r/\/(?:[^\/\n\\]|\\.)+\/[gimuy]*/,
        function: ~r/\bfunction\s+(\w+)|(\w+)\s*(?=\(.*\)\s*=>)/,
        class: ~r/\bclass\s+(\w+)/
      }
    }
  end

  defp load_python_rules do
    %{
      keywords: ~w[
        and as assert async await break class continue def del elif
        else except False finally for from global if import in is
        lambda None nonlocal not or pass raise return True try
        while with yield
      ],
      operators: ~w[
        = == != < > <= >= + - * / // % ** 
        += -= *= /= //= %= **= & | ^ ~ << >> 
        and or not in is
      ],
      builtins: ~w[
        abs all any ascii bin bool breakpoint bytearray bytes
        callable chr classmethod compile complex delattr dict
        dir divmod enumerate eval exec filter float format
        frozenset getattr globals hasattr hash help hex id
        input int isinstance issubclass iter len list locals
        map max memoryview min next object oct open ord pow
        print property range repr reversed round set setattr
        slice sorted staticmethod str sum super tuple type
        vars zip __import__
      ],
      patterns: %{
        string: ~r/("""[\s\S]*?"""|'''[\s\S]*?'''|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/,
        number: ~r/\b\d+(\.\d+)?([eE][+-]?\d+)?\b/,
        comment: ~r/#.*/,
        decorator: ~r/@\w+/,
        function: ~r/\bdef\s+(\w+)/,
        class: ~r/\bclass\s+(\w+)/
      }
    }
  end

  defp load_shell_rules do
    %{
      keywords: ~w[
        if then else elif fi case esac for while do done
        function return break continue exit
      ],
      builtins: ~w[
        echo cd ls pwd mkdir rm cp mv cat grep sed awk
        chmod chown find which export source alias unalias
        curl wget git docker npm yarn pip python node
      ],
      patterns: %{
        string: ~r/("(?:[^"\\]|\\.)*"|'[^']*')/,
        variable: ~r/\$\w+|\$\{[^}]+\}/,
        comment: ~r/#.*/,
        flag: ~r/\s(-{1,2}[\w-]+)/,
        path: ~r/(?:\.{0,2}\/)?(?:[\w-]+\/)*[\w-]+(?:\.\w+)?/,
        pipe: ~r/[|><&]/,
        subcommand: ~r/\$\([^)]+\)|`[^`]+`/
      }
    }
  end

  defp load_json_rules do
    %{
      patterns: %{
        string: ~r/"(?:[^"\\]|\\.)*"/,
        number: ~r/-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b/,
        boolean: ~r/\b(true|false)\b/,
        null: ~r/\bnull\b/,
        key: ~r/"[^"]+"\s*:/
      }
    }
  end

  defp load_markdown_rules do
    %{
      patterns: %{
        heading: ~r/^#\{1,6\}\s+.*/m,
        bold: ~r/\*\*[^*]+\*\*|__[^_]+__/,
        italic: ~r/\*[^*]+\*|_[^_]+_/,
        code: ~r/`[^`]+`/,
        code_block: ~r/```[\s\S]*?```/,
        link: ~r/\[([^\]]+)\]\(([^)]+)\)/,
        list: ~r/^[\s]*[-*+]\s+.*/m,
        quote: ~r/^>\s+.*/m
      }
    }
  end

  defp load_theme(theme_name) do
    themes = %{
      monokai: %{
        keyword: :magenta,
        string: :yellow,
        number: :cyan,
        comment: :light_black,
        operator: :red,
        function: :green,
        variable: :white,
        constant: :cyan,
        type: :blue,
        punctuation: :white,
        error: :red,
        warning: :yellow,
        builtin: :cyan,
        command: :green,
        flag: :blue,
        path: :cyan,
        url: :blue,
        # Diff colors
        diff_add: :green,
        diff_remove: :red,
        diff_header: :cyan,
        diff_range: :magenta
      },
      solarized: %{
        keyword: :green,
        string: :cyan,
        number: :cyan,
        comment: :light_black,
        operator: :blue,
        function: :blue,
        variable: :yellow,
        constant: :magenta,
        type: :yellow,
        punctuation: :light_white,
        error: :red,
        warning: :yellow,
        builtin: :blue,
        command: :green,
        flag: :blue,
        path: :cyan,
        url: :blue,
        diff_add: :green,
        diff_remove: :red,
        diff_header: :blue,
        diff_range: :magenta
      },
      dracula: %{
        keyword: :magenta,
        string: :yellow,
        number: :blue,
        comment: :light_black,
        operator: :red,
        function: :green,
        variable: :white,
        constant: :magenta,
        type: :cyan,
        punctuation: :white,
        error: :red,
        warning: :yellow,
        builtin: :cyan,
        command: :green,
        flag: :magenta,
        path: :cyan,
        url: :blue,
        diff_add: :green,
        diff_remove: :red,
        diff_header: :cyan,
        diff_range: :yellow
      }
    }

    Map.get(themes, theme_name, themes.monokai)
  end

  defp perform_highlighting(text, language, state) do
    detected_language =
      if language == :auto and state.settings.auto_detect do
        detect_language(text)
      else
        language
      end

    case Map.get(state.language_rules, detected_language) do
      # No highlighting for unknown languages
      nil -> text
      rules -> apply_highlighting_rules(text, rules, state.theme)
    end
  end

  defp detect_language(text) do
    cond do
      String.contains?(text, "defmodule") -> :elixir
      String.contains?(text, "function") or String.contains?(text, "const") -> :javascript
      String.contains?(text, "def ") or String.contains?(text, "import ") -> :python
      String.starts_with?(text, "{") and String.contains?(text, ":") -> :json
      String.contains?(text, "```") -> :markdown
      true -> :shell
    end
  end

  defp apply_highlighting_rules(text, rules, theme) do
    # Start with the original text
    highlighted = text

    # Apply patterns in order of precedence
    # Comments first (to avoid highlighting inside them)
    highlighted =
      if patterns = rules[:patterns] do
        highlighted =
          if pattern = patterns[:comment] do
            apply_pattern_highlight(highlighted, pattern, :comment, theme)
          else
            highlighted
          end

        # Strings next
        highlighted =
          if pattern = patterns[:string] do
            apply_pattern_highlight(highlighted, pattern, :string, theme)
          else
            highlighted
          end

        # Numbers
        highlighted =
          if pattern = patterns[:number] do
            apply_pattern_highlight(highlighted, pattern, :number, theme)
          else
            highlighted
          end

        # Apply other patterns
        Enum.reduce(patterns, highlighted, fn {type, pattern}, acc ->
          if type not in [:comment, :string, :number] do
            apply_pattern_highlight(acc, pattern, type, theme)
          else
            acc
          end
        end)
      else
        highlighted
      end

    # Apply keyword highlighting
    if keywords = rules[:keywords] do
      apply_keyword_highlight(highlighted, keywords, theme)
    else
      highlighted
    end
  end

  defp apply_pattern_highlight(text, pattern, type, theme) do
    color = get_color_for_type(type, theme)

    Regex.replace(pattern, text, fn match ->
      colorize(match, color)
    end)
  end

  defp apply_keyword_highlight(text, keywords, theme) do
    color = get_color_for_type(:keyword, theme)

    # Build pattern for word boundaries
    pattern =
      keywords
      |> Enum.map(&Regex.escape/1)
      |> Enum.join("|")
      |> then(&"\\b(#{&1})\\b")
      |> Regex.compile!()

    Regex.replace(pattern, text, fn match ->
      colorize(match, color)
    end)
  end

  defp highlight_command_line(command, state) do
    parts = String.split(command, " ", parts: 2)

    case parts do
      [cmd] ->
        colorize(cmd, get_color_for_type(:command, state.theme))

      [cmd, args] ->
        highlighted_cmd = colorize(cmd, get_color_for_type(:command, state.theme))
        highlighted_args = highlight_command_args(args, state)
        highlighted_cmd <> " " <> highlighted_args
    end
  end

  defp highlight_command_args(args, state) do
    # Highlight flags
    args =
      Regex.replace(~r/\s(-{1,2}[\w-]+)/, args, fn _, flag ->
        " " <> colorize(flag, get_color_for_type(:flag, state.theme))
      end)

    # Highlight paths if enabled
    if state.settings.highlight_paths do
      args =
        Regex.replace(~r/(?:\.{0,2}\/)?(?:[\w-]+\/)*[\w-]+(?:\.\w+)?/, args, fn path ->
          if String.contains?(path, "/") or String.starts_with?(path, ".") do
            colorize(path, get_color_for_type(:path, state.theme))
          else
            path
          end
        end)
    end

    # Highlight URLs if enabled
    if state.settings.highlight_urls do
      args =
        Regex.replace(~r/https?:\/\/[^\s]+/, args, fn url ->
          colorize(url, get_color_for_type(:url, state.theme))
        end)
    end

    args
  end

  defp highlight_diff_content(diff_text, state) do
    diff_text
    |> String.split("\n")
    |> Enum.map(fn line ->
      cond do
        String.starts_with?(line, "+++") or String.starts_with?(line, "---") ->
          colorize(line, get_color_for_type(:diff_header, state.theme))

        String.starts_with?(line, "@@") ->
          colorize(line, get_color_for_type(:diff_range, state.theme))

        String.starts_with?(line, "+") ->
          colorize(line, get_color_for_type(:diff_add, state.theme))

        String.starts_with?(line, "-") ->
          colorize(line, get_color_for_type(:diff_remove, state.theme))

        true ->
          line
      end
    end)
    |> Enum.join("\n")
  end

  defp get_color_for_type(type, theme) do
    Map.get(theme, type, :white)
  end

  defp colorize(text, color) do
    color_code = apply(ANSI, color, [])
    color_code <> text <> ANSI.reset()
  end

  defp update_cache(cache, key, value, max_size) do
    new_cache = Map.put(cache, key, value)

    # Simple LRU: remove oldest if over size limit
    if map_size(new_cache) > max_size do
      {oldest_key, _} =
        cache
        |> Map.to_list()
        |> List.first()

      Map.delete(new_cache, oldest_key)
    else
      new_cache
    end
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Syntax Highlighter shutting down")
    :ok
  end
end
