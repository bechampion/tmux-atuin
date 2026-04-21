# tmux-atuin.plugin.zsh
# Baseline Atuin integration with tmux popup support

# Load Atuin's official zsh integration (widgets, keybinds, popup handling).
eval "$(atuin init zsh)"

# atuin init sets ATUIN_TMUX_POPUP=false by default; force-enable popup mode.
export ATUIN_TMUX_POPUP=true
