"""
Unit tests for Gateway Tool agent analysis functions.
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestInvokeMcpTool:
    """Tests for MCP tool invocation."""

    def test_invoke_titanic_fetch(self):
        """Test fetching Titanic dataset returns data."""
        from runtime import invoke_mcp_tool

        result = invoke_mcp_tool("titanic-dataset", "fetch")

        assert result["status"] == "success"
        assert "data" in result
        assert len(result["data"]) > 0

    def test_invoke_titanic_schema(self):
        """Test fetching Titanic schema returns columns."""
        from runtime import invoke_mcp_tool

        result = invoke_mcp_tool("titanic-dataset", "schema")

        assert result["status"] == "success"
        assert "columns" in result
        assert "Survived" in result["columns"]
        assert "Pclass" in result["columns"]

    def test_invoke_unknown_tool(self):
        """Test invoking unknown tool returns error."""
        from runtime import invoke_mcp_tool

        result = invoke_mcp_tool("unknown-tool", "action")

        assert result["status"] == "error"
        assert "Unknown tool/action" in result["message"]


class TestGetMockTitanicData:
    """Tests for mock data generation."""

    def test_mock_data_structure(self):
        """Test mock data has correct structure."""
        from runtime import get_mock_titanic_data

        data = get_mock_titanic_data()

        assert len(data) == 10
        for row in data:
            assert "PassengerId" in row
            assert "Survived" in row
            assert "Pclass" in row
            assert "Sex" in row

    def test_mock_data_has_survivors(self):
        """Test mock data includes both survivors and non-survivors."""
        from runtime import get_mock_titanic_data

        data = get_mock_titanic_data()
        survivors = sum(1 for p in data if p["Survived"] == 1)
        non_survivors = sum(1 for p in data if p["Survived"] == 0)

        assert survivors > 0
        assert non_survivors > 0


class TestAnalyzeSurvival:
    """Tests for survival analysis function."""

    def test_analyze_basic_stats(self, sample_titanic_data):
        """Test basic survival statistics calculation."""
        from runtime import analyze_survival

        result = analyze_survival(sample_titanic_data)

        assert result["total_passengers"] == 5
        assert result["survivors"] == 3
        assert result["overall_survival_rate"] == 0.6

    def test_analyze_survival_by_class(self, sample_titanic_data):
        """Test survival rate by passenger class."""
        from runtime import analyze_survival

        result = analyze_survival(sample_titanic_data)

        # With pandas available
        if "survival_by_class" in result:
            assert "1" in result["survival_by_class"] or 1 in result["survival_by_class"]
            assert "3" in result["survival_by_class"] or 3 in result["survival_by_class"]

    def test_analyze_survival_by_gender(self, sample_titanic_data):
        """Test survival rate by gender."""
        from runtime import analyze_survival

        result = analyze_survival(sample_titanic_data)

        # With pandas available
        if "survival_by_gender" in result:
            assert "female" in result["survival_by_gender"]
            assert "male" in result["survival_by_gender"]
            # Females should have higher survival in this sample
            assert result["survival_by_gender"]["female"] > result["survival_by_gender"]["male"]

    def test_analyze_empty_data(self):
        """Test analysis handles empty data."""
        from runtime import analyze_survival

        result = analyze_survival([])

        assert result["total_passengers"] == 0

    def test_analyze_large_dataset(self, large_titanic_data):
        """Test analysis handles larger datasets."""
        from runtime import analyze_survival

        result = analyze_survival(large_titanic_data)

        assert result["total_passengers"] == 100
        assert 0 < result["overall_survival_rate"] < 1


class TestGenerateInsights:
    """Tests for insight generation."""

    def test_generate_insights_basic(self):
        """Test basic insight generation."""
        from runtime import generate_insights

        analysis = {
            "overall_survival_rate": 0.38,
            "survival_by_class": {"1": 0.63, "3": 0.24},
            "survival_by_gender": {"female": 0.74, "male": 0.19},
        }

        insights = generate_insights(analysis)

        assert len(insights) > 0
        assert any("38.0%" in i for i in insights)

    def test_generate_insights_with_class_data(self):
        """Test insights include class information."""
        from runtime import generate_insights

        analysis = {
            "overall_survival_rate": 0.38,
            "survival_by_class": {"1": 0.63, "3": 0.24},
        }

        insights = generate_insights(analysis)

        assert any("First class" in i for i in insights)
        assert any("Third class" in i for i in insights)

    def test_generate_insights_with_gender_data(self):
        """Test insights include gender comparison."""
        from runtime import generate_insights

        analysis = {"overall_survival_rate": 0.38, "survival_by_gender": {"female": 0.74, "male": 0.19}}

        insights = generate_insights(analysis)

        assert any("Women" in i for i in insights)
        assert any("men" in i for i in insights)

    def test_generate_insights_minimal(self):
        """Test insights with minimal data."""
        from runtime import generate_insights

        analysis = {"overall_survival_rate": 0.5}

        insights = generate_insights(analysis)

        assert len(insights) >= 1
        assert "50.0%" in insights[0]


class TestHandler:
    """Tests for the main handler function."""

    def test_handler_success(self, sample_event):
        """Test handler completes successfully."""
        from runtime import handler

        result = handler(sample_event, None)

        assert result["status"] == "success"
        assert "analysis" in result
        assert "insights" in result

    def test_handler_returns_timestamp(self, sample_event):
        """Test handler includes timestamp."""
        from runtime import handler

        result = handler(sample_event, None)

        assert "timestamp" in result
        assert result["timestamp"].endswith("Z")

    def test_handler_analysis_structure(self, sample_event):
        """Test handler returns proper analysis structure."""
        from runtime import handler

        result = handler(sample_event, None)

        assert "analysis" in result
        analysis = result["analysis"]
        assert "total_passengers" in analysis
        assert "overall_survival_rate" in analysis

    def test_handler_insights_list(self, sample_event):
        """Test handler returns insights as list."""
        from runtime import handler

        result = handler(sample_event, None)

        assert "insights" in result
        assert isinstance(result["insights"], list)
        assert len(result["insights"]) > 0
