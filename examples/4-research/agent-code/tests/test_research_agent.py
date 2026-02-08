"""
Unit tests for Research agent.
"""
import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestResearchAgent:
    """Tests for ResearchAgent class."""

    def test_agent_initialization(self):
        """Test agent initializes with empty state."""
        from runtime import ResearchAgent

        agent = ResearchAgent()

        assert agent.memory == {}
        assert agent.sources == []
        assert agent.findings == []

    def test_search_arxiv(self, sample_query):
        """Test ArXiv search returns results."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        results = agent.search_arxiv(sample_query)

        assert len(results) > 0
        assert all("title" in r for r in results)
        assert all("url" in r for r in results)
        assert all("id" in r for r in results)

    def test_search_pubmed(self, sample_query):
        """Test PubMed search returns results."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        results = agent.search_pubmed(sample_query)

        assert len(results) > 0
        assert all("title" in r for r in results)
        assert all("pmid" in r for r in results)

    def test_browse_paper(self):
        """Test paper browsing returns content."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        url = "https://arxiv.org/abs/2401.00001"
        result = agent.browse_paper(url)

        assert result["url"] == url
        assert "title" in result
        assert "content" in result
        assert "sections" in result

    def test_analyze_findings_with_papers(self, sample_arxiv_papers):
        """Test findings analysis with paper data."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        analysis = agent.analyze_findings(sample_arxiv_papers)

        assert analysis["total_papers"] == 2
        assert "sources" in analysis

    def test_analyze_findings_empty(self):
        """Test findings analysis with empty data."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        analysis = agent.analyze_findings([])

        assert analysis["total_papers"] == 0

    def test_store_memory(self):
        """Test memory storage."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        agent.store_memory("test_key", {"data": "value"})

        assert "test_key" in agent.memory
        assert agent.memory["test_key"]["value"] == {"data": "value"}
        assert "timestamp" in agent.memory["test_key"]

    def test_recall_memory(self):
        """Test memory recall."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        agent.store_memory("test_key", "test_value")

        result = agent.recall_memory("test_key")

        assert result == "test_value"

    def test_recall_memory_not_found(self):
        """Test memory recall for non-existent key."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        result = agent.recall_memory("nonexistent")

        assert result is None

    def test_generate_report(self, sample_arxiv_papers):
        """Test report generation."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        findings = {"total_papers": 2}
        report = agent.generate_report("test query", findings, sample_arxiv_papers)

        assert "title" in report
        assert "test query" in report["title"]
        assert "generated" in report
        assert "summary" in report
        assert "methodology" in report
        assert "findings" in report
        assert "papers" in report
        assert "recommendations" in report
        assert "limitations" in report

    def test_research_workflow(self, sample_query):
        """Test full research workflow."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        report = agent.research(sample_query)

        assert "title" in report
        assert sample_query in report["title"]
        assert report["methodology"]["papers_reviewed"] > 0
        assert len(agent.sources) > 0
        assert len(agent.memory) > 0


class TestHandler:
    """Tests for the main handler function."""

    def test_handler_success(self, sample_event):
        """Test handler completes successfully."""
        from runtime import handler

        result = handler(sample_event, None)

        assert result["status"] == "success"
        assert "report" in result

    def test_handler_with_query(self):
        """Test handler processes query from event."""
        from runtime import handler

        event = {"query": "deep learning"}
        result = handler(event, None)

        assert result["status"] == "success"
        assert "deep learning" in result["message"]

    def test_handler_with_topic(self):
        """Test handler accepts topic parameter."""
        from runtime import handler

        event = {"topic": "computer vision"}
        result = handler(event, None)

        assert result["status"] == "success"
        assert "computer vision" in result["message"]

    def test_handler_default_query(self):
        """Test handler uses default query when none provided."""
        from runtime import handler

        result = handler({}, None)

        assert result["status"] == "success"
        assert "machine learning" in result["message"]

    def test_handler_returns_timestamp(self, sample_event):
        """Test handler includes timestamp."""
        from runtime import handler

        result = handler(sample_event, None)

        assert "timestamp" in result
        assert result["timestamp"].endswith("Z")

    def test_handler_report_structure(self, sample_event):
        """Test handler returns complete report structure."""
        from runtime import handler

        result = handler(sample_event, None)
        report = result["report"]

        assert "title" in report
        assert "methodology" in report
        assert "findings" in report
        assert "papers" in report
        assert "recommendations" in report


class TestReportQuality:
    """Tests for report quality and completeness."""

    def test_report_has_papers(self):
        """Test report includes paper references."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        report = agent.research("test query")

        assert len(report["papers"]) > 0

    def test_report_papers_have_sources(self):
        """Test each paper has source URL."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        report = agent.research("test query")

        for paper in report["papers"]:
            assert "source" in paper
            assert paper["source"] is not None

    def test_report_has_recommendations(self):
        """Test report includes recommendations."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        report = agent.research("test query")

        assert len(report["recommendations"]) > 0

    def test_report_has_limitations(self):
        """Test report acknowledges limitations."""
        from runtime import ResearchAgent

        agent = ResearchAgent()
        report = agent.research("test query")

        assert len(report["limitations"]) > 0
