# Vproj_AI — CLAUDE.md

AI add-on for vproj. Adds `A` key to the vproj pane that opens a
`:terminal`-based chat for multi-turn AI-powered coding assistance via
OpenAI-compatible API. ~250 lines; layers on vproj, does not duplicate it.

**All code is Vim9Script.** Every file begins with `vim9script`. Use `def`
functions, script-local `var` for state, `export def` for public API. Never
write legacy `function!` or `let`/`const` in these files.

## Add-on Architecture

vproj_ai is NOT a fork. It's a lightweight add-on that:

1. **Calls vproj# functions** for all pane/mode/navigation operations
2. **Adds exactly one new feature**: AI prompt via `A` key or `:VprojAiPrompt`
3. **Injects the A mapping** via BufEnter autocommand into vproj's pane buffer
4. **Requires vproj** — refuses to load if `g:loaded_vproj` is not set

## Rules

1. **Call vproj, don't copy it.** Use `vproj#GetPaneBufnr()`, `vproj#PaneOpen()`,
   `vproj#IsPaneVisible()`, etc. Never duplicate vproj logic.

2. **Vim9Script only.** `def` functions, `var` state, `export def` for public API.
   Script-local `var` at top of autoload file for all persistent state.

3. **No new dependencies.** No external JSON parsers, no framework libraries.
   `system('curl ...')` for HTTP, manual JSON string extraction.

4. **Handle the error where it occurs.** Check API key before curl. Check
   curl exit code. Handle empty responses. Guard every boundary.

5. **Filesystem writes are dangerous.** Only `writefile()` for the temp
   request body passed to curl; always `delete()` after. Everything else
   is read-only. No automatic file creation.

6. **Vim is not Python.** `maparg()` return type depends on argument values
   and Vim version. `getenv()` returns `v:null`. `string()` adds quotes.
   Look up every builtin's Vim9Script signature.

7. **TDD always.** Write the failing test before the implementation. Watch it
   fail for the right reason. Then write minimal code to pass. No exceptions
   without the user's permission.

8. **Before writing Vimscript, ask "can bash do this instead?"** A 15-line
   bash script that calls `vim -c "source file" -c "messages"` is simpler,
   more portable, and has no circular dependency. Use `bin/verify_vim.sh`
   to verify Vimscript edits before committing them.

## Vim9Script Version-Specific Pitfalls

- **`maparg()` 5th argument (buffer number)**: NOT available in Vim 9.2.
  Using it causes `E118: Too many arguments for function`. Use 2-arg
  `maparg('key', 'mode')` instead when in the target buffer.
- **`maparg()` return type**: Vim9Script may type it as `dict<any>` even
  with `{dict}=false`. Either omit type annotation or test with Vim 9.2.
- **`false`/`true`**: Available in vim9script. `v:false`/`v:true` in legacy.
- **`null`**: Use `v:null` for unset values. Not the same as empty string.
- **`exists('*FuncName')`**: Works for autoload functions only after the
  autoload file is sourced. Trigger autoload by calling any exported function
  before checking existence.
- **`def` functions**: Lambda vars must start with capital letter. Slice
  expressions need spaces: `lines[ : 10]` not `lines[:10]`.
- **Autocommand in vim9script**: Use `augroup` + `autocmd!` + `autocmd` pattern.
  Autocommands in vim9script files inherit the script context and can trigger
  autoload sourcing which runs during nested event handling.

## Codebase

```
src/
├── plugin/vproj_ai.vim           # Entry point — guard, command, Plug, BufEnter autocmd
├── autoload/vproj_ai.vim         # All logic — Vim9Script (AI state, context, curl, routing, terminal)
├── bin/vproj-ai-chat             # Bash script — terminal chat loop, SSE streaming, multi-turn
└── doc/
    ├── vproj_ai.txt               # Help file
    └── tags                       # Help tag index
tests/
├── unit/
├── integration/
│   └── test_ai_addon.vim          # Add-on integration (runs vproj + vproj_ai together)
├── smoke.vim                       # Load, function existence, basic vproj ops
├── demo.vim
└── hand_test.md
```

Three source files. Plugin declares the public surface. Autoload owns all logic
and state. Bash script handles the terminal chat. Nothing else.

## State

Script-local variables at the top of `autoload/vproj_ai.vim`:

```
ai_api_url, ai_api_key, ai_model          # Persistent config
ai_mode, ai_target_bufnr, ai_target_cursor_line  # Per-request
stream_job, stream_accumulated, stream_cancelled, stream_full_response  # Streaming
```

No session persistence. No filesystem writes for state.

## Public API

| Function | Purpose |
|----------|---------|
| `vproj_ai#AiTerminalChat()` | Open `:terminal` running bin/vproj-ai-chat for multi-turn conversation |
| `vproj_ai#AiPrompt(prompt_from_cmdline)` | One-shot: detect mode, gather context, stream to API, route result |
| `vproj_ai#AiPromptFromKey()` | Interactive `input()` prompt (used by `:VprojAiPrompt` without arg) |
| `vproj_ai#AiCall(prompt, ctx)` | POST to OpenAI-compatible API via curl (sync fallback) |
| `vproj_ai#OnBufEnter()` | Inject `A` mapping when entering vproj pane buffer |
| `vproj_ai#StreamCancelCmd()` | Cancel in-progress streaming API call |

Command: `:VprojAiPrompt`
Mapping: `<Plug>VprojAiPrompt`

## API Configuration

Priority order:
1. `g:vproj_ai_api_key` + optional `g:vproj_ai_api_url`
2. `$DEEPSEEK_API_KEY` → defaults to `https://api.deepseek.com/v1/chat/completions`
3. `$OPENAI_API_KEY` + optional `$OPENAI_API_BASE` → defaults to OpenAI endpoint

## Internal Functions (private `def`)

| Function | Purpose |
|----------|---------|
| `AiConfigure()` | Read API key/URL from g: vars and env vars |
| `GatherContext()` | Build context dict (mode, file, cursor, selection) |
| `DetectMode(prompt)` | Classify prompt as 'code' or 'question' |
| `StripPrefix(prompt)` | Remove !/? mode-forcing prefix from prompt |
| `JsonEscape(s)` | Escape string for JSON embedding |
| `ExtractJsonField(json, field)` | Walk JSON string to extract field value |
| `ExtractCodeBlocks(text)` | Parse ``` fenced code blocks from response text |
| `ApplyCode(bufnr, blocks, line)` | Insert code into target buffer at cursor line |
| `ShowPopup(text)` | Display response in centered floating popup |
| `PopupFilter(winid, key)` | Popup key handler — q/Esc/Ctrl-C to close |
| `BuildRequestBody(prompt, ctx, stream)` | Build JSON request body |
| `BuildStreamCommand(prompt, ctx)` | Build curl command for streaming API call |
| `AiCallStream(prompt, ctx)` | Start async streaming API call via job_start |
| `ProcessStreamChunk(chan, msg)` | Parse SSE frames, accumulate response |
| `StreamJobExit(job, status)` | On completion, route to ApplyCode or ShowPopup |
| `StreamCancel()` | Stop in-progress stream |
| `ParseJsonString/Container/Scalar` | JSON parsing helpers |

## Direct-to-Code + Floating Popup

`AiPrompt()` detects the prompt's intent and routes the streaming response
accordingly. Zero new permanent splits. Two panels max: pane + code.

### Mode Detection

`DetectMode(prompt)` classifies the prompt:
- `!` prefix → force **code** mode (strip prefix, apply response as code)
- `?` prefix → force **question** mode (strip prefix, show popup)
- Question words (what, how, why, explain, describe, etc.) or `?` anywhere → **question**
- Everything else → **code** mode

### Code Mode (default)

On stream completion, `StreamJobExit` calls `ExtractCodeBlocks` to parse
```fenced code blocks from the response, then `ApplyCode` inserts the first
block (or the entire response if no fences) at the cursor position in the
target file using `append()`. Status message: `vproj_ai: applied N lines to
file.vim (u to undo)`.

### Question Mode

On stream completion, `StreamJobExit` calls `ShowPopup` which uses
`popup_create()` — centered, ~60 cols, ~20 lines, scrollable. `q`, `Esc`,
or `Ctrl-C` closes the popup. No new split or buffer.

### Streaming UX

While streaming, a brief status line shows `vproj_ai: streaming for file...`.
Ctrl-C cancels the stream. On completion, code is applied or popup shown.

### Target Buffer Selection

The target is the alternate buffer (`bufnr('#')`) — the file the user was
editing before focusing the pane. Falls back to the first listed non-pane
buffer. If no valid target exists, defaults to question mode.

## OnBufEnter Mapping Injection

```
BufEnter → vproj_ai#OnBufEnter()
  → checks vproj#GetPaneBufnr() exists
  → checks current buffer IS the pane buffer
  → nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiTerminalChat()<CR>
```

Idempotent: `nnoremap` replaces any existing mapping silently.

`AiTerminalChat()` gathers context, writes it to a temp JSON file, and opens
a `:terminal` running `bin/vproj-ai-chat`. The terminal handles all input —
no Vim modes, no `input()`, no typeahead issues.

## Terminal Chat Architecture

The `:terminal` (Vim 8.0+) runs a real shell. Keys pass through to the shell
without Vim's modal system touching them. Zero mode conflicts.

```
┌──────────┬──────────────┐
│  pane    │  code        │
│ (vproj)  │  (your file) │
├──────────┴──────────────┤
│  :terminal — chat       │  ← bash script, no Vim modes
│  ▸ how do I add auth?   │     keys pass through
│  AI: here's how...      │     streaming visible in real time
│  ▸ show me the code     │     history scrolls naturally
│  AI: ```python ...```   │
└─────────────────────────┘
```

**Data flow:**
1. User presses `A` in pane → `AiTerminalChat()`
2. Vim gathers context (file path, cursor, mode)
3. Vim writes context to temp JSON file
4. Vim opens `:terminal` running `vproj-ai-chat /tmp/request.json`
5. Script reads context, enters multi-turn chat loop
6. Each turn: read stdin → curl SSE → stream to terminal → repeat
7. `Ctrl-D` or `/exit` quits

**`A` is buffer-local to the pane only.** In normal buffers, `A` does Vim's
default append. The global `A` mapping was removed — no key hijacking.

**The old one-shot flow (`AiPrompt`/`AiPromptFromKey`) is preserved** for
`:VprojAiPrompt` command-line usage.

## `input()` in Mapping Context

**Use `<Cmd>` mappings for `input()`.** `<Cmd>` mappings process the command
before entering command-line mode and don't use typeahead. This makes `input()`
safe inside functions called from `<Cmd>` mappings.

**Never use `input()` from a `:call` mapping RHS** (e.g., `:map A :call Func()<CR>`).
The `:` mapping feeds the trailing `<CR>` as typeahead, which `input()` consumes
instantly, returning empty string before the user can type.

## Apply AI-Generated Code

In the one-shot `:VprojAiPrompt` flow, code mode applies AI output directly:
1. `ExtractCodeBlocks(text)` parses ``` fenced blocks from response text
2. First fenced block is used; if none, entire response is applied as code
3. `ApplyCode()` inserts at cursor line via `appendbufline()` in target buffer
4. All operations are undoable with `u`

In the terminal chat flow, the user sees the code in the terminal and copies
it manually. Future: `/apply` command in the chat script to trigger code insertion.

## Testing

Run: `vim -N -u NONE -S tests/<test_file>.vim`

Both vproj and vproj_ai must be in rtp. Smoke test verifies:
- Both plugins load
- vproj exports `GetPaneBufnr`
- vproj_ai exports `AiPrompt`, `AiCall`, `OnBufEnter`, `StreamCancelCmd`
- `:VprojAiPrompt` command and `<Plug>` mapping exist
- Pane opens via `vproj#PaneOpen()`
- Basic mode switching works
- Deleted conversation functions (HandleConvBufWipeout, SendFollowup, AiApplyCode) are gone

## Development Methodology

1. **Loops and checks.** After every change, run the test suite. If tests pass,
   do a manual smoke check. Never batch multiple untested changes — one change,
   one verification cycle.

2. **Self-check your work.** Before declaring something done, ask: did I
   introduce regressions? Does the fix handle edge cases? Read the diff as if
   you were reviewing a colleague's code.

3. **Research when stuck.** If you don't understand a bug, don't guess. Search
   the internet, read the Vim help (`:help`), look at similar implementations.
   Guessing wastes time and creates new bugs.

4. **Narrow reproduction.** Before fixing, reproduce the bug with the minimum
   possible steps. A bug you can't reproduce is a bug you can't verify as fixed.

5. **Fix root causes, not symptoms.** A swallowed error, a missing guard, an
   incorrect assumption — find and fix the source, don't paper over the fallout.

## File Locations & Deployment

Working tree and Vim bundle are the **same files** via hard links:

```
~/.vim/pack/bundle/start/vproj/       ← Vim loads vproj from here
~/.vim/pack/bundle/start/vproj_ai/    ← Vim loads vproj_ai from here
/home/aldous/work/vproj/vproj/        ← same inodes as ~/.vim/pack/bundle/start/vproj/
/home/aldous/work/vproj/vproj_ai/     ← same inodes as ~/.vim/pack/bundle/start/vproj_ai/
```

Changes to files under either path are immediately live — no copy or sync step
needed. To verify: `stat -c '%i' <path1> <path2>` shows the same inode number.

### Mapping Syntax in vim9script

Use `<Cmd>` mappings, not command-line `:Command<Space>`:

```
nnoremap <silent> A <Cmd>call vproj_ai#AiPromptFromKey()<CR>
```

`<Cmd>` avoids the typeahead issues of `:` mappings — the trailing `<CR>` in
the RHS is processed by the mapping engine, not fed as typeahead. This means
`input()` can be called safely from functions invoked via `<Cmd>` mappings.

Avoid `<Space>` key code in `:nnoremap` RHS within `vim9script` files — it may
not expand reliably.
