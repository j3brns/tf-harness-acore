"""
Integration tests for DeepResearch agent creation and configuration.

These tests verify the agent can be created with various configurations
without actually invoking the model (no API calls).
"""

import pytest
from unittest.mock import MagicMock, patch


class TestAgentCreation:
    """Integration tests for agent creation."""

    @staticmethod
    def _extract_graph_summary(agent):
        """Extract a minimal graph summary from a Strands-compatible agent object."""
        graph = getattr(agent, "graph", None)
        if graph is None:
            raise AssertionError("Agent graph not found")

        nodes_raw = graph.get("nodes", [])
        edges_raw = graph.get("edges", [])

        node_names = []
        for node in nodes_raw:
            if isinstance(node, dict):
                node_names.append(node.get("id") or node.get("name"))
            else:
                node_names.append(str(node))

        edge_pairs = []
        for edge in edges_raw:
            if isinstance(edge, dict):
                edge_pairs.append((edge.get("from"), edge.get("to")))
            else:
                edge_pairs.append(tuple(edge))

        return {
            "nodes": [n for n in node_names if n],
            "edges": edge_pairs,
        }

    @pytest.fixture
    def mock_strands_components(self):
        """Mock Strands DeepAgents components."""
        with patch("deepresearch.main.SubAgent") as mock_subagent, patch(
            "deepresearch.main.create_deep_agent"
        ) as mock_create, patch("deepresearch.main.get_default_model") as mock_model, patch(
            "deepresearch.main.basic_claude_haiku_4_5"
        ) as mock_haiku:
            mock_model.return_value = MagicMock()
            mock_haiku.return_value = MagicMock()

            def _build_subagent(*args, **kwargs):
                subagent = MagicMock()
                subagent.name = kwargs.get("name", "subagent")
                subagent.tools = kwargs.get("tools", [])
                return subagent

            def _build_agent(**kwargs):
                subagents = kwargs.get("subagents", [])
                lead_node = "research_lead"
                subagent_nodes = [getattr(sa, "name", "subagent") for sa in subagents]
                graph = {
                    "nodes": [{"id": lead_node}] + [{"id": name} for name in subagent_nodes],
                    "edges": [{"from": lead_node, "to": name} for name in subagent_nodes],
                }
                agent = MagicMock()
                agent.graph = graph
                return agent

            mock_subagent.side_effect = _build_subagent
            mock_create.side_effect = _build_agent

            yield {
                "subagent": mock_subagent,
                "create_agent": mock_create,
                "model": mock_model,
                "haiku": mock_haiku,
            }

    def test_create_agent_with_default_config(self, mock_strands_components):
        """Should create agent with minimal configuration."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "test_tool"

        agent = create_deepsearch_agent(research_tool=mock_tool)

        assert agent is not None
        mock_strands_components["create_agent"].assert_called_once()

    def test_create_agent_with_explicit_tool_name(self, mock_strands_components):
        """Should create agent with explicit tool name."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock(spec=[])  # No __name__ attribute

        agent = create_deepsearch_agent(
            research_tool=mock_tool,
            tool_name="custom_search",
        )

        assert agent is not None
        mock_strands_components["create_agent"].assert_called_once()

    def test_create_agent_without_tool_name_raises(self, mock_strands_components):
        """Should raise ValueError when tool name can't be determined."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock(spec=[])  # No __name__ attribute

        with pytest.raises(ValueError, match="Tool name not provided"):
            create_deepsearch_agent(research_tool=mock_tool)

    def test_create_agent_with_session_manager(self, mock_strands_components):
        """Should pass session manager to agent."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "test_tool"
        mock_session_manager = MagicMock()

        agent = create_deepsearch_agent(
            research_tool=mock_tool,
            session_manager=mock_session_manager,
        )

        assert agent is not None
        # Verify session_manager was passed
        call_kwargs = mock_strands_components["create_agent"].call_args[1]
        assert call_kwargs["session_manager"] == mock_session_manager

    def test_create_agent_with_session_id(self, mock_strands_components):
        """Should include session ID in trace attributes."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "test_tool"

        agent = create_deepsearch_agent(
            research_tool=mock_tool,
            session_id="test-session-123",
        )

        assert agent is not None
        call_kwargs = mock_strands_components["create_agent"].call_args[1]
        assert "trace_attributes" in call_kwargs
        assert call_kwargs["trace_attributes"]["session.id"] == "test-session-123"

    def test_creates_research_subagent(self, mock_strands_components):
        """Should create research subagent with correct configuration."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "internet_search"

        create_deepsearch_agent(research_tool=mock_tool)

        # Verify SubAgent was called for research_subagent
        subagent_calls = mock_strands_components["subagent"].call_args_list
        assert len(subagent_calls) == 2  # research_subagent and citations_agent

        research_call = subagent_calls[0]
        assert research_call[1]["name"] == "research_subagent"
        assert mock_tool in research_call[1]["tools"]

    def test_creates_citations_subagent(self, mock_strands_components):
        """Should create citations subagent with correct configuration."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "internet_search"

        create_deepsearch_agent(research_tool=mock_tool)

        subagent_calls = mock_strands_components["subagent"].call_args_list
        citations_call = subagent_calls[1]
        assert citations_call[1]["name"] == "citations_agent"

    def test_detects_strands_graph(self, mock_strands_components):
        """Should expose a detectable graph with expected node topology."""
        from deepresearch.main import create_deepsearch_agent

        mock_tool = MagicMock()
        mock_tool.__name__ = "internet_search"

        agent = create_deepsearch_agent(research_tool=mock_tool)
        graph = self._extract_graph_summary(agent)

        assert "research_lead" in graph["nodes"]
        assert "research_subagent" in graph["nodes"]
        assert "citations_agent" in graph["nodes"]
        assert ("research_lead", "research_subagent") in graph["edges"]
        assert ("research_lead", "citations_agent") in graph["edges"]


class TestRuntimeIntegration:
    """Integration tests for runtime.py integration."""

    @pytest.fixture
    def mock_runtime_dependencies(self):
        """Mock runtime dependencies."""
        with patch("deepresearch.utils.secrets.load_secrets_from_secrets_manager") as mock_secrets, patch(
            "deepresearch.utils.telemetry.initialize_telemetry"
        ) as mock_telemetry, patch("deepresearch.utils.session.get_session_id") as mock_session, patch(
            "deepresearch.utils.session.create_session_manager"
        ) as mock_manager:
            mock_secrets.return_value = {}
            mock_telemetry.return_value = True
            mock_session.return_value = "test-session-id"
            mock_manager.return_value = None
            yield {
                "secrets": mock_secrets,
                "telemetry": mock_telemetry,
                "session": mock_session,
                "manager": mock_manager,
            }

    def test_runtime_initializes_telemetry(self, mock_runtime_dependencies):
        """Runtime should initialize telemetry on invocation."""
        # This would test the runtime.py invoke function
        # but requires more complex mocking of BedrockAgentCoreApp
        pass

    def test_runtime_loads_secrets(self, mock_runtime_dependencies):
        """Runtime should load secrets from Secrets Manager."""
        # This would test that secrets are loaded during agent creation
        pass


class TestAgentWithMockedTools:
    """Integration tests with mocked external tools."""

    @pytest.fixture
    def mock_internet_search(self):
        """Create a mock internet search tool."""
        mock_search = MagicMock()
        mock_search.__name__ = "internet_search"
        mock_search.return_value = {
            "results": [
                {"title": "Test Result 1", "url": "https://example.com/1"},
                {"title": "Test Result 2", "url": "https://example.com/2"},
            ]
        }
        return mock_search

    def test_agent_creation_with_mock_search(self, mock_internet_search):
        """Should create agent with mocked search tool."""
        with patch("deepresearch.main.SubAgent") as mock_subagent, patch(
            "deepresearch.main.create_deep_agent"
        ) as mock_create, patch("deepresearch.main.get_default_model") as mock_model, patch(
            "deepresearch.main.basic_claude_haiku_4_5"
        ) as mock_haiku:
            mock_model.return_value = MagicMock()
            mock_haiku.return_value = MagicMock()
            mock_subagent.return_value = MagicMock()
            mock_create.return_value = MagicMock()

            from deepresearch.main import create_deepsearch_agent

            agent = create_deepsearch_agent(research_tool=mock_internet_search)

            assert agent is not None
