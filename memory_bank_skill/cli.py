"""memory-bank CLI — thin Python wrapper over install.sh / uninstall.sh.

Subcommands:
    install       Run global + optional cross-agent adapter install
    uninstall     Remove global install
    init          Bootstrap .memory-bank/ in current project (hint: use /mb init)
    version       Print version string
    self-update   Suggest pipx upgrade command
    doctor        Print resolved bundle path + platform info

Platform support:
    - macOS / Linux: native bash
    - Windows + Git for Windows: auto-detects bash.exe (C:\\Program Files\\Git\\bin\\)
    - Windows + WSL: routes through `wsl bash` if `bash.exe` not found on PATH
    - Windows without either: exits with install hint for Git/WSL
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from memory_bank_skill import __version__
from memory_bank_skill._bundle import find_bundle_root

PACKAGE_NAME = "memory-bank-skill"
VALID_CLIENTS = (
    "claude-code",
    "cursor",
    "windsurf",
    "cline",
    "kilo",
    "opencode",
    "pi",
    "codex",
)
VALID_LANGUAGES = ("en", "ru", "es", "zh")
EXIT_INVALID_USAGE = 2
EXIT_MISSING_SCRIPT = 3
EXIT_BASH_NOT_FOUND = 4


# ═══ Platform detection ═══
def is_windows() -> bool:
    return platform.system().lower() == "windows"


# Common locations where Git for Windows installs bash.exe.
# Listed in priority order (user install first, system install second).
WINDOWS_BASH_CANDIDATES: tuple[str, ...] = (
    r"C:\Program Files\Git\bin\bash.exe",
    r"C:\Program Files (x86)\Git\bin\bash.exe",
    r"C:\Users\Public\Git\bin\bash.exe",
)


def _env_bash_override() -> str | None:
    """Explicit user override: MB_BASH=/path/to/bash.exe."""
    override = os.environ.get("MB_BASH")
    if override and Path(override).exists():
        return override
    return None


def find_bash() -> str | None:
    """Locate a usable bash executable. Returns absolute path or None."""
    # Explicit override wins.
    override = _env_bash_override()
    if override:
        return override

    # POSIX: `bash` on PATH is the normal case.
    if not is_windows():
        found = shutil.which("bash")
        return found

    # Windows: prefer `bash.exe` on PATH (Git Bash adds its dir).
    found = shutil.which("bash.exe") or shutil.which("bash")
    if found and "system32" not in found.lower():
        # Guard against WSL's C:\Windows\System32\bash.exe — that launches WSL
        # interactively without forwarding the script path correctly in every
        # environment. Skip it; fall through to explicit Git Bash paths first.
        return found

    # Check well-known Git for Windows install locations.
    for candidate in WINDOWS_BASH_CANDIDATES:
        if Path(candidate).exists():
            return candidate

    # Last resort: WSL via `wsl bash`. Only return if wsl.exe exists.
    wsl = shutil.which("wsl.exe") or shutil.which("wsl")
    if wsl:
        return wsl  # run_shell() handles the `wsl bash ...` invocation form.

    return None


def windows_install_hint() -> str:
    return (
        "memory-bank-skill needs bash on Windows. Install one of:\n"
        "  • Git for Windows:  winget install Git.Git   (provides bash.exe)\n"
        "  • WSL:              wsl --install            (full Linux env)\n"
        "\n"
        "Then re-run the command. Override detection with:\n"
        '  set MB_BASH="C:\\path\\to\\bash.exe"\n'
    )


def require_bash() -> str:
    """Return path to bash or exit with a helpful message."""
    bash = find_bash()
    if bash:
        return bash
    if is_windows():
        sys.stderr.write(windows_install_hint())
    else:
        sys.stderr.write("[memory-bank] `bash` not found on PATH\n")
    sys.exit(2)


# ═══ Shell invocation ═══
def run_shell(script: str, *args: str) -> int:
    """Execute a bundled shell script, returning its exit code."""
    bundle = find_bundle_root()
    script_path = bundle / script
    if not script_path.is_file():
        sys.stderr.write(f"[memory-bank] missing bundled script: {script_path}\n")
        return EXIT_MISSING_SCRIPT

    bash = require_bash()
    bash_lower = bash.lower()
    is_wsl_wrapper = is_windows() and (bash_lower.endswith("wsl.exe") or bash_lower.endswith("wsl"))

    if is_wsl_wrapper:
        # WSL mode: `wsl bash <script> <args>`. WSL auto-translates C:\ paths
        # under /mnt/c/ when the script resides on the Windows filesystem.
        cmd = [bash, "bash", str(script_path), *args]
    else:
        cmd = [bash, str(script_path), *args]

    try:
        result = subprocess.run(cmd, check=False)  # noqa: S603
    except FileNotFoundError:
        sys.stderr.write(f"[memory-bank] `{bash}` not found on PATH\n")
        return EXIT_BASH_NOT_FOUND
    return result.returncode


def _invalid_clients(raw: str) -> list[str]:
    invalid: list[str] = []
    for client in raw.split(","):
        candidate = client.strip()
        if not candidate:
            continue
        if candidate not in VALID_CLIENTS:
            invalid.append(candidate)
    return invalid


# ═══ Subcommand handlers ═══
def cmd_install(args: argparse.Namespace) -> int:
    if args.clients:
        invalid = _invalid_clients(args.clients)
        if invalid:
            sys.stderr.write(
                "[memory-bank] invalid client(s): "
                f"{', '.join(invalid)}. Valid: {', '.join(VALID_CLIENTS)}\n"
            )
            return EXIT_INVALID_USAGE
    sh_args: list[str] = []
    if args.clients:
        sh_args.extend(["--clients", args.clients])
    if args.language:
        sh_args.extend(["--language", args.language])
    if args.project_root:
        sh_args.extend(["--project-root", args.project_root])
    if args.non_interactive:
        sh_args.append("--non-interactive")
    return run_shell("install.sh", *sh_args)


def cmd_uninstall(args: argparse.Namespace) -> int:
    sh_args: list[str] = []
    if args.non_interactive:
        sh_args.append("-y")
    return run_shell("uninstall.sh", *sh_args)


def cmd_init(args: argparse.Namespace) -> int:
    # `/mb init` is handled by Claude Code command; CLI just hints
    target = args.project_root or os.getcwd()
    lang = args.lang or "en"
    sys.stdout.write(
        f"[memory-bank] To initialize Memory Bank for a project, run inside Claude Code:\n"
        f"    /mb init --lang {lang}\n\n"
        f"  Target project: {target}\n"
        f"  Locale: lang={lang}\n"
        f"  This creates .memory-bank/ with status.md, roadmap.md, checklist.md, "
        f"backlog.md, research.md, progress.md, lessons.md.\n"
    )
    return 0


def cmd_version(_args: argparse.Namespace) -> int:
    sys.stdout.write(f"memory-bank-skill {__version__}\n")
    return 0


def cmd_self_update(_args: argparse.Namespace) -> int:
    sys.stdout.write(
        f"To update memory-bank-skill:\n"
        f"    pipx upgrade {PACKAGE_NAME}\n\n"
        f"Or (if installed via pip): pip install --upgrade {PACKAGE_NAME}\n"
    )
    return 0


def cmd_doctor(_args: argparse.Namespace) -> int:
    sys.stdout.write(f"memory-bank-skill {__version__}\n")
    sys.stdout.write(f"Platform: {platform.system()} {platform.release()}\n")
    sys.stdout.write(f"Python: {sys.version.split()[0]}\n")
    try:
        root = find_bundle_root()
        sys.stdout.write(f"Bundle root: {root}\n")
        sys.stdout.write(f"install.sh: {(root / 'install.sh').is_file()}\n")
        sys.stdout.write(f"adapters/: {(root / 'adapters').is_dir()}\n")
    except FileNotFoundError as e:
        sys.stdout.write(f"Bundle: NOT FOUND ({e})\n")
        return 1

    # Bash discovery: now same report on every platform.
    bash = find_bash()
    if bash:
        sys.stdout.write(f"bash: {bash}\n")
        if is_windows():
            sys.stdout.write("  (Windows: Git Bash / WSL detected — install / uninstall work.)\n")
    else:
        sys.stdout.write("bash: NOT FOUND\n")
        if is_windows():
            sys.stdout.write(windows_install_hint())
        return 1
    return 0


# ═══ Argparse ═══
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="memory-bank",
        description="Universal long-term project memory for AI coding clients.",
    )
    parser.add_argument("--version", action="version", version=f"memory-bank-skill {__version__}")
    sub = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    p_install = sub.add_parser("install", help="Install skill globally + optional cross-agent adapters")
    p_install.add_argument(
        "--clients",
        help=f"Comma-separated client list. Valid: {', '.join(VALID_CLIENTS)}. "
             "Omit to use interactive menu when running in a TTY.",
    )
    p_install.add_argument(
        "--language",
        choices=VALID_LANGUAGES,
        help=f"Preferred installed rules language. Valid: {', '.join(VALID_LANGUAGES)}.",
    )
    p_install.add_argument("--project-root", help="Target directory for cross-agent adapters (default: PWD)")
    p_install.add_argument(
        "--non-interactive",
        action="store_true",
        help="Skip interactive prompts; use defaults when --clients not specified.",
    )
    p_install.set_defaults(func=cmd_install)

    p_uninstall = sub.add_parser("uninstall", help="Remove global skill install")
    p_uninstall.add_argument(
        "-y",
        "--non-interactive",
        action="store_true",
        help="Skip the confirmation prompt and uninstall immediately.",
    )
    p_uninstall.set_defaults(func=cmd_uninstall)

    p_init = sub.add_parser("init", help="Print initialization hint (use /mb init inside Claude Code)")
    p_init.add_argument("--project-root", help="Target project directory (default: PWD)")
    p_init.add_argument(
        "--lang",
        choices=VALID_LANGUAGES,
        default=None,
        help=f"Preferred locale for .memory-bank/ templates. "
             f"Valid: {', '.join(VALID_LANGUAGES)}. Default: en.",
    )
    p_init.set_defaults(func=cmd_init)

    p_version = sub.add_parser("version", help="Print version")
    p_version.set_defaults(func=cmd_version)

    p_update = sub.add_parser("self-update", help="Show upgrade command")
    p_update.set_defaults(func=cmd_self_update)

    p_doctor = sub.add_parser("doctor", help="Show bundle resolution + platform info")
    p_doctor.set_defaults(func=cmd_doctor)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)
