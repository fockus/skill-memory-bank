#!/usr/bin/env bash
# mb_vcs.sh — VCS seam (contract C6) for git and arc. Read-mostly; `add`/`commit` act only on the
# explicit file list given (`commit` is path-scoped: git --only, arc commit <paths>). There is no push/rebase/reset path.
#   mb_vcs.sh <op> --tree <dir> [args]
#   ops: kind | root | head | diff <base> | changed <base> | untracked | add -- <files> | commit -m <msg> -- <paths> | show <rev>:<path>
# `changed` and `untracked` print NUL-separated raw paths relative to the root (no git quoting; a rename
# lists both sides); `untracked` excludes ignored files.
# Detection: git, then arc; MB_VCS=git|arc overrides. Not inside any tree -> exit 2.
set -euo pipefail

op="${1:-}"; [ -n "$op" ] || { echo "usage: mb_vcs.sh <op> --tree <dir> [args]" >&2; exit 2; }
shift
tree="."; rest=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) tree="${2:?--tree needs a dir}"; shift 2 ;;
    *) rest+=("$1"); shift ;;
  esac
done
[ -d "$tree" ] || { echo "mb_vcs: no such directory: $tree" >&2; exit 2; }
cd "$tree"

kind="${MB_VCS:-}"
if [ -z "$kind" ]; then
  if git rev-parse --show-toplevel >/dev/null 2>&1; then kind=git
  elif command -v arc >/dev/null 2>&1 && arc root >/dev/null 2>&1; then kind=arc
  else echo "mb_vcs: $tree is not inside a git or arc tree" >&2; exit 2
  fi
fi
case "$kind" in git|arc) ;; *) echo "mb_vcs: unknown VCS '$kind'" >&2; exit 2 ;; esac

# arc status --short -u all prints "?? <path>" for untracked, ignored files excluded.
arc_untracked() { arc status --short -u all | sed -n 's/^?? //p' | tr '\n' '\0'; }

if [ "$kind" = git ]; then root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
else root=$(arc root 2>/dev/null) || root=""; fi
[ -n "$root" ] || { echo "mb_vcs: $tree is not inside a $kind tree" >&2; exit 2; }
cd "$root"

case "$op" in
  kind) echo "$kind" ;;
  root) echo "$root" ;;
  head) "$kind" rev-parse HEAD ;;
  diff) base="${rest[0]:?base revision required}"
        if [ "$kind" = git ]; then git diff --binary "$base"; else arc diff --git --binary "$base"; fi ;;
  changed) base="${rest[0]:?base revision required}"
           # arc has no -z / quotePath and prints raw names one per line.
           if [ "$kind" = git ]; then git -c core.quotePath=false diff --name-only -z --no-renames "$base"
           else arc diff --name-only "$base" | tr '\n' '\0'; fi ;;
  untracked)
    if [ "$kind" = git ]; then git ls-files -z -o --exclude-standard; else arc_untracked; fi ;;
  add) [ "${rest[0]:-}" = "--" ] && rest=("${rest[@]:1}")
       [ "${#rest[@]}" -gt 0 ] || { echo "mb_vcs: add needs files after --" >&2; exit 2; }
       if [ "$kind" = git ]; then
         # A path gone from both the tree and the index (old side of a staged rename) is already staged.
         keep=()
         for p in "${rest[@]}"; do
           if [ -e "$p" ] || [ -L "$p" ] || git --literal-pathspecs ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
             keep+=("$p")
           fi
         done
         [ "${#keep[@]}" -eq 0 ] || git --literal-pathspecs add -- "${keep[@]}"
       else arc add -- "${rest[@]}"; fi ;;
  commit) [ "${rest[0]:-}" = "-m" ] && [ -n "${rest[1]:-}" ] && [ "${rest[2]:-}" = "--" ] && [ "${#rest[@]}" -gt 3 ] ||
            { echo "mb_vcs: commit needs -m <msg> -- <path>..." >&2; exit 2; }
          # Path-scoped: anything else already staged (another session) stays staged and out of the commit.
          if [ "$kind" = git ]; then git --literal-pathspecs commit --only -m "${rest[1]}" -- "${rest[@]:3}"
          else arc commit -m "${rest[1]}" -- "${rest[@]:3}"; fi ;;
  show) "$kind" show "${rest[0]:?rev:path required}" ;;
  *) echo "mb_vcs: unknown op '$op'" >&2; exit 2 ;;
esac
