"""
Pytest fixtures for Gateway Tool agent tests.
"""
import pytest


@pytest.fixture
def sample_titanic_data():
    """Sample Titanic dataset for testing."""
    return [
        {"PassengerId": 1, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": 22, "Fare": 7.25},
        {"PassengerId": 2, "Survived": 1, "Pclass": 1, "Sex": "female", "Age": 38, "Fare": 71.28},
        {"PassengerId": 3, "Survived": 1, "Pclass": 3, "Sex": "female", "Age": 26, "Fare": 7.92},
        {"PassengerId": 4, "Survived": 1, "Pclass": 1, "Sex": "female", "Age": 35, "Fare": 53.10},
        {"PassengerId": 5, "Survived": 0, "Pclass": 3, "Sex": "male", "Age": 35, "Fare": 8.05},
    ]


@pytest.fixture
def sample_event():
    """Sample input event for handler."""
    return {"action": "analyze"}


@pytest.fixture
def large_titanic_data():
    """Larger Titanic dataset for testing edge cases."""
    data = []
    for i in range(100):
        data.append({
            "PassengerId": i + 1,
            "Survived": 1 if i % 3 == 0 else 0,  # ~33% survival rate
            "Pclass": (i % 3) + 1,
            "Sex": "female" if i % 2 == 0 else "male",
            "Age": 20 + (i % 50),
            "Fare": 10.0 + (i * 0.5)
        })
    return data
