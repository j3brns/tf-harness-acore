"""
Titanic Dataset MCP Lambda Tool

Provides the Titanic dataset via MCP protocol for the Gateway Tool example.
This Lambda function is invoked through the Bedrock AgentCore MCP Gateway.

Actions:
- fetch: Download and return the Titanic dataset
- schema: Return dataset schema information
"""

import json
import urllib.request
from typing import Any

# Titanic dataset URL (public GitHub)
TITANIC_URL = "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv"


def fetch_titanic_data() -> tuple[list, int]:
    """
    Fetch Titanic dataset from GitHub.

    Returns:
        tuple: (list of records, total count)
    """
    with urllib.request.urlopen(TITANIC_URL, timeout=30) as response:
        csv_data = response.read().decode('utf-8')

    lines = csv_data.strip().split('\n')
    headers = lines[0].split(',')

    records = []
    for line in lines[1:]:  # Skip header
        values = line.split(',')
        if len(values) >= len(headers):
            record = {}
            for i, header in enumerate(headers[:len(values)]):
                value = values[i].strip('"')
                # Convert numeric fields
                if header in ['PassengerId', 'Survived', 'Pclass', 'SibSp', 'Parch']:
                    try:
                        record[header] = int(value) if value else None
                    except ValueError:
                        record[header] = None
                elif header in ['Age', 'Fare']:
                    try:
                        record[header] = float(value) if value else None
                    except ValueError:
                        record[header] = None
                else:
                    record[header] = value if value else None
            records.append(record)

    return records, len(records)


def get_schema() -> dict:
    """Return Titanic dataset schema."""
    return {
        "columns": [
            {"name": "PassengerId", "type": "integer", "description": "Unique passenger identifier"},
            {"name": "Survived", "type": "integer", "description": "0 = No, 1 = Yes"},
            {"name": "Pclass", "type": "integer", "description": "Ticket class: 1 = 1st, 2 = 2nd, 3 = 3rd"},
            {"name": "Name", "type": "string", "description": "Passenger name"},
            {"name": "Sex", "type": "string", "description": "male or female"},
            {"name": "Age", "type": "float", "description": "Age in years"},
            {"name": "SibSp", "type": "integer", "description": "# of siblings/spouses aboard"},
            {"name": "Parch", "type": "integer", "description": "# of parents/children aboard"},
            {"name": "Ticket", "type": "string", "description": "Ticket number"},
            {"name": "Fare", "type": "float", "description": "Passenger fare"},
            {"name": "Cabin", "type": "string", "description": "Cabin number"},
            {"name": "Embarked", "type": "string", "description": "Port: C = Cherbourg, Q = Queenstown, S = Southampton"},
        ],
        "total_records": 891,
        "source": "Kaggle Titanic Dataset"
    }


def lambda_handler(event: dict, context: Any) -> dict:
    """
    MCP Lambda handler for Titanic dataset.

    Args:
        event: MCP request with 'action' and optional parameters
        context: Lambda context

    Returns:
        dict: MCP response with statusCode and body
    """
    print(f"Received event: {json.dumps(event)}")

    try:
        # Extract action from event
        action = event.get('action', 'fetch')

        if action == 'fetch':
            # Fetch dataset
            records, count = fetch_titanic_data()

            # Optionally limit records
            limit = event.get('limit', 100)
            if limit and limit < len(records):
                records = records[:limit]

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'success',
                    'dataset': 'titanic',
                    'format': 'json',
                    'total_records': count,
                    'returned_records': len(records),
                    'data': records
                })
            }

        elif action == 'schema':
            schema = get_schema()
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'success',
                    'schema': schema
                })
            }

        elif action == 'sample':
            # Return small sample for testing
            records, _ = fetch_titanic_data()
            sample = records[:10]
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'success',
                    'sample_size': len(sample),
                    'data': sample
                })
            }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'status': 'error',
                    'message': f"Unknown action: {action}. Valid actions: fetch, schema, sample"
                })
            }

    except urllib.error.URLError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'message': f"Failed to fetch dataset: {str(e)}"
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'message': f"Internal error: {str(e)}"
            })
        }


# Local testing
if __name__ == "__main__":
    # Test fetch action
    print("Testing fetch action:")
    result = lambda_handler({"action": "fetch", "limit": 5}, None)
    print(json.dumps(json.loads(result['body']), indent=2))

    print("\nTesting schema action:")
    result = lambda_handler({"action": "schema"}, None)
    print(json.dumps(json.loads(result['body']), indent=2))
