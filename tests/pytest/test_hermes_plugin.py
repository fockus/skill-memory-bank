"""Hermes plugin: picks the session's bank and drives the skill's own scripts against it."""

import importlib.util
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
PLUGIN = REPO / "hermes" / "memory-bank" / "__init__.py"


class Host:
    """The slice of Hermes's PluginContext the plugin uses."""

    def __init__(self, cwd=""):
        self.cwd = str(cwd)
        self.sections, self.env, self.hooks = {}, {}, {}

    def register_system_prompt_section(self, id, content, **kwargs):
        self.sections[id] = content

    def register_session_env(self, names, resolver):
        self.env = {"names": list(names), "resolver": resolver}

    def register_hook(self, name, callback, **kwargs):
        self.hooks[name] = callback

    def session_cwd(self):
        return self.cwd


@pytest.fixture
def plugin(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path / "profile"))
    spec = importlib.util.spec_from_file_location("hermes_memory_bank_plugin", PLUGIN)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "_project_slug", lambda cwd: None)
    return module


def render(plugin, cwd, session_id="s1"):
    host = Host(cwd)
    plugin.register(host)
    text = host.sections["memory-bank"]({"cwd": str(cwd), "session_id": session_id})
    return host, text


def test_folder_bank_used_from_nested_cwd(plugin, tmp_path):
    bank = tmp_path / "repo" / ".memory-bank"
    bank.mkdir(parents=True)
    (bank / "status.md").write_text("# Status\nphase-marker-42\n")
    deep = tmp_path / "repo" / "src" / "deep"
    deep.mkdir(parents=True)

    host, text = render(plugin, deep)

    assert str(bank) in text and "(folder)" in text
    assert "phase-marker-42" in text  # rendered by the skill's own session-start context script
    assert "\\n" not in text
    env = host.env["resolver"]("s1")
    assert env["MB_PATH"] == str(bank)
    assert env["MB_SKILLS_ROOT"] == str(REPO)


def test_hermes_project_without_bank_gets_one_in_profile(plugin, tmp_path, monkeypatch):
    repo = tmp_path / "work"
    repo.mkdir()
    monkeypatch.setattr(plugin, "_project_slug", lambda cwd: "shop-app")

    _, text = render(plugin, repo)

    bank = tmp_path / "profile" / "projects" / "shop-app" / ".memory-bank"
    assert (bank / "status.md").is_file()  # scaffolded by the skill's mb-init-bank.sh
    assert str(bank) in text and "(project)" in text
    assert not (repo / ".memory-bank").exists()


def test_plain_session_uses_profile_general_bank(plugin, tmp_path):
    chat = tmp_path / "anywhere"
    chat.mkdir()

    for cwd in (chat, ""):
        _, text = render(plugin, cwd)
        bank = tmp_path / "profile" / ".memory-bank"
        assert (bank / "status.md").is_file()
        assert str(bank) in text and "(general)" in text


def test_unsafe_project_slug_falls_back_to_general(plugin, tmp_path, monkeypatch):
    monkeypatch.setattr(plugin, "_project_slug", lambda cwd: "../escape")
    _, text = render(plugin, tmp_path)
    assert "(general)" in text
    assert not (tmp_path / "escape").exists()


def test_session_end_and_compaction_refresh_handoff(plugin, tmp_path):
    bank = tmp_path / "repo" / ".memory-bank"
    bank.mkdir(parents=True)
    (bank / "status.md").write_text("# Status\n")
    host, _ = render(plugin, tmp_path / "repo", session_id="s9")

    host.hooks["post_compaction"](session_id="s10", old_session_id="s9")
    assert (bank / "handoff" / "latest.md").is_file()

    (bank / "handoff" / "latest.md").unlink()
    host.hooks["on_session_finalize"](session_id="s9", platform="cli")
    assert (bank / "handoff" / "latest.md").is_file()


def test_unknown_session_hooks_do_nothing(plugin, tmp_path):
    host, _ = render(plugin, tmp_path, session_id="s1")
    host.hooks["on_session_finalize"](session_id="other")
    host.hooks["post_compaction"](session_id="x", old_session_id="y")
    assert not (tmp_path / "profile" / ".memory-bank" / "handoff" / "latest.md").exists()


def test_session_end_refreshes_semantic_index_in_background(plugin, tmp_path, monkeypatch):
    marker = tmp_path / "reindexed"
    fake = tmp_path / "fake-python"
    fake.write_text(f'#!/bin/sh\necho "$MB_ROOT $2 $3" > "{marker}"\n')
    fake.chmod(0o755)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(fake))
    bank = tmp_path / "repo" / ".memory-bank"
    bank.mkdir(parents=True)
    host, _ = render(plugin, tmp_path / "repo", session_id="s1")

    host.hooks["on_session_finalize"](session_id="s1")

    for _ in range(50):
        if marker.exists():
            break
        time.sleep(0.1)
    assert marker.read_text().split() == [str(bank), "reindex"]


def test_section_says_who_shares_the_bank_and_how_to_search(plugin, tmp_path):
    _, text = render(plugin, tmp_path)
    assert "shared by all of its sessions" in text
    assert "/mb recall" in text and "mb-graph.sh" in text


def test_global_rules_sections_come_from_the_skill(plugin, tmp_path):
    host = Host(tmp_path)
    plugin.register(host)
    key_rules = host.sections["mb-key-rules"]({"cwd": str(tmp_path)})
    engineering = host.sections["mb-engineering-rules"]({"cwd": str(tmp_path)})
    assert "## Key rules" in key_rules and "<!--" not in key_rules
    assert "Memory Bank" in engineering
    assert len(key_rules) <= 4000 and len(engineering) <= 4000
