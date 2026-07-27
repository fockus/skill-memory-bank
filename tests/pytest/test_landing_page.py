"""Smoke tests for the static GitHub Pages landing page."""

from __future__ import annotations

import hashlib
import re
from html.parser import HTMLParser
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SITE_ROOT = REPO_ROOT / "site"


class _AssetParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.stylesheets: list[str] = []
        self.scripts: list[str] = []
        self.sections: set[str] = set()
        self.anchors: set[str] = set()
        self.title = ""
        self.description = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = dict(attrs)
        if tag == "link" and attr_map.get("rel") == "stylesheet" and attr_map.get("href"):
            self.stylesheets.append(attr_map["href"])
        if tag == "script" and attr_map.get("src"):
            self.scripts.append(attr_map["src"])
        if tag == "section" and attr_map.get("id"):
            self.sections.add(attr_map["id"])
        if tag == "a" and attr_map.get("href"):
            self.anchors.add(attr_map["href"])
        if tag == "meta" and attr_map.get("name") == "description" and attr_map.get("content"):
            self.description = attr_map["content"]

    def handle_data(self, data: str) -> None:
        if data.strip() and not self.title:
            return

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)


class _TitleParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._inside_title = False
        self.title = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "title":
            self._inside_title = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._inside_title = False

    def handle_data(self, data: str) -> None:
        if self._inside_title:
            self.title += data


def _parse_html() -> tuple[str, _AssetParser]:
    index_file = SITE_ROOT / "index.html"
    html = index_file.read_text(encoding="utf-8")

    asset_parser = _AssetParser()
    asset_parser.feed(html)

    title_parser = _TitleParser()
    title_parser.feed(html)

    return title_parser.title.strip(), asset_parser


def test_landing_page_contains_core_sections_and_assets() -> None:
    index_file = SITE_ROOT / "index.html"
    assert index_file.is_file(), "site/index.html must exist"

    title, parsed = _parse_html()

    assert title == "memory-bank-skill v5 — Persistent memory for AI coding agents"
    assert parsed.description.startswith("Long-term project memory")
    assert {"problem", "workflow", "agents", "install", "cta"} <= parsed.sections
    assert "#install" in parsed.anchors
    assert any("github.com/fockus/skill-memory-bank" in href for href in parsed.anchors)

    for asset_path in [*parsed.stylesheets, *parsed.scripts]:
        assert not asset_path.startswith("http"), (
            f"Expected a local asset, not a remote one: {asset_path}"
        )
        # Assets carry a content-hash cache-buster (`styles.css?v=<sha256[:8]>`);
        # the query is not part of the on-disk path.
        file_part, _, query = asset_path.partition("?")
        candidate = (SITE_ROOT / file_part).resolve()
        assert candidate.is_file(), f"Asset referenced from HTML is missing on disk: {file_part}"

        # A stale cache-buster is worse than none: browsers keep serving the old
        # file. Pin the query to the real content hash so editing an asset without
        # bumping its `?v=` fails here.
        if query:
            assert query.startswith("v="), (
                f"Only a `v=<hash>` cache-buster is expected on {file_part}, got {query!r}"
            )
            digest = hashlib.sha256(candidate.read_bytes()).hexdigest()[: len(query) - 2]
            assert query[2:] == digest, (
                f"Stale cache-buster on {file_part}: HTML says v={query[2:]}, "
                f"content hashes to {digest}. Update the `?v=` in site/index.html."
            )


def test_pages_workflow_publishes_site_directory() -> None:
    workflow_file = REPO_ROOT / ".github" / "workflows" / "pages.yml"
    assert workflow_file.is_file(), "A dedicated GitHub Pages workflow is required"

    workflow = workflow_file.read_text(encoding="utf-8")
    assert "actions/configure-pages" in workflow
    assert "actions/upload-pages-artifact" in workflow
    assert "actions/deploy-pages" in workflow

    # The landing page is no longer uploaded straight from `site/`: since the
    # combined deploy (landing at `/`, MkDocs at `/docs/`) both are staged into
    # $RUNNER_TEMP/pages first. What must stay true is that site/ ends up in the
    # uploaded artifact — assert the copy and the upload, not the old literal path.
    staging = "$RUNNER_TEMP/pages"
    assert re.search(rf'cp -R site/\. "{re.escape(staging)}/?"', workflow), (
        f"pages.yml must copy the landing page into the artifact staging dir ({staging})"
    )
    assert "path: ${{ runner.temp }}/pages" in workflow, (
        "upload-pages-artifact must upload the staging dir that site/ was copied into"
    )
