#!/usr/bin/env python3
"""
MCP server providing demo data generation and manipulation.
"""

import asyncio
import json
import random
import string
from datetime import datetime, timedelta
from typing import List, Dict, Any
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent, Resource

# Create server instance
server = Server("data-server")

# Sample data storage
data_store: Dict[str, List[Dict[str, Any]]] = {}

# Predefined data templates
FIRST_NAMES = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Iris", "Jack"]
LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Wilson", "Martinez"]
CITIES = ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix", "Philadelphia", "San Antonio", "San Diego", "Dallas", "Austin"]
PRODUCTS = ["Laptop", "Phone", "Tablet", "Monitor", "Keyboard", "Mouse", "Headphones", "Camera", "Printer", "Speaker"]
DEPARTMENTS = ["Engineering", "Sales", "Marketing", "HR", "Finance", "Operations", "Support", "Research", "Legal", "Admin"]

@server.list_resources()
async def list_resources():
    """List available data resources."""
    resources = []
    for collection_name, items in data_store.items():
        resources.append(
            Resource(
                uri=f"data://{collection_name}",
                name=f"{collection_name} Collection",
                description=f"Collection with {len(items)} items",
                mimeType="application/json"
            )
        )
    return resources

@server.read_resource()
async def read_resource(uri: str):
    """Read data from a collection."""
    collection_name = uri.replace("data://", "")
    if collection_name in data_store:
        data = data_store[collection_name]
        return json.dumps(data, indent=2)
    else:
        return f"Collection '{collection_name}' not found"

@server.list_tools()
async def list_tools():
    """List available data tools."""
    return [
        Tool(
            name="generate_users",
            description="Generate sample user data",
            input_schema={
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of users to generate",
                        "default": 10
                    },
                    "include_fields": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Fields to include: name, email, age, city, department, salary",
                        "default": ["name", "email", "age", "city"]
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="generate_products",
            description="Generate sample product data",
            input_schema={
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of products to generate",
                        "default": 10
                    },
                    "price_range": {
                        "type": "object",
                        "properties": {
                            "min": {"type": "number", "default": 10},
                            "max": {"type": "number", "default": 1000}
                        }
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="generate_transactions",
            description="Generate sample transaction data",
            input_schema={
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of transactions to generate",
                        "default": 20
                    },
                    "days_back": {
                        "type": "integer",
                        "description": "Generate transactions from the last N days",
                        "default": 30
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="query_data",
            description="Query data from a collection",
            input_schema={
                "type": "object",
                "properties": {
                    "collection": {
                        "type": "string",
                        "description": "Collection name"
                    },
                    "filter": {
                        "type": "object",
                        "description": "Filter criteria (e.g., {\"age\": {\"$gt\": 25}})"
                    },
                    "sort_by": {
                        "type": "string",
                        "description": "Field to sort by"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum results to return",
                        "default": 10
                    }
                },
                "required": ["collection"]
            }
        ),
        Tool(
            name="aggregate_data",
            description="Perform aggregations on data",
            input_schema={
                "type": "object",
                "properties": {
                    "collection": {
                        "type": "string",
                        "description": "Collection name"
                    },
                    "operation": {
                        "type": "string",
                        "enum": ["count", "sum", "avg", "min", "max", "group_by"],
                        "description": "Aggregation operation"
                    },
                    "field": {
                        "type": "string",
                        "description": "Field to aggregate on"
                    },
                    "group_field": {
                        "type": "string",
                        "description": "Field to group by (for group_by operation)"
                    }
                },
                "required": ["collection", "operation"]
            }
        ),
        Tool(
            name="clear_data",
            description="Clear a data collection",
            input_schema={
                "type": "object",
                "properties": {
                    "collection": {
                        "type": "string",
                        "description": "Collection name to clear"
                    }
                },
                "required": ["collection"]
            }
        )
    ]

def generate_email(first_name: str, last_name: str) -> str:
    """Generate email from name."""
    domains = ["email.com", "mail.co", "inbox.net", "post.org"]
    return f"{first_name.lower()}.{last_name.lower()}@{random.choice(domains)}"

def apply_filter(item: Dict, filter_criteria: Dict) -> bool:
    """Apply MongoDB-style filter to item."""
    for field, condition in filter_criteria.items():
        if isinstance(condition, dict):
            for op, value in condition.items():
                item_value = item.get(field)
                if op == "$gt" and not (item_value > value):
                    return False
                elif op == "$lt" and not (item_value < value):
                    return False
                elif op == "$gte" and not (item_value >= value):
                    return False
                elif op == "$lte" and not (item_value <= value):
                    return False
                elif op == "$eq" and not (item_value == value):
                    return False
                elif op == "$ne" and not (item_value != value):
                    return False
        else:
            if item.get(field) != condition:
                return False
    return True

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    """Execute data tools."""
    global data_store
    
    try:
        if name == "generate_users":
            count = arguments.get("count", 10)
            fields = arguments.get("include_fields", ["name", "email", "age", "city"])
            
            users = []
            for i in range(count):
                first = random.choice(FIRST_NAMES)
                last = random.choice(LAST_NAMES)
                user = {"id": i + 1}
                
                if "name" in fields:
                    user["name"] = f"{first} {last}"
                if "email" in fields:
                    user["email"] = generate_email(first, last)
                if "age" in fields:
                    user["age"] = random.randint(22, 65)
                if "city" in fields:
                    user["city"] = random.choice(CITIES)
                if "department" in fields:
                    user["department"] = random.choice(DEPARTMENTS)
                if "salary" in fields:
                    user["salary"] = random.randint(40000, 150000)
                
                users.append(user)
            
            data_store["users"] = users
            return [TextContent(
                type="text",
                text=f"Generated {count} users with fields: {', '.join(fields)}"
            )]
        
        elif name == "generate_products":
            count = arguments.get("count", 10)
            price_range = arguments.get("price_range", {"min": 10, "max": 1000})
            
            products = []
            for i in range(count):
                product = {
                    "id": i + 1,
                    "name": f"{random.choice(['Pro', 'Ultra', 'Mini', 'Max', 'Plus'])} {random.choice(PRODUCTS)}",
                    "price": round(random.uniform(price_range["min"], price_range["max"]), 2),
                    "stock": random.randint(0, 100),
                    "category": random.choice(["Electronics", "Accessories", "Computing", "Audio"]),
                    "rating": round(random.uniform(3.0, 5.0), 1)
                }
                products.append(product)
            
            data_store["products"] = products
            return [TextContent(
                type="text",
                text=f"Generated {count} products with prices ${price_range['min']}-${price_range['max']}"
            )]
        
        elif name == "generate_transactions":
            count = arguments.get("count", 20)
            days_back = arguments.get("days_back", 30)
            
            # Need users and products
            if "users" not in data_store or "products" not in data_store:
                return [TextContent(
                    type="text",
                    text="Please generate users and products first"
                )]
            
            transactions = []
            start_date = datetime.now() - timedelta(days=days_back)
            
            for i in range(count):
                user = random.choice(data_store["users"])
                product = random.choice(data_store["products"])
                quantity = random.randint(1, 5)
                
                transaction = {
                    "id": i + 1,
                    "user_id": user["id"],
                    "user_name": user.get("name", "Unknown"),
                    "product_id": product["id"],
                    "product_name": product["name"],
                    "quantity": quantity,
                    "price": product["price"],
                    "total": round(product["price"] * quantity, 2),
                    "date": (start_date + timedelta(days=random.randint(0, days_back))).isoformat(),
                    "status": random.choice(["completed", "pending", "shipped"])
                }
                transactions.append(transaction)
            
            data_store["transactions"] = transactions
            return [TextContent(
                type="text",
                text=f"Generated {count} transactions over the last {days_back} days"
            )]
        
        elif name == "query_data":
            collection = arguments["collection"]
            if collection not in data_store:
                return [TextContent(type="text", text=f"Collection '{collection}' not found")]
            
            data = data_store[collection]
            
            # Apply filter
            if "filter" in arguments and arguments["filter"]:
                data = [item for item in data if apply_filter(item, arguments["filter"])]
            
            # Sort
            if "sort_by" in arguments and arguments["sort_by"]:
                data = sorted(data, key=lambda x: x.get(arguments["sort_by"], 0))
            
            # Limit
            limit = arguments.get("limit", 10)
            data = data[:limit]
            
            return [TextContent(
                type="text",
                text=json.dumps(data, indent=2)
            )]
        
        elif name == "aggregate_data":
            collection = arguments["collection"]
            if collection not in data_store:
                return [TextContent(type="text", text=f"Collection '{collection}' not found")]
            
            data = data_store[collection]
            operation = arguments["operation"]
            field = arguments.get("field")
            
            if operation == "count":
                result = len(data)
            
            elif operation in ["sum", "avg", "min", "max"] and field:
                values = [item.get(field, 0) for item in data if field in item]
                if not values:
                    result = 0
                elif operation == "sum":
                    result = sum(values)
                elif operation == "avg":
                    result = sum(values) / len(values)
                elif operation == "min":
                    result = min(values)
                elif operation == "max":
                    result = max(values)
            
            elif operation == "group_by":
                group_field = arguments.get("group_field")
                if not group_field:
                    return [TextContent(type="text", text="group_field required for group_by")]
                
                groups = {}
                for item in data:
                    key = item.get(group_field, "Unknown")
                    if key not in groups:
                        groups[key] = []
                    groups[key].append(item)
                
                result = {k: len(v) for k, v in groups.items()}
            
            else:
                return [TextContent(type="text", text=f"Invalid operation or missing field")]
            
            return [TextContent(
                type="text",
                text=f"{operation} result: {json.dumps(result, indent=2)}"
            )]
        
        elif name == "clear_data":
            collection = arguments["collection"]
            if collection in data_store:
                del data_store[collection]
                return [TextContent(type="text", text=f"Cleared collection '{collection}'")]
            else:
                return [TextContent(type="text", text=f"Collection '{collection}' not found")]
        
        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
            
    except Exception as e:
        return [TextContent(
            type="text",
            text=f"Error: {str(e)}"
        )]

async def main():
    """Run the data server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, {})

if __name__ == "__main__":
    asyncio.run(main())