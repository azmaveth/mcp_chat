#!/usr/bin/env python3
"""
MCP server providing calculator functionality with advanced math operations.
"""

import asyncio
import json
import math
from typing import List, Union
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Create server instance
server = Server("calculator-server")

# Store calculation history
calculation_history: List[str] = []
last_result: float = 0

@server.list_tools()
async def list_tools():
    """List available calculator tools."""
    return [
        Tool(
            name="calculate",
            description="Perform basic arithmetic calculation",
            input_schema={
                "type": "object",
                "properties": {
                    "expression": {
                        "type": "string",
                        "description": "Math expression (e.g., '2 + 3 * 4', '(10 - 5) / 2')"
                    }
                },
                "required": ["expression"]
            }
        ),
        Tool(
            name="scientific_calc",
            description="Perform scientific calculations",
            input_schema={
                "type": "object",
                "properties": {
                    "operation": {
                        "type": "string",
                        "enum": ["sin", "cos", "tan", "log", "ln", "sqrt", "pow", "factorial"],
                        "description": "Scientific operation"
                    },
                    "value": {
                        "type": "number",
                        "description": "Input value"
                    },
                    "base": {
                        "type": "number",
                        "description": "Base for pow operation (optional)"
                    }
                },
                "required": ["operation", "value"]
            }
        ),
        Tool(
            name="statistics",
            description="Calculate statistics for a list of numbers",
            input_schema={
                "type": "object",
                "properties": {
                    "numbers": {
                        "type": "array",
                        "items": {"type": "number"},
                        "description": "List of numbers"
                    },
                    "operation": {
                        "type": "string",
                        "enum": ["mean", "median", "mode", "std_dev", "sum"],
                        "description": "Statistical operation"
                    }
                },
                "required": ["numbers", "operation"]
            }
        ),
        Tool(
            name="unit_convert",
            description="Convert between units",
            input_schema={
                "type": "object",
                "properties": {
                    "value": {
                        "type": "number",
                        "description": "Value to convert"
                    },
                    "from_unit": {
                        "type": "string",
                        "description": "Source unit (e.g., 'km', 'miles', 'celsius', 'fahrenheit')"
                    },
                    "to_unit": {
                        "type": "string",
                        "description": "Target unit"
                    }
                },
                "required": ["value", "from_unit", "to_unit"]
            }
        ),
        Tool(
            name="history",
            description="Show calculation history",
            input_schema={
                "type": "object",
                "properties": {
                    "limit": {
                        "type": "integer",
                        "description": "Number of recent calculations to show",
                        "default": 10
                    }
                }
            }
        )
    ]

def safe_eval(expression: str) -> float:
    """Safely evaluate mathematical expressions."""
    # Allow only safe operations
    allowed_names = {
        k: v for k, v in math.__dict__.items() if not k.startswith("__")
    }
    allowed_names.update({
        "abs": abs,
        "round": round,
        "min": min,
        "max": max
    })
    
    # Remove spaces and validate characters
    expr = expression.replace(" ", "")
    valid_chars = set("0123456789+-*/().,")
    if not all(c in valid_chars for c in expr):
        raise ValueError(f"Invalid characters in expression: {expression}")
    
    try:
        # Replace ^ with ** for exponentiation
        expr = expr.replace("^", "**")
        result = eval(expr, {"__builtins__": {}}, allowed_names)
        return float(result)
    except Exception as e:
        raise ValueError(f"Invalid expression: {str(e)}")

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    """Execute calculator tools."""
    global last_result, calculation_history
    
    try:
        if name == "calculate":
            expression = arguments["expression"]
            
            # Replace 'ans' with last result
            if "ans" in expression.lower():
                expression = expression.lower().replace("ans", str(last_result))
            
            result = safe_eval(expression)
            last_result = result
            
            # Add to history
            history_entry = f"{expression} = {result}"
            calculation_history.append(history_entry)
            
            return [TextContent(
                type="text",
                text=f"{history_entry}"
            )]
        
        elif name == "scientific_calc":
            operation = arguments["operation"]
            value = float(arguments["value"])
            
            if operation == "sin":
                result = math.sin(math.radians(value))
            elif operation == "cos":
                result = math.cos(math.radians(value))
            elif operation == "tan":
                result = math.tan(math.radians(value))
            elif operation == "log":
                base = float(arguments.get("base", 10))
                result = math.log(value, base)
            elif operation == "ln":
                result = math.log(value)
            elif operation == "sqrt":
                result = math.sqrt(value)
            elif operation == "pow":
                base = float(arguments.get("base", 2))
                result = math.pow(value, base)
            elif operation == "factorial":
                result = math.factorial(int(value))
            else:
                return [TextContent(type="text", text=f"Unknown operation: {operation}")]
            
            last_result = result
            history_entry = f"{operation}({value}) = {result}"
            calculation_history.append(history_entry)
            
            return [TextContent(type="text", text=history_entry)]
        
        elif name == "statistics":
            numbers = arguments["numbers"]
            operation = arguments["operation"]
            
            if not numbers:
                return [TextContent(type="text", text="No numbers provided")]
            
            if operation == "mean":
                result = sum(numbers) / len(numbers)
            elif operation == "median":
                sorted_nums = sorted(numbers)
                n = len(sorted_nums)
                if n % 2 == 0:
                    result = (sorted_nums[n//2-1] + sorted_nums[n//2]) / 2
                else:
                    result = sorted_nums[n//2]
            elif operation == "mode":
                from collections import Counter
                counts = Counter(numbers)
                max_count = max(counts.values())
                modes = [k for k, v in counts.items() if v == max_count]
                result = modes[0] if len(modes) == 1 else modes
            elif operation == "std_dev":
                mean = sum(numbers) / len(numbers)
                variance = sum((x - mean) ** 2 for x in numbers) / len(numbers)
                result = math.sqrt(variance)
            elif operation == "sum":
                result = sum(numbers)
            else:
                return [TextContent(type="text", text=f"Unknown operation: {operation}")]
            
            return [TextContent(
                type="text",
                text=f"{operation} of {numbers} = {result}"
            )]
        
        elif name == "unit_convert":
            value = float(arguments["value"])
            from_unit = arguments["from_unit"].lower()
            to_unit = arguments["to_unit"].lower()
            
            # Distance conversions
            conversions = {
                ("km", "miles"): lambda x: x * 0.621371,
                ("miles", "km"): lambda x: x * 1.60934,
                ("m", "ft"): lambda x: x * 3.28084,
                ("ft", "m"): lambda x: x / 3.28084,
                ("celsius", "fahrenheit"): lambda x: x * 9/5 + 32,
                ("fahrenheit", "celsius"): lambda x: (x - 32) * 5/9,
                ("kg", "lbs"): lambda x: x * 2.20462,
                ("lbs", "kg"): lambda x: x / 2.20462,
            }
            
            key = (from_unit, to_unit)
            if key in conversions:
                result = conversions[key](value)
                return [TextContent(
                    type="text",
                    text=f"{value} {from_unit} = {result:.4f} {to_unit}"
                )]
            else:
                return [TextContent(
                    type="text",
                    text=f"Conversion from {from_unit} to {to_unit} not supported"
                )]
        
        elif name == "history":
            limit = arguments.get("limit", 10)
            recent = calculation_history[-limit:] if calculation_history else []
            
            if not recent:
                return [TextContent(type="text", text="No calculation history")]
            
            history_text = "Recent calculations:\n" + "\n".join(recent)
            return [TextContent(type="text", text=history_text)]
        
        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
            
    except Exception as e:
        return [TextContent(
            type="text",
            text=f"Error: {str(e)}"
        )]

async def main():
    """Run the calculator server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, {})

if __name__ == "__main__":
    asyncio.run(main())