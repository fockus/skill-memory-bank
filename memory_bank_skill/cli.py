"""memory-bank CLI — thin Python wrapper over install.sh / uninstall.sh.

Subcommands:
    install       Run global + optional cross-agent adapter install
    uninstall     Remove global install
    init          Bootstrap .memory-bank/ in current project (hint: use /mb init)
    version       Print version string
    self-update   Suggest pipx upgrade command
    doctor        Print resolved bundle path + platform info

Windows is not supported (skill relies on bash); CLI exits with a helpful
message + WSL hint instead of silently failing.
"""

from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys

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


# ═══ Platform gate ═══
def is_windows() -> bool:
    return platform.system().lower() == "windows"


def require_posix() -> None:
    if is_windows():
        sys.stderr.write(
            "memory-bank-skill requires a POSIX shell (macOS or Linux).\n"
            "Windows: use WSL (Windows Subsystem for Linux) to run the skill.\n"
            "  1. wsl --install\n"
            "  2. From inside WSL: pipx install memory-bank-skill && memory-bank install\n"
        )
        sys.exit(2)


# ═══ Shell invocation ═══
def run_shell(script: str, *args: str) -> int:
    """Execute a bundled shell script, returning its exit code."""
    bundle = find_bundle_root()
    script_path = bundle / script
    if not script_path.is_file():
        sys.stderr.write(f"[memory-bank] missing bundled script: {script_path}\n")
        return 3
    cmd = ["bash", str(script_path), *args]
    try:
        result = subprocess.run(cmd, check=False)  # noqa: S603
    except FileNotFoundError:
        sys.stderr.write("[memory-bank] `bash` not found on PATH\n")
        return 4
    return result.returncode


# ═══ Subcommand handlers ═══
def cmd_install(args: argparse.Namespace) -> int:
    require_posix()
    sh_args: list[str] = []
    if args.clients:
        sh_args.extend(["--clients", args.clients])
    if args.project_root:
        sh_args.extend(["--project-root", args.project_root])
    return run_shell("install.sh", *sh_args)


def cmd_uninstall(_args: argparse.Namespace) -> int:
    require_posix()
    return run_shell("uninstall.sh")


def cmd_init(args: argparse.Namespace) -> int:
    require_posix()
    # `/mb init` is handled by Claude Code command; CLI just hints
    target = args.project_root or os.getcwd()
    sys.stdout.write(
        f"[memory-bank] To initialize Memory Bank for a project, run inside Claude Code:\n"
        f"    /mb init\n\n"
        f"  Target project: {target}\n"
        f"  This creates .memory-bank/ with STATUS.md, checklist.md, plan.md, RESEARCH.md.\n"
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
    if is_windows():
        sys.stdout.write("Windows detected — `install` / `uninstall` blocked (use WSL).\n")
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
        help=f"Comma-separated client list. Valid: {', '.join(VALID_CLIENTS)}",
    )
    p_install.add_argument("--project-root", help="Target directory for cross-agent adapters (default: PWD)")
    p_install.set_defaults(func=cmd_install)

    p_uninstall = sub.add_parser("uninstall", help="Remove global skill install")
    p_uninstall.set_defaults(func=cmd_uninstall)

    p_init = sub.add_parser("init", help="Print initialization hint (use /mb init inside Claude Code)")
    p_init.add_argument("--project-root", help="Target project directory (default: PWD)")
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
