vim9script

# autoload/vproj_ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) for natural-language
# coding assistance via OpenAI-compatible API with streaming responses.
#
# Two modes:
#   Code mode (default) — AI response applied directly to file at cursor
#   Question mode (?, what, how, why, etc.) — response in floating popup
#
# Force code mode with ! prefix. Force question mode with ? prefix.

# ── Script-level paths (expand('<sfile>') not available in def functions in Vim 9.2) ──
var script_dir: string = expand('<sfile>:p:h')
var chat_script_path: string = script_dir .. '/../../bin/vproj-ai-chat'
var ai_api_url: string = ''
var ai_api_key: string = ''
var ai_model: string = ''

def LogError(msg: string): void
  var entry: dict<any> = {ts: strftime('%Y-%m-%dT%H:%M:%S'), event: 'error', msg: msg}
  writefile([json_encode(entry)], '/tmp/vproj-ai-errors.log', 'a')
enddef

# ── Per-request State ──
var ai_mode: string = 'code'
var ai_target_bufnr: number = -1
var ai_target_cursor_line: number = 1

# ── Streaming State ──
var stream_job: any = v:null
var stream_accumulated: string = ''
var stream_cancelled: bool = false
var stream_full_response: string = ''

# Inject buffer-local A mapping into vproj pane.
# Called via BufEnter + User VprojPaneReady autocmds.
# VprojPaneReady is the guaranteed injection point — BufEnter fires
# during :new before pane_bufnr is assigned, so OnBufEnter returns
# early on first open. VprojPaneReady catches the race.
export def OnBufEnter(): void
  if !exists('g:loaded_vproj')
    return
  endif
  var pane: number = vproj#GetPaneBufnr()
  var is_pane: bool = (pane > 0 && bufnr('%') == pane)
  # Timing gap: during PaneOpen(), BufEnter fires on :new before
  # pane_bufnr is assigned. Fall back to buffer name (always "VPROJ").
  if !is_pane
    if bufname('%') != 'VPROJ'
      return
    endif
  endif
  nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiTerminalChat()<CR>
enddef

# Open terminal-based AI chat. Gathers context, writes temp request file,
# launches :terminal running bin/vproj-ai-chat for multi-turn conversation.
export def AiTerminalChat(): void
  # Self-defense: ensure A mapping exists so next press doesn't fall
  # through to default Vim A (append) which fails with E21 in the
  # nomodifiable pane buffer (BufEnter fires during :new before
  # pane_bufnr is assigned — VprojPaneReady is the guaranteed fix,
  # this is the safety net).
  if exists('g:loaded_vproj')
    var pane: number = vproj#GetPaneBufnr()
    if pane > 0 && bufexists(pane) && bufnr('%') == pane
      sil! nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiTerminalChat()<CR>
    endif
  endif

  if !has('terminal')
    echohl ErrorMsg | echom 'vproj_ai: terminal support required (Vim 8.0+)' | echohl None
    return
  endif

  # Cancel any in-progress stream
  if stream_job != v:null && job_status(stream_job) == 'run'
    StreamCancel()
  endif

  AiConfigure()
  if empty(ai_api_key)
    echohl ErrorMsg | echom 'vproj_ai: no API key. Set g:vproj_ai_api_key or $DEEPSEEK_API_KEY.' | echohl None
    return
  endif

  # Gather context and write to temp file for the chat script
  var ctx: dict<any> = GatherContext()
  var tmpfile: string = tempname()
  var ctx_json: string = json_encode(ctx)
  if writefile([ctx_json], tmpfile) != 0
    echohl ErrorMsg | echom 'vproj_ai: failed to write request (disk full?)' | echohl None
    return
  endif

  # chat_script_path computed at script level (<sfile> not available in def functions)
  if !filereadable(chat_script_path)
    echohl ErrorMsg | echom 'vproj_ai: chat script not found at ' .. chat_script_path | echohl None
    return
  endif

  # Use term_start() to create terminal with env vars in a dict.
  # This avoids shell quoting issues with env command approach.
  var env_vars: dict<string> = {
    VPROJ_AI_API_KEY: ai_api_key,
    VPROJ_AI_API_URL: ai_api_url,
    VPROJ_AI_MODEL: ai_model,
    VPROJ_AI_TMPFILE: tmpfile,
  }
  var opts: dict<any> = {
    term_finish: 'close',
    env: env_vars,
  }
  botright new
  execute 'resize 15'
  var termbuf: number = term_start(['bash', chat_script_path], opts)
  if termbuf == 0
    echohl ErrorMsg | echom 'vproj_ai: failed to start terminal' | echohl None
    LogError('failed to start terminal')
    close
    return
  endif
  tnoremap <buffer> <nowait> <Esc> <C-\><C-n>:bdelete!<CR>

  # Log terminal creation for diagnostic purposes
  var diag_log: string = '/tmp/vproj-ai-errors.log'
  var entry: dict<any> = {ts: strftime('%Y-%m-%dT%H:%M:%S'), event: 'terminal_created',
    bufnr: termbuf, rows: 15, script: chat_script_path}
  writefile([json_encode(entry)], diag_log, 'a')
enddef

def AiConfigure(): void
  var g_key: any = get(g:, 'vproj_ai_api_key', '')
  var g_url: any = get(g:, 'vproj_ai_api_url', '')

  # Validate URL before use (prevent SSRF/credential forwarding)
  def UrlValid(url: string): bool
    return url =~# '^https://'
  enddef

  if type(g_url) == v:t_string && !empty(g_url) && !UrlValid(g_url)
    echohl ErrorMsg | echom 'vproj_ai: only HTTPS URLs allowed for API endpoint' | echohl None
    return
  endif
  if type(g_key) == v:t_string && !empty(g_key)
    ai_api_key = g_key
    ai_api_url = (type(g_url) == v:t_string && !empty(g_url)) ? g_url : 'https://api.deepseek.com/v1/chat/completions'
  else
    var dk: any = getenv('DEEPSEEK_API_KEY')
    if type(dk) == v:t_string && !empty(dk)
      ai_api_key = dk
      ai_api_url = 'https://api.deepseek.com/v1/chat/completions'
    else
      var ok: any = getenv('OPENAI_API_KEY')
      if type(ok) == v:t_string && !empty(ok)
        ai_api_key = ok
        var base: any = getenv('OPENAI_API_BASE')
        if type(base) == v:t_string && !empty(base)
          var base_str: string = base
          if !UrlValid(base_str)
            echohl ErrorMsg | echom 'vproj_ai: only HTTPS URLs allowed for OPENAI_API_BASE' | echohl None
            return
          endif
          if base_str !~ '/chat/completions$'
            base_str = substitute(base_str, '/$', '', '') .. '/chat/completions'
          endif
          ai_api_url = base_str
        else
          ai_api_url = 'https://api.openai.com/v1/chat/completions'
        endif
      endif
    endif
  endif

  # Select model: explicit override > endpoint inference > hardcoded default
  var g_model: any = get(g:, 'vproj_ai_model', '')
  if type(g_model) == v:t_string && !empty(g_model)
    ai_model = g_model
  elseif stridx(ai_api_url, 'openai.com') >= 0
    ai_model = 'gpt-4o-mini'
  else
    ai_model = 'deepseek-chat'
  endif
enddef

def GatherContext(target_bufnr: number = -1): dict<any>
  var ctx: dict<any> = {}
  ctx.cwd = getcwd()
  if exists('*vproj#GetCurrentMode')
    ctx.mode = vproj#GetCurrentMode()
  else
    ctx.mode = 'file'
  endif
  var bufnr: number = target_bufnr > 0 ? target_bufnr : bufnr('%')
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  if bufnr > 0 && bufnr != pane
    ctx.file = fnamemodify(bufname(bufnr), ':p')
    ctx.filetype = getbufvar(bufnr, '&filetype', '')
    var target_win: number = bufwinnr(bufnr)
    if target_win > 0
      ctx.cursor_line = win_execute(target_win, 'echo line(".")')->trim()->str2nr()
      ctx.cursor_col = win_execute(target_win, 'echo col(".")')->trim()->str2nr()
    else
      ctx.cursor_line = 1
      ctx.cursor_col = 1
    endif
    var total: number = get(getbufinfo(bufnr)[0], 'linecount', 0)
    var ctx_start: number = max([1, ctx.cursor_line - 100])
    var ctx_end: number = min([total, ctx.cursor_line + 100])
    ctx.file_lines = getbufline(bufnr, ctx_start, ctx_end)
    ctx.file_line_offset = ctx_start
    ctx.file_total_lines = total
  endif
  return ctx
enddef

def BuildRequestBody(prompt: string, ctx: dict<any>, stream: bool): string
  var system_msg: string = 'You are a coding assistant embedded in Vim. '
  var ctx_file: string = get(ctx, 'file', '')
  system_msg ..= 'The user is editing ' .. (empty(ctx_file) ? 'unknown' : fnamemodify(ctx_file, ':t'))
  system_msg ..= ' (' .. get(ctx, 'filetype', 'text') .. '). '
  system_msg ..= 'Current mode: ' .. get(ctx, 'mode', 'file') .. '. '
  system_msg ..= 'Be concise. ALWAYS wrap code in ``` fences with a language tag (```python, ```vim, etc). '
  system_msg ..= 'The user needs ``` fences to extract and apply your code. '
  system_msg ..= 'Never output code without ``` fences.'
  if has_key(ctx, 'file_lines')
    system_msg ..= ' The file has ' .. get(ctx, 'file_total_lines', 0) .. ' lines.'
  endif

  var messages: string = '[{"role":"system","content":' .. JsonEscape(system_msg) .. '}'
  messages ..= ',{"role":"user","content":' .. JsonEscape(prompt) .. '}]'

  return '{"model":' .. JsonEscape(ai_model) .. ',"messages":' .. messages .. ',"stream":' .. (stream ? 'true' : 'false') .. '}'
enddef

# ── Synchronous API call (fallback, used by tests) ──
export def AiCall(prompt: string, ctx: dict<any>): string
  AiConfigure()
  if empty(ai_api_key)
    echohl ErrorMsg | echom 'vproj_ai: no API key. Set g:vproj_ai_api_key or $DEEPSEEK_API_KEY.' | echohl None
    return ''
  endif
  if !executable('curl')
    echohl ErrorMsg | echom 'vproj_ai: curl is required but not found' | echohl None
    return ''
  endif

  var body: string = BuildRequestBody(prompt, ctx, false)

  var result: string = ''
  var tmpfile: string = tempname()
  var hdrfile: string = tempname()
  try
    if writefile([body], tmpfile) != 0
      echohl ErrorMsg | echom 'vproj_ai: failed to write request body (disk full? permissions?)' | echohl None
      return ''
    endif
    if writefile(['Authorization: Bearer ' .. ai_api_key], hdrfile) != 0
      echohl ErrorMsg | echom 'vproj_ai: failed to write header file' | echohl None
      return ''
    endif
    var cmd: string = 'curl -s -f --connect-timeout 10 -m 60 -X POST ' .. shellescape(ai_api_url)
    cmd ..= ' -H ' .. shellescape('Content-Type: application/json')
    cmd ..= ' -H ' .. shellescape('Authorization: Bearer ' .. ai_api_key)
    cmd ..= ' -d @' .. shellescape(tmpfile)

    var output: string = system(cmd)
    var shell_err: number = v:shell_error

    if shell_err != 0
      var truncated: string = substitute(output, '\n', ' ', 'g')
      if len(truncated) > 200
        truncated = truncated[ : 199] .. '...'
      endif
      echohl ErrorMsg | echom 'vproj_ai: curl error ' .. shell_err .. ' — ' .. truncated | echohl None
      return ''
    endif

    const MAX_RESPONSE: number = 1048576
    if len(output) > MAX_RESPONSE
      output = output[ : MAX_RESPONSE - 1]
    endif

    var content: string = ExtractJsonField(output, 'content')
    if empty(content)
      var err: string = ExtractJsonField(output, 'message')
      var err_truncated: string = empty(err) ? 'empty response' : err
      if len(err_truncated) > 200
        err_truncated = err_truncated[ : 199] .. '...'
      endif
      echohl ErrorMsg | echom 'vproj_ai: API error — ' .. err_truncated | echohl None
      return ''
    endif
    result = content
  catch
    echohl ErrorMsg | echom 'vproj_ai: request failed — ' .. v:exception | echohl None
  finally
    delete(tmpfile)
    delete(hdrfile)
  endtry
  return result
enddef

def JsonEscape(s: string): string
  var result: string = ''
  var ch: string
  for pos in range(len(s))
    ch = s[pos]
    if ch == '\\'
      result ..= '\\\\'
    elseif ch == '"'
      result ..= '\\"'
    elseif ch == "\n"
      result ..= '\\n'
    elseif ch == "\r"
      result ..= '\\r'
    elseif ch == "\t"
      result ..= '\\t'
    elseif ch == "\b"
      result ..= '\\b'
    elseif ch == "\f"
      result ..= '\\f'
    elseif char2nr(ch) <= 0x1f
      result ..= printf('\u%04X', char2nr(ch))
    else
      result ..= ch
    endif
  endfor
  return '"' .. result .. '"'
enddef

def ParseJsonString(s: string): string
  var result: string = ''
  var i: number = 0
  while i < len(s)
    var ch: string = s[i]
    if ch == '\\' && i + 1 < len(s)
      var nextch: string = s[i + 1]
      i += 2
      if nextch == '"'
        result ..= '"'
      elseif nextch == '\\'
        result ..= '\\'
      elseif nextch == '/'
        result ..= '/'
      elseif nextch == 'n'
        result ..= "\n"
      elseif nextch == 'r'
        result ..= "\r"
      elseif nextch == 't'
        result ..= "\t"
      elseif nextch == 'b'
        result ..= "\b"
      elseif nextch == 'f'
        result ..= "\f"
      elseif nextch == 'u'
        if i + 4 <= len(s)
          var hex: string = s[i : i + 3]
          if hex =~ '^[0-9a-fA-F]\{4\}$'
            result ..= nr2char(str2nr(hex, 16))
            i += 4
            continue
          endif
        endif
        result ..= '\u'
      else
        result ..= '\' .. nextch
      endif
      continue
    elseif ch == '"'
      return result
    endif
    result ..= ch
    i += 1
  endwhile
  return result
enddef

def ParseJsonContainer(s: string): string
  var open_ch: string = s[0]
  var close_ch: string = (open_ch == '{') ? '}' : ']'
  var depth: number = 1
  var i: number = 1
  var in_string: bool = false
  while i < len(s) && depth > 0
    var ch: string = s[i]
    if in_string
      if ch == '\\' && i + 1 < len(s)
        i += 2
        continue
      endif
      if ch == '"'
        in_string = false
      endif
    else
      if ch == '"'
        in_string = true
      elseif ch == open_ch
        depth += 1
      elseif ch == close_ch
        depth -= 1
      endif
    endif
    i += 1
  endwhile
  return s[ : i - 1]
enddef

def ParseJsonScalar(s: string): string
  var end_chars: list<number> = [stridx(s, ','), stridx(s, '}'), stridx(s, ']'), stridx(s, "\n")]
  var min_end: number = -1
  for e in end_chars
    if e >= 0 && (min_end < 0 || e < min_end)
      min_end = e
    endif
  endfor
  if min_end < 0
    return s
  elseif min_end == 0
    return ''
  else
    return s[ : min_end - 1]
  endif
enddef

def ExtractJsonField(json: string, field: string): string
  var target: string = '"' .. field .. '"'
  var i: number = 0
  var in_string: bool = false
  var json_len: number = len(json)

  while i < json_len
    var quote_idx: number = stridx(json, '"', i)
    if quote_idx < 0
      break
    endif

    if in_string
      var bs_count: number = 0
      var j: number = quote_idx - 1
      while j >= 0 && json[j] == '\\'
        bs_count += 1
        j -= 1
      endwhile
      if bs_count % 2 == 1
        i = quote_idx + 1
        continue
      endif
      in_string = false
      i = quote_idx + 1
      continue
    endif

    if quote_idx + len(target) <= json_len
      if json[quote_idx : quote_idx + len(target) - 1] == target
        var after: number = quote_idx + len(target)
        while after < json_len && (json[after] == ' ' || json[after] == "\t" || json[after] == "\n" || json[after] == "\r")
          after += 1
        endwhile
        if after < json_len && json[after] == ':'
          var rest: string = substitute(json[after + 1 : ], '^\s*', '', '')
          if empty(rest)
            return ''
          elseif rest[0] == '"'
            return ParseJsonString(rest[1 : ])
          elseif rest[0] == '{' || rest[0] == '['
            return ParseJsonContainer(rest)
          else
            return ParseJsonScalar(rest)
          endif
        endif
      endif
    endif

    in_string = true
    i = quote_idx + 1
  endwhile

  return ''
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Streaming API via job_start + SSE
# ══════════════════════════════════════════════════════════════════════════════

def ProcessStreamChunk(chan: channel, msg: string): void
  if stream_cancelled
    return
  endif
  stream_accumulated ..= msg

  while stridx(stream_accumulated, "\n\n") >= 0
    var parts: list<string> = split(stream_accumulated, "\n\n", 1)
    var frame: string = parts[0]
    stream_accumulated = join(parts[1 : ], "\n\n")

    for line in split(frame, "\n")
      if line !~ '^data:\s*'
        continue
      endif
      var json_str: string = substitute(line, '^data:\s*', '', '')
      if json_str == '[DONE]'
        return
      endif
      try
        var data: any = json_decode(json_str)
        if type(data) == v:t_dict
          var choices: any = get(data, 'choices', [])
          if type(choices) == v:t_list && len(choices) > 0
            var choice: any = choices[0]
            if type(choice) == v:t_dict
              var delta: any = get(choice, 'delta', {})
              if type(delta) == v:t_dict
                var content: string = get(delta, 'content', '')
                if !empty(content)
                  stream_full_response ..= content
                endif
              endif
            endif
          endif
        endif
      catch
        # Malformed JSON or partial frame — skip, wait for more data
      endtry
    endfor
  endwhile
enddef

def StreamJobExit(job: job, status: number): void
  if job != stream_job
    return
  endif

  if stream_cancelled
    echom 'vproj_ai: cancelled'
  elseif status != 0
    echohl ErrorMsg | echom 'vproj_ai: API call failed — status ' .. status | echohl None
  else
    if ai_mode == 'question' || ai_target_bufnr <= 0 || !bufexists(ai_target_bufnr)
      ShowPopup(stream_full_response)
    else
      var blocks: list<dict<any>> = ExtractCodeBlocks(stream_full_response)
      ApplyCode(ai_target_bufnr, blocks, ai_target_cursor_line)
    endif
  endif

  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false
enddef

def BuildStreamCommand(prompt: string, ctx: dict<any>): list<string>
  var body: string = BuildRequestBody(prompt, ctx, true)
  var hdr: string = 'Authorization: Bearer ' .. ai_api_key
  return ['curl', '--no-buffer', '-s', '-f',
    '--connect-timeout', '10', '-m', '120',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', hdr,
    '-d', body,
    ai_api_url]
enddef

def AiCallStream(prompt: string, ctx: dict<any>): bool
  AiConfigure()
  if empty(ai_api_key)
    echohl ErrorMsg | echom 'vproj_ai: no API key' | echohl None
    return false
  endif
  if !executable('curl')
    echohl ErrorMsg | echom 'vproj_ai: curl required' | echohl None
    return false
  endif

  var cmd: list<string> = BuildStreamCommand(prompt, ctx)

  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  var opts: dict<any> = {}
  opts.mode = 'raw'
  opts.out_cb = (chan, msg) => ProcessStreamChunk(chan, msg)
  opts.exit_cb = StreamJobExit
  opts.timeout = 120000

  stream_job = job_start(cmd, opts)
  if job_status(stream_job) == 'fail'
    stream_job = v:null
    echohl ErrorMsg | echom 'vproj_ai: failed to start API request' | echohl None
    return false
  endif

  return true
enddef

def StreamCancel(): void
  if stream_job == v:null || job_status(stream_job) != 'run'
    return
  endif
  stream_cancelled = true
  job_stop(stream_job)
enddef

export def StreamCancelCmd(): void
  if stream_job != v:null
    StreamCancel()
    echom 'vproj_ai: stream cancelled'
  endif
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Mode Detection
# ══════════════════════════════════════════════════════════════════════════════

def DetectMode(prompt: string): string
  if empty(prompt)
    return 'code'
  endif
  if prompt[0] == '!'
    return 'code'
  endif
  if prompt[0] == '?'
    return 'question'
  endif
  var lower: string = tolower(prompt)
  var question_words: list<string> = ['what', 'how', 'why', 'explain', 'describe', 'where', 'when', 'who', 'which', 'can you', 'could you', 'would you', 'is it', 'are there', 'does ', 'do you', 'show me', 'tell me', 'find ']
  for w in question_words
    if lower =~ '^' .. w || lower =~ '\s' .. w
      return 'question'
    endif
  endfor
  if stridx(prompt, '?') >= 0
    return 'question'
  endif
  return 'code'
enddef

# Strip mode-forcing prefix (! or ?) from prompt.
def StripPrefix(prompt: string): string
  if empty(prompt)
    return prompt
  endif
  if prompt[0] == '!' || prompt[0] == '?'
    var stripped: string = prompt[1 : ]
    return substitute(stripped, '^\s*', '', '')
  endif
  return prompt
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Code Extraction & Application
# ══════════════════════════════════════════════════════════════════════════════

def ExtractCodeBlocks(text: string): list<dict<any>>
  var blocks: list<dict<any>> = []
  var lines: list<string> = split(text, "\n")
  var i: number = 0
  while i < len(lines)
    if lines[i] =~ '^```'
      var lang: string = substitute(lines[i], '^```\s*', '', '')
      i += 1
      var code_lines: list<string> = []
      while i < len(lines)
        if lines[i] =~ '^```'
          var code: string = join(code_lines, "\n")
          if !empty(code)
            blocks->add({language: lang, code: code})
          endif
          break
        endif
        code_lines->add(lines[i])
        i += 1
      endwhile
    endif
    i += 1
  endwhile
  return blocks
enddef

def ApplyCode(target_bufnr: number, blocks: list<dict<any>>, cursor_line: number): void
  var code: string = ''
  var lang: string = 'code'

  if empty(blocks)
    code = stream_full_response
  else
    code = blocks[0].code
    lang = get(blocks[0], 'language', 'code')
  endif

  if empty(code)
    echom 'vproj_ai: no code in response'
    return
  endif

  if !bufexists(target_bufnr)
    echohl ErrorMsg | echom 'vproj_ai: target buffer no longer exists' | echohl None
    return
  endif

  if !getbufvar(target_bufnr, '&modifiable')
    echohl ErrorMsg | echom 'vproj_ai: target buffer not modifiable' | echohl None
    return
  endif

  var code_lines: list<string> = split(code, "\n")
  var insert_at: number = cursor_line > 0 ? cursor_line : 1

  # Apply directly to target buffer — no window switch, stay in the pane
  appendbufline(target_bufnr, insert_at, code_lines)
  setbufvar(target_bufnr, '&modified', 1)

  var fname: string = fnamemodify(bufname(target_bufnr), ':t')
  var label: string = empty(lang) || lang == 'code' ? '' : ' (' .. lang .. ')'
  echom 'vproj_ai: applied ' .. len(code_lines) .. ' lines to ' .. fname .. label .. ' (u to undo)'
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Floating Popup for Question Mode
# ══════════════════════════════════════════════════════════════════════════════

def PopupFilter(winid: number, key: string): bool
  if key == 'q' || key == "\<Esc>" || key == "\<C-C>"
    popup_close(winid)
    return true
  endif
  return false
enddef

def ShowPopup(text: string): void
  var lines: list<string> = split(text, "\n")
  var max_width: number = 0
  for l in lines
    var w: number = strdisplaywidth(l)
    if w > max_width
      max_width = w
    endif
  endfor

  var popup_width: number = min([max([max_width + 2, 40]), 80])
  var popup_height: number = min([len(lines), 20])

  var opts: dict<any> = {
    title: ' vproj_ai (q/Esc to close) ',
    line: 'cursor',
    col: 'center',
    pos: 'center',
    wrap: true,
    close: 'button',
    padding: [1, 1, 1, 1],
    border: [1, 1, 1, 1],
    borderchars: ['-', '|', '-', '|', '+', '+', '+', '+'],
    filter: PopupFilter,
    mapping: false,
    scrollbar: true,
    maxheight: 20,
    minwidth: 40,
    maxwidth: 80,
    cursorline: 0,
  }

  popup_create(lines, opts)
  echom 'vproj_ai: response in popup (q or Esc to close)'
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Public API — AI Prompt
# ══════════════════════════════════════════════════════════════════════════════

# Entry point from A key mapping. Uses input() to get the prompt.
# Safe because <Cmd> mappings don't consume typeahead.
export def AiPromptFromKey(): void
  var prompt: string = input('vproj_ai: ')
  redraw
  if empty(prompt)
    return
  endif
  AiPrompt(prompt)
enddef

export def AiPrompt(prompt_from_cmdline: string = ''): void
  # Cancel any in-progress stream
  if stream_job != v:null && job_status(stream_job) == 'run'
    StreamCancel()
  endif

  # Reset state
  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  var prompt: string = prompt_from_cmdline
  if empty(prompt)
    return
  endif

  # Detect mode and strip prefix before sending to API
  ai_mode = DetectMode(prompt)
  prompt = StripPrefix(prompt)
  if empty(prompt)
    return
  endif

  # Find target file buffer (the file being edited, not the pane)
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  var file_bufnr: number = bufnr('#')
  if file_bufnr <= 0 || file_bufnr == pane
    for info in getbufinfo({buflisted: true})
      if info.bufnr != pane
        file_bufnr = info.bufnr
        break
      endif
    endfor
  endif
  ai_target_bufnr = file_bufnr

  var ctx: dict<any> = GatherContext(file_bufnr)
  ai_target_cursor_line = get(ctx, 'cursor_line', 1)

  var ctx_file: string = get(ctx, 'file', '')
  var display_file: string = empty(ctx_file) ? 'unknown' : fnamemodify(ctx_file, ':t')
  var mode_label: string = ai_mode == 'question' ? ' (question)' : ''
  echom 'vproj_ai: streaming' .. mode_label .. ' for ' .. display_file .. '...'

  if !AiCallStream(prompt, ctx)
    echohl ErrorMsg | echom 'vproj_ai: failed to start stream' | echohl None
  endif
enddef
