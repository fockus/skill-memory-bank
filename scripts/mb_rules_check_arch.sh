# shellcheck shell=bash
# Preset-driven architecture checks for mb-rules-check.sh (I-252).
#
# An architecture preset (references/rules-presets/architecture/<name>.json) is
# "mechanical": true when a script can check it. Presets with a "check" block are
# scanned here; fsd keeps its own check (mb_rules_check_stack.sh). clean's
# domain → infrastructure is the always-on baseline clean_arch/direction; its preset
# check covers the other backward edges and is not counted as an extra check.
# "mechanical": false presets are guidance only: nothing is scanned and nothing is
# emitted.
#
# "check" is one check object or a list of them; a line reports its first hit only.
# "check" kinds — directory conventions, all names matched as whole path segments:
#   layer         a file under any `from` dir must not import a target that has a
#                 `to` segment (hexagonal: core → adapters; mobile-udf: usecase → ui).
#   cross-module  a file under <root>/<A>/ must not import <root>/<B>/... (B ≠ A) unless
#                 B is in `shared` or the first segment after <root>/<B> is in `public`
#                 (a bare <root>/<B> import counts as its `index` entry). <root>/<B>
#                 must exist as a directory next to <root>/<A>; otherwise the layout
#                 does not match the convention and the import is skipped.
# Import targets: quoted paths (JS/TS, Go incl. import blocks, require, #include;
# relative ones resolved against the file) and dotted/:: names (Python incl.
# relative `from ..x`, Java/Kotlin/Swift `import`, Rust/PHP `use`).

# check_arch_preset <architecture-name>
check_arch_preset() {
  local name="$1" preset
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || return 0
  preset="$REPO_ROOT/references/rules-presets/architecture/$name.json"
  [[ -f "$preset" ]] && grep -q '"check"' "$preset" || return 0
  (( ${#FILES[@]} == 0 )) && return 0
  # clean extends the baseline clean_arch/direction check (already counted).
  [[ "$name" == clean ]] || CHECKS_RUN=$((CHECKS_RUN + 1))
  local arch_source sev="" sev_rule="" rule_id line file excerpt rationale
  arch_source="$(profile_source_for architecture)"
  while IFS=$'\t' read -r rule_id line file excerpt rationale; do
    [[ -n "$file" ]] || continue
    if [[ "$rule_id" != "$sev_rule" ]]; then
      sev_rule="$rule_id"
      sev="$(preset_severity "$rule_id" WARNING)"
    fi
    emit_violation "$rule_id" "$sev" "$file" "$line" "$excerpt" "$rationale" "$rule_id" "$arch_source"
  done < <(_arch_scan "$preset" "${FILES[@]}")
}

# _arch_scan <preset.json> <file>... — TSV: rule_id, line, file, excerpt, rationale.
_arch_scan() {
  python3 - "$@" <<'PY'
import json, os, re, sys

preset = json.load(open(sys.argv[1], encoding="utf-8"))
arch = preset["name"]
checks = preset["check"] if isinstance(preset["check"], list) else [preset["check"]]

QUOTED = [
    re.compile(r"""^\s*(?:import|export)\b.*?["']([^"']+)["']"""),
    re.compile(r"""\brequire\(\s*["']([^"']+)["']"""),
    re.compile(r"""^\s*#\s*include\s+["<]([^">]+)[">]"""),
]
GO_BLOCK_ENTRY = re.compile(r'^\s*(?:[\w.]+\s+)?"([^"]+)"\s*$')
DOTTED = [
    re.compile(r"^\s*from\s+([\w.]+)\s+import\b"),
    re.compile(r"^\s*import\s+(?:static\s+)?([\w.]+)"),
    re.compile(r"^\s*use\s+([\w:\\]+)"),
]


def target_segments(line, dsegs, in_go_block):
    pats = QUOTED + ([GO_BLOCK_ENTRY] if in_go_block else [])
    for pat in pats:
        m = pat.search(line)
        if m:
            t = m.group(1)
            if t.startswith("."):
                t = os.path.normpath(os.path.join("/".join(dsegs), t))
            return [s for s in t.split("/") if s]
    for pat in DOTTED:
        m = pat.search(line)
        if m:
            t = m.group(1)
            dots = len(t) - len(t.lstrip("."))
            segs = re.split(r"::|\\|\.", t[dots:])
            if dots:
                segs = dsegs[: len(dsegs) - (dots - 1)] + segs
            return [s for s in segs if s]
    return []


def layer_hit(cfg, dsegs, tsegs):
    if not set(dsegs) & set(cfg["from"]) or set(dsegs) & set(cfg["to"]):
        return None
    # domain → infrastructure is already the baseline clean_arch/direction finding.
    if "domain" in dsegs and "infrastructure" in tsegs:
        return None
    hit = next((s for s in tsegs if s in cfg["to"]), None)
    src = next(s for s in dsegs if s in cfg["from"])
    return hit and f"{arch}: code under {src}/ must not import {hit}/ (dependency points outward); depend on a port it owns."


def cross_module_hit(cfg, dsegs, tsegs):
    i = next((k for k, s in enumerate(dsegs[:-1]) if s in cfg["roots"]), None)
    if i is None:
        return None
    root, a = dsegs[i], dsegs[i + 1]
    j = next((k for k, s in enumerate(tsegs[:-1]) if s == root), None)
    if j is None:
        return None
    b, rest = tsegs[j + 1], tsegs[j + 2:]
    if b == a or b in cfg["shared"] or not os.path.isdir("/".join(dsegs[: i + 1] + [b])):
        return None
    entry = os.path.splitext(rest[0])[0] if rest else "index"
    if entry in cfg["public"]:
        return None
    way = f"its public entry ({', '.join(cfg['public'])})" if cfg["public"] else "its API or events"
    return f"{arch}: {root}/{a} reaches into {root}/{b}; go through {way} or a shared module ({', '.join(cfg['shared'])})."


KINDS = {"layer": layer_hit, "cross-module": cross_module_hit}
for f in sys.argv[2:]:
    if not os.path.isfile(f):
        continue
    dsegs = os.path.dirname(f).split("/")
    in_go_block = False
    with open(f, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            if re.match(r"^\s*import\s*\(\s*$", line):
                in_go_block = True
                continue
            if in_go_block and re.match(r"^\s*\)", line):
                in_go_block = False
                continue
            tsegs = target_segments(line, dsegs, in_go_block)
            if not tsegs:
                continue
            hit = next(((c, why) for c in checks if (why := KINDS[c["kind"]](c, dsegs, tsegs))), None)
            if hit:
                excerpt = line.rstrip("\n").replace("\t", " ")[:120]
                print("\t".join([hit[0]["rule_id"], str(n), f, excerpt, hit[1]]))
PY
}
