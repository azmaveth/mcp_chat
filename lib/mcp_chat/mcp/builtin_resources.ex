defmodule MCPChat.MCP.BuiltinResources do
  @moduledoc """
  Built-in MCP resources and prompts for MCP Chat.
  Provides default resources like documentation links and useful prompts.
  """

  @app_version Mix.Project.config()[:version]

  # Default Resources
  def list_resources do
    [
      %{
        uri: "mcp-chat://docs/readme",
        name: "MCP Chat Documentation",
        description: "Main documentation and getting started guide",
        mimeType: "text/markdown"
      },
      %{
        uri: "mcp-chat://docs/commands",
        name: "Command Reference",
        description: "Complete list of available commands",
        mimeType: "text/markdown"
      },
      %{
        uri: "mcp-chat://docs/mcp-servers",
        name: "MCP Server Guide",
        description: "How to connect and use MCP servers",
        mimeType: "text/markdown"
      },
      %{
        uri: "mcp-chat://info/version",
        name: "Version Information",
        description: "Current version and build information",
        mimeType: "text/plain"
      },
      %{
        uri: "mcp-chat://info/config",
        name: "Current Configuration",
        description: "Active configuration settings",
        mimeType: "application/json"
      },
      %{
        uri: "mcp-chat://examples/multi-agent",
        name: "Multi-Agent Examples",
        description: "Examples of chaining MCP Chat instances",
        mimeType: "text/markdown"
      }
    ]
  end

  def read_resource(uri) do
    case uri do
      "mcp-chat://docs/readme" ->
        {:ok, """
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
        - GitHub: https://github.com/yourusername/mcp_chat
        - Docs: https://mcp-chat.dev/docs
        """}

      "mcp-chat://docs/commands" ->
        {:ok, generate_command_reference()}

      "mcp-chat://docs/mcp-servers" ->
        {:ok, """
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
        {:ok, """
        MCP Chat v#{@app_version}
        Elixir #{System.version()}
        Erlang/OTP #{:erlang.system_info(:otp_release)}
        
        Build: #{DateTime.utc_now() |> DateTime.to_iso8601()}
        Platform: #{:erlang.system_info(:system_architecture)}
        """}

      "mcp-chat://info/config" ->
        config = MCPChat.Config.get_all()
        {:ok, Jason.encode!(config, pretty: true)}

      "mcp-chat://examples/multi-agent" ->
        {:ok, File.read!(Path.join(:code.priv_dir(:mcp_chat), "examples/multi_agent_setup.md"))}

      _ ->
        {:error, "Resource not found"}
    end
  end

  # Default Prompts
  def list_prompts do
    [
      %{
        name: "getting_started",
        description: "Interactive tutorial for new users"
      },
      %{
        name: "demo",
        description: "Showcase MCP Chat capabilities"
      },
      %{
        name: "troubleshoot",
        description: "Diagnose common issues"
      },
      %{
        name: "code_review",
        description: "Template for reviewing code"
      },
      %{
        name: "research_mode",
        description: "Structured research workflow"
      },
      %{
        name: "setup_mcp_server",
        description: "Guide for adding new MCP servers"
      }
    ]
  end

  def get_prompt(name) do
    case name do
      "getting_started" ->
        {:ok, %{
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
        {:ok, %{
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

      "code_review" ->
        {:ok, %{
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
        {:ok, %{
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

      _ ->
        {:error, "Prompt not found"}
    end
  end

  # Helper to generate command reference
  defp generate_command_reference do
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
end