#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# ── 1. Current directory basename ────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
dir_name=$(basename "${cwd:-$(pwd)}")

# ── 2. Git branch + status summary ───────────────────────────────────────────
git_info=""
git_dir="${cwd:-$(pwd)}"
if git -C "$git_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$git_dir" \
        -c core.fileMode=false \
        -c core.fsmonitor=false \
        branch --show-current 2>/dev/null || echo "detached")

    git_stat=$(git -C "$git_dir" \
        -c core.fileMode=false \
        -c core.fsmonitor=false \
        status --porcelain 2>/dev/null)

    staged=$(echo "$git_stat"    | grep -c '^[MADRC]' 2>/dev/null || echo 0)
    modified=$(echo "$git_stat"  | grep -c '^ [MD]'   2>/dev/null || echo 0)
    untracked=$(echo "$git_stat" | grep -c '^??'      2>/dev/null || echo 0)

    stat_parts=""
    [ "$staged"    -gt 0 ] && stat_parts="${stat_parts}+${staged} "
    [ "$modified"  -gt 0 ] && stat_parts="${stat_parts}~${modified} "
    [ "$untracked" -gt 0 ] && stat_parts="${stat_parts}?${untracked} "
    stat_parts="${stat_parts% }"  # trim trailing space

    if [ -n "$stat_parts" ]; then
        git_info="${git_branch} [${stat_parts}]"
    else
        git_info="${git_branch}"
    fi
fi

# ── 3. Model name ─────────────────────────────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // empty')

# ── 4. Cost / token counts + context percentage ───────────────────────────────
# Pricing (per 1M tokens): input $3, output $15 — approximate for Claude Sonnet
tok_info=""
current_usage=$(echo "$input" | jq -r '.context_window.current_usage // empty')
if [ -n "$current_usage" ] && [ "$current_usage" != "null" ]; then
    total_in=$(echo "$input"  | jq '.context_window.total_input_tokens  // 0')
    total_out=$(echo "$input" | jq '.context_window.total_output_tokens // 0')

    # Estimated cost in dollars
    cost=$(echo "$total_in $total_out" | awk '{printf "%.2f", ($1 * 3 + $2 * 15) / 1000000}')

    # Total tokens formatted: use M suffix for >= 1M, K for >= 1K
    total_tok=$(( total_in + total_out ))
    if [ "$total_tok" -ge 1000000 ]; then
        total_fmt=$(echo "$total_tok" | awk '{printf "%.1fm", $1/1000000}')
    elif [ "$total_tok" -ge 1000 ]; then
        total_fmt="$((total_tok / 1000))k"
    else
        total_fmt="${total_tok}"
    fi

    used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
    if [ -n "$used_pct" ]; then
        pct=$(printf "%.0f" "$used_pct")
        tok_info="\$${cost}/${total_fmt} ctx:${pct}%"
    else
        tok_info="\$${cost}/${total_fmt}"
    fi
fi

# ── 5. Session uptime + message count ────────────────────────────────────────
msg_info=""
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    msg_count=$(jq '[.[] | select(.role == "user")] | length' "$transcript_path" 2>/dev/null || echo "0")

    file_mtime=$(stat -c %Y "$transcript_path" 2>/dev/null || echo "0")
    now=$(date +%s)
    first_ts=$(jq -r 'first(.[] | .timestamp? // empty)' "$transcript_path" 2>/dev/null || echo "")
    if [ -n "$first_ts" ] && [ "$first_ts" != "null" ]; then
        start_ts=$(date -d "$first_ts" +%s 2>/dev/null || echo "$file_mtime")
    else
        start_ts=$file_mtime
    fi

    elapsed=$(( now - start_ts ))
    if [ "$elapsed" -ge 3600 ]; then
        uptime_str="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
    elif [ "$elapsed" -ge 60 ]; then
        uptime_str="$(( elapsed / 60 ))m"
    else
        uptime_str="${elapsed}s"
    fi

    msg_info="${uptime_str} msgs:${msg_count}"
fi

# ── 6. Rate limit info ────────────────────────────────────────────────────────
rate_info=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
    five_str=""
    week_str=""
    [ -n "$five_pct" ] && five_str=$(printf "%.0f" "$five_pct")
    [ -n "$week_pct" ] && week_str=$(printf "%.0f" "$week_pct")
    if [ -n "$five_str" ] && [ -n "$week_str" ]; then
        rate_info="rate:${five_str}/${week_str}%"
    elif [ -n "$five_str" ]; then
        rate_info="rate:${five_str}%"
    else
        rate_info="rate:${week_str}%"
    fi
fi

# ── Assemble in specified order ───────────────────────────────────────────────
# Colors (dim palette — status line renders dimmed)
C_BLUE="\033[34m"
C_MAG="\033[35m"
C_CYAN="\033[36m"
C_YEL="\033[33m"
C_GRY="\033[90m"
C_RST="\033[0m"

parts=()
parts+=("${C_BLUE}${dir_name}${C_RST}")
[ -n "$git_info"  ] && parts+=("${C_MAG}${git_info}${C_RST}")
[ -n "$model_name" ] && parts+=("${C_CYAN}${model_name}${C_RST}")
[ -n "$tok_info"  ] && parts+=("${C_YEL}${tok_info}${C_RST}")
[ -n "$msg_info"  ] && parts+=("${C_GRY}${msg_info}${C_RST}")
[ -n "$rate_info" ] && parts+=("${C_GRY}${rate_info}${C_RST}")

# Join with " | "
result=""
for part in "${parts[@]}"; do
    if [ -z "$result" ]; then
        result="$part"
    else
        result="${result} | ${part}"
    fi
done

printf "%b" "$result"
