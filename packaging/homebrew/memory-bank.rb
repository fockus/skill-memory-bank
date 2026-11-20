class MemoryBank < Formula
  include Language::Python::Virtualenv

  desc "Universal long-term project memory for AI coding clients (Claude Code, Cursor, etc.)"
  homepage "https://github.com/fockus/skill-memory-bank"
  # url tracks VERSION (CI invariant: tests/pytest/test_homebrew_formula_version.py).
  # sha256 is the real digest of the pinned sdist (verified via
  #   curl -sL <url> | shasum -a 256, cross-checked against PyPI's JSON API
  #   digest for this release). On future bumps, recompute both fields —
  #   e.g. via `brew bump-formula-pr fockus/tap/memory-bank --url "<pypi-sdist-url>"`
  #   (it re-downloads the sdist and rewrites both fields); see docs/release-process.md.
  url "https://files.pythonhosted.org/packages/source/m/memory-bank-skill/memory_bank_skill-5.4.1.tar.gz"
  sha256 "2f8e706b549f6aaa49be72d6815c7dca26e239f1bd636d81e0cc41e69a3a52b9"
  license "MIT"
  head "https://github.com/fockus/skill-memory-bank.git", branch: "main"

  depends_on "python@3.12"
  depends_on "jq"

  def install
    virtualenv_install_with_resources
  end

  test do
    # Smoke: CLI prints version and resolves its bundle
    assert_match "memory-bank-skill", shell_output("#{bin}/memory-bank version")
    assert_match "Bundle root:", shell_output("#{bin}/memory-bank doctor")
  end
end
