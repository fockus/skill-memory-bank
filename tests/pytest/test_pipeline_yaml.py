"""Contract tests for memory_bank_skill.pipeline_yaml."""

from __future__ import annotations

import pytest

yaml = pytest.importorskip("yaml")

# E402 is deliberate: the import must run AFTER importorskip, or this module
# fails to collect on an interpreter without PyYAML instead of skipping.
from memory_bank_skill.pipeline_yaml import PipelineYamlError, load_text  # noqa: E402


def test_load_text_accepts_clean_mapping():
    data = load_text("version: 1\nroles:\n  judge:\n    agent: mb-judge\n")
    assert data["version"] == 1
    assert data["roles"]["judge"]["agent"] == "mb-judge"


def test_load_text_rejects_duplicate_top_level_key():
    text = "version: 1\nbudget:\n  warn_at_percent: 80\nbudget:\n  warn_at_percent: 90\n"
    with pytest.raises(PipelineYamlError, match="duplicate key 'budget'"):
        load_text(text)


def test_load_text_empty_returns_empty_dict():
    assert load_text("") == {}
