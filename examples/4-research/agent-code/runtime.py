"""
Deep Research Agent

A full-featured research agent with web browsing, code analysis, and memory.
Demonstrates all Bedrock AgentCore capabilities for comprehensive research tasks.

Features demonstrated:
- MCP gateway with multiple research tools
- Code interpreter for data analysis
- Web browser for literature access
- Long-term memory for knowledge retention
- Policy enforcement and quality evaluation
"""

import json
import logging
from datetime import datetime
from typing import Any, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ResearchAgent:
    """
    Deep Research Agent for comprehensive literature research.

    Workflow:
    1. Parse research query
    2. Search academic sources (ArXiv, PubMed) via MCP tools
    3. Browse relevant papers via browser tool
    4. Analyze findings with code interpreter
    5. Store learnings in long-term memory
    6. Generate comprehensive research report
    """

    def __init__(self):
        self.memory = {}
        self.sources = []
        self.findings = []

    def search_arxiv(self, query: str, max_results: int = 5) -> list:
        """
        Search ArXiv for research papers.

        In production, this calls the MCP gateway.
        Returns mock data for local testing.
        """
        logger.info(f"Searching ArXiv: {query}")

        # Mock ArXiv results
        return [
            {
                "id": "2401.00001",
                "title": f"Research on {query}: A Comprehensive Study",
                "authors": ["Smith, J.", "Jones, A."],
                "abstract": f"This paper presents a comprehensive study on {query}...",
                "published": "2024-01-15",
                "url": "https://arxiv.org/abs/2401.00001",
            },
            {
                "id": "2401.00002",
                "title": f"Advances in {query} Methodology",
                "authors": ["Williams, R."],
                "abstract": f"We present new methodological advances for {query}...",
                "published": "2024-01-10",
                "url": "https://arxiv.org/abs/2401.00002",
            },
        ]

    def search_pubmed(self, query: str, max_results: int = 5) -> list:
        """
        Search PubMed for biomedical literature.

        In production, this calls the MCP gateway.
        Returns mock data for local testing.
        """
        logger.info(f"Searching PubMed: {query}")

        # Mock PubMed results
        return [
            {
                "pmid": "12345678",
                "title": f"Clinical implications of {query}",
                "authors": ["Brown, M.D.", "Davis, P."],
                "journal": "Nature Medicine",
                "published": "2024-01-12",
                "doi": "10.1038/s41591-024-00001-0",
            }
        ]

    def browse_paper(self, url: str) -> dict:
        """
        Browse and extract content from a research paper.

        In production, this uses the browser tool.
        Returns mock data for local testing.
        """
        logger.info(f"Browsing paper: {url}")

        return {
            "url": url,
            "title": "Research Paper Title",
            "content": "Full paper content extracted via browser...",
            "sections": ["Introduction", "Methods", "Results", "Discussion"],
            "figures": 5,
            "tables": 3,
        }

    def analyze_findings(self, papers: list) -> dict:
        """
        Analyze collected papers using code interpreter.

        Uses pandas/numpy for statistical analysis if available.
        """
        logger.info(f"Analyzing {len(papers)} papers")

        try:
            import pandas as pd

            # Create dataframe from papers
            if papers:
                df = pd.DataFrame(papers)
                return {
                    "total_papers": len(papers),
                    "sources": df["url"].nunique() if "url" in df.columns else len(papers),
                    "year_range": "2024",
                    "methodology": "Systematic literature review",
                }
        except ImportError:
            pass

        return {
            "total_papers": len(papers),
            "sources": len(set(p.get("url", p.get("pmid", "")) for p in papers)),
            "note": "Detailed analysis requires pandas",
        }

    def store_memory(self, key: str, value: Any) -> None:
        """Store findings in long-term memory."""
        logger.info(f"Storing in memory: {key}")
        self.memory[key] = {"value": value, "timestamp": datetime.utcnow().isoformat()}

    def recall_memory(self, key: str) -> Optional[Any]:
        """Recall from long-term memory."""
        return self.memory.get(key, {}).get("value")

    def generate_report(self, query: str, findings: dict, papers: list) -> dict:
        """Generate comprehensive research report."""
        return {
            "title": f"Research Report: {query}",
            "generated": datetime.utcnow().isoformat() + "Z",
            "summary": f"Comprehensive analysis of {len(papers)} papers on {query}",
            "methodology": {
                "sources": ["ArXiv", "PubMed"],
                "papers_reviewed": len(papers),
                "analysis_method": "Systematic literature review",
            },
            "findings": findings,
            "papers": [
                {"title": p.get("title"), "source": p.get("url") or p.get("doi"), "relevance": "high"}
                for p in papers[:5]
            ],
            "recommendations": [
                "Further investigation recommended in specific areas",
                "Consider experimental validation",
                "Review related work in adjacent fields",
            ],
            "limitations": ["Limited to English language publications", "Focused on recent publications (2024)"],
        }

    def research(self, query: str) -> dict:
        """
        Execute full research workflow.

        Args:
            query: Research topic/question

        Returns:
            dict: Comprehensive research report
        """
        logger.info(f"Starting research on: {query}")

        # Step 1: Search academic sources
        logger.info("Step 1: Searching academic sources...")
        arxiv_papers = self.search_arxiv(query)
        pubmed_papers = self.search_pubmed(query)

        all_papers = arxiv_papers + pubmed_papers
        self.sources.extend(all_papers)

        # Step 2: Browse top papers
        logger.info("Step 2: Browsing relevant papers...")
        for paper in arxiv_papers[:2]:  # Browse top 2
            content = self.browse_paper(paper.get("url", ""))
            paper["full_content"] = content

        # Step 3: Analyze findings
        logger.info("Step 3: Analyzing findings...")
        findings = self.analyze_findings(all_papers)

        # Step 4: Store in memory
        logger.info("Step 4: Storing in memory...")
        self.store_memory(
            f"research_{query}",
            {"papers": len(all_papers), "findings": findings, "timestamp": datetime.utcnow().isoformat()},
        )

        # Step 5: Generate report
        logger.info("Step 5: Generating report...")
        report = self.generate_report(query, findings, all_papers)

        return report


def handler(event: dict, context: Any) -> dict:
    """
    Main handler for Deep Research Agent.

    Args:
        event: Input event with research query
        context: Lambda context

    Returns:
        dict: Research results
    """
    logger.info("Deep Research agent invoked")
    logger.info(f"Event: {json.dumps(event)}")

    try:
        # Extract query
        query = event.get("query", event.get("topic", "machine learning"))

        # Create agent and run research
        agent = ResearchAgent()
        report = agent.research(query)

        return {
            "status": "success",
            "message": f"Research completed on: {query}",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "report": report,
        }

    except Exception as e:
        logger.error(f"Research failed: {str(e)}")
        return {
            "status": "error",
            "message": f"Research failed: {str(e)}",
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }


# Local testing
if __name__ == "__main__":
    test_event = {"query": "transformer neural networks", "max_papers": 10}

    result = handler(test_event, None)
    print(json.dumps(result, indent=2))
