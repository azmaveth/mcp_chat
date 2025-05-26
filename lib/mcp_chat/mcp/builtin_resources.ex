defmodule MCPChat.MCP.BuiltinResources do
  @moduledoc """
  Built-in MCP resources and prompts for MCP Chat.
  Provides default resources like documentation links and useful prompts.
  """

  @app_version Mix.Project.config()[:version]

  # Default Resources
  def list_resources() do
    [
      %{
        "uri" => "mcp-chat://docs/readme",
        "name" => "MCP Chat Documentation",
        "description" => "Main documentation and getting started guide",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://docs/commands",
        "name" => "Command Reference",
        "description" => "Complete list of available commands",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://docs/mcp-servers",
        "name" => "MCP Server Guide",
        "description" => "How to connect and use MCP servers",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://info/version",
        "name" => "Version Information",
        "description" => "Current version and build information",
        "mimeType" => "text/plain"
      },
      %{
        "uri" => "mcp-chat://info/config",
        "name" => "Current Configuration",
        "description" => "Active configuration settings",
        "mimeType" => "application/json"
      },
      %{
        "uri" => "mcp-chat://examples/multi-agent",
        "name" => "Multi-Agent Examples",
        "description" => "Examples of chaining MCP Chat instances",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://docs/troubleshooting",
        "name" => "Troubleshooting Guide",
        "description" => "Common issues and solutions",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://docs/api-keys",
        "name" => "API Key Setup",
        "description" => "How to configure API keys for different providers",
        "mimeType" => "text/markdown"
      },
      %{
        "uri" => "mcp-chat://info/libraries",
        "name" => "Library Information",
        "description" => "Information about extracted libraries (ex_mcp, ex_llm, etc.)",
        "mimeType" => "text/markdown"
      }
    ]
  end

  def read_resource(uri) do
    case uri do
      "mcp-chat://docs/readme" ->
        {:ok,
         """
         # MCP Chat Quick Reference

         MCP Chat is an Elixir-based chat client with Model Context Protocol support.

         ## Key Features
         - Multiple LLM backends (Anthropic, OpenAI, Ollama, Local)
         - MCP server integration for extended capabilities
         - Context management with token tracking
         - Cost tracking and estimation
         - Session persistence
         - Command aliases

         ## Quick Start
         1. Set your API key: `export ANTHROPIC_API_KEY="your-key"`
         2. Run: `./mcp_chat`
         3. Type `/help` for commands
         4. Start chatting!

         ## Useful Commands
         - `/models` - List available models
         - `/discover` - Find MCP servers
         - `/cost` - Show session cost
         - `/save` - Save your session

         ## Documentation
         - GitHub: https://github.com/azmaveth/mcp_chat
         - MCP Protocol: https://modelcontextprotocol.io
         """}

      "mcp-chat://docs/commands" ->
        {:ok, generate_command_reference()}

      "mcp-chat://docs/mcp-servers" ->
        {:ok,
         """
         # MCP Server Guide

         ## Connecting to MCP Servers

         ### Quick Discovery
         ```
         /discover
         ```
         Automatically finds and suggests MCP servers to connect.

         ### Manual Connection
         ```
         /connect filesystem
         /connect github
         ```

         ### Using MCP Tools
         ```
         /tools                    # List all available tools
         /tool <server> <tool>     # Call a specific tool
         ```

         ## Popular MCP Servers

         1. **Filesystem** - File operations
            ```
            npx -y @modelcontextprotocol/server-filesystem /path
            ```

         2. **GitHub** - Repository interaction
            ```
            npx -y @modelcontextprotocol/server-github
            ```

         3. **SQLite** - Database queries
            ```
            npx -y @modelcontextprotocol/server-sqlite db.sqlite
            ```

         ## Creating Your Own
         See the examples directory for creating custom MCP servers.
         """}

      "mcp-chat://info/version" ->
        {:ok,
         """
         MCP Chat v#{@app_version}
         Elixir #{System.version()}
         Erlang/OTP #{:erlang.system_info(:otp_release)}

         Build: #{DateTime.utc_now() |> DateTime.to_iso8601()}
         Platform: #{:erlang.system_info(:system_architecture)}
         """}

      "mcp-chat://info/config" ->
        config = MCPChat.Config.get_all()
        # Convert config to JSON format manually
        config_string = format_config_as_json(config)
        {:ok, config_string}

      "mcp-chat://examples/multi-agent" ->
        {:ok, generate_multi_agent_examples()}

      "mcp-chat://docs/troubleshooting" ->
        {:ok, generate_troubleshooting_guide()}

      "mcp-chat://docs/api-keys" ->
        {:ok, generate_api_key_guide()}

      "mcp-chat://info/libraries" ->
        {:ok, generate_library_info()}

      _ ->
        {:error, "Resource not found"}
    end
  end

  # Default Prompts
  def list_prompts() do
    [
      %{
        "name" => "getting_started",
        "description" => "Interactive tutorial for new users"
      },
      %{
        "name" => "demo",
        "description" => "Showcase MCP Chat capabilities"
      },
      %{
        "name" => "troubleshoot",
        "description" => "Diagnose common issues"
      },
      %{
        "name" => "code_review",
        "description" => "Template for reviewing code"
      },
      %{
        "name" => "research_mode",
        "description" => "Structured research workflow"
      },
      %{
        "name" => "setup_mcp_server",
        "description" => "Guide for adding new MCP servers"
      },
      %{
        "name" => "explain_code",
        "description" => "Explain code with context from MCP servers"
      },
      %{
        "name" => "debug_session",
        "description" => "Interactive debugging session"
      },
      %{
        "name" => "create_agent",
        "description" => "Multi-agent system setup wizard"
      },
      %{
        "name" => "api_integration",
        "description" => "Connect external services to MCP Chat"
      }
    ]
  end

  def get_prompt(name) do
    case name do
      "getting_started" ->
        {:ok,
         %{
           name: "getting_started",
           template: """
           Welcome to MCP Chat! I'll help you get started.

           First, let me check your setup:
           1. LLM Backend: {{backend}}
           2. Available Models: {{models}}
           3. MCP Servers: {{servers}}

           What would you like to learn about?
           - Basic chat features
           - Connecting MCP servers
           - Managing conversations
           - Cost tracking
           - Advanced features

           Just ask, and I'll guide you through it!
           """,
           arguments: [
             %{name: "backend", description: "Current LLM backend"},
             %{name: "models", description: "Available models"},
             %{name: "servers", description: "Connected MCP servers"}
           ]
         }}

      "demo" ->
        {:ok,
         %{
           name: "demo",
           template: """
           I'll demonstrate MCP Chat's capabilities!

           Here's what I can show you:

           1. **LLM Features**
              - Switch between models
              - Stream responses
              - Track costs

           2. **MCP Integration**
              - Connect to servers
              - Use tools
              - Access resources

           3. **Session Management**
              - Save/load conversations
              - Context management
              - Token tracking

           4. **Advanced Features**
              - Command aliases
              - Multi-agent setup
              - Custom configurations

           Which feature would you like to see in action?
           """,
           arguments: []
         }}

      "troubleshoot" ->
        {:ok,
         %{
           name: "troubleshoot",
           template: """
           Let's diagnose the issue you're experiencing.

           Current environment:
           - Backend: {{backend}}
           - Model: {{model}}
           - MCP Servers: {{servers}}
           - Session ID: {{session_id}}

           Please describe:
           1. What you were trying to do
           2. What happened instead
           3. Any error messages

           I'll help identify and resolve the issue.
           """,
           arguments: [
             %{name: "backend", description: "Current LLM backend"},
             %{name: "model", description: "Current model"},
             %{name: "servers", description: "Connected MCP servers"},
             %{name: "session_id", description: "Current session ID"}
           ]
         }}

      "research_mode" ->
        {:ok,
         %{
           name: "research_mode",
           template: """
           Entering research mode for: {{topic}}

           I'll help you conduct thorough research using a structured approach:

           ## Phase 1: Information Gathering
           - Search for relevant sources
           - Collect diverse perspectives
           - Identify key concepts

           ## Phase 2: Analysis
           - Synthesize findings
           - Identify patterns
           - Evaluate reliability

           ## Phase 3: Summary
           - Key insights
           - Recommendations
           - Further resources

           {{#if mcp_tools}}
           Available research tools: {{mcp_tools}}
           {{/if}}

           {{#if constraints}}
           Research constraints: {{constraints}}
           {{/if}}

           Let's begin with understanding your research goals...
           """,
           arguments: [
             %{name: "topic", description: "Research topic", required: true},
             %{name: "mcp_tools", description: "Available MCP research tools", required: false},
             %{name: "constraints", description: "Time, scope, or other constraints", required: false}
           ]
         }}

      "code_review" ->
        {:ok,
         %{
           name: "code_review",
           template: """
           I'll review the code at: {{file_path}}

           My review will cover:
           1. **Code Quality**
              - Readability and clarity
              - Following best practices
              - Potential improvements

           2. **Potential Issues**
              - Bugs or logic errors
              - Performance concerns
              - Security considerations

           3. **Suggestions**
              - Refactoring opportunities
              - Better patterns to use
              - Testing recommendations

           {{#if specific_concerns}}
           Focusing on: {{specific_concerns}}
           {{/if}}
           """,
           arguments: [
             %{name: "file_path", description: "Path to file to review", required: true},
             %{name: "specific_concerns", description: "Specific areas to focus on", required: false}
           ]
         }}

      "setup_mcp_server" ->
        {:ok,
         %{
           name: "setup_mcp_server",
           template: """
           Let's set up a new MCP server!

           Server type: {{server_type}}

           I'll help you:
           1. Install the server
           2. Configure it properly
           3. Connect it to MCP Chat
           4. Test the connection
           5. Use its features

           {{#if custom_server}}
           For your custom server, I'll also help with:
           - Creating the server implementation
           - Defining tools and resources
           - Testing the integration
           {{/if}}
           """,
           arguments: [
             %{name: "server_type", description: "Type of server (filesystem, github, custom, etc.)", required: true},
             %{name: "custom_server", description: "Whether this is a custom server", required: false}
           ]
         }}

      "explain_code" ->
        {:ok,
         %{
           name: "explain_code",
           template: """
           I'll explain the code {{#if file_path}}in {{file_path}}{{else}}you provided{{/if}}.

           {{#if mcp_context}}
           Using MCP context from: {{mcp_context}}
           {{/if}}

           My explanation will cover:
           1. **Purpose**: What the code does
           2. **How it works**: Step-by-step breakdown
           3. **Key concepts**: Important patterns and techniques
           4. **Dependencies**: External libraries or modules used
           5. **Potential improvements**: Suggestions if applicable

           {{#if focus_area}}
           Focusing specifically on: {{focus_area}}
           {{/if}}
           """,
           arguments: [
             %{name: "file_path", description: "Path to code file", required: false},
             %{name: "mcp_context", description: "MCP servers to use for context", required: false},
             %{name: "focus_area", description: "Specific aspect to focus on", required: false}
           ]
         }}

      "debug_session" ->
        {:ok,
         %{
           name: "debug_session",
           template: """
           Starting interactive debugging session for: {{issue_description}}

           {{#if error_message}}
           Error: {{error_message}}
           {{/if}}

           {{#if stack_trace}}
           Stack trace:
           {{stack_trace}}
           {{/if}}

           I'll help you:
           1. Understand the error
           2. Identify the root cause
           3. Suggest fixes
           4. Test the solution

           {{#if mcp_tools}}
           Available MCP tools: {{mcp_tools}}
           {{/if}}

           Let's start by examining the issue...
           """,
           arguments: [
             %{name: "issue_description", description: "Description of the issue", required: true},
             %{name: "error_message", description: "Error message if available", required: false},
             %{name: "stack_trace", description: "Stack trace if available", required: false},
             %{name: "mcp_tools", description: "Relevant MCP tools available", required: false}
           ]
         }}

      "create_agent" ->
        {:ok,
         %{
           name: "create_agent",
           template: """
           Let's create a multi-agent MCP Chat setup!

           Agent Purpose: {{agent_purpose}}
           {{#if agent_count}}
           Number of agents: {{agent_count}}
           {{/if}}

           I'll help you design a multi-agent system:

           ## Step 1: Define Agent Roles
           Based on your purpose, here are suggested agent roles:
           {{#if agent_purpose contains "research"}}
           - Research Agent: Gathers and analyzes information
           - Synthesis Agent: Combines findings into insights
           - Writer Agent: Produces final reports
           {{else if agent_purpose contains "development"}}
           - Code Analyzer: Reviews existing code
           - Implementation Agent: Writes new code
           - Test Agent: Creates and runs tests
           - Documentation Agent: Updates docs
           {{else}}
           - Coordinator Agent: Manages workflow
           - Worker Agents: Perform specific tasks
           - Quality Agent: Validates results
           {{/if}}

           ## Step 2: Agent Communication
           We'll use BEAM message passing for agent coordination:
           - Agents run as MCP servers (stdio mode)
           - Main instance connects to all agents
           - Agents can send/receive messages via tools

           ## Step 3: Configuration
           I'll generate the configuration files needed:
           1. Individual agent configs
           2. Main coordinator config
           3. Startup scripts

           What specific capabilities should each agent have?
           """,
           arguments: [
             %{name: "agent_purpose", description: "What the multi-agent system will do", required: true},
             %{name: "agent_count", description: "Number of agents needed", required: false}
           ]
         }}

      "api_integration" ->
        {:ok,
         %{
           name: "api_integration",
           template: """
           Setting up API integration for: {{service_name}}

           {{#if api_type}}
           API Type: {{api_type}}
           {{/if}}

           I'll help you integrate {{service_name}} with MCP Chat:

           ## Integration Approach

           {{#if api_type == "REST"}}
           ### REST API Integration
           1. Create MCP server wrapper
           2. Define tools for each endpoint
           3. Handle authentication
           4. Implement rate limiting
           {{else if api_type == "GraphQL"}}
           ### GraphQL Integration
           1. Schema introspection
           2. Query/mutation tools
           3. Subscription support
           4. Type mapping
           {{else if api_type == "WebSocket"}}
           ### WebSocket Integration
           1. Connection management
           2. Message routing
           3. Event handling
           4. Reconnection logic
           {{else}}
           ### Generic API Integration
           1. Protocol detection
           2. Authentication setup
           3. Tool generation
           4. Error handling
           {{/if}}

           ## Implementation Steps

           1. **MCP Server Creation**
              ```elixir
              defmodule {{service_name}}Server do
                use ExMCP.Server

                def handle_tool_call("{{service_name}}.request", params) do
                  # API call implementation
                end
              end
              ```

           2. **Configuration**
              ```toml
              [mcp.servers.{{service_name|lowercase}}]
              command = ["./{{service_name|lowercase}}_server"]
              env = { API_KEY = "your-key" }
              ```

           3. **Usage Example**
              ```
              /mcp connect {{service_name|lowercase}}
              /mcp tool {{service_name|lowercase}} request {...}
              ```

           {{#if requires_auth}}
           Note: This service requires authentication. Make sure to set up your API credentials.
           {{/if}}

           Would you like me to generate the complete MCP server code?
           """,
           arguments: [
             %{name: "service_name", description: "Name of the service to integrate", required: true},
             %{name: "api_type", description: "Type of API (REST, GraphQL, WebSocket, etc.)", required: false},
             %{name: "requires_auth", description: "Whether authentication is required", required: false}
           ]
         }}

      _ ->
        {:error, "Prompt not found"}
    end
  end

  # Helper to generate multi-agent examples
  defp generate_multi_agent_examples() do
    """
    # Multi-Agent MCP Chat Examples

    ## Basic Agent Chain

    Start an MCP Chat instance as a server:
    ```bash
    # Terminal 1: Start MCP Chat as a server
    ./mcp_chat --server stdio
    ```

    Connect from another instance:
    ```bash
    # Terminal 2: Connect to the first instance
    ./mcp_chat
    /connect mcp_chat_stdio
    ```

    ## Advanced Setup

    ### Research Assistant Chain
    1. **Web Research Agent** - Gathers information
    2. **Analysis Agent** - Processes and analyzes data
    3. **Writer Agent** - Creates reports

    ### Development Assistant
    1. **Code Review Agent** - Reviews code quality
    2. **Test Writer Agent** - Generates tests
    3. **Documentation Agent** - Updates docs

    ## Configuration Example

    ```toml
    # config.toml
    [mcp.servers.research_agent]
    command = ["./mcp_chat", "--server", "stdio"]
    env = { AGENT_ROLE = "researcher" }

    [mcp.servers.writer_agent]
    command = ["./mcp_chat", "--server", "stdio"]
    env = { AGENT_ROLE = "writer" }
    ```

    ## Using Agent Chains

    ```
    # In your main MCP Chat instance
    /connect research_agent
    /connect writer_agent

    # Use tools from both agents
    /tool research_agent search "Elixir best practices"
    /tool writer_agent draft "Create a guide based on the research"
    ```
    """
  end

  # Helper to generate command reference
  defp generate_command_reference() do
    """
    # MCP Chat Command Reference

    ## Chat Commands
    - `/help` - Show available commands
    - `/clear` - Clear the screen
    - `/history` - Show conversation history
    - `/new` - Start new conversation
    - `/exit`, `/quit` - Exit application

    ## Session Management
    - `/save [name]` - Save current session
    - `/load <name>` - Load saved session
    - `/sessions` - List saved sessions
    - `/export [format]` - Export conversation

    ## LLM Configuration
    - `/backend [name]` - Show/switch LLM backend
    - `/model [name]` - Show/switch model
    - `/models` - List available models
    - `/cost` - Show session cost

    ## MCP Server Commands
    - `/servers` - List connected servers
    - `/discover` - Auto-discover servers
    - `/connect <name>` - Connect to server
    - `/disconnect <name>` - Disconnect server
    - `/tools` - List all tools
    - `/tool <server> <tool> [args]` - Call tool
    - `/resources` - List resources
    - `/resource <server> <uri>` - Read resource
    - `/prompts` - List prompts
    - `/prompt <server> <name>` - Get prompt

    ## Context Management
    - `/context` - Show context stats
    - `/system <prompt>` - Set system prompt
    - `/tokens <max>` - Set max tokens
    - `/strategy <type>` - Set truncation strategy

    ## Other Features
    - `/alias <cmd>` - Manage aliases
    - `/acceleration` - Show GPU info
    - `/config` - Show configuration
    """
  end

  defp generate_troubleshooting_guide() do
    """
    # MCP Chat Troubleshooting Guide

    ## Common Issues

    ### 1. API Key Errors
    **Problem**: "Invalid API key" or authentication errors
    **Solution**:
    - Check environment variable: `echo $ANTHROPIC_API_KEY`
    - Ensure key is set: `export ANTHROPIC_API_KEY="your-key"`
    - Verify key format (no extra spaces or quotes)

    ### 2. MCP Server Connection Issues
    **Problem**: "Failed to connect to server"
    **Solutions**:
    - Check server is installed: `which npx`
    - Verify npm package: `npm list -g @modelcontextprotocol/server-name`
    - Check permissions for file system servers
    - Ensure GitHub token is set for GitHub server

    ### 3. High Token Usage
    **Problem**: Hitting token limits quickly
    **Solutions**:
    - Use `/context` to check usage
    - Set lower max tokens: `/tokens 1_000`
    - Use `/strategy smart` for better truncation
    - Clear history with `/new`

    ### 4. Cost Tracking Issues
    **Problem**: Costs seem incorrect
    **Solutions**:
    - Check model pricing with `/models`
    - Verify token counting with `/context`
    - Cost data updates periodically

    ### 5. Session Save/Load Problems
    **Problem**: Can't save or load sessions
    **Solutions**:
    - Check permissions: `ls -la ~/.config/mcp_chat/sessions/`
    - Ensure directory exists
    - Try explicit path: `/save my_session`

    ## Debug Commands

    ```
    # Check configuration
    /config

    # Test MCP server
    /discover
    /connect filesystem

    # Verify LLM connection
    /models
    /backend

    # System information
    /acceleration
    ```

    ## Getting Help

    - GitHub Issues: https://github.com/azmaveth/mcp_chat/issues
    - MCP Protocol Docs: https://modelcontextprotocol.io
    """
  end

  defp generate_api_key_guide() do
    """
    # API Key Configuration Guide

    ## Anthropic (Claude)
    1. Get key from: https://console.anthropic.com/
    2. Set environment variable:
       ```bash
       export ANTHROPIC_API_KEY="sk-ant-..."
       ```

    ## OpenAI
    1. Get key from: https://platform.openai.com/api-keys
    2. Set environment variable:
       ```bash
       export OPENAI_API_KEY="sk-..."
       ```

    ## Ollama (Local)
    1. Install Ollama: https://ollama.ai
    2. Start Ollama service:
       ```bash
       ollama serve
       ```
    3. Pull models:
       ```bash
       ollama pull llama2
       ollama pull mistral
       ```

    ## AWS Bedrock
    1. Configure AWS credentials:
       ```bash
       export AWS_ACCESS_KEY_ID="..."
       export AWS_SECRET_ACCESS_KEY="..."
       export AWS_REGION="us-east-1"
       ```
    2. Ensure Bedrock model access is enabled

    ## Google Gemini
    1. Get key from: https://makersuite.google.com/app/apikey
    2. Set environment variable:
       ```bash
       export GEMINI_API_KEY="..."
       ```

    ## Configuration File

    You can also set keys in `~/.config/mcp_chat/config.toml`:

    ```toml
    [llm.anthropic]
    api_key = "sk-ant-..."

    [llm.openai]
    api_key = "sk-..."

    [llm.gemini]
    api_key = "..."
    ```

    ## Security Notes

    - Never commit API keys to version control
    - Use environment variables for production
    - Rotate keys regularly
    - Set minimal required permissions
    """
  end

  defp generate_library_info() do
    """
    # MCP Chat Library Architecture

    MCP Chat is built on extracted, reusable libraries:

    ## ex_mcp (#{get_library_version(:ex_mcp)})
    **Model Context Protocol implementation**
    - Client and server support
    - Multiple transports (stdio, SSE)
    - Tool and resource management
    - Server discovery

    ## ex_llm (#{get_library_version(:ex_llm)})
    **Unified LLM interface**
    - Multiple providers (Anthropic, OpenAI, Ollama, Bedrock, Gemini)
    - Streaming support
    - Cost tracking
    - Context management
    - Local model support via Bumblebee

    ## ex_alias (#{get_library_version(:ex_alias)})
    **Command alias system**
    - Recursive expansion
    - Circular reference detection
    - Persistent storage

    ## ex_readline (#{get_library_version(:ex_readline)})
    **Enhanced line editing**
    - History management
    - Tab completion
    - Multi-line editing

    ## Architecture Benefits

    1. **Modularity**: Each library has a single responsibility
    2. **Reusability**: Libraries can be used in other projects
    3. **Testing**: Isolated testing of each component
    4. **Maintenance**: Easier to update individual parts

    ## Using the Libraries

    Add to your `mix.exs`:

    ```elixir
    defp deps() do
      [
        {:ex_mcp, "~> 0.1"},
        {:ex_llm, "~> 0.2"},
        {:ex_alias, "~> 0.1"},
        {:ex_readline, "~> 0.1"}
      ]
    end
    ```

    ## Contributing

    Each library welcomes contributions:
    - ex_mcp: MCP protocol features
    - ex_llm: New LLM providers
    - ex_alias: Alias functionality
    - ex_readline: Line editing features
    """
  end

  defp get_library_version(lib) do
    case Application.spec(lib, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp format_config_as_json(config) do
    # Simple JSON formatting for config display
    config
    |> Enum.map(fn {key, value} ->
      ~s{"#{key}": #{format_json_value(value)}}
    end)
    |> Enum.join(",\n  ")
    |> then(&"{\n  #{&1}\n}")
  end

  defp format_json_value(value) when is_binary(value), do: ~s{"#{value}"}
  defp format_json_value(value) when is_atom(value), do: ~s{"#{value}"}
  defp format_json_value(value) when is_number(value), do: "#{value}"
  defp format_json_value(value) when is_boolean(value), do: "#{value}"
  defp format_json_value(value) when is_nil(value), do: "null"

  defp format_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} ->
      ~s{"#{k}": #{format_json_value(v)}}
    end)
    |> Enum.join(", ")
    |> then(&"{#{&1}}")
  end

  defp format_json_value(value) when is_list(value) do
    value
    |> Enum.map_join(&format_json_value/1, ", ")
    |> then(&"[#{&1}]")
  end

  defp format_json_value(value), do: ~s{"#{inspect(value)}"}
end
