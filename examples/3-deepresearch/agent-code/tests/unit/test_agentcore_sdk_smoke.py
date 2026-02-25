"""
AgentCore SDK API-surface smoke tests.

These tests verify that the exact import paths and API shapes used by this repo
remain stable across upstream SDK releases. They are import/shape-only checks:
no network calls, no AWS credentials, no live resources.

Coverage:
- bedrock_agentcore.BedrockAgentCoreApp
- bedrock_agentcore.memory.integrations.strands.config.AgentCoreMemoryConfig
- bedrock_agentcore.memory.integrations.strands.session_manager.AgentCoreMemorySessionManager
"""

import inspect


class TestBedrockAgentCoreAppImport:
    """Smoke tests for BedrockAgentCoreApp - used in runtime.py."""

    def test_top_level_import_path(self):
        """bedrock_agentcore.BedrockAgentCoreApp must be importable from the top-level package."""
        from bedrock_agentcore import BedrockAgentCoreApp  # noqa: F401

    def test_is_class(self):
        """BedrockAgentCoreApp must be a class (not a function or module alias)."""
        from bedrock_agentcore import BedrockAgentCoreApp

        assert isinstance(BedrockAgentCoreApp, type), (
            "BedrockAgentCoreApp must be a class; "
            f"got {type(BedrockAgentCoreApp)} — check for upstream rename or restructure"
        )

    def test_constructor_accepts_debug_kwarg(self):
        """BedrockAgentCoreApp.__init__ must accept a 'debug' keyword argument."""
        from bedrock_agentcore import BedrockAgentCoreApp

        sig = inspect.signature(BedrockAgentCoreApp.__init__)
        assert "debug" in sig.parameters, (
            "BedrockAgentCoreApp.__init__ must accept 'debug' kwarg; "
            "runtime.py calls BedrockAgentCoreApp(debug=True)"
        )

    def test_instantiation_no_network(self):
        """BedrockAgentCoreApp() must instantiate without network calls."""
        from bedrock_agentcore import BedrockAgentCoreApp

        app = BedrockAgentCoreApp(debug=False)
        assert app is not None

    def test_entrypoint_attribute_exists_and_is_callable(self):
        """Instance must expose an 'entrypoint' attribute that is callable (used as decorator)."""
        from bedrock_agentcore import BedrockAgentCoreApp

        app = BedrockAgentCoreApp(debug=False)
        assert hasattr(app, "entrypoint"), (
            "BedrockAgentCoreApp instance must have 'entrypoint' attribute; "
            "runtime.py uses @app.entrypoint decorator"
        )
        assert callable(app.entrypoint), "app.entrypoint must be callable (used as a decorator)"

    def test_run_method_exists_and_is_callable(self):
        """Instance must expose a 'run' method (used in __main__ block)."""
        from bedrock_agentcore import BedrockAgentCoreApp

        app = BedrockAgentCoreApp(debug=False)
        assert hasattr(app, "run"), (
            "BedrockAgentCoreApp instance must have 'run' method; "
            "runtime.py calls app.run() in __main__"
        )
        assert callable(app.run), "app.run must be callable"


class TestAgentCoreMemoryConfigImport:
    """Smoke tests for AgentCoreMemoryConfig - used in session.py."""

    def test_deep_import_path(self):
        """The deep module path must be importable."""
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig  # noqa: F401

    def test_is_class(self):
        """AgentCoreMemoryConfig must be a class."""
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig

        assert isinstance(AgentCoreMemoryConfig, type), (
            "AgentCoreMemoryConfig must be a class; "
            f"got {type(AgentCoreMemoryConfig)} — check for upstream rename or restructure"
        )

    def test_required_fields_present(self):
        """AgentCoreMemoryConfig must declare memory_id, session_id, actor_id as required fields."""
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig

        fields = getattr(AgentCoreMemoryConfig, "model_fields", None)
        assert fields is not None, (
            "AgentCoreMemoryConfig must be a Pydantic model with 'model_fields'; "
            "check for upstream API change"
        )
        for field in ("memory_id", "session_id", "actor_id"):
            assert field in fields, (
                f"AgentCoreMemoryConfig must have required field '{field}'; "
                "session.py constructs it with memory_id, actor_id, session_id kwargs"
            )

    def test_instantiation_with_required_fields(self):
        """AgentCoreMemoryConfig must instantiate with memory_id, actor_id, session_id (no network)."""
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig

        cfg = AgentCoreMemoryConfig(
            memory_id="smoke-test-mem-id",
            actor_id="smoke-test-actor",
            session_id="smoke-test-session",
        )
        assert cfg is not None

    def test_instantiated_field_values_accessible(self):
        """Constructed AgentCoreMemoryConfig must expose correct attribute values."""
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig

        cfg = AgentCoreMemoryConfig(
            memory_id="mem-001",
            actor_id="actor-001",
            session_id="sess-001",
        )
        assert cfg.memory_id == "mem-001", "cfg.memory_id must return the supplied value"
        assert cfg.actor_id == "actor-001", "cfg.actor_id must return the supplied value"
        assert cfg.session_id == "sess-001", "cfg.session_id must return the supplied value"


class TestAgentCoreMemorySessionManagerImport:
    """Smoke tests for AgentCoreMemorySessionManager - used in session.py."""

    def test_deep_import_path(self):
        """The deep module path must be importable."""
        from bedrock_agentcore.memory.integrations.strands.session_manager import (  # noqa: F401
            AgentCoreMemorySessionManager,
        )

    def test_is_class(self):
        """AgentCoreMemorySessionManager must be a class."""
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )

        assert isinstance(AgentCoreMemorySessionManager, type), (
            "AgentCoreMemorySessionManager must be a class; "
            f"got {type(AgentCoreMemorySessionManager)} — check for upstream rename or restructure"
        )

    def test_constructor_has_agentcore_memory_config_param(self):
        """Constructor must accept 'agentcore_memory_config' as a parameter."""
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )

        sig = inspect.signature(AgentCoreMemorySessionManager.__init__)
        assert "agentcore_memory_config" in sig.parameters, (
            "AgentCoreMemorySessionManager.__init__ must accept 'agentcore_memory_config'; "
            "session.py passes agentcore_memory_config=<instance>"
        )

    def test_constructor_has_region_name_param(self):
        """Constructor must accept 'region_name' as a parameter."""
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )

        sig = inspect.signature(AgentCoreMemorySessionManager.__init__)
        assert "region_name" in sig.parameters, (
            "AgentCoreMemorySessionManager.__init__ must accept 'region_name'; "
            "session.py passes region_name=memory_config['region_name']"
        )

    def test_expected_session_methods_exist(self):
        """Session manager class must expose the expected session lifecycle methods."""
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )

        for method in ("initialize", "create_session"):
            assert hasattr(AgentCoreMemorySessionManager, method), (
                f"AgentCoreMemorySessionManager must have '{method}' method; "
                "check for upstream API surface regression"
            )
