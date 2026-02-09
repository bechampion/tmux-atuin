# tmux-atuin.plugin.zsh
# Open atuin history search via fzf in a styled tmux popup
# Triggered with Ctrl+r
# Uses same Kanagawa color scheme as tmux-ghostcomplete
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
    
    # Kanagawa colors - full palette
    local c_time=$'\033[38;2;127;180;202m'     # springBlue - soft blue for time
    local c_dur=$'\033[38;2;152;187;108m'      # springGreen - green for duration
    local c_cmd=$'\033[38;2;220;215;186m'      # fujiWhite - white for command
    local c_sep=$'\033[38;2;84;84;109m'        # sumiInk4 - dim separator
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
            --exact \
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
            --color='bg:#1F1F28,fg:#DCD7BA,bg+:#2A2A37,fg+:#DCD7BA,hl:#E6C384,hl+:#FFA066,pointer:#E6C384,prompt:#957FB8,gutter:#1F1F28,border:#54546D,label:#7E9CD8,header:#957FB8')
        
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

# Kanagawa colors - full palette
c_time=\$'\033[38;2;127;180;202m'     # springBlue
c_dur=\$'\033[38;2;152;187;108m'      # springGreen
c_cmd=\$'\033[38;2;220;215;186m'      # fujiWhite
c_sep=\$'\033[38;2;84;84;109m'        # sumiInk4
c_reset=\$'\033[0m'

selection=\$(sqlite3 -separator \$'\t' "\$db" "\$sql" 2>/dev/null | while IFS=\$'\t' read -r time dur cmd; do
    printf '%s%s %s│%s %s%s %s│%s %s%s%s\n' \\
        "\$c_time" "\$time" "\$c_sep" "\$c_reset" \\
        "\$c_dur" "\$dur" "\$c_sep" "\$c_reset" \\
        "\$c_cmd" "\$cmd" "\$c_reset"
done | fzf \\
    --ansi \\
    --exact \\
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
    --nth=3.. \\
    --color='bg:#1F1F28,fg:#DCD7BA,bg+:#2A2A37,fg+:#DCD7BA,hl:#E6C384,hl+:#FFA066,pointer:#E6C384,prompt:#957FB8,gutter:#1F1F28,border:#54546D,label:#7E9CD8,header:#957FB8')

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
    
    # Run in tmux popup with Kanagawa colors
    tmux display-popup -E -w 80% -h 60% \
        -b rounded \
        -S 'fg=#54546D' \
        -s 'bg=#1F1F28' \
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

zle -N _atuin_tmux_popup
bindkey '^r' _atuin_tmux_popup
