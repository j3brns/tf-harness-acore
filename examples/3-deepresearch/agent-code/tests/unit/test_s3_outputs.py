"""
Unit tests for deepresearch.utils.s3_outputs module.
"""

import pytest
from pathlib import Path
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

from deepresearch.utils.s3_outputs import (
    get_s3_client,
    upload_file_to_s3,
    collect_output_files,
    upload_session_outputs,
    upload_single_file,
)


class TestGetS3Client:
    """Tests for get_s3_client function."""

    @patch("deepresearch.utils.s3_outputs.boto3.client")
    def test_creates_client_with_region(self, mock_boto_client):
        """Should create S3 client with specified region."""
        mock_client = MagicMock()
        mock_boto_client.return_value = mock_client

        result = get_s3_client(region_name="us-west-2")

        mock_boto_client.assert_called_once_with("s3", region_name="us-west-2")
        assert result == mock_client

    @patch("deepresearch.utils.s3_outputs.boto3.client")
    def test_uses_env_region_when_not_specified(self, mock_boto_client, monkeypatch):
        """Should use AWS_REGION from environment when not specified."""
        monkeypatch.setenv("AWS_REGION", "eu-west-1")
        mock_client = MagicMock()
        mock_boto_client.return_value = mock_client

        result = get_s3_client()

        mock_boto_client.assert_called_once_with("s3", region_name="eu-west-1")


class TestUploadFileToS3:
    """Tests for upload_file_to_s3 function."""

    def test_uploads_markdown_file(self, tmp_path):
        """Should upload markdown file with correct content type."""
        mock_client = MagicMock()
        test_file = tmp_path / "report.md"
        test_file.write_text("# Test Report")

        result = upload_file_to_s3(
            s3_client=mock_client,
            file_path=test_file,
            bucket_name="test-bucket",
            s3_key="session/report.md",
        )

        assert result is True
        mock_client.upload_file.assert_called_once()
        call_args = mock_client.upload_file.call_args
        assert call_args[0][1] == "test-bucket"
        assert call_args[0][2] == "session/report.md"
        assert call_args[1]["ExtraArgs"]["ContentType"] == "text/markdown"

    def test_uploads_text_file(self, tmp_path):
        """Should upload text file with correct content type."""
        mock_client = MagicMock()
        test_file = tmp_path / "data.txt"
        test_file.write_text("Test data")

        result = upload_file_to_s3(
            s3_client=mock_client,
            file_path=test_file,
            bucket_name="test-bucket",
            s3_key="session/data.txt",
        )

        assert result is True
        call_args = mock_client.upload_file.call_args
        assert call_args[1]["ExtraArgs"]["ContentType"] == "text/plain"

    def test_returns_false_on_error(self, tmp_path):
        """Should return False when upload fails."""
        mock_client = MagicMock()
        mock_client.upload_file.side_effect = ClientError(
            {"Error": {"Code": "AccessDenied", "Message": "Access Denied"}},
            "PutObject",
        )
        test_file = tmp_path / "report.md"
        test_file.write_text("# Test")

        result = upload_file_to_s3(
            s3_client=mock_client,
            file_path=test_file,
            bucket_name="test-bucket",
            s3_key="session/report.md",
        )

        assert result is False


class TestCollectOutputFiles:
    """Tests for collect_output_files function."""

    def test_collects_research_documents(self, tmp_path):
        """Should collect files from research_documents directories."""
        # Create research documents directory
        docs_dir = tmp_path / "research_documents_ai_safety"
        docs_dir.mkdir()
        (docs_dir / "source1.md").write_text("Source 1")
        (docs_dir / "source2.txt").write_text("Source 2")

        result = collect_output_files(tmp_path)

        assert len(result["intermediate"]) == 2
        assert len(result["final"]) == 0

    def test_collects_findings_files(self, tmp_path):
        """Should collect findings files."""
        (tmp_path / "research_findings_summary.md").write_text("Findings")

        result = collect_output_files(tmp_path)

        assert len(result["final"]) == 1
        assert "findings" in result["final"][0].name

    def test_collects_report_files(self, tmp_path):
        """Should collect report files."""
        (tmp_path / "ai_safety_report.md").write_text("Report")

        result = collect_output_files(tmp_path)

        assert len(result["final"]) == 1
        assert "report" in result["final"][0].name

    def test_ignores_unrelated_files(self, tmp_path):
        """Should ignore files that don't match patterns."""
        (tmp_path / "random_file.md").write_text("Random")
        (tmp_path / "notes.txt").write_text("Notes")

        result = collect_output_files(tmp_path)

        assert len(result["intermediate"]) == 0
        assert len(result["final"]) == 0


class TestUploadSessionOutputs:
    """Tests for upload_session_outputs function."""

    def test_returns_empty_when_no_bucket(self):
        """Should return empty result when bucket not specified."""
        result = upload_session_outputs(
            session_id="session-123",
            bucket_name="",
        )

        assert result == {"uploaded": [], "failed": []}

    @patch("deepresearch.utils.s3_outputs.get_s3_client")
    @patch("deepresearch.utils.s3_outputs.upload_file_to_s3")
    def test_uploads_all_outputs(self, mock_upload, mock_client, tmp_path):
        """Should upload both intermediate and final outputs."""
        # Setup test files
        docs_dir = tmp_path / "research_documents_topic"
        docs_dir.mkdir()
        (docs_dir / "source.md").write_text("Source")
        (tmp_path / "research_findings_topic.md").write_text("Findings")

        mock_upload.return_value = True
        mock_s3 = MagicMock()
        mock_client.return_value = mock_s3

        result = upload_session_outputs(
            session_id="session-123",
            bucket_name="test-bucket",
            working_dir=tmp_path,
        )

        assert len(result["uploaded"]) == 2
        assert len(result["failed"]) == 0
        assert mock_upload.call_count == 2

    @patch("deepresearch.utils.s3_outputs.get_s3_client")
    @patch("deepresearch.utils.s3_outputs.upload_file_to_s3")
    def test_tracks_failed_uploads(self, mock_upload, mock_client, tmp_path):
        """Should track failed uploads."""
        (tmp_path / "research_findings_topic.md").write_text("Findings")

        mock_upload.return_value = False
        mock_s3 = MagicMock()
        mock_client.return_value = mock_s3

        result = upload_session_outputs(
            session_id="session-123",
            bucket_name="test-bucket",
            working_dir=tmp_path,
        )

        assert len(result["uploaded"]) == 0
        assert len(result["failed"]) == 1


class TestUploadSingleFile:
    """Tests for upload_single_file function."""

    def test_returns_none_when_no_bucket(self, tmp_path):
        """Should return None when bucket not specified."""
        test_file = tmp_path / "test.md"
        test_file.write_text("Test")

        result = upload_single_file(
            session_id="session-123",
            bucket_name="",
            file_path=test_file,
        )

        assert result is None

    def test_returns_none_when_file_not_found(self):
        """Should return None when file doesn't exist."""
        result = upload_single_file(
            session_id="session-123",
            bucket_name="test-bucket",
            file_path="/nonexistent/file.md",
        )

        assert result is None

    @patch("deepresearch.utils.s3_outputs.get_s3_client")
    @patch("deepresearch.utils.s3_outputs.upload_file_to_s3")
    def test_uploads_file_successfully(self, mock_upload, mock_client, tmp_path):
        """Should return S3 URI when upload succeeds."""
        test_file = tmp_path / "report.md"
        test_file.write_text("# Report")

        mock_upload.return_value = True
        mock_s3 = MagicMock()
        mock_client.return_value = mock_s3

        result = upload_single_file(
            session_id="session-123",
            bucket_name="test-bucket",
            file_path=test_file,
        )

        assert result == "s3://test-bucket/session-123/final/report.md"

    @patch("deepresearch.utils.s3_outputs.get_s3_client")
    @patch("deepresearch.utils.s3_outputs.upload_file_to_s3")
    def test_uses_output_type_in_path(self, mock_upload, mock_client, tmp_path):
        """Should use output_type in S3 path."""
        test_file = tmp_path / "source.md"
        test_file.write_text("Source")

        mock_upload.return_value = True
        mock_s3 = MagicMock()
        mock_client.return_value = mock_s3

        result = upload_single_file(
            session_id="session-123",
            bucket_name="test-bucket",
            file_path=test_file,
            output_type="intermediate",
        )

        assert result == "s3://test-bucket/session-123/intermediate/source.md"
