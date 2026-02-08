"""
Gateway Tool Agent - Titanic Data Analysis

Demonstrates MCP gateway integration with code interpreter for data analysis.
Uses a Lambda-based MCP tool to fetch the Titanic dataset, then analyzes
survival rates using pandas.

Features demonstrated:
- MCP gateway tool invocation
- Code interpreter for pandas analysis
- Multi-step agent workflow
- Structured insights output
"""

import json
import logging
from datetime import datetime
from typing import Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def invoke_mcp_tool(tool_name: str, action: str, **kwargs) -> dict:
    """
    Invoke an MCP tool through the gateway.

    In production, this calls the Bedrock AgentCore gateway.
    For local testing, returns mock data.
    """
    logger.info(f"Invoking MCP tool: {tool_name}, action: {action}")

    # Mock response for local testing
    # In production, this would invoke the actual MCP gateway
    if tool_name == "titanic-dataset" and action == "fetch":
        return {
            "status": "success",
            "data": get_mock_titanic_data()
        }
    elif tool_name == "titanic-dataset" and action == "schema":
        return {
            "status": "success",
            "columns": [
                "PassengerId", "Survived", "Pclass", "Name",
                "Sex", "Age", "SibSp", "Parch", "Fare", "Embarked"
            ]
        }

    return {"status": "error", "message": f"Unknown tool/action: {tool_name}/{action}"}


def get_mock_titanic_data() -> list:
    """Return sample Titanic data for local testing."""
    return [
        {"PassengerId": 1, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": 22, "Fare": 7.25},
        {"PassengerId": 2, "Survived": 1, "Pclass": 1, "Sex": "female", "Age": 38, "Fare": 71.28},
        {"PassengerId": 3, "Survived": 1, "Pclass": 3, "Sex": "female", "Age": 26, "Fare": 7.92},
        {"PassengerId": 4, "Survived": 1, "Pclass": 1, "Sex": "female", "Age": 35, "Fare": 53.10},
        {"PassengerId": 5, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": 35, "Fare": 8.05},
        {"PassengerId": 6, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": None, "Fare": 8.46},
        {"PassengerId": 7, "Survived": 0, "Pclass": 1, "Sex": "male", "Age": 54, "Fare": 51.86},
        {"PassengerId": 8, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": 2, "Fare": 21.08},
        {"PassengerId": 9, "Survived": 1, "Pclass": 3, "Sex": "female", "Age": 27, "Fare": 11.13},
        {"PassengerId": 10, "Survived": 1, "Pclass": 2, "Sex": "female", "Age": 14, "Fare": 30.07},
    ]


def analyze_survival(data: list) -> dict:
    """
    Analyze survival rates from Titanic data.

    Uses pandas if available, falls back to manual calculation.
    """
    try:
        import pandas as pd

        df = pd.DataFrame(data)

        # Calculate survival statistics
        total = len(df)
        survived = df['Survived'].sum()
        survival_rate = survived / total if total > 0 else 0

        # By class
        survival_by_class = df.groupby('Pclass')['Survived'].mean().to_dict()

        # By gender
        survival_by_gender = df.groupby('Sex')['Survived'].mean().to_dict()

        # Average age of survivors vs non-survivors
        avg_age_survived = df[df['Survived'] == 1]['Age'].mean()
        avg_age_died = df[df['Survived'] == 0]['Age'].mean()

        return {
            "total_passengers": total,
            "survivors": int(survived),
            "overall_survival_rate": round(survival_rate, 3),
            "survival_by_class": {
                str(k): round(v, 3) for k, v in survival_by_class.items()
            },
            "survival_by_gender": {
                k: round(v, 3) for k, v in survival_by_gender.items()
            },
            "avg_age": {
                "survivors": round(avg_age_survived, 1) if pd.notna(avg_age_survived) else None,
                "non_survivors": round(avg_age_died, 1) if pd.notna(avg_age_died) else None
            }
        }

    except ImportError:
        # Manual calculation without pandas
        total = len(data)
        survived = sum(1 for p in data if p.get('Survived') == 1)
        survival_rate = survived / total if total > 0 else 0

        return {
            "total_passengers": total,
            "survivors": survived,
            "overall_survival_rate": round(survival_rate, 3),
            "note": "Detailed analysis requires pandas"
        }


def generate_insights(analysis: dict) -> list:
    """Generate human-readable insights from analysis."""
    insights = []

    survival_rate = analysis.get('overall_survival_rate', 0)
    insights.append(f"Overall survival rate was {survival_rate * 100:.1f}%")

    if 'survival_by_class' in analysis:
        class_rates = analysis['survival_by_class']
        if '1' in class_rates:
            insights.append(
                f"First class passengers had {class_rates['1'] * 100:.1f}% survival rate"
            )
        if '3' in class_rates:
            insights.append(
                f"Third class passengers had {class_rates['3'] * 100:.1f}% survival rate"
            )

    if 'survival_by_gender' in analysis:
        gender_rates = analysis['survival_by_gender']
        if 'female' in gender_rates and 'male' in gender_rates:
            female_rate = gender_rates['female'] * 100
            male_rate = gender_rates['male'] * 100
            insights.append(
                f"Women survived at {female_rate:.1f}% vs men at {male_rate:.1f}%"
            )

    return insights


def handler(event: dict, context: Any) -> dict:
    """
    Main handler for the Titanic Analysis agent.

    Workflow:
    1. Fetch Titanic dataset via MCP tool
    2. Analyze survival rates using code interpreter (pandas)
    3. Generate insights
    4. Return structured response
    """
    logger.info("Titanic Analysis agent invoked")
    logger.info(f"Event: {json.dumps(event)}")

    try:
        # Step 1: Fetch dataset from MCP tool
        logger.info("Step 1: Fetching Titanic dataset...")
        dataset_response = invoke_mcp_tool("titanic-dataset", "fetch")

        if dataset_response.get("status") != "success":
            raise Exception(f"Failed to fetch dataset: {dataset_response}")

        data = dataset_response.get("data", [])
        logger.info(f"Fetched {len(data)} records")

        # Step 2: Analyze survival rates
        logger.info("Step 2: Analyzing survival rates...")
        analysis = analyze_survival(data)

        # Step 3: Generate insights
        logger.info("Step 3: Generating insights...")
        insights = generate_insights(analysis)

        # Build response
        result = {
            "status": "success",
            "message": "Titanic survival analysis complete",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "analysis": analysis,
            "insights": insights
        }

        logger.info("Analysis complete")
        return result

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "status": "error",
            "message": f"Analysis failed: {str(e)}",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }


# Allow local testing
if __name__ == "__main__":
    test_event = {"action": "analyze"}
    result = handler(test_event, None)
    print(json.dumps(result, indent=2))
