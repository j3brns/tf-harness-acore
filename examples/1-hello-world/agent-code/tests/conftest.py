"""
Pytest fixtures for the minimal Strands baseline example.
"""

import pytest


@pytest.fixture
def addition_prompt():
    return "What is 7 + 5?"


@pytest.fixture
def comparison_prompt():
    return "When should I use this baseline example instead of deepresearch and integrated?"
