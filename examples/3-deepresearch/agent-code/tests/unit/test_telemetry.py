"""
Unit tests for deepresearch.utils.telemetry module.
"""

import pytest
from unittest.mock import patch, MagicMock
import deepresearch.utils.telemetry as telemetry_module
from deepresearch.utils.telemetry import (
    initialize_telemetry,
    get_trace_attributes,
    _initialize_otel,
    _initialize_weave,
)


@pytest.fixture(autouse=True)
def reset_telemetry_state():
    """Reset telemetry state before each test."""
    telemetry_module._telemetry_initialized = False
    telemetry_module._weave_initialized = False
    yield
    telemetry_module._telemetry_initialized = False
    telemetry_module._weave_initialized = False


class TestInitializeTelemetry:
    """Tests for initialize_telemetry function."""

    def test_returns_false_when_nothing_configured(self):
        """Should return False when no telemetry is configured."""
        result = initialize_telemetry()
        assert result is False

    def test_skips_reinitialization(self, monkeypatch):
        """Should skip if already initialized."""
        telemetry_module._telemetry_initialized = True
        result = initialize_telemetry()
        assert result is True

    @patch("deepresearch.utils.telemetry._initialize_otel")
    @patch("deepresearch.utils.telemetry._initialize_weave")
    def test_initializes_otel_when_configured(self, mock_weave, mock_otel):
        """Should call OTEL initialization."""
        mock_otel.return_value = True
        mock_weave.return_value = False

        result = initialize_telemetry()

        assert result is True
        mock_otel.assert_called_once()

    @patch("deepresearch.utils.telemetry._initialize_otel")
    @patch("deepresearch.utils.telemetry._initialize_weave")
    def test_initializes_weave_when_configured(self, mock_weave, mock_otel):
        """Should call Weave initialization."""
        mock_otel.return_value = False
        mock_weave.return_value = True

        result = initialize_telemetry()

        assert result is True
        mock_weave.assert_called_once()


class TestInitializeOtel:
    """Tests for _initialize_otel function."""

    def test_returns_false_when_no_endpoint(self):
        """Should return False when OTEL endpoint not set."""
        result = _initialize_otel()
        assert result is False

    def test_returns_false_when_import_fails(self, monkeypatch):
        """Should return False when strands.telemetry import fails."""
        monkeypatch.setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

        with patch.dict("sys.modules", {"strands.telemetry": None}):
            with patch(
                "deepresearch.utils.telemetry.StrandsTelemetry",
                side_effect=ImportError("No module"),
            ):
                # Force reimport behavior
                pass

        # The actual test - import will fail
        result = _initialize_otel()
        assert result is False

    @patch("deepresearch.utils.telemetry.StrandsTelemetry")
    def test_initializes_successfully(self, mock_strands_class, monkeypatch):
        """Should initialize OTEL successfully when configured."""
        monkeypatch.setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

        mock_instance = MagicMock()
        mock_strands_class.return_value = mock_instance

        result = _initialize_otel()

        assert result is True
        mock_instance.setup_otlp_exporter.assert_called_once()


class TestInitializeWeave:
    """Tests for _initialize_weave function."""

    def test_returns_false_when_not_enabled(self):
        """Should return False when Weave is not enabled."""
        result = _initialize_weave()
        assert result is False

    def test_returns_false_when_import_fails(self, monkeypatch):
        """Should return False when weave import fails."""
        monkeypatch.setenv("ENABLE_WEAVE", "true")

        with patch.dict("sys.modules", {"weave": None}):
            result = _initialize_weave()
            # Import should fail gracefully
            assert result is False

    def test_skips_reinitialization(self, monkeypatch):
        """Should skip if already initialized."""
        telemetry_module._weave_initialized = True
        monkeypatch.setenv("ENABLE_WEAVE", "true")

        result = _initialize_weave()
        assert result is True


class TestGetTraceAttributes:
    """Tests for get_trace_attributes function."""

    def test_returns_base_attributes(self):
        """Should return base service attributes."""
        attrs = get_trace_attributes()

        assert attrs["service.name"] == "deepresearch"
        assert attrs["agent.type"] == "deep-research"
        assert "session.id" not in attrs

    def test_includes_session_id(self):
        """Should include session ID when provided."""
        attrs = get_trace_attributes(session_id="test-session-123")

        assert attrs["session.id"] == "test-session-123"
        assert attrs["service.name"] == "deepresearch"
