#!/usr/bin/env python3
"""
Simple MCP server that provides time and date functionality.
"""

import asyncio
import json
from datetime import datetime, timezone
import pytz
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Create server instance
server = Server("time-server")

# Available timezones for demo
TIMEZONES = {
    "UTC": "UTC",
    "EST": "America/New_York", 
    "PST": "America/Los_Angeles",
    "CST": "America/Chicago",
    "MST": "America/Denver",
    "GMT": "Europe/London",
    "CET": "Europe/Paris",
    "JST": "Asia/Tokyo",
    "AEST": "Australia/Sydney"
}

@server.list_tools()
async def list_tools():
    """List available time/date tools."""
    return [
        Tool(
            name="get_current_time",
            description="Get current time in specified timezone",
            input_schema={
                "type": "object",
                "properties": {
                    "timezone": {
                        "type": "string",
                        "description": f"Timezone code: {', '.join(TIMEZONES.keys())}",
                        "default": "UTC"
                    },
                    "format": {
                        "type": "string", 
                        "description": "Time format: '12h' or '24h'",
                        "default": "24h"
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="get_date",
            description="Get current date in specified timezone",
            input_schema={
                "type": "object",
                "properties": {
                    "timezone": {
                        "type": "string",
                        "description": f"Timezone code: {', '.join(TIMEZONES.keys())}",
                        "default": "UTC"
                    },
                    "format": {
                        "type": "string",
                        "description": "Date format: 'iso', 'us', 'eu'",
                        "default": "iso"
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="time_until",
            description="Calculate time until a future date",
            input_schema={
                "type": "object",
                "properties": {
                    "target_date": {
                        "type": "string",
                        "description": "Target date in YYYY-MM-DD format"
                    },
                    "target_time": {
                        "type": "string",
                        "description": "Target time in HH:MM format (24h)",
                        "default": "00:00"
                    },
                    "timezone": {
                        "type": "string",
                        "description": f"Timezone code: {', '.join(TIMEZONES.keys())}",
                        "default": "UTC"
                    }
                },
                "required": ["target_date"]
            }
        ),
        Tool(
            name="timezone_converter",
            description="Convert time between timezones",
            input_schema={
                "type": "object",
                "properties": {
                    "time": {
                        "type": "string",
                        "description": "Time in HH:MM format (24h)"
                    },
                    "from_timezone": {
                        "type": "string",
                        "description": f"Source timezone: {', '.join(TIMEZONES.keys())}"
                    },
                    "to_timezone": {
                        "type": "string",
                        "description": f"Target timezone: {', '.join(TIMEZONES.keys())}"
                    }
                },
                "required": ["time", "from_timezone", "to_timezone"]
            }
        )
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    """Execute time/date tools."""
    
    if name == "get_current_time":
        tz_code = arguments.get("timezone", "UTC")
        tz_name = TIMEZONES.get(tz_code, "UTC")
        format_type = arguments.get("format", "24h")
        
        tz = pytz.timezone(tz_name)
        now = datetime.now(tz)
        
        if format_type == "12h":
            time_str = now.strftime("%I:%M:%S %p")
        else:
            time_str = now.strftime("%H:%M:%S")
        
        return [TextContent(
            type="text",
            text=f"Current time in {tz_code}: {time_str}"
        )]
    
    elif name == "get_date":
        tz_code = arguments.get("timezone", "UTC")
        tz_name = TIMEZONES.get(tz_code, "UTC")
        format_type = arguments.get("format", "iso")
        
        tz = pytz.timezone(tz_name)
        now = datetime.now(tz)
        
        if format_type == "us":
            date_str = now.strftime("%m/%d/%Y")
        elif format_type == "eu":
            date_str = now.strftime("%d/%m/%Y")
        else:  # iso
            date_str = now.strftime("%Y-%m-%d")
        
        return [TextContent(
            type="text",
            text=f"Current date in {tz_code}: {date_str}"
        )]
    
    elif name == "time_until":
        target_date = arguments["target_date"]
        target_time = arguments.get("target_time", "00:00")
        tz_code = arguments.get("timezone", "UTC")
        tz_name = TIMEZONES.get(tz_code, "UTC")
        
        # Parse target datetime
        target_str = f"{target_date} {target_time}"
        tz = pytz.timezone(tz_name)
        target = tz.localize(datetime.strptime(target_str, "%Y-%m-%d %H:%M"))
        
        # Calculate difference
        now = datetime.now(tz)
        diff = target - now
        
        if diff.total_seconds() < 0:
            return [TextContent(
                type="text",
                text=f"The target date {target_str} has already passed!"
            )]
        
        days = diff.days
        hours = diff.seconds // 3600
        minutes = (diff.seconds % 3600) // 60
        
        return [TextContent(
            type="text",
            text=f"Time until {target_str} {tz_code}: {days} days, {hours} hours, {minutes} minutes"
        )]
    
    elif name == "timezone_converter":
        time_str = arguments["time"]
        from_tz = TIMEZONES.get(arguments["from_timezone"], "UTC")
        to_tz = TIMEZONES.get(arguments["to_timezone"], "UTC")
        
        # Create datetime for today with given time
        today = datetime.now().date()
        dt = datetime.strptime(f"{today} {time_str}", "%Y-%m-%d %H:%M")
        
        # Localize to source timezone
        from_zone = pytz.timezone(from_tz)
        dt_from = from_zone.localize(dt)
        
        # Convert to target timezone
        to_zone = pytz.timezone(to_tz)
        dt_to = dt_from.astimezone(to_zone)
        
        return [TextContent(
            type="text",
            text=f"{time_str} {arguments['from_timezone']} = {dt_to.strftime('%H:%M')} {arguments['to_timezone']}"
        )]
    
    else:
        return [TextContent(
            type="text",
            text=f"Unknown tool: {name}"
        )]

async def main():
    """Run the time server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, {})

if __name__ == "__main__":
    asyncio.run(main())