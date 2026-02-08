"""
Unit tests for deepresearch.utils.session module.
"""

from unittest.mock import MagicMock, patch
from deepresearch.utils.session import get_session_id, create_session_manager


class TestGetSessionId:
    """Tests for get_session_id function."""

    def test_returns_context_session_id(self):
        """Should return session ID from context when available."""
        context = MagicMock()
        context.session_id = "context-session-123"

        result = get_session_id(context=context)

        assert result == "context-session-123"

    def test_returns_env_session_id(self, monkeypatch):
        """Should return session ID from environment when context not available."""
        monkeypatch.setenv("AGENTCORE_SESSION_ID", "env-session-456")

        result = get_session_id(context=None)

        assert result == "env-session-456"

    def test_generates_uuid_when_nothing_available(self):
        """Should generate UUID when no session ID available."""
        result = get_session_id(context=None)

        # Should be a valid UUID format
        assert len(result) == 36
        assert result.count("-") == 4

    def test_context_takes_priority_over_env(self, monkeypatch):
        """Context session ID should take priority over environment."""
        monkeypatch.setenv("AGENTCORE_SESSION_ID", "env-session")
        context = MagicMock()
        context.session_id = "context-session"

        result = get_session_id(context=context)

        assert result == "context-session"

    def test_handles_context_without_session_id(self):
        """Should handle context object without session_id attribute."""
        context = MagicMock(spec=[])  # No session_id attribute

        result = get_session_id(context=context)

        # Should generate UUID
        assert len(result) == 36

    def test_handles_empty_context_session_id(self):
        """Should handle context with empty session_id."""
        context = MagicMock()
        context.session_id = ""

        result = get_session_id(context=context)

        # Should generate UUID since session_id is empty
        assert len(result) == 36


class TestCreateSessionManager:
    """Tests for create_session_manager function."""

    def test_returns_none_when_memory_disabled(self):
        """Should return None when memory is disabled."""
        result = create_session_manager("session-123")
        assert result is None

    @patch("deepresearch.utils.session.get_memory_config")
    def test_returns_none_when_no_memory_config(self, mock_config):
        """Should return None when get_memory_config returns None."""
        mock_config.return_value = None

        result = create_session_manager("session-123")

        assert result is None
        mock_config.assert_called_once_with(session_id="session-123")

    @patch("deepresearch.utils.session.get_memory_config")
    @patch("deepresearch.utils.session.AgentCoreMemorySessionManager")
    @patch("deepresearch.utils.session.AgentCoreMemoryConfig")
    def test_creates_session_manager_when_enabled(self, mock_config_class, mock_manager_class, mock_get_config):
        """Should create session manager when memory is configured."""
        mock_get_config.return_value = {
            "memory_id": "mem-abc123",
            "session_id": "session-123",
            "actor_id": "test-actor",
            "region_name": "us-east-1",
        }
        mock_config_instance = MagicMock()
        mock_config_class.return_value = mock_config_instance
        mock_manager_instance = MagicMock()
        mock_manager_class.return_value = mock_manager_instance

        result = create_session_manager("session-123")

        assert result == mock_manager_instance
        mock_config_class.assert_called_once_with(
            memory_id="mem-abc123",
            actor_id="test-actor",
            session_id="session-123",
        )
        mock_manager_class.assert_called_once_with(
            agentcore_memory_config=mock_config_instance,
            region_name="us-east-1",
        )
