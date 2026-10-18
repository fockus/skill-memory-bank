# shellcheck shell=bash
# Selective orchestration of the existing removal paths; no other-host cleanup.
opencode_scoped_uninstall() {
  local project
  project="$(jq -r '.project_root // ""' "$MANIFEST")" || return 1
  if [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "$project" ]; then
    echo '[uninstall.sh] project does not match recorded ownership; use the recorded project' >&2
    return 1
  fi
  opencode_preflight_remove "$MANIFEST" "$OPENCODE_DIR" || return 1
  opencode_preflight_remove "$OPENCODE_DIR/.mb-global-extensions-manifest.json" "$OPENCODE_DIR" || return 1
  if [ -n "$project" ] && [ -d "$project" ]; then
    bash "$SKILL_DIR/adapters/opencode.sh" preflight-remove "$project" || return 1
  fi
  _mb_oc_start "$MANIFEST" "$OPENCODE_DIR" || return 1
  trap _mb_oc_exit EXIT
  if [ -n "$project" ] && [ -d "$project" ]; then
    bash "$SKILL_DIR/adapters/opencode.sh" uninstall "$project" || return 1
  fi
  # shellcheck source=opencode_uninstall.sh
  . "$SKILL_DIR/adapters/opencode_uninstall.sh" || return 1
  _mb_strict_file global-remove "$MANIFEST" "$MANIFEST" "$OPENCODE_DIR" || return 1
  "$MB_PY" - "$SKILL_DIR" "$MANIFEST" "$OPENCODE_DIR" <<'PY'
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(sys.argv[1], "adapters"))
from opencode_files import manifest

path, root = sys.argv[2:]
data = manifest(path)
prefix = root.rstrip("/") + "/"
data["files"] = [p for p in data.get("files", []) if not p.startswith(prefix)]
data["file_sha256"] = {p: h for p, h in (data.get("file_sha256") or {}).items() if not p.startswith(prefix)}
data["backups"] = [b for b in data.get("backups", []) if not b.split("|", 1)[0].startswith(prefix)]
for key in ("clients", "adapters_failed", "extensions_installed"):
    data[key] = [host for host in data.get(key, []) if host != "opencode"]
data["clients_requested"] = ",".join(host for host in data.get("clients_requested", "").split(",") if host.strip() != "opencode")
data.pop("install_scope", None)
if not data["files"] and not data["clients"] and not data["adapters_failed"] and not data["backups"]:
    os.unlink(path)
else:
    fd, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".mb-manifest.")
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(data, output, indent=2)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY
  echo 'OpenCode uninstalled; other hosts and project memory retained.'
}
