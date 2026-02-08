"""
Pytest fixtures for Research agent tests.
"""
import pytest


@pytest.fixture
def sample_query():
    """Sample research query."""
    return "machine learning transformers"


@pytest.fixture
def sample_event():
    """Sample input event for handler."""
    return {"query": "neural networks"}


@pytest.fixture
def sample_arxiv_papers():
    """Sample ArXiv search results."""
    return [
        {
            "id": "2401.00001",
            "title": "Research on ML: A Study",
            "authors": ["Smith, J."],
            "abstract": "This paper presents...",
            "published": "2024-01-15",
            "url": "https://arxiv.org/abs/2401.00001"
        },
        {
            "id": "2401.00002",
            "title": "Advances in ML",
            "authors": ["Jones, A."],
            "abstract": "We present new...",
            "published": "2024-01-10",
            "url": "https://arxiv.org/abs/2401.00002"
        }
    ]


@pytest.fixture
def sample_pubmed_papers():
    """Sample PubMed search results."""
    return [
        {
            "pmid": "12345678",
            "title": "Clinical implications",
            "authors": ["Brown, M.D."],
            "journal": "Nature Medicine",
            "published": "2024-01-12",
            "doi": "10.1038/s41591-024-00001-0"
        }
    ]
