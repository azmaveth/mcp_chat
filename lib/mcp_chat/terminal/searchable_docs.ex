defmodule MCPChat.Terminal.SearchableDocs do
  @moduledoc """
  Searchable documentation system with full-text search.

  Provides comprehensive documentation search across all
  help topics, tutorials, and reference materials.
  """

  use GenServer
  require Logger

  # Searchable docs state
  defstruct [
    # Inverted index for search
    :docs_index,
    # Document storage
    :documents,
    # Search result cache
    :search_cache,
    # Search settings
    :settings
  ]

  # Document types (for future use)
  # @doc_types [:guide, :reference, :tutorial, :troubleshooting, :api]

  # Built-in documentation
  @documents [
    %{
      id: "getting-started",
      type: :guide,
      title: "Getting Started with MCP Chat",
      tags: ["beginner", "introduction", "setup"],
      content: """
      # Getting Started with MCP Chat

      MCP Chat is a powerful command-line interface for interacting with AI models
      and Model Context Protocol (MCP) servers.

      ## Installation

      1. Clone the repository
      2. Run `scripts/build/setup.sh` for initial setup
      3. Start with `bin/mcp_chat` or `iex -S mix` then `MCPChat.main()`

      ## First Steps

      - Type messages to chat with the AI
      - Use `/help` to see available commands
      - Try `/tutorial` for an interactive walkthrough
      - Use Tab for autocomplete suggestions

      ## Key Features

      - Multiple AI model support (Claude, GPT-4, etc.)
      - MCP server integration for extended capabilities
      - Session management with auto-save
      - Cost tracking and optimization
      - Rich terminal interface with syntax highlighting
      """
    },
    %{
      id: "mcp-guide",
      type: :guide,
      title: "Understanding Model Context Protocol",
      tags: ["mcp", "servers", "tools", "advanced"],
      content: """
      # Model Context Protocol (MCP)

      MCP extends AI assistants with tools and resources through servers.

      ## What are MCP Servers?

      MCP servers provide:
      - File system access
      - Database connections
      - API integrations
      - Custom tools and functions

      ## Adding MCP Servers

      1. Configure in `config.toml`:
      ```toml
      [mcp.servers.filesystem]
      command = "npx"
      args = ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
      ```

      2. Or use commands:
      ```
      /servers add filesystem 'npx -y @modelcontextprotocol/server-filesystem /path'
      ```

      ## Using MCP Tools

      Once connected, the AI can use server tools automatically:
      - Ask to read files
      - Query databases
      - Call APIs
      - Execute custom functions

      Use `/tools` to see available tools.
      """
    },
    %{
      id: "keyboard-shortcuts",
      type: :reference,
      title: "Keyboard Shortcuts Reference",
      tags: ["shortcuts", "keyboard", "navigation", "editing"],
      content: """
      # Keyboard Shortcuts

      ## Navigation
      - ↑/↓ - Command history
      - ←/→ - Move cursor
      - Ctrl+A - Beginning of line
      - Ctrl+E - End of line
      - Ctrl+←/→ - Move by word
      - Home/End - Line start/end

      ## Editing
      - Ctrl+U - Clear line
      - Ctrl+W - Delete word backward
      - Ctrl+K - Delete to end of line
      - Ctrl+L - Clear screen
      - Tab - Autocomplete
      - Backspace - Delete character
      - Delete - Delete forward

      ## Special Actions
      - Ctrl+C - Cancel/interrupt
      - Ctrl+D - Exit (empty line)
      - Ctrl+R - Search history
      - Escape - Clear input
      - Enter - Send message
      - \\ + Enter - Continue on next line
      """
    },
    %{
      id: "cost-optimization",
      type: :guide,
      title: "Managing Costs and Token Usage",
      tags: ["cost", "tokens", "optimization", "budget"],
      content: """
      # Cost Optimization Guide

      ## Understanding Tokens

      - ~4 characters = 1 token (rough estimate)
      - Both input and output tokens count
      - Context accumulates throughout conversation

      ## Cost Management Strategies

      1. **Clear context regularly**
         - Use `/context clear` to reset
         - Remove unnecessary files with `/context remove`

      2. **Choose appropriate models**
         - Use smaller models for simple tasks
         - Reserve large models for complex work
         - See `/models` for pricing info

      3. **Monitor usage**
         - Check with `/cost` regularly
         - Use `/stats` for token counts
         - Set budgets in config.toml

      4. **Efficient prompting**
         - Be concise and specific
         - Avoid repetitive questions
         - Use aliases for common commands
      """
    },
    %{
      id: "troubleshooting",
      type: :troubleshooting,
      title: "Common Issues and Solutions",
      tags: ["errors", "problems", "fixes", "troubleshooting"],
      content: """
      # Troubleshooting Guide

      ## API Key Issues

      **Problem**: "API key not found"
      **Solutions**:
      - Set environment variable: `export ANTHROPIC_API_KEY=your-key`
      - Add to config.toml under `[llm.anthropic]`
      - Check spelling and formatting

      ## MCP Server Connection

      **Problem**: "Server connection failed"
      **Solutions**:
      - Verify server command is correct
      - Check if executable exists and is accessible
      - Try `/servers restart <name>`
      - Check logs with `/logs`

      ## High Token Usage

      **Problem**: "Context too long"
      **Solutions**:
      - Use `/context clear` to reset
      - Remove files with `/context remove`
      - Switch to model with higher limits
      - Export and start new session

      ## Terminal Display Issues

      **Problem**: Garbled output or missing colors
      **Solutions**:
      - Ensure terminal supports ANSI codes
      - Try different terminal emulator
      - Disable colors in config.toml
      - Use `TERM=xterm-256color` environment
      """
    },
    %{
      id: "advanced-features",
      type: :guide,
      title: "Advanced Features and Workflows",
      tags: ["advanced", "workflows", "automation", "power-user"],
      content: """
      # Advanced Features

      ## Multi-Agent Workflows

      Use multiple specialized agents:
      ```
      /agent spawn coder
      /agent spawn reviewer
      /agent workflow code-review
      ```

      ## Plan Mode

      Execute complex tasks safely:
      ```
      /plan
      1. Analyze codebase
      2. Identify improvements
      3. Implement changes
      4. Run tests
      /plan execute
      ```

      ## Custom Aliases

      Create powerful command shortcuts:
      ```
      /alias add review '/agent spawn reviewer; /context add *.py'
      /alias add deploy '/plan deploy.yaml'
      ```

      ## Session Templates

      Save and reuse session setups:
      ```
      /session save-template coding
      /session from-template coding
      ```

      ## Automation Scripts

      Integrate with shell scripts:
      ```bash
      echo "analyze this code" | mcp_chat --model gpt-4
      ```
      """
    }
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Search documentation.
  """
  def search(pid \\ __MODULE__, query, options \\ %{}) do
    GenServer.call(pid, {:search, query, options})
  end

  @doc """
  Get document by ID.
  """
  def get_document(pid \\ __MODULE__, doc_id) do
    GenServer.call(pid, {:get_document, doc_id})
  end

  @doc """
  List all documents.
  """
  def list_documents(pid \\ __MODULE__, filters \\ %{}) do
    GenServer.call(pid, {:list_documents, filters})
  end

  @doc """
  Add custom documentation.
  """
  def add_document(pid \\ __MODULE__, document) do
    GenServer.call(pid, {:add_document, document})
  end

  @doc """
  Get related documents.
  """
  def get_related(pid \\ __MODULE__, doc_id) do
    GenServer.call(pid, {:get_related, doc_id})
  end

  @doc """
  Get documents by tag.
  """
  def get_by_tag(pid \\ __MODULE__, tag) do
    GenServer.call(pid, {:get_by_tag, tag})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Logger.info("Starting Searchable Docs")

    settings = %{
      max_results: Keyword.get(opts, :max_results, 10),
      min_score: Keyword.get(opts, :min_score, 0.3),
      cache_enabled: Keyword.get(opts, :cache_enabled, true),
      # 5 minutes
      cache_ttl: Keyword.get(opts, :cache_ttl, 300_000),
      fuzzy_search: Keyword.get(opts, :fuzzy_search, true),
      highlight_matches: Keyword.get(opts, :highlight_matches, true)
    }

    # Build initial index
    {documents, index} = build_index(@documents)

    state = %__MODULE__{
      docs_index: index,
      documents: documents,
      search_cache: %{},
      settings: settings
    }

    Logger.info("Searchable Docs initialized",
      document_count: map_size(documents),
      index_terms: map_size(index)
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:search, query, options}, _from, state) do
    # Check cache first
    cache_key = {query, options}

    result =
      if state.settings.cache_enabled do
        case get_from_cache(state.search_cache, cache_key, state.settings.cache_ttl) do
          {:ok, cached} -> cached
          :miss -> perform_search(query, options, state)
        end
      else
        perform_search(query, options, state)
      end

    # Update cache
    new_cache =
      if state.settings.cache_enabled do
        put_in_cache(state.search_cache, cache_key, result)
      else
        state.search_cache
      end

    {:reply, result, %{state | search_cache: new_cache}}
  end

  @impl true
  def handle_call({:get_document, doc_id}, _from, state) do
    document = Map.get(state.documents, doc_id)
    {:reply, document, state}
  end

  @impl true
  def handle_call({:list_documents, filters}, _from, state) do
    filtered = filter_documents(state.documents, filters)
    {:reply, filtered, state}
  end

  @impl true
  def handle_call({:add_document, document}, _from, state) do
    doc_id = document[:id] || generate_doc_id(document)
    normalized_doc = normalize_document(document, doc_id)

    # Update documents
    new_documents = Map.put(state.documents, doc_id, normalized_doc)

    # Update index
    new_index = update_index(state.docs_index, doc_id, normalized_doc)

    # Clear cache
    new_state = %{state | documents: new_documents, docs_index: new_index, search_cache: %{}}

    {:reply, {:ok, doc_id}, new_state}
  end

  @impl true
  def handle_call({:get_related, doc_id}, _from, state) do
    case Map.get(state.documents, doc_id) do
      nil ->
        {:reply, [], state}

      document ->
        related = find_related_documents(document, state)
        {:reply, related, state}
    end
  end

  @impl true
  def handle_call({:get_by_tag, tag}, _from, state) do
    documents =
      state.documents
      |> Enum.filter(fn {_id, doc} ->
        tag in Map.get(doc, :tags, [])
      end)
      |> Enum.map(fn {_id, doc} -> doc end)

    {:reply, documents, state}
  end

  # Private functions

  defp build_index(documents) do
    indexed_docs =
      documents
      |> Enum.map(fn doc ->
        doc_id = doc[:id] || generate_doc_id(doc)
        {doc_id, normalize_document(doc, doc_id)}
      end)
      |> Enum.into(%{})

    index =
      indexed_docs
      |> Enum.reduce(%{}, fn {doc_id, doc}, acc ->
        terms = extract_terms(doc)

        Enum.reduce(terms, acc, fn {term, positions}, acc2 ->
          Map.update(acc2, term, %{doc_id => positions}, fn existing ->
            Map.put(existing, doc_id, positions)
          end)
        end)
      end)

    {indexed_docs, index}
  end

  defp normalize_document(doc, doc_id) do
    doc
    |> Map.put(:id, doc_id)
    |> Map.put_new(:type, :general)
    |> Map.put_new(:tags, [])
    |> Map.put_new(:created_at, DateTime.utc_now())
  end

  defp extract_terms(document) do
    # Extract terms from title, content, and tags
    text =
      [
        Map.get(document, :title, ""),
        Map.get(document, :content, ""),
        Enum.join(Map.get(document, :tags, []), " ")
      ]
      |> Enum.join(" ")
      |> String.downcase()

    # Tokenize and build position map
    text
    |> tokenize()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {token, pos}, acc ->
      Map.update(acc, token, [pos], fn positions -> [pos | positions] end)
    end)
  end

  defp tokenize(text) do
    text
    |> String.replace(~r/[^\w\s-]/, " ")
    |> String.split(~r/\s+/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp perform_search(query, options, state) do
    # Parse query
    query_terms = query |> String.downcase() |> tokenize()

    # Search in index
    doc_scores =
      query_terms
      |> Enum.reduce(%{}, fn term, acc ->
        matching_docs =
          if state.settings.fuzzy_search do
            fuzzy_search_term(term, state.docs_index)
          else
            Map.get(state.docs_index, term, %{})
          end

        # Update scores
        Enum.reduce(matching_docs, acc, fn {doc_id, positions}, acc2 ->
          score = calculate_score(term, positions, query_terms)
          Map.update(acc2, doc_id, score, &(&1 + score))
        end)
      end)

    # Get top results
    results =
      doc_scores
      |> Enum.filter(fn {_id, score} -> score >= state.settings.min_score end)
      |> Enum.sort_by(fn {_id, score} -> score end, :desc)
      |> Enum.take(Map.get(options, :limit, state.settings.max_results))
      |> Enum.map(fn {doc_id, score} ->
        doc = Map.get(state.documents, doc_id)

        result = %{
          document: doc,
          score: score,
          id: doc_id
        }

        if state.settings.highlight_matches do
          Map.put(result, :highlights, generate_highlights(doc, query_terms))
        else
          result
        end
      end)

    results
  end

  defp fuzzy_search_term(term, index) do
    # Simple fuzzy search - find terms within edit distance
    index
    |> Enum.filter(fn {index_term, _docs} ->
      String.jaro_distance(term, index_term) > 0.8
    end)
    |> Enum.flat_map(fn {_term, docs} -> docs end)
    |> Enum.reduce(%{}, fn {doc_id, positions}, acc ->
      Map.update(acc, doc_id, positions, fn existing ->
        existing ++ positions
      end)
    end)
  end

  defp calculate_score(term, positions, query_terms) do
    base_score = length(positions) * 0.1

    # Boost for exact matches
    exact_match_boost = if term in query_terms, do: 0.5, else: 0

    # Position boost (earlier positions score higher)
    position_boost =
      positions
      |> Enum.map(fn pos -> 1 / (pos + 1) end)
      |> Enum.sum()

    base_score + exact_match_boost + position_boost * 0.1
  end

  defp generate_highlights(document, query_terms) do
    content = Map.get(document, :content, "")

    # Find matches and their contexts
    query_terms
    |> Enum.flat_map(fn term ->
      regex = ~r/\b#{Regex.escape(term)}\b/i

      Regex.scan(regex, content, return: :index)
      |> Enum.map(fn [{start, length}] ->
        context_start = max(0, start - 50)
        context_end = min(String.length(content), start + length + 50)

        snippet =
          String.slice(content, context_start, context_end - context_start)
          |> highlight_term(term)

        %{
          term: term,
          snippet: "..." <> snippet <> "..."
        }
      end)
    end)
    |> Enum.take(3)
  end

  defp highlight_term(text, term) do
    regex = ~r/\b(#{Regex.escape(term)})\b/i
    String.replace(text, regex, "#{IO.ANSI.yellow()}\\1#{IO.ANSI.reset()}")
  end

  defp filter_documents(documents, filters) do
    documents
    |> Enum.filter(fn {_id, doc} ->
      type_match =
        case Map.get(filters, :type) do
          nil -> true
          type -> doc.type == type
        end

      tag_match =
        case Map.get(filters, :tag) do
          nil -> true
          tag -> tag in Map.get(doc, :tags, [])
        end

      type_match and tag_match
    end)
    |> Enum.map(fn {_id, doc} -> doc end)
    |> Enum.sort_by(& &1.title)
  end

  defp find_related_documents(document, state) do
    # Find related by tags
    doc_tags = Map.get(document, :tags, [])

    if length(doc_tags) > 0 do
      state.documents
      |> Enum.filter(fn {id, doc} ->
        id != document.id and
          MapSet.size(
            MapSet.intersection(
              MapSet.new(doc_tags),
              MapSet.new(Map.get(doc, :tags, []))
            )
          ) > 0
      end)
      |> Enum.map(fn {_id, doc} -> doc end)
      |> Enum.take(5)
    else
      []
    end
  end

  defp update_index(index, doc_id, document) do
    terms = extract_terms(document)

    Enum.reduce(terms, index, fn {term, positions}, acc ->
      Map.update(acc, term, %{doc_id => positions}, fn existing ->
        Map.put(existing, doc_id, positions)
      end)
    end)
  end

  defp generate_doc_id(document) do
    title = Map.get(document, :title, "untitled")
    timestamp = System.unique_integer([:positive])

    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, "-")
    |> Kernel.<>("-#{timestamp}")
  end

  defp get_from_cache(cache, key, ttl) do
    case Map.get(cache, key) do
      nil ->
        :miss

      {result, timestamp} ->
        if System.monotonic_time(:millisecond) - timestamp < ttl do
          {:ok, result}
        else
          :miss
        end
    end
  end

  defp put_in_cache(cache, key, result) do
    Map.put(cache, key, {result, System.monotonic_time(:millisecond)})
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Searchable Docs shutting down")
    :ok
  end
end
