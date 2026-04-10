#!/usr/bin/env bash
#
# .agents/mcp/generate.sh — canonical MCP → per-tool writer
#
# Reads .agents/mcp/servers.json (authoritative list of MCP servers in
# Claude Code's `mcpServers` shape) and writes the equivalent config
# into each of the four tools' native formats:
#
#     Tool        Path                                    Format
#     ----------  --------------------------------------- -------
#     Claude      ~/.claude.json                          JSON   (.mcpServers)
#     Gemini      ~/.gemini/settings.json                 JSON   (.mcpServers)
#     OpenCode    ~/.config/opencode/opencode.json        JSON   (.mcp, reshaped)
#     Codex       ~/.codex/config.toml                    TOML   ([mcp_servers.*])
#
# Each writer:
#   - uses atomic tmp-file + rename (never leaves the target in a half-written state)
#   - preserves all non-MCP keys in the target file (merge semantics, not clobber)
#   - validates before committing (jq or tomllib round-trip)
#
# Usage:
#     generate.sh            # propagate servers.json → all 4 tools
#     generate.sh seed       # extract .mcpServers from ~/.claude.json into servers.json
#     generate.sh -h|--help  # this message
#
# The canonical servers.json is gitignored by default because MCP entries
# often contain API keys. Re-seed from ~/.claude.json on each new machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_JSON="$SCRIPT_DIR/servers.json"

CLAUDE_CONF="$HOME/.claude.json"
GEMINI_CONF="$HOME/.gemini/settings.json"
OPENCODE_CONF="$HOME/.config/opencode/opencode.json"
CODEX_CONF="$HOME/.codex/config.toml"

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

usage() {
    sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

die()  { echo "[!!] $*" >&2; exit 1; }
warn() { echo "[warn] $*" >&2; }
ok()   { echo "[ok] $*"; }

# atomic_json_merge <target> <jq-filter>
#   Reads target as JSON, applies jq filter with servers.json slurped as $s,
#   validates the result parses as JSON, writes via tmp + atomic rename.
#   Skips silently if target file doesn't exist (fresh machine).
atomic_json_merge() {
    local target="$1" filter="$2"
    if [ ! -f "$target" ]; then
        warn "skipping $target (file doesn't exist yet)"
        return 0
    fi
    local tmp
    tmp="$(mktemp "${target}.XXXXXX")"
    if jq --slurpfile s "$SERVERS_JSON" "$filter" "$target" > "$tmp" 2>/dev/null; then
        # Double-check: the output must still be valid JSON
        if jq -e . "$tmp" > /dev/null 2>&1; then
            mv "$tmp" "$target"
            ok "wrote $target"
        else
            rm -f "$tmp"
            die "generated output for $target is not valid JSON — original untouched"
        fi
    else
        rm -f "$tmp"
        die "jq filter failed for $target — original untouched"
    fi
}

# ----------------------------------------------------------------------
# Writers
# ----------------------------------------------------------------------

write_claude() {
    atomic_json_merge "$CLAUDE_CONF" '.mcpServers = $s[0].mcpServers'
}

write_gemini() {
    atomic_json_merge "$GEMINI_CONF" '.mcpServers = $s[0].mcpServers'
}

write_opencode() {
    # OpenCode distinguishes two MCP transports:
    #   - local  — spawns a stdio subprocess. Claude shape: {command, args, env}
    #   - remote — connects to an HTTP/SSE URL. Claude shape: {type: "http"|"sse", url, headers}
    #
    # We branch on the presence of a `url` field. Anything with a url becomes
    # an OpenCode remote; anything else (or stdio-explicit) becomes a local.
    atomic_json_merge "$OPENCODE_CONF" '
        .mcp = ($s[0].mcpServers | map_values(
            if .url then {
                type: "remote",
                url: .url,
                headers: (.headers // {})
            } else {
                type: "local",
                command: ([.command] + (.args // [])),
                environment: (.env // {})
            } end
        ))
    '
}

# write_codex: TOML target needs a Python helper (stdlib has no TOML writer).
#   1. Parse existing config.toml with tomllib
#   2. Drop any existing mcp_servers key
#   3. Re-emit preserved top-level structure
#   4. Append fresh [mcp_servers.<name>] tables from servers.json
#   5. Round-trip validate via tomllib.loads() before atomic rename
write_codex() {
    if [ ! -f "$CODEX_CONF" ]; then
        warn "skipping $CODEX_CONF (file doesn't exist yet)"
        return 0
    fi
    local tmp
    tmp="$(mktemp "${CODEX_CONF}.XXXXXX")"
    if python3 - "$CODEX_CONF" "$SERVERS_JSON" "$tmp" <<'PY'
import json, re, sys, tomllib
from pathlib import Path

config_path, servers_path, out_path = map(Path, sys.argv[1:])

with config_path.open("rb") as f:
    existing = tomllib.load(f)

# Drop existing MCP server definitions — they'll be regenerated below.
existing.pop("mcp_servers", None)

with servers_path.open() as f:
    servers = json.load(f).get("mcpServers", {})


def toml_escape(s: str) -> str:
    """Escape a string for a TOML basic-string literal."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_value(v):
    """Serialize a JSON value as TOML."""
    if isinstance(v, str):
        return toml_escape(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join(emit_value(x) for x in v) + "]"
    raise TypeError(f"cannot emit {type(v).__name__} as TOML scalar")


def emit_scalar_table(name: str, table: dict) -> str:
    """Emit a [name] block with only scalar/array keys."""
    lines = [f"[{name}]"]
    for k, v in table.items():
        if isinstance(v, dict):
            # Nested table — emit as [name.k]
            continue
        lines.append(f"{k} = {emit_value(v)}")
    # Nested tables next
    for k, v in table.items():
        if isinstance(v, dict):
            sub = emit_scalar_table(f"{name}.{k}", v)
            lines.append("")
            lines.append(sub)
    return "\n".join(lines)


def emit_top_level_scalars(data: dict) -> list[str]:
    lines = []
    for k, v in data.items():
        if isinstance(v, dict):
            continue
        lines.append(f"{k} = {emit_value(v)}")
    return lines


# --- Serialize preserved sections ---
out_lines: list[str] = []
out_lines.extend(emit_top_level_scalars(existing))

# Named table keys that use dotted-quoted-key TOML syntax
# (e.g. [projects."/home/dgon/sources/foo"]).
def quote_if_needed(key: str) -> str:
    return key if re.fullmatch(r"[A-Za-z0-9_\-]+", key) else toml_escape(key)


def walk_tables(prefix: str, table: dict):
    for k, v in table.items():
        if not isinstance(v, dict):
            continue
        full = f"{prefix}.{quote_if_needed(k)}" if prefix else quote_if_needed(k)
        out_lines.append("")
        # Emit scalar keys for this table (quote keys with dots/special chars)
        out_lines.append(f"[{full}]")
        for kk, vv in v.items():
            if not isinstance(vv, dict):
                out_lines.append(f"{quote_if_needed(kk)} = {emit_value(vv)}")
        # Recurse into nested tables
        walk_tables(full, v)


walk_tables("", existing)

# --- Append fresh [mcp_servers.<name>] tables ---
#
# Codex MCP supports two transports:
#   stdio — [mcp_servers.name] command = "..." args = [...]
#   http  — [mcp_servers.name] url = "..." (+ optional bearer_token / headers)
#
# We branch on the presence of a `url` field in the source, matching what
# Claude / Gemini use for HTTP-type servers. Stdio is the default.
for name, cfg in servers.items():
    out_lines.append("")
    out_lines.append(f"[mcp_servers.{quote_if_needed(name)}]")

    if cfg.get("url"):
        out_lines.append(f"url = {emit_value(cfg['url'])}")
        # Optional: bearer token as a single string, or full headers table.
        if "bearer_token" in cfg:
            out_lines.append(f"bearer_token = {emit_value(cfg['bearer_token'])}")
        if cfg.get("headers"):
            out_lines.append("")
            out_lines.append(f"[mcp_servers.{quote_if_needed(name)}.headers]")
            for hk, hv in cfg["headers"].items():
                out_lines.append(f"{hk} = {emit_value(hv)}")
    else:
        if "command" in cfg:
            out_lines.append(f"command = {emit_value(cfg['command'])}")
        if cfg.get("args"):
            out_lines.append(f"args = {emit_value(cfg['args'])}")
        if cfg.get("env"):
            out_lines.append("")
            out_lines.append(f"[mcp_servers.{quote_if_needed(name)}.env]")
            for ek, ev in cfg["env"].items():
                out_lines.append(f"{ek} = {emit_value(ev)}")

rendered = "\n".join(out_lines).strip() + "\n"

# --- Validate round-trip ---
#
# Two checks:
#   1. Output must be parseable TOML.
#   2. Round-tripped structure (minus mcp_servers) must match the source
#      structure (also minus mcp_servers). This catches dotted-key
#      misquoting bugs where `gpt-5.3-codex = "..."` would re-parse as
#      nested tables `{gpt-5: {3-codex: "..."}}`.
try:
    round_tripped = tomllib.loads(rendered)
except Exception as e:
    sys.stderr.write(f"round-trip parse failed: {e}\n")
    sys.exit(2)

round_tripped.pop("mcp_servers", None)
if round_tripped != existing:
    sys.stderr.write("round-trip semantic check failed: preserved sections diverged\n")
    sys.stderr.write(f"  expected: {json.dumps(existing, default=str, sort_keys=True)}\n")
    sys.stderr.write(f"  got:      {json.dumps(round_tripped, default=str, sort_keys=True)}\n")
    sys.exit(3)

out_path.write_text(rendered)
PY
    then
        mv "$tmp" "$CODEX_CONF"
        ok "wrote $CODEX_CONF"
    else
        rm -f "$tmp"
        die "codex TOML generation failed — original untouched"
    fi
}

# ----------------------------------------------------------------------
# Seed: extract current MCP config from ~/.claude.json
# ----------------------------------------------------------------------
seed() {
    [ -f "$CLAUDE_CONF" ] || die "$CLAUDE_CONF doesn't exist — can't seed"
    if [ -f "$SERVERS_JSON" ]; then
        warn "$SERVERS_JSON already exists — not overwriting. Delete it first if you want a fresh seed."
        return 0
    fi
    jq '{mcpServers: .mcpServers}' "$CLAUDE_CONF" > "$SERVERS_JSON"
    ok "seeded $SERVERS_JSON from $CLAUDE_CONF"
    local count
    count="$(jq '.mcpServers | length' "$SERVERS_JSON")"
    echo "    ($count servers: $(jq -r '.mcpServers | keys | join(", ")' "$SERVERS_JSON"))"
    echo "    review + keep in this machine (gitignored)"
}

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

case "${1:-}" in
    -h|--help) usage ;;
    seed)      seed ;;
    "")
        [ -f "$SERVERS_JSON" ] || die "$SERVERS_JSON missing — run '$0 seed' first"
        jq -e . "$SERVERS_JSON" > /dev/null 2>&1 || die "$SERVERS_JSON is not valid JSON"
        write_claude
        write_gemini
        write_opencode
        write_codex
        ;;
    *) die "unknown command: $1 (try --help)" ;;
esac
