# tmux-atuin.plugin.zsh
# Baseline Atuin integration with tmux popup support

# Load Atuin's official zsh integration (widgets, keybinds, popup handling).
eval "$(atuin init zsh)"

# atuin init sets ATUIN_TMUX_POPUP=false by default; force-enable popup mode.
export ATUIN_TMUX_POPUP=true

# Keep normal shell history navigation on arrow keys (disable Atuin on Up/Down).
bindkey '^[[A' up-line-or-history
bindkey '^[OA' up-line-or-history
bindkey '^[[B' down-line-or-history
bindkey '^[OB' down-line-or-history
