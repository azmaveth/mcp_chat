# Demo MCP Servers

This directory contains demonstration MCP servers that can be used with MCP Chat.

## Available Servers

### 1. Time Server (`time_server.py`)
Provides time and date functionality:
- Get current time in various timezones
- Get current date with different formats
- Calculate time until future dates
- Convert times between timezones

### 2. Calculator Server (`calculator_server.py`)
Advanced calculator with:
- Basic arithmetic expressions
- Scientific functions (sin, cos, log, etc.)
- Statistical operations
- Unit conversions
- Calculation history

### 3. Data Server (`data_server.py`)
Demo data generation and manipulation:
- Generate sample users, products, transactions
- Query data with filters
- Perform aggregations
- Store and retrieve data collections

## Installation

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install mcp pytz
```

## Usage

### Starting a Server

```bash
# Run directly
python time_server.py

# Or make executable
chmod +x time_server.py
./time_server.py
```

### Configuring with MCP Chat

Add to your MCP Chat configuration:

```toml
[[mcp_servers]]
name = "time"
command = "python"
args = ["/path/to/examples/demo_servers/time_server.py"]

[[mcp_servers]]
name = "calc"
command = "python" 
args = ["/path/to/examples/demo_servers/calculator_server.py"]

[[mcp_servers]]
name = "data"
command = "python"
args = ["/path/to/examples/demo_servers/data_server.py"]
```

### Example Commands in MCP Chat

```bash
# Time server
/mcp tools time
/mcp call time get_current_time timezone:PST format:12h
/mcp call time timezone_converter time:14:30 from_timezone:EST to_timezone:PST

# Calculator server
/mcp call calc calculate expression:"(10 + 20) * 3"
/mcp call calc scientific_calc operation:sin value:90
/mcp call calc unit_convert value:100 from_unit:km to_unit:miles

# Data server
/mcp call data generate_users count:50
/mcp call data generate_products count:20
/mcp call data query_data collection:users filter:{"age":{"$gt":30}} limit:5
/mcp call data aggregate_data collection:users operation:avg field:age
```

## Creating Your Own MCP Server

Use these examples as templates for creating your own MCP servers:

1. Import required modules from `mcp`
2. Create a `Server` instance
3. Implement tool handlers with `@server.list_tools()` and `@server.call_tool()`
4. Optional: Add resources with `@server.list_resources()` and `@server.read_resource()`
5. Run with `stdio_server()` in the main function

See the official MCP documentation for more details on server development.