#!/usr/bin/env bash
# mb-team-checkpoint.sh — checkpoint of a working tree (design §7). Reads the tree through mb_vcs.sh;
# writes only into --dir. Restore commands are printed, never run.
#   create --tree <dir> --baseline <rev> --topic <t> --dir <out> [--label L] [--max-untracked-mb N]
#   verify --dir <out> <id>
# Exit: 0 ok · 1 verify mismatch · 2 usage / not inside a tree.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sub="${1:-}"; [ -n "$sub" ] && shift || { echo "usage: create|verify ..." >&2; exit 2; }
tree=""; base=""; topic=""; out=""; label="cp"; maxmb=512; id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) tree="$2"; shift 2 ;; --baseline) base="$2"; shift 2 ;; --topic) topic="$2"; shift 2 ;;
    --dir) out="$2"; shift 2 ;; --label) label="$2"; shift 2 ;; --max-untracked-mb) maxmb="$2"; shift 2 ;;
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
    mkdir -p "$out"
    cid="$(date +%Y-%m-%d-%H%M)-$topic-$label"
    bash "$here/mb_vcs.sh" diff --tree "$tree" "$base" >"$out/$cid.diff"
    bash "$here/mb_vcs.sh" changed --tree "$tree" "$base" >"$out/.$cid.changed"
    bash "$here/mb_vcs.sh" untracked --tree "$tree" >"$out/.$cid.untracked"
    python3 - "$out" "$cid" "$root" "$vcs" "$head" "$base" "$maxmb" <<'PY'
import hashlib, json, os, sys, tarfile
out, cid, root, vcs, head, base, maxmb = sys.argv[1:]
cap = float(maxmb) * 1024 * 1024
tmp = lambda n: os.path.join(out, "." + cid + "." + n)
changed = [p for p in open(tmp("changed"), "rb").read().decode().split("\0") if p]
paths = [p for p in open(tmp("untracked"), "rb").read().decode().split("\0") if p]
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
    echo "restore: git -C $root apply $out/$cid.diff (arc trees: patch -p1 -d $root < $out/$cid.diff) && tar -xzf $out/$cid-untracked.tar.gz -C $root" >&2
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
