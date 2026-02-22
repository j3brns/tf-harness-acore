"""
Unit tests for deepresearch.config module.
"""

from deepresearch.config import is_memory_enabled, get_memory_config


class TestIsMemoryEnabled:
    """Tests for is_memory_enabled function."""

    def test_memory_disabled_by_default(self):
        """Memory should be disabled when ENABLE_MEMORY is not set."""
        assert is_memory_enabled() is False

    def test_memory_enabled_true(self, monkeypatch):
        """Memory should be enabled when ENABLE_MEMORY=true."""
        monkeypatch.setenv("ENABLE_MEMORY", "true")
        assert is_memory_enabled() is True

    def test_memory_enabled_true_uppercase(self, monkeypatch):
        """Memory should be enabled when ENABLE_MEMORY=TRUE (case insensitive)."""
        monkeypatch.setenv("ENABLE_MEMORY", "TRUE")
        assert is_memory_enabled() is True

    def test_memory_disabled_false(self, monkeypatch):
        """Memory should be disabled when ENABLE_MEMORY=false."""
        monkeypatch.setenv("ENABLE_MEMORY", "false")
        assert is_memory_enabled() is False

    def test_memory_disabled_invalid(self, monkeypatch):
        """Memory should be disabled for invalid values."""
        monkeypatch.setenv("ENABLE_MEMORY", "yes")
        assert is_memory_enabled() is False


class TestGetMemoryConfig:
    """Tests for get_memory_config function."""

    def test_returns_none_when_disabled(self):
        """Should return None when memory is disabled."""
        config = get_memory_config("session-123")
        assert config is None

    def test_returns_none_when_no_memory_id(self, monkeypatch):
        """Should return None when AGENTCORE_MEMORY_ID is not set."""
        monkeypatch.setenv("ENABLE_MEMORY", "true")
        config = get_memory_config("session-123")
        assert config is None

    def test_returns_config_when_enabled(self, monkeypatch):
        """Should return config dict when memory is properly configured."""
        monkeypatch.setenv("ENABLE_MEMORY", "true")
        monkeypatch.setenv("AGENTCORE_MEMORY_ID", "mem-abc123")
        monkeypatch.setenv("AWS_REGION", "eu-west-2")

        config = get_memory_config("session-123")

        assert config is not None
        assert config["memory_id"] == "mem-abc123"
        assert config["session_id"] == "session-123"
        assert config["actor_id"] == "deepsearch-agent"  # default
        assert config["region_name"] == "eu-west-2"

    def test_uses_custom_actor_id(self, monkeypatch):
        """Should use custom AGENTCORE_ACTOR_ID when set."""
        monkeypatch.setenv("ENABLE_MEMORY", "true")
        monkeypatch.setenv("AGENTCORE_MEMORY_ID", "mem-abc123")
        monkeypatch.setenv("AGENTCORE_ACTOR_ID", "custom-actor")

        config = get_memory_config("session-123")

        assert config["actor_id"] == "custom-actor"
