"""Pytest fixtures for LangGraph baseline example tests."""

import pytest


@pytest.fixture
def sample_event():
    """Default prompt event."""
    return {"prompt": "What can you do?"}


@pytest.fixture
def echo_event():
    """Prompt that exercises the non-capabilities branch."""
    return {"message": "Echo this back"}
