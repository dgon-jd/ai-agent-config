#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract values from JSON
model_name=$(echo "$input" | jq -r '.model.display_name')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir')
project_name=$(basename "$project_dir")

# Get git branch if in a git repo (skip optional locks)
if git -C "$project_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$project_dir" -c core.fileMode=false -c core.fsmonitor=false branch --show-current 2>/dev/null || echo "detached")
else
    git_branch=""
fi

# Context window calculations
context_window=$(echo "$input" | jq '.context_window')
current_usage=$(echo "$context_window" | jq '.current_usage')

if [ "$current_usage" != "null" ]; then
    # Calculate current context tokens (input + cache creation + cache read)
    input_tokens=$(echo "$current_usage" | jq '.input_tokens // 0')
    cache_creation=$(echo "$current_usage" | jq '.cache_creation_input_tokens // 0')
    cache_read=$(echo "$current_usage" | jq '.cache_read_input_tokens // 0')
    output_tokens=$(echo "$current_usage" | jq '.output_tokens // 0')

    current_context=$((input_tokens + cache_creation + cache_read))
    context_window_size=$(echo "$context_window" | jq '.context_window_size')

    # Calculate percentage
    if [ "$context_window_size" -gt 0 ]; then
        pct=$((current_context * 100 / context_window_size))
    else
        pct=0
    fi

    # Choose color based on usage level
    if [ "$pct" -lt 50 ]; then
        bar_color="\033[32m"  # Green
    elif [ "$pct" -lt 75 ]; then
        bar_color="\033[33m"  # Yellow
    else
        bar_color="\033[31m"  # Red
    fi

    # Create progress bar (20 characters wide)
    bar_width=20
    filled=$((pct * bar_width / 100))
    empty=$((bar_width - filled))

    bar="["
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="]"

    # Format tokens with K suffix if > 1000
    if [ "$current_context" -ge 1000 ]; then
        tokens_in=$((current_context / 1000))
        tokens_in="${tokens_in}K"
    else
        tokens_in="${current_context}"
    fi

    if [ "$output_tokens" -ge 1000 ]; then
        tokens_out=$((output_tokens / 1000))
        tokens_out="${tokens_out}K"
    else
        tokens_out="${output_tokens}"
    fi

    # Apply colors to context info
    context_info="${bar_color}${bar}\033[0m \033[36m${pct}%\033[0m | \033[90m${tokens_in}↑ ${tokens_out}↓\033[0m"
else
    context_info="\033[32m[░░░░░░░░░░░░░░░░░░░░]\033[0m \033[36m0%\033[0m"
fi

# Build status line with colors
# Model name in blue
status="\033[34m$model_name\033[0m"

# Project and branch in magenta
if [ -n "$git_branch" ]; then
    status="$status | \033[35m$project_name@$git_branch\033[0m"
else
    status="$status | \033[35m$project_name\033[0m"
fi

status="$status | $context_info"

# Output the status line
printf "%b" "$status"
