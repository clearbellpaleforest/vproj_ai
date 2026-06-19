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
ai_api_url, ai_api_key, ai_last_prompt, ai_last_response, ai_history
ai_conversation_bufnr, ai_conversation_ctx
stream_job, stream_tmpfile, stream_accumulated
```

No session persistence. No filesystem writes for state. History is in-memory
only (last 5 exchanges).

## Public API

| Function | Purpose |
|----------|---------|
| `vproj_ai#AiPrompt()` | Gather context, prompt user, call API, create conversation view |
| `vproj_ai#AiCall(prompt, ctx)` | POST to OpenAI-compatible API via curl |
| `vproj_ai#OnBufEnter()` | Inject `A` mapping when entering vproj pane buffer |
| `vproj_ai#AiSendFollowup()` | Send follow-up from conversation `> ` prompt line |
| `vproj_ai#AiApplyCode()` | Find nearest code fence, confirm, apply to target file |
| `vproj_ai#AiCancelStream()` | Kill active streaming job, append cancellation note |

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
| `GatherContext()` | Build context dict (mode, file, cursor, selection, history) |
| `JsonEscape(s)` | Escape string for JSON embedding |
| `ExtractJsonField(json, field)` | Walk JSON string to extract field value |
| `RouteResponse(text)` | Classify response → qfix, markdown view, or echom |
| `CreateView(text, filetype)` | Open botright vnew with content, q/a-to-close/apply |
| `CreateConversationView(prompt, response)` | Open conversation buffer with `> ` prompt |
| `FindCodeBlocks()` | Scan buffer for ``` fence pairs, return block list |
| `FindNearestBlock(blocks, cursor_lnum)` | Select code block closest to cursor |
| `ApplyCodeToFile(file, code, ctx)` | Insert code into target file (visual→cursor→append) |
| `BuildRequestBody(prompt, ctx, stream)` | Build JSON request body (shared by AiCall/AiCallStream) |
| `AiCallStream(prompt, ctx, bufnr)` | Start async curl job with SSE streaming callbacks |
| `StreamOutCallback(ch, msg)` | Parse SSE data: lines, append content deltas to buffer |
| `StreamExitCallback(ch, exit_code)` | Cleanup tmpfile, finalize buffer, record history |
| `StreamErrCallback(ch, msg)` | Show stream error in buffer |
| `ParseSSEDelta(line)` | Extract content delta from SSE data: payload |

## Response Routing

AI responses are classified:
- **`file:line:` patterns** (2+ matches) → `setqflist()` + `vproj#SwitchMode('qfix')`
- **``` code fences** → `CreateView(text, 'markdown')` in a split
- **Short** (1-2 lines, no fences) → `echom`
- **Long fallback** → `CreateView(text, 'markdown')`, echo first 10 lines on failure

## OnBufEnter Mapping Injection

```
BufEnter → vproj_ai#OnBufEnter()
  → checks vproj#GetPaneBufnr() exists
  → checks current buffer IS the pane buffer
  → nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiPrompt()<CR>
```

Idempotent: `nnoremap` replaces any existing mapping silently.

## Multi-Turn Conversation

AiPrompt creates a conversation scratch buffer instead of a one-shot view.
Buffer format:

```
===============================================================================
 AI Assistant                                                     q to close
───────────────────────────────────────────────────────────────────────────────

User: <prompt>

AI: <response>

> _
```

Buffer-local mappings:
| Key | Action |
|-----|--------|
| `q` | Close buffer |
| `<CR>` | Send follow-up from `> ` line |
| `a` | Apply nearest code block to original file |

Context is frozen at conversation start (`ai_conversation_ctx`). Follow-ups
send full history (up to 5 exchanges) to the API for continuity.

## Apply AI-Generated Code

`a` in a conversation or markdown view buffer:
1. `FindCodeBlocks()` scans for ``` fence pairs
2. `FindNearestBlock()` selects the block closest to cursor
3. Confirmation: `Apply (<lang>) code block to <file>? (y/N): `
4. `ApplyCodeToFile()` inserts into target file

Insertion strategy (priority order):
1. **Visual selection active** in context → replace selection
2. **Cursor position known** → insert after cursor line
3. **Fallback** → append at end of file

Safety: code is inserted into buffer (not written to disk), all operations
undoable, confirmation required before any insertion.

## Streaming Responses

AiPrompt and AiSendFollowup stream tokens in real-time via `job_start()` +
SSE parsing instead of blocking on `system(curl ...)`. The conversation
buffer appears immediately with an "AI: ..." placeholder; tokens replace
the placeholder as they arrive.

### Architecture

```
AiPrompt → CreateConversationView('...') → AiCallStream → job_start
                                                              ↓
                                         StreamOutCallback: parse SSE data:
                                         lines, extract delta.content,
                                         append to buffer → redraw
                                                              ↓
                                         StreamExitCallback: add "> ",
                                         record history, cleanup
```

### SSE Format

`data: {"choices":[{"delta":{"content":"token"}}]}` — parsed by
`ParseSSEDelta()` which extracts `choices[0].delta.content` using
`ExtractJsonField` twice.

### Cancel

`<C-c>` in the conversation buffer calls `AiCancelStream()`, which:
- Kills the curl job via `job_stop()`
- Deletes the tempfile
- Appends "(cancelled)" to the buffer
- Adds a fresh `> ` prompt

`q` also kills any active stream before closing.

### Error Handling

| Condition | Behavior |
|-----------|----------|
| curl exits non-zero | `(curl error N)` shown in buffer |
| No content in stream | Placeholder replaced with `(empty response)` |
| Buffer closed during stream | Callbacks detect `!bufexists()` and return silently |
| Job fails to start | `echohl ErrorMsg` echo, stream_job reset to v:null |

## Testing

Run: `vim -N -u NONE -S tests/<test_file>.vim`

Both vproj and vproj_ai must be in rtp. Smoke test verifies:
- Both plugins load
- vproj exports `GetPaneBufnr`
- vproj_ai exports `AiPrompt`, `AiCall`, `OnBufEnter`, `AiSendFollowup`, `AiApplyCode`, `AiCancelStream`
- `:VprojAiPrompt` command and `<Plug>` mapping exist
- Pane opens via `vproj#PaneOpen()`
- Basic mode switching works
