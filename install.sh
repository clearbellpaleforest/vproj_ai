#!/bin/bash
# install.sh — Install vproj_ai to ~/.vim/pack/bundle/start/vproj_ai
#
# Usage:
#   git clone https://github.com/clearbellpaleforest/vproj_ai.git ~/dev/vproj_ai
#   cd ~/dev/vproj_ai
#   bash install.sh
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# Respect XDG if set, otherwise default to ~/.vim
# Vim's 'packpath' includes ~/.vim regardless, but some distributions
# patch this — check XDG_CONFIG_HOME first.
if [ -n "$XDG_CONFIG_HOME" ]; then
  TARGET_DIR="$XDG_CONFIG_HOME/vim/pack/bundle/start/vproj_ai"
elif [ -d "$HOME/.config/vim" ]; then
  TARGET_DIR="$HOME/.config/vim/pack/bundle/start/vproj_ai"
else
  TARGET_DIR="$HOME/.vim/pack/bundle/start/vproj_ai"
fi

mkdir -p "$TARGET_DIR"
ln -sf "$SRC_DIR/src/plugin" "$TARGET_DIR/plugin"
ln -sf "$SRC_DIR/src/autoload" "$TARGET_DIR/autoload"
ln -sf "$SRC_DIR/src/doc" "$TARGET_DIR/doc"
vim --cmd "helptags $TARGET_DIR/doc" --cmd "q" 2>/dev/null || true

echo "vproj_ai installed. Start Vim and press F4 to open the project pane."
echo "Run :help vproj_ai for documentation."
