vim9script

# autoload/vproj_ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) and natural-language
# coding assistance via OpenAI-compatible API with streaming responses.

# ── Persistent State ──
var ai_api_url: string = ''
var ai_api_key: string = ''
var ai_model: string = ''
var ai_conversation_bufnr: number = -1
var ai_conversation_history: list<dict<any>> = []
var ai_conversation_ctx: dict<any> = {}

# ── Streaming State ──
var stream_job: any = v:null
var stream_accumulated: string = ''
var stream_line_nr: number = 0
var stream_line_text: string = ''
var stream_cancelled: bool = false
var stream_full_response: string = ''

# Inject buffer-local A mapping into vproj pane.
export def OnBufEnter(): void
  if !exists('g:loaded_vproj')
    return
  endif
  var pane: number = vproj#GetPaneBufnr()
  var is_pane: bool = (pane > 0 && bufnr('%') == pane)
  if !is_pane
    return
  endif
  nnoremap <buffer> <silent> A :VprojAiPrompt<Space>
enddef

def AiConfigure(): void
  var g_key: any = get(g:, 'vproj_ai_api_key', '')
  var g_url: any = get(g:, 'vproj_ai_api_url', '')
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
          if base_str !~ '/chat/completions$'
            base_str = substitute(base_str, '/$', '', '') .. '/v1/chat/completions'
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
  elseif !empty(ai_model)
    # Already configured — skip endpoint inference
    return
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
  var hist: list<any> = get(ctx, 'history', [])
  const MAX_HISTORY: number = 20
  if len(hist) > MAX_HISTORY
    hist = hist[len(hist) - MAX_HISTORY : ]
  endif
  for entry in hist
    messages ..= ',{"role":"user","content":' .. JsonEscape(get(entry, 'prompt', '')) .. '}'
    messages ..= ',{"role":"assistant","content":' .. JsonEscape(get(entry, 'response', '')) .. '}'
  endfor
  messages ..= ',{"role":"user","content":' .. JsonEscape(prompt) .. '}]'

  return '{"model":"' .. ai_model .. '","messages":' .. messages .. ',"stream":' .. (stream ? 'true' : 'false') .. '}'
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
    cmd ..= ' --header @' .. shellescape(hdrfile)
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
    return content
  catch
    echohl ErrorMsg | echom 'vproj_ai: request failed — ' .. v:exception | echohl None
    return ''
  finally
    delete(tmpfile)
    delete(hdrfile)
  endtry
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

def AppendStreamToken(token: string): void
  if !bufexists(ai_conversation_bufnr) || stream_cancelled
    return
  endif
  var parts: list<string> = split(token, "\n", 1)
  stream_line_text ..= parts[0]
  setbufline(ai_conversation_bufnr, stream_line_nr, stream_line_text)
  if len(parts) > 1
    for i in range(1, len(parts) - 1)
      stream_line_nr += 1
      stream_line_text = parts[i]
      appendbufline(ai_conversation_bufnr, stream_line_nr - 1, [stream_line_text])
    endfor
  endif
  redraw
enddef

def ProcessStreamChunk(chan: channel, msg: string): void
  if stream_cancelled || !bufexists(ai_conversation_bufnr)
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
                  AppendStreamToken(content)
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
    if bufexists(ai_conversation_bufnr)
      setbufvar(ai_conversation_bufnr, '&modifiable', 1)
      var last: number = len(getbufline(ai_conversation_bufnr, 1, '$'))
      appendbufline(ai_conversation_bufnr, last, ['', '[cancelled]'])
      setbufvar(ai_conversation_bufnr, '&modifiable', 0)
    endif
  elseif status != 0
    if bufexists(ai_conversation_bufnr)
      setbufvar(ai_conversation_bufnr, '&modifiable', 1)
      var last: number = len(getbufline(ai_conversation_bufnr, 1, '$'))
      appendbufline(ai_conversation_bufnr, last, ['', '[error: API call failed — status ' .. status .. ']'])
      setbufvar(ai_conversation_bufnr, '&modifiable', 0)
    endif
  else
    # Success — save full response to history
    if len(ai_conversation_history) > 0
      ai_conversation_history[len(ai_conversation_history) - 1].response = stream_full_response
    endif
  endif

  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  if bufexists(ai_conversation_bufnr)
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
    setbufvar(ai_conversation_bufnr, '&modified', 0)
    redraw
  endif
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
  if ai_conversation_bufnr <= 0 || !bufexists(ai_conversation_bufnr)
    return false
  endif

  var cmd: list<string> = BuildStreamCommand(prompt, ctx)

  # Prepare streaming state
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false
  stream_line_nr = len(getbufline(ai_conversation_bufnr, 1, '$'))
  stream_line_text = getbufline(ai_conversation_bufnr, stream_line_nr)[0]

  # Buffer must be modifiable for streaming callbacks
  setbufvar(ai_conversation_bufnr, '&modifiable', 1)

  var opts: dict<any> = {}
  opts.mode = 'raw'
  opts.out_cb = (chan, msg) => ProcessStreamChunk(chan, msg)
  opts.exit_cb = StreamJobExit
  opts.timeout = 120000

  stream_job = job_start(cmd, opts)
  if job_status(stream_job) == 'fail'
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
    stream_job = v:null
    stream_line_nr = 0
    stream_line_text = ''
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
# Public API — AI Prompt & Conversation
# ══════════════════════════════════════════════════════════════════════════════

export def AiPrompt(prompt_from_cmdline: string = ''): void
  # Cancel any in-progress stream
  if stream_job != v:null && job_status(stream_job) == 'run'
    StreamCancel()
  endif

  # If conversation is already active, close old buffer and reset
  if ai_conversation_bufnr > 0 && bufexists(ai_conversation_bufnr)
    execute 'bwipeout! ' .. ai_conversation_bufnr
  endif
  ai_conversation_bufnr = -1
  ai_conversation_history = []
  ai_conversation_ctx = {}
  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  # Capture context from the file the user was editing (alternate buffer).
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

  var ctx: dict<any> = GatherContext(file_bufnr)
  ai_conversation_ctx = ctx

  var prompt: string = ''
  if empty(prompt_from_cmdline)
    return
  endif
  prompt = prompt_from_cmdline
  if empty(prompt)
    return
  endif
  var ctx_file: string = get(ctx, 'file', '')
  var ctx_lines: number = has_key(ctx, 'file_lines') ? len(ctx.file_lines) : 0
  var display_file: string = empty(ctx_file) ? 'unknown' : fnamemodify(ctx_file, ':t')
  echom 'vproj_ai: sending ' .. display_file .. ' (' .. ctx_lines .. ' lines)...'

  # Create conversation buffer (callbacks need it to exist)
  ai_conversation_bufnr = CreateConversationView(ctx)
  if ai_conversation_bufnr <= 0
    return
  endif

  # Render initial view: header + user prompt + "AI: " placeholder
  var header_lines: list<string> = []
  var hdr_width: number = winwidth(0)
  header_lines->add(repeat('=', hdr_width))
  header_lines->add(' AI Assistant' .. repeat(' ', hdr_width - 13 - 14) .. 'q to close  Ctrl-C to cancel')
  header_lines->add(repeat('-', hdr_width))
  header_lines->add('')
  header_lines->add('User: ' .. prompt)
  header_lines->add('')
  header_lines->add('AI: ')

  setbufvar(ai_conversation_bufnr, '&modifiable', 1)
  deletebufline(ai_conversation_bufnr, 1, '$')
  setline(1, header_lines)
  setbufvar(ai_conversation_bufnr, '&modified', 0)

  # Record prompt in history (response filled on stream completion)
  ai_conversation_history->add({prompt: prompt, response: ''})

  # Start streaming — returns immediately, response rendered via callbacks.
  # Leave modifiable=1; callbacks and StreamJobExit manage it.
  if !AiCallStream(prompt, ctx)
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  endif
  redraw!
enddef

export def CreateConversationView(ctx: dict<any>): number
  # Move to a non-pane window before splitting, so the split happens in
  # the file area instead of crushing the narrow vproj pane.
  var pane_wid: number = exists('*vproj#GetPaneBufnr') ? win_getid(bufwinnr(vproj#GetPaneBufnr())) : 0
  var current_tab: number = tabpagenr()
  var moved: bool = false
  for info in getwininfo()
    if info.winid != pane_wid && get(info, 'tabpage', 0) == current_tab
      win_gotoid(info.winid)
      moved = true
      break
    endif
  endfor

  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  var orig_winid: number = win_getid()
  set winminwidth=1 winminheight=1
  try
    if moved
      botright new
    else
      # Only the pane exists — create the file area first
      botright vnew
    endif
  catch
    if pane_wid > 0
      win_gotoid(pane_wid)
    endif
    echohl ErrorMsg
    echom 'vproj_ai: cannot create window — ' .. v:exception
    echohl None
    return -1
  finally
    call setwinvar(orig_winid, '&winminwidth', saved_minwidth)
    call setwinvar(orig_winid, '&winminheight', saved_minheight)
  endtry
  var bufnr: number = bufnr('%')
  setbufvar(bufnr, '&buftype', 'nofile')
  setbufvar(bufnr, '&bufhidden', 'wipe')
  setbufvar(bufnr, '&swapfile', 0)
  setbufvar(bufnr, '&buflisted', 0)
  setbufvar(bufnr, '&modifiable', 0)
  setbufvar(bufnr, '&syntax', 'markdown')

  b:vproj_ai_target_file = get(ctx, 'file', '')
  b:vproj_ai_cursor_line = get(ctx, 'cursor_line', 1)

  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> a :call vproj_ai#AiApplyCode()<CR>
  nnoremap <buffer> <silent> A :call vproj_ai#AiApplyCode()<CR>
  nnoremap <buffer> <silent> <CR> :call vproj_ai#SendFollowup()<CR>
  nnoremap <buffer> <silent> <C-C> <Cmd>call vproj_ai#StreamCancelCmd()<CR>

  return bufnr
enddef

def RenderConversation(bufnr: number): void
  if !bufexists(bufnr) | return | endif
  if stream_job != v:null && job_status(stream_job) == 'run'
    return
  endif

  var cur_win: number = bufwinnr(bufnr)
  if cur_win <= 0 | return | endif

  win_gotoid(win_getid(cur_win))
  setbufvar(bufnr, '&modifiable', 1)
  deletebufline(bufnr, 1, '$')

  var lines: list<string> = []
  var hdr_width: number = winwidth(0)
  lines->add(repeat('=', hdr_width))
  lines->add(' AI Assistant' .. repeat(' ', hdr_width - 13 - 14) .. 'q to close  Ctrl-C to cancel')
  lines->add(repeat('-', hdr_width))

  for entry in ai_conversation_history
    lines->add('')
    lines->add('User: ' .. get(entry, 'prompt', ''))
    lines->add('')
    var resp: string = get(entry, 'response', '')
    if empty(resp)
      lines->add('AI: ')
    elseif stridx(resp, "\n") >= 0
      lines->add('AI:')
      for ln in split(resp, "\n")
        lines->add(ln)
      endfor
    else
      lines->add('AI: ' .. resp)
    endif
  endfor

  setline(1, lines)
  setbufvar(bufnr, '&modifiable', 0)
  setbufvar(bufnr, '&modified', 0)
  stopinsert
  cursor(line('$'), 1)
enddef

export def SendFollowup(): void
  if ai_conversation_bufnr <= 0 || !bufexists(ai_conversation_bufnr)
    echom 'vproj_ai: no active conversation'
    return
  endif
  if stream_job != v:null && job_status(stream_job) == 'run'
    echom 'vproj_ai: API call in progress — wait or press Ctrl-C to cancel'
    return
  endif

  # Focus conversation buffer
  if bufnr('%') != ai_conversation_bufnr
    var conv_win: number = bufwinnr(ai_conversation_bufnr)
    if conv_win > 0
      win_gotoid(win_getid(conv_win))
    endif
  endif

  inputsave()
  try
    var prompt: string = input('> ')
  finally
    inputrestore()
  endtry
  if empty(prompt) | return | endif
  if !bufexists(ai_conversation_bufnr) | return | endif

  # Append user prompt + AI placeholder to buffer
  setbufvar(ai_conversation_bufnr, '&modifiable', 1)
  var last: number = len(getbufline(ai_conversation_bufnr, 1, '$'))
  appendbufline(ai_conversation_bufnr, last, ['', 'User: ' .. prompt, '', 'AI: '])
  setbufvar(ai_conversation_bufnr, '&modified', 0)

  # Scroll to bottom
  var cw: number = bufwinnr(ai_conversation_bufnr)
  if cw > 0
    win_execute(cw, 'normal! G')
  endif

  echom 'vproj_ai: streaming...'

  # Add history for this follow-up
  ai_conversation_ctx.history = copy(ai_conversation_history)
  ai_conversation_history->add({prompt: prompt, response: ''})

  if !AiCallStream(prompt, ai_conversation_ctx)
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  endif
enddef

export def HandleConvBufWipeout(wiped_bufnr: number): void
  if ai_conversation_bufnr > 0 && ai_conversation_bufnr == wiped_bufnr
    if stream_job != v:null && job_status(stream_job) == 'run'
      StreamCancel()
    endif
    ai_conversation_bufnr = -1
    ai_conversation_history = []
    ai_conversation_ctx = {}
    stream_job = v:null
    stream_accumulated = ''
    stream_full_response = ''
    stream_cancelled = false
  endif
enddef

# Apply AI-generated code from the markdown view buffer.
export def AiApplyCode(): void
  var blocks: list<dict<any>> = FindCodeBlocks()
  if empty(blocks)
    # No fenced blocks. Use all non-blank lines as the code body.
    var code_lines: list<string> = []
    for ln in getline(1, '$')
      if !empty(ln)
        code_lines->add(ln)
      endif
    endfor
    if empty(code_lines)
      echom 'vproj_ai: no code found in buffer'
      return
    endif
    var code: string = join(code_lines, "\n")
    var lang: string = 'code'
    if code =~ '^#!/' | lang = 'script' | endif

    var target_file: string = get(b:, 'vproj_ai_target_file', '')
    var cursor_line: number = get(b:, 'vproj_ai_cursor_line', 1)
    if empty(target_file)
      echohl ErrorMsg | echom 'vproj_ai: no target file known' | echohl None
      return
    endif

    inputsave()
    var confirm: string = ''
    try
      confirm = input('Apply (' .. lang .. ') to ' .. fnamemodify(target_file, ':t') .. '? (y/N): ')
    finally
      inputrestore()
    endtry
    if confirm !~? '^y\(es\)\?$'
      echom 'vproj_ai: cancelled'
      return
    endif
    ApplyCodeToFile(target_file, code, cursor_line)
    return
  endif

  var nearest: dict<any> = FindNearestBlock(blocks, line('.'))
  if empty(nearest)
    echom 'vproj_ai: could not find a code block'
    return
  endif

  var target_file: string = get(b:, 'vproj_ai_target_file', '')
  var cursor_line: number = get(b:, 'vproj_ai_cursor_line', 1)
  if empty(target_file)
    target_file = expand('%:p')
  endif
  if empty(target_file)
    echohl ErrorMsg | echom 'vproj_ai: no target file known' | echohl None
    return
  endif

  var lang: string = get(nearest, 'language', 'code')
  var code: string = get(nearest, 'code', '')
  if empty(code)
    echom 'vproj_ai: empty code block'
    return
  endif

  inputsave()
  var confirm: string = ''
  try
    confirm = input('Apply (' .. lang .. ') code block to ' .. fnamemodify(target_file, ':t') .. '? (y/N): ')
  finally
    inputrestore()
  endtry
  if confirm !~? '^y\(es\)\?$'
    echom 'vproj_ai: cancelled'
    return
  endif

  ApplyCodeToFile(target_file, code, cursor_line)
enddef

def FindCodeBlocks(): list<dict<any>>
  var blocks: list<dict<any>> = []
  var i: number = 1
  var last: number = line('$')
  while i <= last
    var ln: string = getline(i)
    if ln =~ '^```'
      var lang: string = substitute(ln, '^```\s*', '', '')
      var start: number = i
      i += 1
      var code_lines: list<string> = []
      while i <= last
        if getline(i) =~ '^```'
          var code: string = join(code_lines, "\n")
          if !empty(code)
            blocks->add({start_lnum: start, end_lnum: i, language: lang, code: code})
          endif
          break
        endif
        code_lines->add(getline(i))
        i += 1
      endwhile
    endif
    i += 1
  endwhile
  return blocks
enddef

def FindNearestBlock(blocks: list<dict<any>>, cursor_lnum: number): dict<any>
  var nearest: dict<any> = {}
  var min_dist: number = 0
  for b in blocks
    var start: number = get(b, 'start_lnum', 0)
    var end: number = get(b, 'end_lnum', 0)
    var dist: number
    if cursor_lnum >= start && cursor_lnum <= end
      dist = 0
    else
      var dist_start: number = abs(cursor_lnum - start)
      var dist_end: number = abs(cursor_lnum - end)
      dist = min([dist_start, dist_end])
    endif
    if empty(nearest) || dist < min_dist
      nearest = b
      min_dist = dist
    endif
  endfor
  return nearest
enddef

def ApplyCodeToFile(file: string, code: string, cursor_line: number): void
  var target_buf: number = bufnr(file)
  var target_win: number = 0
  if target_buf > 0
    target_win = bufwinnr(target_buf)
  endif

  var saved_win: number = win_getid()

  if target_win > 0
    win_gotoid(win_getid(target_win))
  elseif target_buf > 0
    execute 'sbuffer ' .. target_buf
  else
    execute 'split ' .. fnameescape(file)
    target_buf = bufnr('%')
  endif

  if !&modifiable
    echohl ErrorMsg | echom 'vproj_ai: buffer not modifiable' | echohl None
    if win_id2win(saved_win) > 0
      win_gotoid(saved_win)
    endif
    return
  endif
  if &modified
    echohl WarningMsg | echom 'vproj_ai: warning — buffer has unsaved changes' | echohl None
  endif

  if cursor_line >= 0
    call append(cursor_line, split(code, "\n"))
  else
    call append(line('$'), split(code, "\n"))
  endif

  setbufvar(bufnr('%'), '&modified', 1)

  if win_id2win(saved_win) > 0
    win_gotoid(saved_win)
  endif
enddef
