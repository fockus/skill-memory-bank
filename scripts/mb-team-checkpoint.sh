#!/usr/bin/env bash
# mb-team-checkpoint.sh — checkpoint of a working tree (design §7). Reads the tree through mb_vcs.sh;
# writes only into --dir. Restore commands are printed, never run.
#   create --tree <dir> --baseline <rev> --topic <t> --dir <out> [--label L] [--max-untracked-mb N] [--adopt]
#   verify --dir <out> <id>
# Exit: 0 ok · 1 verify mismatch or id already exists · 2 usage / not inside a tree.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sub="${1:-}"; [ -n "$sub" ] && shift || { echo "usage: create|verify ..." >&2; exit 2; }
tree=""; base=""; topic=""; out=""; label="cp"; maxmb=512; id=""; adopt=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) tree="$2"; shift 2 ;; --baseline) base="$2"; shift 2 ;; --topic) topic="$2"; shift 2 ;;
    --dir) out="$2"; shift 2 ;; --label) label="$2"; shift 2 ;; --max-untracked-mb) maxmb="$2"; shift 2 ;;
    --adopt) adopt=1; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;; *) id="$1"; shift ;;
  esac
done
[ -n "$out" ] || { echo "--dir is required" >&2; exit 2; }

case "$sub" in
  create)
    [ -n "$tree" ] && [ -n "$base" ] && [ -n "$topic" ] || { echo "create needs --tree --baseline --topic" >&2; exit 2; }
    vcs=$(bash "$here/mb_vcs.sh" kind --tree "$tree") || exit 2
    root=$(bash "$here/mb_vcs.sh" root --tree "$tree")
    head=$(bash "$here/mb_vcs.sh" head --tree "$tree")
    [[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "invalid --label '$label'" >&2; exit 2; }
    # --dir is user config. The self-exclusion filter below drops everything under --dir from the tar and
    # the `*` .gitignore hides it from git, so both may only touch a dir this script owns: one it creates,
    # an existing empty one, one marked by `.mb-team-checkpoint` (a regular file), or one the caller adopts
    # (--adopt: the default <bank>/backups/team). The tree root or an ancestor, and any other existing dir
    # inside the tree, are refused before anything is written.
    where=$(python3 -c 'import os, sys
o, r = (os.path.realpath(p) for p in sys.argv[1:])
print("contains" if r == o or r.startswith(o.rstrip(os.sep) + os.sep) else "inside" if o.startswith(r + os.sep) else "outside")' "$out" "$root")
    [ "$where" != contains ] || { echo "--dir $out contains the tree $root; choose a dir inside or outside it" >&2; exit 2; }
    marker="$out/.mb-team-checkpoint"; owned=1
    if [ -e "$out" ] || [ -L "$out" ]; then
      owned=0
      if [ "$adopt" = 1 ] || { [ -f "$marker" ] && [ ! -L "$marker" ]; }; then owned=1
      elif [ -d "$out" ] && [ -z "$(ls -A "$out")" ]; then owned=1
      fi
    fi
    if [ "$owned" = 0 ] && [ "$where" = inside ]; then
      echo "--dir $out is not a dedicated checkpoint dir (no $marker); use a new or empty dir" >&2; exit 2
    fi
    umask 077; mkdir -p "$out" || exit 2
    # Private and git-ignored: the tars hold every untracked file, and a dir inside the tree must not show up
    # as an untracked candidate for a commit. A foreign dir outside the tree is left as it is.
    if [ "$owned" = 1 ]; then
      chmod 700 "$out"
      [ -e "$out/.gitignore" ] || printf '*\n' >"$out/.gitignore"
      [ -f "$marker" ] || : >"$marker"
    fi
    cid="$(date +%Y-%m-%d-%H%M%S)-$topic-$label"
    if [ -e "$out/$cid.diff" ] || [ -e "$out/$cid-manifest.json" ]; then
      echo "checkpoint $cid already exists; nothing written" >&2; exit 1
    fi
    bash "$here/mb_vcs.sh" diff --tree "$tree" "$base" >"$out/$cid.diff"
    bash "$here/mb_vcs.sh" changed --tree "$tree" "$base" >"$out/.$cid.changed"
    bash "$here/mb_vcs.sh" untracked --tree "$tree" >"$out/.$cid.untracked"
    python3 - "$out" "$cid" "$root" "$vcs" "$head" "$base" "$maxmb" <<'PY'
import hashlib, json, os, sys, tarfile
out, cid, root, vcs, head, base, maxmb = sys.argv[1:]
cap = float(maxmb) * 1024 * 1024
tmp = lambda n: os.path.join(out, "." + cid + "." + n)
changed = [p for p in open(tmp("changed"), "rb").read().decode().split("\0") if p]
own = os.path.realpath(out) + os.sep
# The checkpoint dir itself (arc trees ignore no .gitignore) never goes into its own tar.
paths = [p for p in open(tmp("untracked"), "rb").read().decode().split("\0")
         if p and not os.path.realpath(os.path.join(root, p)).startswith(own)]
files, sizes, skipped = [], {}, []
tar_path = os.path.join(out, cid + "-untracked.tar.gz")
with tarfile.open(tar_path, "w:gz") as tar:
    for p in paths:
        full = os.path.join(root, p)
        if not os.path.isfile(full):
            skipped.append({"path": p, "size": None, "reason": "not a regular file"})
            continue
        size = os.path.getsize(full)
        if size > cap:
            skipped.append({"path": p, "size": size, "reason": "larger than max_untracked_mb=" + maxmb})
            continue
        tar.add(full, arcname=p, recursive=False)
        files.append(p); sizes[p] = size
diff_path = os.path.join(out, cid + ".diff")
manifest = {"id": cid, "tree": root, "vcs": vcs, "head": head, "baseline": base,
            "tracked_changed": changed, "files": files, "sizes": sizes,
            "diff_bytes": os.path.getsize(diff_path), "skipped_large": skipped}
man_path = os.path.join(out, cid + "-manifest.json")
json.dump(manifest, open(man_path, "w"), indent=2)
with open(os.path.join(out, cid + ".sha256"), "w") as f:
    for p in (diff_path, tar_path, man_path):
        f.write(hashlib.sha256(open(p, "rb").read()).hexdigest() + "  " + os.path.basename(p) + "\n")
for n in ("changed", "untracked"):
    os.remove(tmp(n))
if skipped:
    print("skipped %d file(s), see manifest skipped_large" % len(skipped), file=sys.stderr)
PY
    echo "$cid"
    # Heads-up when the checkpoint directory is inside a git repo that tracks it.
    if git -C "$out" rev-parse --show-toplevel >/dev/null 2>&1 && [ -n "$(git -C "$out" ls-files . | head -1)" ]; then
      echo "warning: $out contains files tracked by a repository" >&2
    fi
    printf 'restore: git -C %q apply %q && tar -xzf %q -C %q\n' "$root" "$out/$cid.diff" "$out/$cid-untracked.tar.gz" "$root" >&2
    printf 'restore (arc trees): patch -p1 -d %q < %q && tar -xzf %q -C %q\n' \
      "$root" "$out/$cid.diff" "$out/$cid-untracked.tar.gz" "$root" >&2
    ;;
  verify)
    [ -n "$id" ] || { echo "verify needs <id>" >&2; exit 2; }
    python3 - "$out" "$id" <<'PY'
import hashlib, os, sys
out, cid = sys.argv[1:]
bad = 0
for line in open(os.path.join(out, cid + ".sha256")):
    want, name = line.rstrip("\n").split("  ", 1)
    p = os.path.join(out, name)
    got = hashlib.sha256(open(p, "rb").read()).hexdigest() if os.path.exists(p) else "missing"
    if got != want:
        print("MISMATCH " + name, file=sys.stderr); bad += 1
sys.exit(1 if bad else 0)
PY
    ;;
  *) echo "unknown subcommand: $sub" >&2; exit 2 ;;
esac
