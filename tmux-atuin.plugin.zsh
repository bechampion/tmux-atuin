# tmux-atuin.plugin.zsh
# Open atuin history search via fzf in a styled tmux popup
# Triggered with Ctrl+r
# Uses same Catppuccin Mocha color scheme as tmux-ghostcomplete
# Only shows commands with exit code 0 (successful commands)
# Queries sqlite directly for speed

_atuin_tmux_popup() {
    emulate -L zsh
    zle -I
    
    local tmpfile=$(mktemp)
    local editfile=$(mktemp)
    local query="$BUFFER"
    local db="$HOME/.local/share/atuin/history.db"
    
    # SQL query: successful commands, newest first, deduplicated by command
    # Optimized by limiting to recent rows before deduplication
    local sql="
        WITH recent AS (
            SELECT timestamp, duration, command
            FROM history
            WHERE exit = 0 AND deleted_at IS NULL
            ORDER BY timestamp DESC
            LIMIT 20000
        ),
        latest_per_cmd AS (
            SELECT
                timestamp,
                duration,
                command,
                ROW_NUMBER() OVER (
                    PARTITION BY command
                    ORDER BY timestamp DESC
                ) AS rn
            FROM recent
        )
        SELECT
            CASE
                WHEN (strftime('%s','now') - timestamp/1000000000) < 60 THEN printf('%3ds', strftime('%s','now') - timestamp/1000000000)
                WHEN (strftime('%s','now') - timestamp/1000000000) < 3600 THEN printf('%3dm', (strftime('%s','now') - timestamp/1000000000) / 60)
                WHEN (strftime('%s','now') - timestamp/1000000000) < 86400 THEN printf('%3dh', (strftime('%s','now') - timestamp/1000000000) / 3600)
                ELSE printf('%3dd', (strftime('%s','now') - timestamp/1000000000) / 86400)
            END,
            CASE
                WHEN duration < 1000000000 THEN printf('%6dms', duration/1000000)
                ELSE printf('%7ds', duration/1000000000)
            END,
            replace(replace(command, char(10), ' '), char(13), ' ')
        FROM latest_per_cmd
        WHERE rn = 1
        ORDER BY timestamp DESC
        LIMIT 3000
    "
    
# Catppuccin Mocha colors - full palette
    local c_time=$'\033[38;2;148;226;213m'     # teal (94e2d5)
    local c_dur=$'\033[38;2;166;227;161m'      # green (a6e3a1)
    local c_cmd=$'\033[38;2;205;214;244m'      # fg (cdd6f4)
    local c_sep=$'\033[38;2;108;112;134m'      # overlay0 (6c7086)
    local c_reset=$'\033[0m'
    
    if [[ -z "$TMUX" ]]; then
        # Not in tmux - run fzf directly
        local selection
        selection=$(sqlite3 -separator $'\t' "$db" "$sql" 2>/dev/null | while IFS=$'\t' read -r time dur cmd; do
            printf '%s%s %s│%s %s%s %s│%s %s%s%s\n' \
                "$c_time" "$time" "$c_sep" "$c_reset" \
                "$c_dur" "$dur" "$c_sep" "$c_reset" \
                "$c_cmd" "$cmd" "$c_reset"
        done | fzf \
            --ansi \
            --algo=v2 --tiebreak=begin,length,index \
            --no-sort \
            --layout=reverse \
            --query="$query" \
            --bind 'esc:abort' \
            --bind 'ctrl-d:half-page-down' \
            --bind 'ctrl-u:half-page-up' \
            --bind 'ctrl-x:become(echo EDIT:{})' \
            --no-info \
            --no-separator \
            --pointer='▸' \
            --prompt='❯ ' \
            --nth=3.. \
            --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7')
        
        # Check if edit mode
        if [[ "$selection" == EDIT:* ]]; then
            selection="${selection#EDIT:}"
            selection=$(echo "$selection" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│[^│]*│ //')
            echo "$selection" > "$editfile"
            nvim -u NONE \
                -c "set noswapfile" \
                -c "set nobackup" \
                -c "set noundofile" \
                -c "set laststatus=0" \
                -c "set noruler" \
                -c "set noshowcmd" \
                -c "set shortmess+=F" \
                -c "set filetype=sh" \
                -c "syntax on" \
                "$editfile"
            selection=$(cat "$editfile")
        else
            # Strip ANSI codes, then extract command (after second │)
            selection=$(echo "$selection" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│[^│]*│ //')
        fi
        
        rm -f "$editfile"
        
        if [[ -n "$selection" ]]; then
            LBUFFER="$selection"
            RBUFFER=""
        fi
        zle reset-prompt
        return
    fi
    
    # Create wrapper for tmux popup - write to tmpfile inside the script
    local wrapper=$(mktemp)
    cat > "$wrapper" << INNERSCRIPT
#!/bin/bash
db="\$HOME/.local/share/atuin/history.db"
tmpfile="$tmpfile"
editfile="$editfile"

sql="
    WITH recent AS (
        SELECT timestamp, duration, command
        FROM history
        WHERE exit = 0 AND deleted_at IS NULL
        ORDER BY timestamp DESC
        LIMIT 20000
    ),
    latest_per_cmd AS (
        SELECT
            timestamp,
            duration,
            command,
            ROW_NUMBER() OVER (
                PARTITION BY command
                ORDER BY timestamp DESC
            ) AS rn
        FROM recent
    )
    SELECT
        CASE
            WHEN (strftime('%s','now') - timestamp/1000000000) < 60 THEN printf('%3ds', strftime('%s','now') - timestamp/1000000000)
            WHEN (strftime('%s','now') - timestamp/1000000000) < 3600 THEN printf('%3dm', (strftime('%s','now') - timestamp/1000000000) / 60)
            WHEN (strftime('%s','now') - timestamp/1000000000) < 86400 THEN printf('%3dh', (strftime('%s','now') - timestamp/1000000000) / 3600)
            ELSE printf('%3dd', (strftime('%s','now') - timestamp/1000000000) / 86400)
        END,
        CASE
            WHEN duration < 1000000000 THEN printf('%6dms', duration/1000000)
            ELSE printf('%7ds', duration/1000000000)
        END,
        replace(replace(command, char(10), ' '), char(13), ' ')
    FROM latest_per_cmd
    WHERE rn = 1
    ORDER BY timestamp DESC
    LIMIT 3000
"

# Catppuccin Mocha colors - full palette
c_time=\$'\033[38;2;148;226;213m'     # teal (94e2d5)
c_dur=\$'\033[38;2;166;227;161m'      # green (a6e3a1)
c_cmd=\$'\033[38;2;205;214;244m'      # fg (cdd6f4)
c_sep=\$'\033[38;2;108;112;134m'      # overlay0 (6c7086)
c_reset=\$'\033[0m'

selection=\$(sqlite3 -separator \$'\t' "\$db" "\$sql" 2>/dev/null | while IFS=\$'\t' read -r time dur cmd; do
    printf '%s%s %s│%s %s%s %s│%s %s%s%s\n' \\
        "\$c_time" "\$time" "\$c_sep" "\$c_reset" \\
        "\$c_dur" "\$dur" "\$c_sep" "\$c_reset" \\
        "\$c_cmd" "\$cmd" "\$c_reset"
done | fzf \\
    --ansi \\
    --algo=v2 --tiebreak=begin,length,index \\
    \\
    --layout=reverse \\
    --query="$query" \\
    --bind 'esc:abort' \\
    --bind 'ctrl-d:half-page-down' \\
    --bind 'ctrl-u:half-page-up' \\
    --bind 'ctrl-x:become(echo EDIT:{})' \\
    --no-info \\
    --no-separator \\
    --pointer='▸' \\
    --prompt='❯ ' \\
    --nth=3.. \\
    --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7')

# Check if edit mode
if [[ "\$selection" == EDIT:* ]]; then
    selection="\${selection#EDIT:}"
    selection=\$(echo "\$selection" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│[^│]*│ //')
    echo "\$selection" > "\$editfile"
    nvim -u NONE \\
        -c "set noswapfile" \\
        -c "set nobackup" \\
        -c "set noundofile" \\
        -c "set laststatus=0" \\
        -c "set noruler" \\
        -c "set noshowcmd" \\
        -c "set shortmess+=F" \\
        -c "set filetype=sh" \\
        -c "syntax on" \\
        "\$editfile"
    cat "\$editfile" > "\$tmpfile"
else
    # Strip ANSI codes, then extract command (after second │)
    echo "\$selection" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│[^│]*│ //' > "\$tmpfile"
fi
INNERSCRIPT
    
    chmod +x "$wrapper"
    
    # Run in tmux popup
    tmux display-popup -E -w 80% -h 60% \
        -b rounded \
        -S 'fg=#6c7086' \
        -s 'bg=#1e1e2e' \
        -T ' 🐙 Atuin History ' \
        "$wrapper"
    
    local selection=$(cat "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile" "$wrapper" "$editfile"
    
    # Trim trailing whitespace/newlines
    selection="${selection%%$'\n'}"
    selection="${selection%"${selection##*[![:space:]]}"}"
    
    if [[ -n "$selection" ]]; then
        LBUFFER="$selection"
        RBUFFER=""
    fi
    
    zle reset-prompt
}

# Local zsh history search via fzf in a tmux popup (Ctrl-r)
_zsh_history_tmux_popup() {
    emulate -L zsh
    zle -I

    local tmpfile=$(mktemp)
    local listfile=$(mktemp)
    local editfile=$(mktemp)
    local query="$BUFFER"

    local c_time=$'\033[38;2;148;226;213m'   # teal
    local c_reset=$'\033[0m'

    # Newest first, deduplicated by exact command text, with colored relative last-run timestamp
    if [[ -n "$HISTFILE" && -r "$HISTFILE" ]]; then
        tac "$HISTFILE" | awk -v c_time="$c_time" -v c_reset="$c_reset" '
            function rel(ts, now, age) {
                now = systime()
                age = now - ts
                if (age < 60) return age "s ago"
                if (age < 3600) return int(age/60) "m ago"
                if (age < 86400) return int(age/3600) "h ago"
                if (age < 604800) return int(age/86400) "d ago"
                return int(age/604800) "w ago"
            }
            match($0, /^: ([0-9]+):[0-9]+;(.*)$/, m) {
                cmd = m[2]
                if (!(cmd in seen)) {
                    seen[cmd] = m[1]
                    order[++n] = cmd
                }
            }
            END {
                for (i = 1; i <= n && i <= 3000; i++) {
                    cmd = order[i]
                    printf "%s%7s%s\t│ %s\n", c_time, rel(seen[cmd]), c_reset, cmd
                }
            }
        ' > "$listfile"
    fi

    if [[ ! -s "$listfile" ]]; then
        # Fallback when history file doesn't contain extended timestamps
        fc -rl 1 | sed -E 's/^[[:space:]]*[0-9]+\*?[[:space:]]+//' | awk '!seen[$0]++' | head -n 3000 | awk -v c_time="$c_time" -v c_reset="$c_reset" '{ printf "%s%7s%s\t│ %s\n", c_time, "-", c_reset, $0 }' > "$listfile"
    fi

    if [[ -z "$TMUX" ]]; then
        local selection
        selection=$(cat "$listfile" | fzf \
            --ansi \
            --exact \
            --delimiter=$'\t' --nth=2.. \
            --algo=v2 --tiebreak=begin,length,index \
            --no-sort \
            --layout=reverse \
            --query="$query" \
            --bind 'esc:abort' \
            --bind 'ctrl-d:half-page-down' \
            --bind 'ctrl-u:half-page-up' \
            --bind 'ctrl-x:become(echo EDIT:{})' \
            --no-info \
            --no-separator \
            --pointer='▸' \
            --prompt='❯ ' \
            --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7')

        if [[ "$selection" == EDIT:* ]]; then
            selection="${selection#EDIT:}"
            selection="${selection#*$'\t'}"
            selection="${selection#│ }"
            printf '%s' "$selection" > "$editfile"
            nvim -u NONE \
                -c "set noswapfile" \
                -c "set nobackup" \
                -c "set noundofile" \
                -c "set laststatus=0" \
                -c "set noruler" \
                -c "set noshowcmd" \
                -c "set shortmess+=F" \
                -c "set filetype=sh" \
                -c "syntax on" \
                "$editfile"
            selection=$(cat "$editfile")
        else
            selection="${selection#*$'\t'}"
            selection="${selection#│ }"
        fi

        rm -f "$editfile" "$listfile"

        if [[ -n "$selection" ]]; then
            LBUFFER="$selection"
            RBUFFER=""
        fi
        zle reset-prompt
        rm -f "$tmpfile"
        return
    fi

    local wrapper=$(mktemp)
    cat > "$wrapper" << INNERSCRIPT
#!/bin/bash
tmpfile="$tmpfile"
listfile="$listfile"
editfile="$editfile"

selection=\$(cat "\$listfile" | fzf \\
    --ansi \\
    --exact \\
    --delimiter=$'\t' --nth=2.. \\
    --algo=v2 --tiebreak=begin,length,index \\
    --no-sort \\
    --layout=reverse \\
    --query="$query" \\
    --bind 'esc:abort' \\
    --bind 'ctrl-d:half-page-down' \\
    --bind 'ctrl-u:half-page-up' \\
    --bind 'ctrl-x:become(echo EDIT:{})' \\
    --no-info \\
    --no-separator \\
    --pointer='▸' \\
    --prompt='❯ ' \\
    --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7')

if [[ "\$selection" == EDIT:* ]]; then
    selection="\${selection#EDIT:}"
    selection="\${selection#*$'\t'}"
    selection="\${selection#│ }"
    printf '%s' "\$selection" > "\$editfile"
    nvim -u NONE \\
        -c "set noswapfile" \\
        -c "set nobackup" \\
        -c "set noundofile" \\
        -c "set laststatus=0" \\
        -c "set noruler" \\
        -c "set noshowcmd" \\
        -c "set shortmess+=F" \\
        -c "set filetype=sh" \\
        -c "syntax on" \\
        "\$editfile"
    cat "\$editfile" > "\$tmpfile"
else
    selection="\${selection#*$'\t'}"
    selection="\${selection#│ }"
    printf '%s' "\$selection" > "\$tmpfile"
fi
INNERSCRIPT

    chmod +x "$wrapper"

    tmux display-popup -E -w 72% -h 50% \
        -b rounded \
        -S 'fg=#6c7086' \
        -s 'bg=#1e1e2e' \
        -T '  Zsh History ' \
        "$wrapper"

    local selection=$(cat "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile" "$wrapper" "$editfile" "$listfile"

    selection="${selection%%$'\n'}"
    selection="${selection%"${selection##*[![:space:]]}"}"

    if [[ -n "$selection" ]]; then
        LBUFFER="$selection"
        RBUFFER=""
    fi

    zle reset-prompt
}

# Edit current command line in nvim popup (C-x C-e)
_edit_command_line_popup() {
    emulate -L zsh
    zle -I
    
    local tmpfile=$(mktemp)
    local current_cmd="${LBUFFER}${RBUFFER}"
    
    # Write current command to temp file
    printf '%s' "$current_cmd" > "$tmpfile"
    
    if [[ -z "$TMUX" ]]; then
        # Not in tmux - run nvim directly
        nvim -u NONE \
            -c "set noswapfile" \
            -c "set nobackup" \
            -c "set noundofile" \
            -c "set laststatus=0" \
            -c "set noruler" \
            -c "set noshowcmd" \
            -c "set shortmess+=F" \
            -c "set filetype=sh" \
            -c "syntax on" \
            "$tmpfile"
        
        local edited=$(cat "$tmpfile")
        rm -f "$tmpfile"
        
        if [[ -n "$edited" ]]; then
            LBUFFER="$edited"
            RBUFFER=""
        fi
        zle reset-prompt
        return
    fi
    
    # Run nvim in tmux popup
    tmux display-popup -E -w 50% -h 40% \
        -b rounded \
        -S 'fg=#6c7086' \
        -s 'bg=#1e1e2e' \
        -T '  Edit Command ' \
        "nvim -u NONE \
            -c 'set noswapfile' \
            -c 'set nobackup' \
            -c 'set noundofile' \
            -c 'set laststatus=0' \
            -c 'set noruler' \
            -c 'set noshowcmd' \
            -c 'set shortmess+=F' \
            -c 'set filetype=sh' \
            -c 'syntax on' \
            '$tmpfile'"
    
    local edited=$(cat "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    
    # Trim trailing newlines
    edited="${edited%%$'\n'}"
    
    if [[ -n "$edited" ]]; then
        LBUFFER="$edited"
        RBUFFER=""
    fi
    
    zle reset-prompt
}

# Zoxide directory jump in tmux popup (C-g)
_zoxide_tmux_popup() {
    emulate -L zsh
    zle -I
    
    local tmpfile=$(mktemp)
    
    # Catppuccin Mocha colors
    local c_score=$'\033[38;2;249;226;175m'    # yellow (f9e2af) - for score
    local c_sep=$'\033[38;2;108;112;134m'      # overlay0 (6c7086) - dim separator
    local c_path=$'\033[38;2;205;214;244m'     # fg (cdd6f4) - for path
    local c_reset=$'\033[0m'
    
    # Preview command for bat
    
    if [[ -z "$TMUX" ]]; then
        # Not in tmux - run fzf directly
        local selection
        selection=$(zoxide query -ls 2>/dev/null | while read -r score path; do
            printf '%s%7.1f %s│%s %s%s%s\n' "$c_score" "$score" "$c_sep" "$c_reset" "$c_path" "$path" "$c_reset"
        done | fzf \
            --ansi \
            --algo=v2 --tiebreak=begin,length,index \
            --no-sort \
            --layout=reverse \
            --bind 'esc:abort' \
            --bind 'ctrl-d:half-page-down' \
            --bind 'ctrl-u:half-page-up' \
            --no-info \
            --no-separator \
            --pointer='▸' \
            --prompt='❯ ' \
            --nth=2.. \
            --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7,preview-bg:#1e1e2e,preview-border:#6c7086')
        
        # Extract path (strip ANSI and get text after │)
        selection=$(echo "$selection" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│ //')
        
        if [[ -n "$selection" ]]; then
            zoxide add "$selection" 2>/dev/null
            cd "$selection"
        fi
        zle reset-prompt
        return
    fi
    
    # Create wrapper for tmux popup
    local wrapper=$(mktemp)
    cat > "$wrapper" << 'INNERSCRIPT'
#!/bin/bash
tmpfile="TMPFILE_PLACEHOLDER"

c_score=$'\033[38;2;249;226;175m'
c_sep=$'\033[38;2;108;112;134m'
c_path=$'\033[38;2;205;214;244m'
c_reset=$'\033[0m'

zoxide query -ls 2>/dev/null | while read -r score path; do
    printf '%s%7.1f %s│%s %s%s%s\n' "$c_score" "$score" "$c_sep" "$c_reset" "$c_path" "$path" "$c_reset"
done | fzf \
    --ansi \
    --algo=v2 --tiebreak=begin,length,index \
    --no-sort \
    --layout=reverse \
    --bind 'esc:abort' \
    --bind 'ctrl-d:half-page-down' \
    --bind 'ctrl-u:half-page-up' \
    --no-info \
    --no-separator \
    --pointer='▸' \
    --prompt='❯ ' \
    --nth=2.. \
    --color='bg:#1e1e2e,fg:#cdd6f4,bg+:#313244,fg+:#cdd6f4,hl:#f9e2af,hl+:#fab387,pointer:#f9e2af,prompt:#cba6f7,gutter:#1e1e2e,border:#6c7086,label:#89b4fa,header:#cba6f7,preview-bg:#1e1e2e,preview-border:#6c7086' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│ //' > "$tmpfile"
INNERSCRIPT
    # Replace placeholder with actual tmpfile path
    sed -i "s|TMPFILE_PLACEHOLDER|$tmpfile|g" "$wrapper"
    chmod +x "$wrapper"
    
    # Run in tmux popup
    tmux display-popup -E -w 80% -h 60% \
        -b rounded \
        -S 'fg=#6c7086' \
        -s 'bg=#1e1e2e' \
        -T '  Zoxide Jump ' \
        "$wrapper"
    
    local selection=$(cat "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile" "$wrapper"
    
    # Trim whitespace
    selection="${selection%%$'\n'}"
    selection="${selection%"${selection##*[![:space:]]}"}"
    
    if [[ -n "$selection" ]]; then
        zoxide add "$selection" 2>/dev/null
        cd "$selection"
    fi
    
    zle reset-prompt
}

zle -N _atuin_tmux_popup
zle -N _zsh_history_tmux_popup
zle -N _edit_command_line_popup
zle -N _zoxide_tmux_popup

# Fast local history on Ctrl+r, keep Atuin popup on Ctrl+x Ctrl+r
bindkey '^r' _zsh_history_tmux_popup
bindkey '^x^r' _atuin_tmux_popup
bindkey '^x^e' _edit_command_line_popup
bindkey '^g' _zoxide_tmux_popup
