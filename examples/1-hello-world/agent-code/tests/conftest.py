"""
Pytest fixtures for Hello World agent tests.
"""
import pytest
from datetime import datetime
from unittest.mock import MagicMock, patch


@pytest.fixture
def mock_s3_client():
    """Mock boto3 S3 client with sample bucket data."""
    mock_client = MagicMock()
    mock_client.list_buckets.return_value = {
        'Buckets': [
            {'Name': 'bucket-1', 'CreationDate': datetime(2024, 1, 1)},
            {'Name': 'bucket-2', 'CreationDate': datetime(2024, 1, 2)},
            {'Name': 'bucket-3', 'CreationDate': datetime(2024, 1, 3)},
        ],
        'ResponseMetadata': {
            'HTTPHeaders': {
                'date': 'Mon, 01 Jan 2024 00:00:00 GMT'
            }
        }
    }
    return mock_client


@pytest.fixture
def mock_boto3(mock_s3_client):
    """Patch boto3.client to return mock S3 client."""
    with patch('boto3.client') as mock:
        mock.return_value = mock_s3_client
        yield mock


@pytest.fixture
def sample_event():
    """Sample input event for handler."""
    return {"action": "list_buckets"}


@pytest.fixture
def empty_event():
    """Empty event for handler."""
    return {}
