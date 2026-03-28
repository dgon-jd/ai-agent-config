#!/usr/bin/env bash
set -euo pipefail

# Claude Code Config - Sync Helper
# Usage: sync.sh [push|pull|status]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "Usage: $0 [push|pull|status]"
    echo ""
    echo "  push    Stage tracked config files, commit, and push to remote"
    echo "  pull    Pull latest config from remote and update submodules"
    echo "  status  Show what's changed since last sync"
    exit 1
}

sync_push() {
    # Update skill-lock.json from live location
    if [ -f "$HOME/.agents/.skill-lock.json" ]; then
        cp "$HOME/.agents/.skill-lock.json" "$SCRIPT_DIR/.agents/.skill-lock.json"
    fi

    git add -A
    if git diff --cached --quiet; then
        echo "Nothing to sync - config is up to date."
        return
    fi

    echo "Changes to sync:"
    git diff --cached --stat
    echo ""

    TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
    git commit -m "sync: update config ($TIMESTAMP)"
    git push
    echo ""
    echo "Config pushed to remote."
}

sync_pull() {
    git pull --rebase
    git submodule update --init --recursive

    # Restore skill-lock.json to live location
    if [ -f "$SCRIPT_DIR/.agents/.skill-lock.json" ]; then
        mkdir -p "$HOME/.agents"
        cp "$SCRIPT_DIR/.agents/.skill-lock.json" "$HOME/.agents/.skill-lock.json"
    fi

    echo ""
    echo "Config pulled. Run ./setup.sh if plugins need reinstalling."
}

sync_status() {
    echo "=== Config Sync Status ==="
    echo ""

    # Check remote
    if git remote get-url origin &>/dev/null; then
        LOCAL=$(git rev-parse HEAD 2>/dev/null)
        git fetch origin --quiet 2>/dev/null || true
        REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
        if [ "$LOCAL" = "$REMOTE" ]; then
            echo "Remote: in sync"
        elif [ "$REMOTE" = "unknown" ]; then
            echo "Remote: could not fetch"
        else
            echo "Remote: out of sync (local: ${LOCAL:0:7}, remote: ${REMOTE:0:7})"
        fi
    else
        echo "Remote: not configured"
    fi
    echo ""

    # Check local changes
    # Update skill-lock.json for accurate diff
    if [ -f "$HOME/.agents/.skill-lock.json" ]; then
        cp "$HOME/.agents/.skill-lock.json" "$SCRIPT_DIR/.agents/.skill-lock.json" 2>/dev/null || true
    fi

    git status --short
}

case "${1:-}" in
    push)   sync_push ;;
    pull)   sync_pull ;;
    status) sync_status ;;
    *)      usage ;;
esac
