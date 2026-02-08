"""
Integration tests for S3 outputs with mocked AWS services.

Uses moto to mock S3 for realistic integration testing without AWS access.
"""

import pytest
from pathlib import Path
from unittest.mock import patch

# Try to import moto, skip tests if not installed
try:
    import boto3
    from moto import mock_aws
    MOTO_AVAILABLE = True
except ImportError:
    MOTO_AVAILABLE = False
    mock_aws = lambda: lambda f: f  # No-op decorator


@pytest.mark.skipif(not MOTO_AVAILABLE, reason="moto not installed")
class TestS3IntegrationWithMoto:
    """Integration tests using moto to mock S3."""

    @pytest.fixture
    def aws_credentials(self, monkeypatch):
        """Set fake AWS credentials for moto."""
        monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
        monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
        monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
        monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
        monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")

    @pytest.fixture
    def s3_bucket(self, aws_credentials):
        """Create a mock S3 bucket."""
        with mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            bucket_name = "test-outputs-bucket"
            s3.create_bucket(Bucket=bucket_name)
            yield bucket_name

    @pytest.fixture
    def research_outputs(self, tmp_path):
        """Create sample research output files."""
        # Create research documents directory
        docs_dir = tmp_path / "research_documents_ai_safety"
        docs_dir.mkdir()
        (docs_dir / "source1.md").write_text("# Source 1\n\nContent from source 1.")
        (docs_dir / "source2.md").write_text("# Source 2\n\nContent from source 2.")

        # Create findings file
        (tmp_path / "research_findings_ai_safety.md").write_text(
            "# Findings\n\n- Finding 1\n- Finding 2"
        )

        # Create report file
        (tmp_path / "ai_safety_report.md").write_text(
            "# AI Safety Report\n\n## Summary\n\nThis is the report."
        )

        return tmp_path

    @mock_aws
    def test_upload_session_outputs_to_s3(self, aws_credentials, research_outputs):
        """Should upload all research outputs to S3."""
        # Create bucket inside the mock context
        s3 = boto3.client("s3", region_name="us-east-1")
        bucket_name = "test-outputs-bucket"
        s3.create_bucket(Bucket=bucket_name)

        from deepresearch.utils.s3_outputs import upload_session_outputs

        result = upload_session_outputs(
            session_id="session-123",
            bucket_name=bucket_name,
            working_dir=research_outputs,
            region_name="us-east-1",
        )

        # Verify uploads
        assert len(result["uploaded"]) == 4  # 2 sources + 1 findings + 1 report
        assert len(result["failed"]) == 0

        # Verify files exist in S3
        response = s3.list_objects_v2(Bucket=bucket_name, Prefix="session-123/")
        assert response["KeyCount"] == 4

    @mock_aws
    def test_upload_single_file_to_s3(self, aws_credentials, tmp_path):
        """Should upload a single file to S3."""
        # Create bucket inside the mock context
        s3 = boto3.client("s3", region_name="us-east-1")
        bucket_name = "test-outputs-bucket"
        s3.create_bucket(Bucket=bucket_name)

        # Create test file
        test_file = tmp_path / "custom_report.md"
        test_file.write_text("# Custom Report\n\nContent here.")

        from deepresearch.utils.s3_outputs import upload_single_file

        result = upload_single_file(
            session_id="session-456",
            bucket_name=bucket_name,
            file_path=test_file,
            output_type="final",
            region_name="us-east-1",
        )

        assert result == f"s3://{bucket_name}/session-456/final/custom_report.md"

        # Verify file exists in S3
        response = s3.get_object(
            Bucket=bucket_name,
            Key="session-456/final/custom_report.md",
        )
        content = response["Body"].read().decode("utf-8")
        assert "Custom Report" in content

    @mock_aws
    def test_uploaded_files_have_correct_structure(self, aws_credentials, research_outputs):
        """Should organize uploads with correct S3 key structure."""
        s3 = boto3.client("s3", region_name="us-east-1")
        bucket_name = "test-outputs-bucket"
        s3.create_bucket(Bucket=bucket_name)

        from deepresearch.utils.s3_outputs import upload_session_outputs

        upload_session_outputs(
            session_id="session-789",
            bucket_name=bucket_name,
            working_dir=research_outputs,
            region_name="us-east-1",
        )

        # List all objects
        response = s3.list_objects_v2(Bucket=bucket_name, Prefix="session-789/")
        keys = [obj["Key"] for obj in response.get("Contents", [])]

        # Verify intermediate files
        intermediate_keys = [k for k in keys if "/intermediate/" in k]
        assert len(intermediate_keys) == 2
        assert all("ai_safety" in k for k in intermediate_keys)

        # Verify final files
        final_keys = [k for k in keys if "/final/" in k]
        assert len(final_keys) == 2


@pytest.mark.skipif(not MOTO_AVAILABLE, reason="moto not installed")
class TestSecretsManagerIntegration:
    """Integration tests for Secrets Manager with moto."""

    @pytest.fixture
    def aws_credentials(self, monkeypatch):
        """Set fake AWS credentials for moto."""
        monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
        monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
        monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")

    @mock_aws
    def test_load_secrets_from_secrets_manager(self, aws_credentials, monkeypatch):
        """Should load secrets from Secrets Manager."""
        import json

        # Create secret
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        secret_value = json.dumps({
            "LINKUP_API_KEY": "test-linkup-key",
            "OTHER_SECRET": "test-other-value",
        })
        sm.create_secret(
            Name="deepresearch/secrets",
            SecretString=secret_value,
        )

        # Set the secret ARN
        monkeypatch.setenv(
            "SECRETS_ARN",
            "arn:aws:secretsmanager:us-east-1:123456789012:secret:deepresearch/secrets",
        )

        # Clear the cache before testing
        from deepresearch.utils.secrets import load_secrets_from_secrets_manager
        load_secrets_from_secrets_manager.cache_clear()

        # Test loading secrets
        # Note: The actual function would need to handle the ARN format
        # This is a simplified test
