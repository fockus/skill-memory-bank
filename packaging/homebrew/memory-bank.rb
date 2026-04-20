class MemoryBank < Formula
  include Language::Python::Virtualenv

  desc "Universal long-term project memory for AI coding clients (Claude Code, Cursor, etc.)"
  homepage "https://github.com/fockus/skill-memory-bank"
  # url/sha256 updated after each release (brew bump-formula-pr or manual)
  url "https://files.pythonhosted.org/packages/5a/12/be71032d252b888a40966c084916f3fdbd562f745c66462a21bec077a20d/memory_bank_skill-3.0.0rc1.tar.gz"
  sha256 "551eb90e463994bd5fba259547d3da779a11e1226fd88507fad81fb08b9be5b8"
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
