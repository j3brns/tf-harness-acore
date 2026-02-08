"""
Pytest fixtures for DeepResearch agent tests.
"""

import pytest
from unittest.mock import MagicMock, patch


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    """Clean environment variables before each test."""
    env_vars_to_clear = [
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "OTEL_EXPORTER_OTLP_HEADERS",
        "ENABLE_WEAVE",
        "WEAVE_PROJECT",
        "ENABLE_MEMORY",
        "AGENTCORE_MEMORY_ID",
        "AGENTCORE_ACTOR_ID",
        "AWS_REGION",
        "OUTPUTS_BUCKET_NAME",
        "SECRETS_ARN",
    ]
    for var in env_vars_to_clear:
        monkeypatch.delenv(var, raising=False)


@pytest.fixture
def mock_aws_region(monkeypatch):
    """Set AWS region for tests."""
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    return "us-east-1"


@pytest.fixture
def mock_s3_client():
    """Create a mock S3 client."""
    with patch("boto3.client") as mock_boto:
        mock_client = MagicMock()
        mock_boto.return_value = mock_client
        yield mock_client


@pytest.fixture
def mock_secrets_manager():
    """Create a mock Secrets Manager client."""
    with patch("boto3.client") as mock_boto:
        mock_client = MagicMock()
        mock_boto.return_value = mock_client
        yield mock_client


@pytest.fixture
def sample_session_id():
    """Provide a sample session ID."""
    return "test-session-12345"


@pytest.fixture
def sample_context():
    """Provide a sample AgentCore context."""
    return {
        "session_id": "context-session-67890",
        "invocation_id": "inv-abc123",
    }


@pytest.fixture
def sample_payload():
    """Provide a sample agent payload."""
    return {
        "prompt": "What is the current state of AI safety?",
    }


@pytest.fixture
def mock_agent():
    """Create a mock DeepSearch agent."""
    agent = MagicMock()
    agent.return_value = MagicMock(message="Test research results")
    agent.state = {"todos": []}
    return agent


@pytest.fixture
def temp_output_dir(tmp_path):
    """Create a temporary directory for test outputs."""
    output_dir = tmp_path / "outputs"
    output_dir.mkdir()

    # Create some test files
    (output_dir / "report.md").write_text("# Test Report\n\nSample content.")
    (output_dir / "data.json").write_text('{"key": "value"}')

    return output_dir
