#!/usr/bin/env bash
# mb-deps-check.sh — preflight dependency checker.
#
# Usage: mb-deps-check.sh [--quiet] [--install-hints]
#
# Required:   bash, python3, jq, git
# Optional:   rg (ripgrep), shellcheck, tree_sitter (Python package),
#             PyYAML (Python package), networkx (Python package),
#             sentence_transformers (Python package — opt-in semantic search)
#
# Output (stdout, key=value — machine-parseable):
#   dep_<name>=ok | missing | optional-missing
#   deps_required_missing=N
#   deps_optional_missing=M
#
# With --install-hints: OS-specific install command suggestions on stderr.
# With --quiet: no emoji/color output, only key=value.
# Exit: 0 if all required present, 1 otherwise.

set -u

QUIET=0
HINTS=0
for arg in "$@"; do
  case "$arg" in
    --quiet)         QUIET=1 ;;
    --install-hints) HINTS=1 ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      exit 1 ;;
  esac
done

# ═══ Helpers ═══
has_cmd() { command -v "$1" >/dev/null 2>&1; }

has_pymod() {
  python3 -c "import $1" >/dev/null 2>&1
}

say() {
  if [ "$QUIET" -eq 0 ]; then echo "$@"; fi
}
say_err() {
  if [ "$QUIET" -eq 0 ]; then echo "$@" >&2; fi
}

# ═══ OS detection ═══
detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
          ubuntu|debian) echo "debian" ;;
          fedora|rhel|centos) echo "fedora" ;;
          arch) echo "arch" ;;
          alpine) echo "alpine" ;;
          *) echo "linux" ;;
        esac
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)

# ═══ Install hint per OS per package ═══
hint_for() {
  local pkg="$1"
  case "$OS:$pkg" in
    macos:python3)     echo "brew install python@3.12" ;;
    "macos:python3>=3.11")  echo "brew install python@3.12 && brew link --overwrite python@3.12" ;;
    macos:jq)          echo "brew install jq" ;;
    macos:git)         echo "brew install git" ;;
    macos:rg)          echo "brew install ripgrep" ;;
    macos:shellcheck)  echo "brew install shellcheck" ;;
    macos:tree_sitter) echo "pip3 install tree-sitter tree-sitter-python tree-sitter-go tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java" ;;
    macos:PyYAML)      echo "pip3 install PyYAML" ;;
    macos:networkx)    echo "pip3 install networkx" ;;
    macos:sentence_transformers) echo "pip3 install sentence-transformers" ;;
    debian:python3)     echo "sudo apt install python3" ;;
    "debian:python3>=3.11") echo "sudo apt install python3.11 (or: pyenv install 3.11)" ;;
    debian:jq)          echo "sudo apt install jq" ;;
    debian:git)         echo "sudo apt install git" ;;
    debian:rg)          echo "sudo apt install ripgrep" ;;
    debian:shellcheck)  echo "sudo apt install shellcheck" ;;
    debian:tree_sitter) echo "pip3 install tree-sitter tree-sitter-python tree-sitter-go tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java" ;;
    debian:PyYAML)      echo "pip3 install PyYAML" ;;
    debian:networkx)    echo "pip3 install networkx" ;;
    debian:sentence_transformers) echo "pip3 install sentence-transformers" ;;
    fedora:python3)     echo "sudo dnf install python3" ;;
    "fedora:python3>=3.11") echo "sudo dnf install python3.11" ;;
    fedora:jq)          echo "sudo dnf install jq" ;;
    fedora:git)         echo "sudo dnf install git" ;;
    fedora:rg)          echo "sudo dnf install ripgrep" ;;
    fedora:shellcheck)  echo "sudo dnf install ShellCheck" ;;
    arch:python3)       echo "sudo pacman -S python" ;;
    "arch:python3>=3.11") echo "sudo pacman -S python (Arch tracks current Python 3.x already)" ;;
    arch:jq)            echo "sudo pacman -S jq" ;;
    arch:git)           echo "sudo pacman -S git" ;;
    arch:rg)            echo "sudo pacman -S ripgrep" ;;
    arch:shellcheck)    echo "sudo pacman -S shellcheck" ;;
    *) echo "install $pkg (see docs)" ;;
  esac
}

# ═══ Check tools ═══
REQUIRED_MISSING=0
OPTIONAL_MISSING=0
MISSING_REQUIRED=()
MISSING_OPTIONAL=()

check_required() {
  local name="$1" binary="$2"
  if has_cmd "$binary"; then
    echo "dep_${name}=ok"
  else
    echo "dep_${name}=missing"
    REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    MISSING_REQUIRED+=("$name")
  fi
}

# A11: the project requires python3 >= 3.11 (pyproject.toml target-version =
# py311). check_required only verifies the binary exists; this verifies the
# version separately so a too-old interpreter is a distinct, explicit blocker
# rather than a confusing downstream failure inside memory_bank_skill.
check_python_version() {
  if ! has_cmd python3; then
    return 0  # already reported missing by check_required above
  fi
  if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    echo "dep_python3_version=ok"
  else
    local found
    found="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
    [ -n "$found" ] || found="unknown"
    echo "dep_python3_version=missing"
    say_err "  python3: found $found, but Memory Bank requires >= 3.11 (pyproject.toml target-version=py311)"
    REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    MISSING_REQUIRED+=("python3>=3.11")
  fi
}

check_optional() {
  local name="$1" binary="$2"
  if has_cmd "$binary"; then
    echo "dep_${name}=ok"
  else
    echo "dep_${name}=optional-missing"
    OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
    MISSING_OPTIONAL+=("$name")
  fi
}

check_pymod_optional() {
  local name="$1" module="$2"
  # Python3 is required for this check; if missing — skip
  if ! has_cmd python3; then
    echo "dep_${name}=optional-missing"
    OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
    MISSING_OPTIONAL+=("$name")
    return
  fi
  if has_pymod "$module"; then
    echo "dep_${name}=ok"
  else
    echo "dep_${name}=optional-missing"
    OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
    MISSING_OPTIONAL+=("$name")
  fi
}

say_err ""
say_err "═══ Memory Bank — dependency check ═══"
say_err ""
say_err "OS: $OS"
say_err ""

# Required
check_required "bash"    "bash"
check_required "python3" "python3"
check_python_version
check_required "jq"      "jq"
check_required "git"     "git"

# Optional CLI
check_optional "rg"         "rg"
check_optional "shellcheck" "shellcheck"

# Optional Python modules
check_pymod_optional "tree_sitter" "tree_sitter"
check_pymod_optional "PyYAML"      "yaml"
check_pymod_optional "networkx"    "networkx"
check_pymod_optional "sentence_transformers" "sentence_transformers"

echo "deps_required_missing=$REQUIRED_MISSING"
echo "deps_optional_missing=$OPTIONAL_MISSING"

# ═══ Hints ═══
if [ "$HINTS" -eq 1 ] || [ "$REQUIRED_MISSING" -gt 0 ]; then
  if [ "${#MISSING_REQUIRED[@]}" -gt 0 ]; then
    say_err ""
    say_err "═══ Required tools missing — install before proceeding ═══"
    for dep in "${MISSING_REQUIRED[@]}"; do
      hint=$(hint_for "$dep")
      say_err "  $dep: $hint"
    done
  fi
  if [ "$HINTS" -eq 1 ] && [ "${#MISSING_OPTIONAL[@]}" -gt 0 ]; then
    say_err ""
    say_err "═══ Optional tools (nice to have) ═══"
    for dep in "${MISSING_OPTIONAL[@]}"; do
      hint=$(hint_for "$dep")
      say_err "  $dep: $hint"
    done
  fi
  say_err ""
fi

# ═══ Summary ═══
if [ "$QUIET" -eq 0 ]; then
  if [ "$REQUIRED_MISSING" -eq 0 ]; then
    say_err "✅ All required dependencies present."
    if [ "$OPTIONAL_MISSING" -gt 0 ]; then
      say_err "   $OPTIONAL_MISSING optional missing — the skill still works, but some features are disabled."
      say_err "   Run with --install-hints to see install commands."
    fi
  else
    say_err "❌ $REQUIRED_MISSING required dep(s) missing — install before using Memory Bank."
  fi
  say_err ""
fi

[ "$REQUIRED_MISSING" -eq 0 ] && exit 0 || exit 1
