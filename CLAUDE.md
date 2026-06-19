# Vproj_AI — CLAUDE.md

Vim project manager. A sidebar pane for browsing files, switching buffers,
and managing project structure.

## Rules

1. **Start with data.** Before drawing flows or sequences, draw the data. What
   the program needs to know, what owns it, where it can change, what invariant
   holds. Data structures outlast control flow and are harder to change later.
   Get them right first.

2. **Explicit control flow.** A reader should be able to read the code top to
   bottom and see who calls whom without charting it on paper. Functions call
   functions directly. No dispatchers, no registries, no callback chains whose
   destination you can't find with grep.

3. **One routine, one job.** A function that decides what to do and a function
   that knows how to do it are two functions. When a function does more than one
   thing, split it. When a file does more than one job, split it. But don't
   abstract until the pattern has repeated three times — an abstraction built on
   one example is a guess.

4. **Handle the error where it occurs.** A swallowed error today is a week of
   debugging next year. Check preconditions at every boundary — if caller A
   passes data to callee B, B checks A's inputs anyway, because A might be wrong
   tomorrow. Guard clauses first, happy path second.

5. **The user's machine is not yours.** `writefile()`, `delete()`, `rename()`,
   `mkdir()` — every call that touches the filesystem must trace back to an
   explicit user action. No automatic file creation, no surprise writes.

6. **Vim is not Python.** Look up the help for every builtin. `string()` adds
   quote characters. `getenv()` returns `v:null` for missing vars. `sort()`
   takes a Funcref, not a string name.

7. **Two source files.** `plugin/vproj_ai.vim` is the public surface — commands,
   mappings, `<Plug>` indirections. `autoload/vproj_ai.vim` is the implementation
   — all logic, all state. Plugin calls autoload. Never the reverse. Do not add
   a third file without approval.

## Development Process

1. **Human designs, AI critiques.** Project structure, subsystem boundaries,
   and file layout are designed by the human. AI reviews designs for gaps,
   inconsistencies, and edge cases but does not originate structural decisions.
   The human owns the architecture.

2. **Stage the work in small pieces.** Skeleton first — function signatures,
   data structures, comments explaining intent. Then fill in one piece at a
   time, testing at each step. A `plan.md` drives the build sequence. Never
   build more than one layer ahead of what is tested.

3. **Validate every input.** Assume nothing about input. Environment variables
   may be unset (`getenv()` returns `v:null`). Files may be missing. User input
   may be empty or malformed. Negative-path first — handle the failure case
   before the happy path. A program that fails cleanly is better than one that
   silently corrupts.

4. **Filesystem writes are dangerous.** A mistake with `writefile()`,
   `delete()`, or `rename()` can damage the user's machine. AI-generated code
   often mishandles these calls — `string()` adds quote characters in Vim,
   `getenv()` returns `v:null` for missing vars, and concatenating either into
   a path produces garbage. Every filesystem call must be explicit, justified,
   and correct before it ships. When in doubt, read-only.

## Documentation Structure

CONCEPT.MD is the source material living in docs/. Each docs/ file extracts
and elaborates one dimension. The docs/ directory is gitignored — design
documents are living references, not shipped artifacts.

```
docs/
├── CONCEPT.MD                 # Source material — vision, modes, navigation, architecture
├── constraints.md             # Hard boundaries — cross-platform, no deps, ASCII-only
├── architecture.md            # How the parts fit together — subsystems, data flow
├── design.md                  # Detailed behavioral spec — state, events, edge cases
├── implementation-plan.md     # Build order, staged milestones, stage gates
├── test-plan.md               # Testing strategy, coverage targets, categories
├── test-cases.md              # Concrete test vectors (TC001-N)
└── decisions.md               # Design decisions + rationale, especially divergences
```

## .gitignore

```
*.swp
*.swo
*~
.claude/
docs/
```

Swap files and backups are editor noise. `.claude/` is Claude Code internal
state. `docs/` is design reference material — not shipped with the plugin.

## Codebase

```
src/
├── plugin/vproj_ai.vim           # Entry point — commands, default F4 mapping
├── autoload/vproj_ai.vim         # All logic — Vim9Script
└── doc/
    ├── vproj_ai.txt               # Help file
    └── tags                    # Help tag index
docs/                          # Per the 7-doc structure above
tests/
├── unit/
│   └── test_first_selectable.vim
├── integration/
│   ├── test_git_mode_full.vim
│   ├── test_buf_mode.vim
│   ├── test_paging.vim
│   └── test_qfix_mode.vim
├── smoke.vim
├── final.vim
├── regression.vim
├── coverage.vim
├── edge_test.vim
├── keybindings.vim
├── demo.vim
├── hand_test.md
└── test_helpers.vim
```

Two source files. The plugin file declares the public surface. The autoload file
owns all logic and state. Nothing else.

## Architecture

Explicit imperative flow. State lives in script-local variables at the top of
the autoload file:

```
pane_bufnr, pane_width, current_mode, selected_line, current_dir, items
project, git_root, match_ids, saved_shortmess, show_info_column, current_page
items_per_page, paging_active, nav_offset, original_cwd, cursor_match_id
```

Commands change state then call `Render()`. The display is always a pure
function of current state — call Render at any time and you get an accurate
picture of the workspace. You can trace every state transition to its source by
reading the file top to bottom.

## Implementing a Feature

When adding a feature, follow this sequence:

1. **Identify the state.** What new information must the program remember? Add
   it to the script-local variable block at the top of the autoload file. If it
   needs initialization, set it there.

2. **Write the command.** Add a function to the autoload file. The function:
   validates inputs, changes state, calls `Render()`. That's it. Display logic
   lives in the render path, not in the command.

3. **Expose the entry point.** If the function is called from a mapping,
   command, or external plugin, add it to the Exported API table in
   `plugin/vproj_ai.vim`. The plugin file is a table of contents — it declares
   what's public. The implementation stays in autoload. Plugin calls autoload.
   Never the reverse.

4. **Update the display.** `Render()` rebuilds the entire pane buffer from
   state. Add the rendering logic for any new visible information there. The
   display reads state. It never modifies it.

5. **Add keybindings.** If the feature gets a key, add it to the buffer-local
   mappings in `MapKeys()`. Keep the mapping table sorted by key so a reader can
   find bindings without scanning the whole file.

6. **Test.** Unit tests in `tests/unit/` for function invariants. Integration
   tests in `tests/integration/` for end-to-end behavior through the public API.

## Modes

| Mode | Key | Shows |
|------|-----|-------|
| File | f | Directory browsing, file sizes, binary detection |
| Buf | b | Open buffers with flags + line counts |
| Git | g | Project tree from .vproj_ai, include/exclude with +/- |
| Qfix | q | Quickfix list — filename:lnum, entry text |
| Log | L | Git commit log — `git log --oneline`, Enter for diff details |

Enter on the mode menu line cycles between modes.

## Exported API

| Function | Purpose |
|----------|---------|
| `vproj_ai#PaneToggle()` | Toggle pane open/closed |
| `vproj_ai#PaneOpen()` | Open pane |
| `vproj_ai#PaneClose()` | Close pane |
| `vproj_ai#SwitchMode(key)` | Switch to 'file', 'buf', 'git', 'qfix', or 'log' |
| `vproj_ai#SelectNext()` / `vproj_ai#SelectPrev()` | Move selection |
| `vproj_ai#SelectCurrent()` | Activate selected item |
| `vproj_ai#PaneGrow()` / `vproj_ai#PaneShrink()` | Width +/- 1 |
| `vproj_ai#SetPaneWidth(n)` | Set exact width (20-80) |
| `vproj_ai#NavigateUp()` | Parent directory |
| `vproj_ai#Refresh()` | Re-render pane contents |
| `vproj_ai#CloseBuffer()` | Close selected buffer (buf mode) |
| `vproj_ai#ToggleInclude()` | Include/exclude item (git mode) |
| `vproj_ai#IncludeItem()` | Include item (git mode, + key) |
| `vproj_ai#ExcludeItem()` | Exclude item (git mode, - key) |
| `vproj_ai#RenameProject()` | Rename/create project (git mode) |
| `vproj_ai#IsPaneVisible()` | Query visibility |
| `vproj_ai#GetPaneWidth()` / `vproj_ai#GetCurrentMode()` | Query state |
| `vproj_ai#SelectFirst()` / `vproj_ai#SelectLast()` | Jump to first / last item |
| `vproj_ai#NavigateIntoFirstDir()` | Enter first subdirectory |
| `vproj_ai#SelectByNavChar(ch)` | Jump to item by nav character |
| `vproj_ai#ShiftNavForward()` / `vproj_ai#ShiftNavBackward()` | Shift nav indicator range |
| `vproj_ai#GetNavOffset()` | Get current nav offset |
| `vproj_ai#ToggleInfoColumn()` | Toggle info column display |
| `vproj_ai#NextPage()` / `vproj_ai#PrevPage()` | Page through long listings |
| `vproj_ai#ToggleGitFilter()` | Toggle showing only git-changed files |
| `vproj_ai#GitStageToggle()` | Stage/unstage file under cursor |
| `vproj_ai#OpenDiffPreview()` | Open git diff in vertical split |
| `vproj_ai#DiscardChanges()` | Discard file changes with confirmation |
| `vproj_ai#GitCommit()` | Commit with message prompt |
| `vproj_ai#GitPush()` | Push to remote |
| `vproj_ai#GitPull()` | Pull --ff-only from remote |
| `vproj_ai#GitBranchSwitch()` | Switch git branch with prompt |
| `vproj_ai#GitStashPush()` | Stash current changes (with optional message) |
| `vproj_ai#GitStashPop()` | Pop a stash (shows list first, select by index) |
| `vproj_ai#GitBlame()` | Open git blame split for file under cursor |
| `vproj_ai#PromptFilter()` | Prompt for filter pattern |
| `vproj_ai#OnDirChanged()` | Handle directory change event |
| `vproj_ai#HandleBufWipeout()` | Cleanup on buffer wipe |
| `vproj_ai#HandleF1()` | Toggle info column (pane) or open help (elsewhere) |
| `vproj_ai#ToggleTreeView()` | Toggle tree view within file mode |
| `vproj_ai#TogglePreview()` | Toggle file preview split (p key) |
| `vproj_ai#GrepSearch()` | Grep project and populate quickfix |
| `vproj_ai#DefineHighlights()` | Define highlight groups |

## Pane Keybindings

Buffer-local (only active in the pane):

| Key | Action |
|-----|--------|
| j/k, Up/Down | Move selection |
| h | Parent directory |
| Left/Right | Shrink/grow width |
| Enter | Open file, switch buffer, cycle mode, or rename project |
| f/b/g/q/L | File / Buf / Git / Qfix / Log mode |
| r | Refresh pane |
| x | Close selected buffer (buf mode) |
| +/- | Include / exclude item (git mode) |
| Q, F4 | Close pane |
| . | Parent directory |
| Ctrl-T / Ctrl-B | Jump to first / last item |
| Ctrl-K / Ctrl-J | Parent dir / enter first subdir |
| F1 | Toggle info column |
| Ctrl-N / Ctrl-P | Next / previous page |
| Ctrl-G | Toggle git-changed-only filter |
| s | Stage/unstage file (git) |
| d | Diff preview for file under cursor |
| D | Discard changes (with confirmation) |
| C | Git commit (with message prompt) |
| P | Git push |
| U | Git pull --ff-only |
| B | Git branch switch |
| z | Git stash push (with optional message) |
| Z | Git stash pop (shows list, select by index) |
| a | Git blame (annotate) for file under cursor |
| T | Toggle tree view (file mode — indented with expand/collapse) |
| p | Toggle file preview split (updates on cursor move) |
| / | Filter by name |
| * | Grep search (populates quickfix) |
| Tab / Shift-Tab | Shift nav indicators |
| a-z, A-Z, 1-9 | Jump by nav character |

## Commands

`:VprojAiToggle`, `:VprojAiOpen`, `:VprojAiClose`, `:VprojAiRefresh`

Default mapping: `<F4>` toggles pane (uses `<Plug>VprojAiToggle` indirection).

## .vproj_ai File Format

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

## Git Mode Behavior

- No .vproj_ai found: status line shows `* (no project found)`, all items in parentheses
- Enter on status line: rename/create project (inline via `input()`)
- `+` on non-included item: include in project, save .vproj_ai
- `-` on included item: exclude from project, save .vproj_ai
- No ex commands needed for project management

## Testing

```
tests/
├── unit/
│   └── test_first_selectable.vim   # FirstSelectableLine mode-awareness
├── integration/
│   ├── test_git_mode_full.vim     # Git mode layout, mode switching
│   ├── test_buf_mode.vim           # Buf mode with real buffers
│   ├── test_paging.vim             # Paging with 60-item directory
│   └── test_qfix_mode.vim          # Qfix mode display, jump-to-entry, empty state
├── smoke.vim                       # Basic open/close
├── final.vim                       # Audit fix verification
├── regression.vim                  # Regression checks
├── coverage.vim                    # Comprehensive API coverage
├── edge_test.vim                   # Edge cases, boundary conditions
├── keybindings.vim                 # Keybinding dispatch
├── demo.vim                        # Interactive demo script
├── hand_test.md                    # Manual test checklist
└── test_helpers.vim                # Shared helpers (legacy Vimscript, unused)
```

Run all: `vim -N -u NONE -S tests/<test_file>.vim`

## Vim9Script Notes

- `def` functions are strict: lambda vars must start with capital
- `readdir()` in `def`: no empty string filter argument
- Use `=~ ':$'` and `substitute()` instead of negative string slices
- Use `get(dict, 'key', default)` for optional dict keys
- Mappings use `<Cmd>` modifier to avoid command-line flicker; `<nowait>` on f/g/q to prevent prefix-key timeout
- `matchadd()` 4th argument is match ID — pass `-1` for auto-assignment, never a window ID
- Global `set shortmess+=S` suppresses search-wrap messages; restore original on pane close
- ASCII-only for separator characters
- `ItemIndex()` extracts the shared `(selected_line - FirstSelectableLine()) + (current_page * items_per_page)` formula used by SelectCurrent, CloseBuffer, and DoToggleInclude
- `getftype()` filters FIFOs/sockets/devices in ReadDir and GitItems to prevent readblob hangs
