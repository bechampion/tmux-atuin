# tmux-atuin.plugin.zsh
# Open atuin history search via fzf in a styled tmux popup
# Triggered with Ctrl+r
# Uses same Tokyo Night color scheme as tmux-ghostcomplete
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
    local sql="
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
        FROM history 
        WHERE exit = 0 AND deleted_at IS NULL 
        GROUP BY command
        ORDER BY MAX(timestamp) DESC 
        LIMIT 3000
    "
    
    # Tokyo Night colors - full palette
    local c_time=$'\033[38;2;125;207;255m'     # blue (7dcfff) - soft blue for time
    local c_dur=$'\033[38;2;158;206;106m'      # green (9ece6a) - green for duration
    local c_cmd=$'\033[38;2;192;202;245m'      # fg (c0caf5) - white for command
    local c_sep=$'\033[38;2;86;95;137m'        # comment (565f89) - dim separator
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
            --color='bg:#1a1b26,fg:#c0caf5,bg+:#24283b,fg+:#c0caf5,hl:#e0af68,hl+:#ff9e64,pointer:#e0af68,prompt:#bb9af7,gutter:#1a1b26,border:#565f89,label:#7aa2f7,header:#bb9af7')
        
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
    FROM history 
    WHERE exit = 0 AND deleted_at IS NULL 
    GROUP BY command
    ORDER BY MAX(timestamp) DESC 
    LIMIT 3000
"

# Tokyo Night colors - full palette
c_time=\$'\033[38;2;125;207;255m'     # blue (7dcfff)
c_dur=\$'\033[38;2;158;206;106m'      # green (9ece6a)
c_cmd=\$'\033[38;2;192;202;245m'      # fg (c0caf5)
c_sep=\$'\033[38;2;86;95;137m'        # comment (565f89)
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
    --color='bg:#1a1b26,fg:#c0caf5,bg+:#24283b,fg+:#c0caf5,hl:#e0af68,hl+:#ff9e64,pointer:#e0af68,prompt:#bb9af7,gutter:#1a1b26,border:#565f89,label:#7aa2f7,header:#bb9af7')

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
        -S 'fg=#565f89' \
        -s 'bg=#1a1b26' \
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
        -S 'fg=#565f89' \
        -s 'bg=#1a1b26' \
        -T ' ✏️ Edit Command ' \
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
    
    # Tokyo Night colors
    local c_score=$'\033[38;2;224;175;104m'    # yellow (e0af68) - for score
    local c_sep=$'\033[38;2;86;95;137m'        # comment (565f89) - dim separator
    local c_path=$'\033[38;2;192;202;245m'     # fg (c0caf5) - for path
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
            --color='bg:#1a1b26,fg:#c0caf5,bg+:#24283b,fg+:#c0caf5,hl:#e0af68,hl+:#ff9e64,pointer:#e0af68,prompt:#bb9af7,gutter:#1a1b26,border:#565f89,label:#7aa2f7,header:#bb9af7,preview-bg:#1a1b26,preview-border:#565f89')
        
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

c_score=$'\033[38;2;224;175;104m'
c_sep=$'\033[38;2;86;95;137m'
c_path=$'\033[38;2;192;202;245m'
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
    --color='bg:#1a1b26,fg:#c0caf5,bg+:#24283b,fg+:#c0caf5,hl:#e0af68,hl+:#ff9e64,pointer:#e0af68,prompt:#bb9af7,gutter:#1a1b26,border:#565f89,label:#7aa2f7,header:#bb9af7,preview-bg:#1a1b26,preview-border:#565f89' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[^│]*│ //' > "$tmpfile"
INNERSCRIPT
    # Replace placeholder with actual tmpfile path
    sed -i "s|TMPFILE_PLACEHOLDER|$tmpfile|g" "$wrapper"
    chmod +x "$wrapper"
    
    # Run in tmux popup
    tmux display-popup -E -w 80% -h 60% \
        -b rounded \
        -S 'fg=#565f89' \
        -s 'bg=#1a1b26' \
        -T ' 📁 Zoxide Jump ' \
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
zle -N _edit_command_line_popup
zle -N _zoxide_tmux_popup

# Removed: ghostcomplete now owns Ctrl+r
# bindkey '^r' _atuin_tmux_popup
bindkey '^x^e' _edit_command_line_popup
bindkey '^g' _zoxide_tmux_popup
