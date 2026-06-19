# Vproj_AI — CLAUDE.md

AI add-on for vproj. Adds `A` key to the vproj pane for AI-powered coding
assistance via OpenAI-compatible API. ~200 lines; layers on vproj, does not
duplicate it.

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
├── autoload/vproj_ai.vim         # All logic — Vim9Script (AI state, context, curl, routing)
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

Two source files. Plugin declares the public surface. Autoload owns all logic
and state. Nothing else.

## State

Script-local variables at the top of `autoload/vproj_ai.vim`:

```
ai_api_url, ai_api_key
```

No session persistence. No filesystem writes for state.

## Public API

| Function | Purpose |
|----------|---------|
| `vproj_ai#AiPrompt()` | Gather context, prompt user, call API, route response |
| `vproj_ai#AiCall(prompt, ctx)` | POST to OpenAI-compatible API via curl |
| `vproj_ai#OnBufEnter()` | Inject `A` mapping when entering vproj pane buffer |
| `vproj_ai#AiApplyCode()` | Find nearest code fence, confirm, apply to target file |

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
| `JsonEscape(s)` | Escape string for JSON embedding |
| `ExtractJsonField(json, field)` | Walk JSON string to extract field value |
| `RouteResponse(text, ctx)` | Classify response → qfix, markdown view, or echom |
| `CreateView(text, filetype, ctx)` | Open botright vnew with content, q/a mappings, set b: vars |
| `FindCodeBlocks()` | Scan buffer for ``` fence pairs, return block list |
| `FindNearestBlock(blocks, cursor_lnum)` | Select code block closest to cursor |
| `ApplyCodeToFile(file, code, cursor_line)` | Insert code into target file after cursor line |
| `BuildRequestBody(prompt, ctx, stream)` | Build JSON request body |

## Response Routing

AI responses are classified:
- **`file:line:` patterns** (2+ matches) → `setqflist()` + `vproj#SwitchMode('qfix')`
- **``` code fences** → `CreateView(text, 'markdown', ctx)` in a split
- **Short** (1-2 lines, no fences) → `echom`
- **Long fallback** → `CreateView(text, 'markdown', ctx)`, echo first 10 lines on failure

`RouteResponse` and `CreateView` both receive the context dict. `CreateView`
stores target file and cursor line in buffer-local `b:vproj_ai_target_file`
and `b:vproj_ai_cursor_line` for `AiApplyCode` to use.

## OnBufEnter Mapping Injection

```
BufEnter → vproj_ai#OnBufEnter()
  → checks vproj#GetPaneBufnr() exists
  → checks current buffer IS the pane buffer
  → nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiPrompt()<CR>
```

Idempotent: `nnoremap` replaces any existing mapping silently.

## Apply AI-Generated Code

`a` in a markdown view buffer:
1. `FindCodeBlocks()` scans for ``` fence pairs (opening `^``` lang` and closing `^``` ` — any line starting with ```)
2. `FindNearestBlock()` selects the block closest to cursor
3. Confirmation: `Apply (<lang>) code block to <file>? (y/N): `
4. `ApplyCodeToFile()` inserts into target file after cursor line

If no fenced blocks are found, fallback extracts the AI response body (text
after "AI:" until blank line) and offers it as a single code block.

Target file and cursor line come from buffer-local `b:vproj_ai_target_file`
and `b:vproj_ai_cursor_line`, set by `CreateView` from the context captured
when the user pressed `A`.

Safety: code is inserted into buffer (not written to disk), all operations
undoable, confirmation required before any insertion.

## Testing

Run: `vim -N -u NONE -S tests/<test_file>.vim`

Both vproj and vproj_ai must be in rtp. Smoke test verifies:
- Both plugins load
- vproj exports `GetPaneBufnr`
- vproj_ai exports `AiPrompt`, `AiCall`, `OnBufEnter`, `AiApplyCode`
- `:VprojAiPrompt` command and `<Plug>` mapping exist
- Pane opens via `vproj#PaneOpen()`
- Basic mode switching works

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
