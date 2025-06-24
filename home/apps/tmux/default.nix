{
  programs.tmux = {
    enable = true;

    sensibleOnTop = true;

    aggressiveResize = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    historyLimit = 102400;
    keyMode = "vi";
    mouse = true;
    prefix = "C-s";
    terminal = "tmux-256color";

    extraConfig = ''
      set -g bell-action any
      set -g repeat-time 325
      set -g set-clipboard on
      set -g visual-bell off

      setw -g alternate-screen on
      setw -g automatic-rename off
      setw -g monitor-activity on
      setw -g xterm-keys on

      set -g set-titles on
      set -g set-titles-string '#T - #S:#I:#W #{session_alerts}'

      unbind C-z

      unbind o
      bind C-s select-pane -t :.+

      unbind Up
      unbind Down
      unbind Left
      unbind Right
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind h select-pane -L

      unbind C-Up
      unbind C-Down
      unbind C-Left
      unbind C-Right
      bind -r C-k resize-pane -U
      bind -r C-j resize-pane -D
      bind -r C-h resize-pane -L
      bind -r C-l resize-pane -R

      unbind M-Up
      unbind M-Down
      unbind M-Left
      unbind M-Right
      bind -r C-M-k resize-pane -U 5
      bind -r C-M-j resize-pane -D 5
      bind -r C-M-h resize-pane -L 5
      bind -r C-M-l resize-pane -R 5

      unbind '"'
      unbind %
      bind | split-window -h -c '#{pane_current_path}'
      bind _ split-window -v -c '#{pane_current_path}'

      bind -T copy-mode-vi v   send -X begin-selection
      bind -T copy-mode-vi C-v send -X rectangle-toggle
      bind -T copy-mode-vi y   send -X copy-pipe 'wl-copy'

      set -g mode-style                     bg=colour220,fg=colour16
      set -g status-style                   fg=colour247

      set -g pane-border-style              fg=colour238
      set -g pane-active-border-style       fg=colour248
      set -g message-style                  bg=colour232,fg=colour220,bold

      setw -g window-status-activity-style  fg=colour251,bold
      setw -g window-status-bell-style      fg=colour251,bold

      setw -g status-left                   '#[fg=colour252,bg=colour244] #S #[fg=colour244,bg=colour232] '
      setw -g status-right                  ' #[fg=colour244,bg=colour232]#[fg=colour252,bg=colour244] #h '
      setw -g window-status-format          " #I│ #W "
      setw -g window-status-current-format  "#[fg=colour232,bg=colour39]#[fg=colour16,bg=colour39] #I│ #W #[fg=colour39,bg=colour232]"

      set -g status-left-length  64
      set -g status-right-length 64

      # Alacritty
      set -sa terminal-features ",alacritty:RGB"
      set -ga terminal-features ",alacritty:usstyle"

      # tmux uses the default cursor style in copy mode, which is configured to be "Beam" in Alacritty. Use a block cursor instead in copy mode.
      set-hook -g after-copy-mode 'set -p cursor-style block'
    '';
  };
}
