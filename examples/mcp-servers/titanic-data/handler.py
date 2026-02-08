"""
Titanic Data MCP Server

A Lambda-based MCP server that serves the Titanic dataset for analysis.
Implements the MCP protocol for tool invocation from Bedrock AgentCore Gateway.

Tools provided:
- fetch_dataset: Get full or partial Titanic dataset
- get_schema: Get dataset column information
- query: Run simple queries on the data
- get_statistics: Get summary statistics
"""

import json
import logging
from typing import Any
from io import StringIO

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Embedded Titanic dataset (first 100 rows for demo)
# In production, this would come from S3 or a database
TITANIC_DATA = """PassengerId,Survived,Pclass,Name,Sex,Age,SibSp,Parch,Ticket,Fare,Cabin,Embarked
1,0,3,"Braund, Mr. Owen Harris",male,22,1,0,A/5 21171,7.25,,S
2,1,1,"Cumings, Mrs. John Bradley (Florence Briggs Thayer)",female,38,1,0,PC 17599,71.2833,C85,C
3,1,3,"Heikkinen, Miss. Laina",female,26,0,0,STON/O2. 3101282,7.925,,S
4,1,1,"Futrelle, Mrs. Jacques Heath (Lily May Peel)",female,35,1,0,113803,53.1,C123,S
5,0,3,"Allen, Mr. William Henry",male,35,0,0,373450,8.05,,S
6,0,3,"Moran, Mr. James",male,,0,0,330877,8.4583,,Q
7,0,1,"McCarthy, Mr. Timothy J",male,54,0,0,17463,51.8625,E46,S
8,0,3,"Palsson, Master. Gosta Leonard",male,2,3,1,349909,21.075,,S
9,1,3,"Johnson, Mrs. Oscar W (Elisabeth Vilhelmina Berg)",female,27,0,2,347742,11.1333,,S
10,1,2,"Nasser, Mrs. Nicholas (Adele Achem)",female,14,1,0,237736,30.0708,,C
11,1,3,"Sandstrom, Miss. Marguerite Rut",female,4,1,1,PP 9549,16.7,G6,S
12,1,1,"Bonnell, Miss. Elizabeth",female,58,0,0,113783,26.55,C103,S
13,0,3,"Saundercock, Mr. William Henry",male,20,0,0,A/5. 2151,8.05,,S
14,0,3,"Andersson, Mr. Anders Johan",male,39,1,5,347082,31.275,,S
15,0,3,"Vestrom, Miss. Hulda Amanda Adolfina",female,14,0,0,350406,7.8542,,S
16,1,2,"Hewlett, Mrs. (Mary D Kingcome)",female,55,0,0,248706,16,,S
17,0,3,"Rice, Master. Eugene",male,2,4,1,382652,29.125,,Q
18,1,2,"Williams, Mr. Charles Eugene",male,,0,0,244373,13,,S
19,0,3,"Vander Planke, Mrs. Julius (Emelia Maria Vandemoortele)",female,31,1,0,345763,18,,S
20,1,3,"Masselmani, Mrs. Fatima",female,,0,0,2649,7.225,,C
21,0,2,"Fynney, Mr. Joseph J",male,35,0,0,239865,26,,S
22,1,2,"Beesley, Mr. Lawrence",male,34,0,0,248698,13,D56,S
23,1,3,"McGowan, Miss. Anna",female,15,0,0,330923,8.0292,,Q
24,1,1,"Sloper, Mr. William Thompson",male,28,0,0,113788,35.5,A6,S
25,0,3,"Palsson, Miss. Torborg Danira",female,8,3,1,349909,21.075,,S
26,1,3,"Asplund, Mrs. Carl Oscar (Selma Augusta Emilia Johansson)",female,38,1,5,347077,31.3875,,S
27,0,3,"Emir, Mr. Farred Chehab",male,,0,0,2631,7.225,,C
28,0,1,"Fortune, Mr. Charles Alexander",male,19,3,2,19950,263,C23 C25 C27,S
29,1,3,"O'Dwyer, Miss. Ellen",female,,0,0,330959,7.8792,,Q
30,0,3,"Todoroff, Mr. Lalio",male,,0,0,349216,7.8958,,S
31,0,1,"Uruchurtu, Don. Manuel E",male,40,0,0,PC 17601,27.7208,,C
32,1,1,"Spencer, Mrs. William Augustus (Marie Eugenie)",female,,1,0,PC 17569,146.5208,B78,C
33,1,3,"Glynn, Miss. Mary Agatha",female,,0,0,335677,7.75,,Q
34,0,2,"Wheadon, Mr. Edward H",male,66,0,0,C.A. 24579,10.5,,S
35,0,1,"Meyer, Mr. Edgar Joseph",male,28,1,0,PC 17604,82.1708,,C
36,0,1,"Holverson, Mr. Alexander Oskar",male,42,1,0,113789,52,,S
37,1,3,"Mamee, Mr. Hanna",male,,0,0,2677,7.2292,,C
38,0,3,"Cann, Mr. Ernest Charles",male,21,0,0,A./5. 2152,8.05,,S
39,0,3,"Vander Planke, Miss. Augusta Maria",female,18,2,0,345764,18,,S
40,1,3,"Nicola-Yarred, Miss. Jamila",female,14,1,0,2651,11.2417,,C
41,0,3,"Ahlin, Mrs. Johan (Johanna Persdotter Larsson)",female,40,1,0,7546,9.475,,S
42,0,2,"Turpin, Mrs. William John Robert (Dorothy Ann Wonnacott)",female,27,1,0,11668,21,,S
43,0,3,"Kraeff, Mr. Theodor",male,,0,0,349253,7.8958,,C
44,1,2,"Laroche, Miss. Simonne Marie Anne Andree",female,3,1,2,SC/Paris 2123,41.5792,,C
45,1,3,"Devaney, Miss. Margaret Delia",female,19,0,0,330958,7.8792,,Q
46,0,3,"Rogers, Mr. William John",male,,0,0,S.C./A.4. 23567,8.05,,S
47,0,3,"Lennon, Mr. Denis",male,,1,0,370371,15.5,,Q
48,1,3,"O'Driscoll, Miss. Bridget",female,,0,0,14311,7.75,,Q
49,0,3,"Samaan, Mr. Youssef",male,,2,0,2662,21.6792,,C
50,0,3,"Arnold-Franchi, Mrs. Josef (Josefine Franchi)",female,18,1,0,349237,17.8,,S
"""


def parse_csv(csv_string: str) -> list[dict]:
    """Parse CSV string into list of dictionaries."""
    import csv
    reader = csv.DictReader(StringIO(csv_string.strip()))
    return list(reader)


def get_data() -> list[dict]:
    """Get parsed Titanic data."""
    return parse_csv(TITANIC_DATA)


def tool_fetch_dataset(params: dict) -> dict:
    """
    Fetch the Titanic dataset.

    Parameters:
        limit: Maximum number of rows to return (default: all)
        offset: Number of rows to skip (default: 0)
        columns: List of columns to include (default: all)
    """
    data = get_data()

    limit = params.get("limit", len(data))
    offset = params.get("offset", 0)
    columns = params.get("columns")

    # Apply offset and limit
    result = data[offset:offset + limit]

    # Filter columns if specified
    if columns:
        result = [{k: v for k, v in row.items() if k in columns} for row in result]

    return {
        "success": True,
        "total_rows": len(data),
        "returned_rows": len(result),
        "offset": offset,
        "data": result
    }


def tool_get_schema(params: dict) -> dict:
    """Get the dataset schema with column information."""
    data = get_data()

    if not data:
        return {"success": False, "error": "No data available"}

    # Analyze columns
    columns = []
    sample_row = data[0]

    for col_name in sample_row.keys():
        # Determine type from data
        values = [row.get(col_name) for row in data if row.get(col_name)]

        # Infer type
        col_type = "string"
        if values:
            try:
                [int(v) for v in values[:10]]
                col_type = "integer"
            except (ValueError, TypeError):
                try:
                    [float(v) for v in values[:10]]
                    col_type = "float"
                except (ValueError, TypeError):
                    col_type = "string"

        columns.append({
            "name": col_name,
            "type": col_type,
            "non_null_count": len(values),
            "sample_values": values[:3]
        })

    return {
        "success": True,
        "total_rows": len(data),
        "total_columns": len(columns),
        "columns": columns
    }


def tool_query(params: dict) -> dict:
    """
    Run a simple query on the dataset.

    Parameters:
        filter: Dictionary of column: value pairs for filtering
        columns: List of columns to return
        limit: Maximum rows to return
    """
    data = get_data()

    filters = params.get("filter", {})
    columns = params.get("columns")
    limit = params.get("limit", 100)

    # Apply filters
    result = []
    for row in data:
        match = True
        for col, value in filters.items():
            if str(row.get(col, "")).lower() != str(value).lower():
                match = False
                break
        if match:
            if columns:
                result.append({k: v for k, v in row.items() if k in columns})
            else:
                result.append(row)
            if len(result) >= limit:
                break

    return {
        "success": True,
        "query": filters,
        "returned_rows": len(result),
        "data": result
    }


def tool_get_statistics(params: dict) -> dict:
    """
    Get summary statistics for the dataset.

    Parameters:
        columns: List of columns to analyze (default: numeric columns)
    """
    data = get_data()

    if not data:
        return {"success": False, "error": "No data available"}

    stats = {
        "total_rows": len(data),
        "columns": {}
    }

    # Calculate statistics for numeric columns
    numeric_cols = ["Survived", "Pclass", "Age", "SibSp", "Parch", "Fare"]
    requested_cols = params.get("columns", numeric_cols)

    for col in requested_cols:
        values = []
        for row in data:
            try:
                val = row.get(col)
                if val and val != "":
                    values.append(float(val))
            except (ValueError, TypeError):
                continue

        if values:
            stats["columns"][col] = {
                "count": len(values),
                "mean": round(sum(values) / len(values), 3),
                "min": min(values),
                "max": max(values),
                "sum": round(sum(values), 3)
            }

    # Add categorical stats
    stats["survival_rate"] = round(
        sum(1 for row in data if row.get("Survived") == "1") / len(data), 3
    )
    stats["gender_distribution"] = {
        "male": sum(1 for row in data if row.get("Sex") == "male"),
        "female": sum(1 for row in data if row.get("Sex") == "female")
    }
    stats["class_distribution"] = {
        "1": sum(1 for row in data if row.get("Pclass") == "1"),
        "2": sum(1 for row in data if row.get("Pclass") == "2"),
        "3": sum(1 for row in data if row.get("Pclass") == "3")
    }

    return {
        "success": True,
        "statistics": stats
    }


# Tool registry
TOOLS = {
    "fetch_dataset": {
        "handler": tool_fetch_dataset,
        "description": "Fetch Titanic passenger data",
        "parameters": {
            "limit": "Maximum rows to return",
            "offset": "Rows to skip",
            "columns": "List of columns to include"
        }
    },
    "get_schema": {
        "handler": tool_get_schema,
        "description": "Get dataset schema and column information",
        "parameters": {}
    },
    "query": {
        "handler": tool_query,
        "description": "Query dataset with filters",
        "parameters": {
            "filter": "Column:value filter pairs",
            "columns": "Columns to return",
            "limit": "Maximum rows"
        }
    },
    "get_statistics": {
        "handler": tool_get_statistics,
        "description": "Get summary statistics",
        "parameters": {
            "columns": "Columns to analyze"
        }
    }
}


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Lambda handler for MCP tool invocation.

    Expected event format (from Bedrock AgentCore Gateway):
    {
        "tool": "fetch_dataset",
        "parameters": {"limit": 10}
    }

    Or MCP protocol format:
    {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": "fetch_dataset",
            "arguments": {"limit": 10}
        },
        "id": "request-123"
    }
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Handle MCP protocol format
        if "jsonrpc" in event:
            method = event.get("method", "")
            request_id = event.get("id")

            if method == "tools/list":
                # Return available tools
                tools_list = [
                    {
                        "name": name,
                        "description": info["description"],
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                k: {"type": "string", "description": v}
                                for k, v in info["parameters"].items()
                            }
                        }
                    }
                    for name, info in TOOLS.items()
                ]
                return {
                    "jsonrpc": "2.0",
                    "result": {"tools": tools_list},
                    "id": request_id
                }

            elif method == "tools/call":
                params = event.get("params", {})
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})

                if tool_name not in TOOLS:
                    return {
                        "jsonrpc": "2.0",
                        "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"},
                        "id": request_id
                    }

                result = TOOLS[tool_name]["handler"](tool_args)
                return {
                    "jsonrpc": "2.0",
                    "result": {"content": [{"type": "text", "text": json.dumps(result)}]},
                    "id": request_id
                }

        # Handle simple format (direct invocation)
        tool_name = event.get("tool", event.get("action", "fetch_dataset"))
        tool_params = event.get("parameters", event.get("params", {}))

        if tool_name not in TOOLS:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": f"Unknown tool: {tool_name}", "available": list(TOOLS.keys())})
            }

        result = TOOLS[tool_name]["handler"](tool_params)

        return {
            "statusCode": 200,
            "body": json.dumps(result)
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }


# Local testing
if __name__ == "__main__":
    # Test fetch
    print("=== Fetch Dataset ===")
    result = lambda_handler({"tool": "fetch_dataset", "parameters": {"limit": 5}}, None)
    print(json.dumps(json.loads(result["body"]), indent=2))

    # Test schema
    print("\n=== Get Schema ===")
    result = lambda_handler({"tool": "get_schema", "parameters": {}}, None)
    print(json.dumps(json.loads(result["body"]), indent=2))

    # Test statistics
    print("\n=== Get Statistics ===")
    result = lambda_handler({"tool": "get_statistics", "parameters": {}}, None)
    print(json.dumps(json.loads(result["body"]), indent=2))

    # Test query
    print("\n=== Query (females in 1st class) ===")
    result = lambda_handler({
        "tool": "query",
        "parameters": {"filter": {"Sex": "female", "Pclass": "1"}, "limit": 5}
    }, None)
    print(json.dumps(json.loads(result["body"]), indent=2))
