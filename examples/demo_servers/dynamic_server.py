#!/usr/bin/env python3
"""
Dynamic MCP Server for testing tool updates and notifications.
This server can add/remove tools at runtime to test change notifications.
"""

import asyncio
import json
import sys
from typing import Dict, List, Any
from datetime import datetime

# MCP imports
try:
    from mcp.server import Server
    from mcp.types import Tool, TextContent
except ImportError:
    print("Error: MCP library not installed. Run: pip install mcp", file=sys.stderr)
    sys.exit(1)


class DynamicServer:
    def __init__(self):
        self.server = Server("dynamic-server")
        self.custom_tools: Dict[str, Tool] = {}
        self._setup_base_tools()
        
    def _setup_base_tools(self):
        """Set up the initial tools."""
        
        @self.server.tool()
        async def list_dynamic_tools() -> str:
            """List all dynamically added tools."""
            tools = list(self.custom_tools.keys())
            return json.dumps({
                "dynamic_tools": tools,
                "count": len(tools),
                "timestamp": datetime.now().isoformat()
            })
        
        @self.server.tool()
        async def add_tool(name: str, description: str = "Dynamic tool") -> str:
            """Add a new tool dynamically."""
            if name in self.custom_tools:
                return json.dumps({"error": f"Tool '{name}' already exists"})
            
            # Create a dynamic tool
            async def dynamic_handler(**kwargs) -> str:
                return json.dumps({
                    "tool": name,
                    "input": kwargs,
                    "result": f"Executed {name} with {kwargs}",
                    "timestamp": datetime.now().isoformat()
                })
            
            # Register the tool
            tool = Tool(
                name=name,
                description=description,
                input_schema={
                    "type": "object",
                    "properties": {
                        "data": {"type": "string", "description": "Input data"}
                    }
                },
                handler=dynamic_handler
            )
            
            self.custom_tools[name] = tool
            self.server._tools[name] = tool
            
            # Send tools changed notification
            await self.server.send_tools_changed_notification()
            
            return json.dumps({
                "success": True,
                "tool": name,
                "message": f"Tool '{name}' added successfully"
            })
        
        @self.server.tool()
        async def remove_tool(name: str) -> str:
            """Remove a dynamically added tool."""
            if name not in self.custom_tools:
                return json.dumps({"error": f"Tool '{name}' not found or is not removable"})
            
            # Remove the tool
            del self.custom_tools[name]
            del self.server._tools[name]
            
            # Send tools changed notification
            await self.server.send_tools_changed_notification()
            
            return json.dumps({
                "success": True,
                "tool": name,
                "message": f"Tool '{name}' removed successfully"
            })
        
        @self.server.tool()
        async def long_running_task(duration: int = 5, with_progress: bool = True) -> str:
            """Execute a long-running task with optional progress updates."""
            if with_progress:
                # Send progress notifications
                for i in range(duration):
                    progress = (i + 1) / duration
                    await self.server.send_progress_notification(
                        progress=progress,
                        message=f"Processing step {i + 1} of {duration}"
                    )
                    await asyncio.sleep(1)
            else:
                await asyncio.sleep(duration)
            
            return json.dumps({
                "completed": True,
                "duration": duration,
                "timestamp": datetime.now().isoformat()
            })
        
        @self.server.tool()
        async def trigger_resource_change() -> str:
            """Trigger a resource change notification."""
            # Send resource changed notification
            await self.server.send_resources_changed_notification()
            
            return json.dumps({
                "success": True,
                "message": "Resource change notification sent"
            })
        
        @self.server.tool()
        async def get_server_info() -> str:
            """Get information about the server."""
            return json.dumps({
                "name": "dynamic-server",
                "version": "1.0.0",
                "capabilities": {
                    "tools": {
                        "base_tools": 6,
                        "dynamic_tools": len(self.custom_tools)
                    },
                    "notifications": [
                        "tools_changed",
                        "resources_changed",
                        "progress"
                    ]
                },
                "timestamp": datetime.now().isoformat()
            })
    
    async def run(self):
        """Run the server."""
        async with self.server:
            await self.server.wait_for_exit()


async def main():
    """Main entry point."""
    server = DynamicServer()
    await server.run()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down dynamic server...", file=sys.stderr)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)