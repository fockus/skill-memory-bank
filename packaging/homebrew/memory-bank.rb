class MemoryBank < Formula
  include Language::Python::Virtualenv

  desc "Universal long-term project memory for AI coding clients (Claude Code, Cursor, etc.)"
  homepage "https://github.com/fockus/skill-memory-bank"
  # url/sha256 updated after each release (brew bump-formula-pr or manual)
  # After `v3.0.0` is pushed and PyPI publishes the sdist, replace the
  # url + sha256 below via `brew bump-formula-pr` in the tap repo.
  url "https://files.pythonhosted.org/packages/source/m/memory-bank-skill/memory_bank_skill-3.0.0.tar.gz"
  sha256 "PENDING_AFTER_PYPI_PUBLISH"
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
