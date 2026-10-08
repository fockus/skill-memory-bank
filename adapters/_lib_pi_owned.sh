# shellcheck shell=bash
# adapters/_lib_pi_owned.sh — ownership ledger for files the opt-in Pi installer
# writes under $PI_AGENT_DIR (sourced by _lib_pi_extensions.sh).
#
# Ledger: $PI_AGENT_DIR/.mb-pi-native-owned.json
#   {"files": {"<abs path>": {"sha256": "...", "preimage": "<abs path>|null"}},
#    "settings": {...}}
# It is updated after every single write, so an interrupted install can still be
# removed precisely. A foreign file we replace is moved to the preimage store
# first; removal restores it. A recorded file whose content no longer matches
# its recorded hash was edited by the user and is never overwritten or removed.

_pi_ledger() { printf '%s\n' "$PI_AGENT_DIR/.mb-pi-native-owned.json"; }
_pi_preimage_dir() { printf '%s\n' "$PI_AGENT_DIR/.mb-pi-preimages"; }

_pi_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# _pi_ledger_update <jq filter> [jq args...] — atomic rewrite of the ledger.
_pi_ledger_update() {
  local ledger tmp filter="$1"
  shift
  ledger="$(_pi_ledger)"
  mkdir -p "$PI_AGENT_DIR"
  [ -f "$ledger" ] || printf '{"files": {}, "settings": {}}\n' > "$ledger"
  tmp="$(mktemp "$ledger.XXXXXX")"
  if jq "$@" "$filter" "$ledger" > "$tmp"; then
    mv "$tmp" "$ledger"
  else
    rm -f "$tmp"
    return 1
  fi
}

_pi_owned_sha() {
  local ledger
  ledger="$(_pi_ledger)"
  [ -f "$ledger" ] || return 0
  jq -r --arg p "$1" '.files[$p].sha256 // empty' "$ledger"
}

# Prints "owned" (absent / identical / recorded-unchanged), "edited" or "foreign".
_pi_owned_state() {
  local dest="$1" new_sha="$2" recorded current
  [ -e "$dest" ] || { echo owned; return 0; }
  recorded="$(_pi_owned_sha "$dest")"
  current="$(_pi_sha256 "$dest")"
  if [ "$current" = "$new_sha" ] || [ "$current" = "$recorded" ]; then
    echo owned
  elif [ -n "$recorded" ]; then
    echo edited
  else
    echo foreign
  fi
}

# _pi_owned_put <prepared tmp file> <dest>: install with ownership semantics.
# The tmp file is consumed. A user-edited owned file is kept as-is.
_pi_owned_put() {
  local src="$1" dest="$2" new_sha state preimage=""
  new_sha="$(_pi_sha256 "$src")"
  state="$(_pi_owned_state "$dest" "$new_sha")"
  if [ "$state" = "edited" ]; then
    echo "[pi-adapter] keeping user-edited $dest" >&2
    rm -f "$src"
    return 0
  fi
  if [ "$state" = "foreign" ]; then
    preimage="$(_pi_preimage_dir)/${dest#"$PI_AGENT_DIR"/}"
    mkdir -p "$(dirname "$preimage")"
    mv "$dest" "$preimage"
  else
    preimage="$(jq -r --arg p "$dest" '.files[$p].preimage // empty' "$(_pi_ledger)" 2>/dev/null || true)"
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$src" "$dest"
  # shellcheck disable=SC2016  # jq variables, not shell
  _pi_ledger_update '.files[$p] = {sha256: $s, preimage: (if $pre == "" then null else $pre end)}' \
    --arg p "$dest" --arg s "$new_sha" --arg pre "$preimage"
}

# _pi_owned_copy <src> <dest> [mode]: verbatim copy through _pi_owned_put.
_pi_owned_copy() {
  local tmp
  mkdir -p "$(dirname "$2")"
  tmp="$(mktemp "$2.mbtmp.XXXXXX")"
  cp "$1" "$tmp"
  chmod "${3:-644}" "$tmp"
  _pi_owned_put "$tmp" "$2"
}

# Removes unchanged owned files, restores preimages, keeps user edits.
_pi_owned_remove_all() {
  local ledger path recorded preimage
  ledger="$(_pi_ledger)"
  [ -f "$ledger" ] || return 0
  while IFS=$'\t' read -r path recorded preimage; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] && [ "$(_pi_sha256 "$path")" != "$recorded" ]; then
      echo "[pi-adapter] keeping user-edited $path" >&2
      continue
    fi
    rm -f "$path"
    if [ -n "$preimage" ] && [ -e "$preimage" ]; then
      mv "$preimage" "$path"
    fi
  done < <(jq -r '.files | to_entries[] | [.key, .value.sha256, (.value.preimage // "")] | @tsv' "$ledger")
  rm -f "$ledger"
  find "$(_pi_preimage_dir)" -depth -type d -empty -delete 2>/dev/null || true
}
