# Hand Test — Keybinding Verification

Run from the vproj_ai project root:

```
vim -N -u NONE --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj_ai.vim'
```

Press `F4` to open the pane, then work through each section.

## Navigation

- [ ] `j` — move cursor down
- [ ] `k` — move cursor up
- [ ] `<Down>` — same as j
- [ ] `<Up>` — same as k
- [ ] `h` — go to parent directory
- [ ] `l` — enter directory or open file
- [ ] `.` — same as h (parent directory)
- [ ] `<CR>` (Enter) — open file / enter dir / cycle mode on menu line
- [ ] `<C-T>` — jump to first item
- [ ] `<C-B>` — jump to last item
- [ ] `<C-K>` — go to parent directory (same as h)
- [ ] `<C-J>` — enter first subdirectory

## Mode Switching

Press these while the pane is focused:

- [ ] `f` — file mode (browse directories)
- [ ] `b` — buf mode (open buffers)
- [ ] `g` — git mode (project tree)
- [ ] `q` — qfix mode (quickfix list)
- [ ] `Enter` on the `[F]ile  [B]uf  [G]it  [Q]fix` menu line (line 1) — cycles to next mode

## Width

- [ ] `<Right>` — grow pane by 1 column (max 80)
- [ ] `<Left>` — shrink pane by 1 column (min 20)
- [ ] `:call vproj_ai#SetPaneWidth(50)` — set exact width

## Actions

- [ ] `r` — refresh pane contents
- [ ] `x` — close selected buffer (buf mode only; shows message in other modes)
- [ ] `+` — include item (git mode, on a parenthesized item)
- [ ] `-` — exclude item (git mode, on an included item)
- [ ] `<F1>` — toggle info column (file sizes / line counts)

## Paging

Navigate to a directory with many files (e.g. /usr/bin via file mode):

- [ ] `<C-N>` — next page
- [ ] `<C-P>` — previous page

## Quick Nav

Nav indicators are the single chars at the start of each line (a, b, c, …).

- [ ] `<Tab>` — shift nav indicators forward (next batch)
- [ ] `<S-Tab>` — shift nav indicators backward (previous batch)

Jump-to-char keys (press the char to jump to that line):

- [ ] `b` `c` `d` `e` `i` `m` `n` `o` `p` `s` `t` `u` `v` `w` `x` `y`
- [ ] `A` `B` `C` `D` `E` `F` `G` `H` `I` `J` `K` `L` `M` `N` `O` `P` `Q` `R` `S` `T` `U` `V` `W` `X` `Y`
- [ ] `1` `2` `3` `4` `5` `6` `7` `8` `9`

If a char is not on the current page, nothing happens (no crash).

## Git Actions

Navigate to a git-tracked file in file mode (or use git/log mode):

- [ ] `s` — stage/unstage file under cursor
- [ ] `d` — open diff preview in vertical split
- [ ] `D` — discard file changes (confirmation prompt appears)
- [ ] `C` — commit with message prompt
- [ ] `P` — push to remote
- [ ] `U` — pull (--ff-only) from remote
- [ ] `B` — switch branch (prompt for branch name)
- [ ] `z` — stash changes (optional message prompt)
- [ ] `Z` — pop a stash (shows list first, select by index)
- [ ] `a` — blame file under cursor (split opens with git annotate, q to close)

## Close

- [ ] `Q` — close pane
- [ ] `<F4>` — close pane (inside the pane)
- [ ] `<F4>` — toggle pane open/closed (outside the pane, globally)

## Passthrough — Standard Vim Keys

These are NOT remapped and should work as usual inside the pane:

- [ ] `t<char>` — find until character
- [ ] `w` — word forward
- [ ] `e` — end of word
- [ ] `0` / `^` / `$` — line start / first non-blank / line end
- [ ] `H` / `M` / `L` — screen top / middle / bottom
- [ ] `%` — jump to matching `( ) { } [ ]`
- [ ] `{` / `}` — paragraph back / forward
- [ ] `(` / `)` — sentence back / forward
- [ ] `y` — yank (copies the filename on the current line)
- [ ] `/` / `?` — search forward / backward
- [ ] `<C-F>` / `<C-B>` — page down / up
- [ ] `<C-D>` / `<C-U>` — half-page down / up
- [ ] `<C-W>` keys — window management (hjkl, w, q, etc.)
- [ ] `zz` / `zt` / `zb` — scroll cursor to center / top / bottom

## Notes

- `f` `b` `g` `q` are mode-switch keys, NOT nav chars — lowercase f/b/g/q are excluded from nav indicators
- `h` `j` `k` `l` `r` `x` are navigation/action keys, not nav chars
- `C` `D` `F` are now free and included as nav chars (uppercase)
- `0` is passthrough (line start), not a nav char — digits start at 1
