# vproj_ai

Vim project manager. A sidebar pane for browsing files, switching buffers,
and managing project structure. Navigate with the keyboard — no commands needed.

## Install

**Option 1 — Install script (recommended):**

```bash
git clone https://github.com/clearbellpaleforest/vproj_ai.git ~/dev/vproj_ai
cd ~/dev/vproj_ai
bash install.sh
```

The script creates `~/.vim/pack/bundle/start/vproj_ai/` with symlinks to `plugin/`, `autoload/`, and `doc/`. Vim's native package system will load the plugin automatically.

**Option 2 — Manual symlinks:**

Replace `~/.vim` with `$XDG_CONFIG_HOME/vim` if you use XDG.

```bash
mkdir -p ~/.vim/pack/bundle/start/vproj_ai
ln -s ~/dev/vproj_ai/src/plugin   ~/.vim/pack/bundle/start/vproj_ai/plugin
ln -s ~/dev/vproj_ai/src/autoload ~/.vim/pack/bundle/start/vproj_ai/autoload
ln -s ~/dev/vproj_ai/src/doc      ~/.vim/pack/bundle/start/vproj_ai/doc
vim -c "helptags ~/.vim/pack/bundle/start/vproj_ai/doc" -c q
```

**Option 3 — Plugin manager (vim-plug):**

```vim
Plug 'clearbellpaleforest/vproj_ai'
```

## Key Map

`F4` toggles the pane (outside the pane). Inside the pane:

### Navigation

| Key | Action |
|-----|--------|
| `j` / `<Down>` | Move selection down |
| `k` / `<Up>` | Move selection up |
| `h` | Parent directory |
| `l` / `Enter` | Open file or enter directory |
| `.` | Parent directory |
| `Ctrl-T` | Jump to first item |
| `Ctrl-B` | Jump to last item |
| `Ctrl-K` | Parent directory |
| `Ctrl-J` | Enter first subdirectory |

### Mode Switching

Each mode has a distinct color on the menu line so you know what you're in:

| Key | Mode | Color | Shows |
|-----|------|-------|-------|
| `f` | File | Yellow | Directory browsing, file sizes |
| `b` | Buf | Green | Open buffers with flags + line counts |
| `g` | Git | Magenta | Project tree from .vproj_ai |
| `q` | Qfix | Blue | Quickfix list entries |
| `L` | Log | Cyan | Git commit log — `Enter` for full diff |
| `Enter` on menu line | — | — | Cycle to next mode |

### Git Actions (file and log modes)

| Key | Action |
|-----|--------|
| `s` | Stage / unstage file under cursor |
| `d` | Open diff preview in vertical split |
| `D` | Discard file changes (with confirmation) |
| `C` | Commit with message prompt |
| `P` | Push to remote |
| `U` | Pull --ff-only from remote |
| `B` | Switch branch (with prompt) |
| `Ctrl-G` | Toggle showing only git-changed files |

### Actions

| Key | Action |
|-----|--------|
| `r` | Refresh listing |
| `x` | Close selected buffer (buf mode only) |
| `+` / `-` | Include / exclude item (git mode) |
| `T` | Toggle tree view (file mode — indented with expand/collapse) |
| `p` | Toggle file preview split (updates on cursor move) |
| `/` | Filter files by name pattern |
| `*` | Grep project and populate quickfix |
| `<Left>` / `<Right>` | Shrink / grow pane width |
| `F1` | Toggle info column (inside pane) |
| `Tab` / `Shift-Tab` | Shift nav indicators forward / backward |
| `a` – `z`, `A` – `Z`, `1` – `9` | Jump to item by nav character (cyan) |

### Paging

| Key | Action |
|-----|--------|
| `Ctrl-N` | Next page |
| `Ctrl-P` | Previous page |

### Close

| Key | Action |
|-----|--------|
| `Q` | Close pane |
| `F4` | Close pane (or toggle when outside pane) |

### Standard Vim Keys (passthrough)

These work as usual inside the pane — we don't override them:

| Key(s) | Behavior |
|--------|----------|
| `w` `b` `e` | Word motions |
| `0` `^` `$` | Line start / end |
| `t<char>` | Find until character |
| `H` `M` | Screen top / middle |
| `?` | Search backward |
| `y` | Yank (copy filename on current line) |
| `Ctrl-F` | Page down |
| `Ctrl-D` `Ctrl-U` | Half-page down / up |
| `Ctrl-W` keys | Window management |
| `%` `{` `}` `(` `)` | Jump / matching pair |
| `zz` `zt` `zb` | Scroll cursor to center / top / bottom |

Or use commands: `:VprojAiToggle`, `:VprojAiOpen`, `:VprojAiClose`, `:VprojAiRefresh`.

Use `let g:vproj_ai_show_dotfiles = 1` to show hidden files.

See `:help vproj_ai` for full documentation.

## .vproj_ai File Format

Git Mode reads a `.vproj_ai` file at the project root to determine which files and directories to include. Example:

```
Project Name: my-project
Project Root: /home/user/dev/my-project
Included Directories:
src
Included Files:
README.md
Excluded Directories:
.git
node_modules
Excluded Files:
.env
```

Lines starting with `#` are comments. See `:help vproj_ai-file-format` for details.

## Remap

```vim
" Change the toggle key
nmap <F2> <Plug>VprojAiToggle

" Disable default F4
nunmap <F4>
```

## Requirements

Vim 9.0 or later.
