vim9script

# autoload/vproj_ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) and natural-language
# coding assistance via OpenAI-compatible API.

# State
var ai_api_url: string = ''
var ai_api_key: string = ''
var ai_last_prompt: string = ''
var ai_last_response: string = ''
var ai_history: list<dict<string>> = []
var ai_conversation_bufnr: number = -1
var ai_conversation_ctx: dict<any> = {}
var stream_job: any = v:null
var stream_tmpfile: string = ''
var stream_accumulated: string = ''

# Inject buffer-local A mapping into vproj pane.
export def OnBufEnter(): void
  if !exists('*vproj#GetPaneBufnr')
    return
  endif
  var pane: number = vproj#GetPaneBufnr()
  if pane <= 0 || bufnr('%') != pane
    return
  endif
  nnoremap <buffer> <silent> A <Cmd>call vproj_ai#AiPrompt()<CR>
enddef

def AiConfigure(): void
  if !empty(ai_api_url) && !empty(ai_api_key)
    return
  endif
  var g_key: any = get(g:, 'vproj_ai_api_key', '')
  var g_url: any = get(g:, 'vproj_ai_api_url', '')
  if type(g_key) == v:t_string && !empty(g_key)
    ai_api_key = g_key
    ai_api_url = (type(g_url) == v:t_string && !empty(g_url)) ? g_url : 'https://api.deepseek.com/v1/chat/completions'
    return
  endif
  var dk: any = getenv('DEEPSEEK_API_KEY')
  if type(dk) == v:t_string && !empty(dk)
    ai_api_key = dk
    ai_api_url = 'https://api.deepseek.com/v1/chat/completions'
    return
  endif
  var ok: any = getenv('OPENAI_API_KEY')
  if type(ok) == v:t_string && !empty(ok)
    ai_api_key = ok
    var base: any = getenv('OPENAI_API_BASE')
    ai_api_url = (type(base) == v:t_string && !empty(base)) ? base : 'https://api.openai.com/v1/chat/completions'
  endif
enddef

def GatherContext(): dict<any>
  var ctx: dict<any> = {}
  ctx.cwd = getcwd()
  if exists('*vproj#GetCurrentMode')
    ctx.mode = vproj#GetCurrentMode()
  else
    ctx.mode = 'file'
  endif
  var bufnr: number = bufnr('%')
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  if bufnr != pane
    ctx.file = expand('%:p')
    ctx.filetype = &filetype
    var line_num: number = line('.')
    ctx.cursor_line = line_num
    ctx.cursor_col = col('.')
    var vis_mode: string = visualmode()
    if vis_mode != ''
      var start: list<number> = getpos("'<")
      var end: list<number> = getpos("'>")
      ctx.visual_selection = getline(start[1], end[1])
      ctx.visual_range = [start[1], end[1]]
    endif
    var total: number = line('$')
    var ctx_start: number = max([1, line_num - 100])
    var ctx_end: number = min([total, line_num + 100])
    ctx.file_lines = getline(ctx_start, ctx_end)
    ctx.file_line_offset = ctx_start
    ctx.file_total_lines = total
  endif
  if !empty(ai_history)
    ctx.history = ai_history
  endif
  return ctx
enddef

def BuildRequestBody(prompt: string, ctx: dict<any>, stream: bool): string
  var system_msg: string = 'You are a coding assistant embedded in Vim. '
  system_msg ..= 'The user is editing ' .. get(ctx, 'file', 'unknown')
  system_msg ..= ' (' .. get(ctx, 'filetype', 'text') .. '). '
  system_msg ..= 'Current mode: ' .. get(ctx, 'mode', 'file') .. '. '
  system_msg ..= 'Be concise. When asked to write code, use ``` fences with language tags.'
  if has_key(ctx, 'file_lines')
    system_msg ..= ' The file has ' .. get(ctx, 'file_total_lines', 0) .. ' lines.'
  endif

  var messages: string = '[{"role":"system","content":' .. JsonEscape(system_msg) .. '}'
  var hist: list<any> = get(ctx, 'history', [])
  for entry in hist
    messages ..= ',{"role":"user","content":' .. JsonEscape(get(entry, 'prompt', '')) .. '}'
    messages ..= ',{"role":"assistant","content":' .. JsonEscape(get(entry, 'response', '')) .. '}'
  endfor
  messages ..= ',{"role":"user","content":' .. JsonEscape(prompt) .. '}]'

  return '{"model":"deepseek-chat","messages":' .. messages .. ',"stream":' .. (stream ? 'true' : 'false') .. '}'
enddef

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
  try
    writefile([body], tmpfile)
  catch
    echohl ErrorMsg | echom 'vproj_ai: failed to write request' | echohl None
    return ''
  endtry

  var cmd: string = 'curl -s -m 60 -X POST ' .. shellescape(ai_api_url)
  cmd ..= ' -H ' .. shellescape('Content-Type: application/json')
  cmd ..= ' -H ' .. shellescape('Authorization: Bearer ' .. ai_api_key)
  cmd ..= ' -d @' .. shellescape(tmpfile)

  var output: string
  try
    output = system(cmd)
  catch
    silent! delete(tmpfile)
    echohl ErrorMsg | echom 'vproj_ai: API call failed' | echohl None
    return ''
  endtry
  silent! delete(tmpfile)

  if v:shell_error != 0
    echohl ErrorMsg | echom 'vproj_ai: curl error ' .. v:shell_error .. ' — ' .. substitute(output, '\n', ' ', 'g') | echohl None
    return ''
  endif

  var content: string = ExtractJsonField(output, 'content')
  if empty(content)
    var err: string = ExtractJsonField(output, 'message')
    echohl ErrorMsg | echom 'vproj_ai: API error — ' .. (empty(err) ? 'empty response' : err) | echohl None
    return ''
  endif
  return content
enddef

def ParseSSEDelta(line: string): string
  if line == '' || line[ : 4] != 'data:'
    return ''
  endif
  var payload: string = line[5 : ]
  if payload == ' [DONE]'
    return '__DONE__'
  endif
  var delta: string = ExtractJsonField(payload, 'delta')
  if empty(delta)
    return ''
  endif
  return ExtractJsonField(delta, 'content')
enddef

def AiCallStream(prompt: string, ctx: dict<any>, bufnr: number): void
  AiConfigure()
  if empty(ai_api_key) || !executable('curl')
    echohl ErrorMsg | echom 'vproj_ai: streaming unavailable — no API key or curl missing' | echohl None
    return
  endif

  var body: string = BuildRequestBody(prompt, ctx, true)
  stream_tmpfile = tempname()
  try
    writefile([body], stream_tmpfile)
  catch
    echohl ErrorMsg | echom 'vproj_ai: failed to write request' | echohl None
    stream_tmpfile = ''
    return
  endtry

  stream_accumulated = ''

  var cmd: string = 'curl -s -N -m 120 -X POST ' .. shellescape(ai_api_url)
  cmd ..= ' -H ' .. shellescape('Content-Type: application/json')
  cmd ..= ' -H ' .. shellescape('Authorization: Bearer ' .. ai_api_key)
  cmd ..= ' -d @' .. shellescape(stream_tmpfile)

  var opts: dict<any> = {}
  opts.out_mode = 'nl'
  opts.out_cb = function('StreamOutCallback')
  opts.exit_cb = function('StreamExitCallback')
  opts.err_cb = function('StreamErrCallback')

  stream_job = job_start(cmd, opts)
  if job_status(stream_job) == 'fail'
    silent! delete(stream_tmpfile)
    stream_tmpfile = ''
    echohl ErrorMsg | echom 'vproj_ai: failed to start streaming job' | echohl None
    stream_job = v:null
  endif
enddef

def StreamOutCallback(ch: channel, msg: string): void
  var delta: string = ParseSSEDelta(msg)
  if delta == '__DONE__'
    return
  endif
  if empty(delta)
    return
  endif

  stream_accumulated ..= delta

  if !bufexists(ai_conversation_bufnr)
    return
  endif

  var lines: list<string> = getbufline(ai_conversation_bufnr, 1, '$')
  var ai_line: number = 0
  for i in range(len(lines) - 1, 0, -1)
    if lines[i] =~ '^AI:'
      ai_line = i + 1
      break
    endif
  endfor

  if ai_line == 0
    return
  endif

  var current: string = lines[ai_line - 1]
  setbufvar(ai_conversation_bufnr, '&modifiable', 1)
  if current == 'AI: ...'
    setbufline(ai_conversation_bufnr, ai_line, 'AI: ' .. delta)
  else
    setbufline(ai_conversation_bufnr, ai_line, current .. delta)
  endif
  setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  redraw
enddef

def StreamExitCallback(ch: channel, exit_code: number): void
  silent! delete(stream_tmpfile)
  stream_tmpfile = ''

  if stream_job == v:null
    return
  endif
  stream_job = v:null

  if !bufexists(ai_conversation_bufnr)
    return
  endif

  if exit_code != 0
    setbufvar(ai_conversation_bufnr, '&modifiable', 1)
    var last: number = line('$', ai_conversation_bufnr)
    if last > 0
      setbufline(ai_conversation_bufnr, last, '(curl error ' .. exit_code .. ')')
    endif
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
    return
  endif

  setbufvar(ai_conversation_bufnr, '&modifiable', 1)

  # Replace placeholder if still there (no content arrived)
  var lines: list<string> = getbufline(ai_conversation_bufnr, 1, '$')
  for i in range(len(lines) - 1, 0, -1)
    if lines[i] == 'AI: ...'
      setbufline(ai_conversation_bufnr, i + 1, 'AI: (empty response)')
      break
    endif
  endfor

  # Add blank line and > prompt
  var last_lnum: number = line('$', ai_conversation_bufnr)
  appendbufline(ai_conversation_bufnr, last_lnum, '')
  appendbufline(ai_conversation_bufnr, last_lnum + 1, '> ')

  setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  cursor(last_lnum + 2, 3)

  # Record history
  if !empty(stream_accumulated)
    ai_last_response = stream_accumulated
    ai_history->add({prompt: ai_last_prompt, response: stream_accumulated})
    if len(ai_history) > 5
      ai_history = ai_history[-5 : ]
    endif
  endif
enddef

def StreamErrCallback(ch: channel, msg: string): void
  if bufexists(ai_conversation_bufnr)
    setbufvar(ai_conversation_bufnr, '&modifiable', 1)
    var last: number = line('$', ai_conversation_bufnr)
    if last > 0
      setbufline(ai_conversation_bufnr, last, '(stream error: ' .. substitute(msg, '\n', ' ', 'g') .. ')')
    endif
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  endif
enddef

def JsonEscape(s: string): string
  var escaped: string = substitute(s, '\\', '\\\\', 'g')
  escaped = substitute(escaped, '"', '\\"', 'g')
  escaped = substitute(escaped, '\n', '\\n', 'g')
  escaped = substitute(escaped, '\r', '\\r', 'g')
  escaped = substitute(escaped, '\t', '\\t', 'g')
  return '"' .. escaped .. '"'
enddef

def ExtractJsonField(json: string, field: string): string
  var pattern: string = '"' .. field .. '"'
  var idx: number = stridx(json, pattern)
  if idx < 0
    return ''
  endif
  var rest: string = json[idx + len(pattern) : ]
  var colon: number = stridx(rest, ':')
  if colon < 0
    return ''
  endif
  rest = rest[colon + 1 : ]
  rest = substitute(rest, '^\s*', '', '')
  if rest[0] != '"'
    var end_chars: list<number> = [stridx(rest, ','), stridx(rest, '}'), stridx(rest, "\n")]
    var min_end: number = 0
    for e in end_chars
      if e >= 0 && (min_end == 0 || e < min_end) | min_end = e | endif
    endfor
    if min_end > 0 | return rest[ : min_end - 1] | endif
    return rest
  endif
  rest = rest[1 : ]
  var result: string = ''
  var i: number = 0
  while i < len(rest)
    var ch: string = rest[i]
    if ch == '\\' && i + 1 < len(rest)
      var nextch: string = rest[i + 1]
      if nextch == '"' | result ..= '"' | i += 2 | continue | endif
      if nextch == '\\' | result ..= '\\' | i += 2 | continue | endif
      if nextch == 'n' | result ..= "\n" | i += 2 | continue | endif
      if nextch == 'r' | result ..= "\r" | i += 2 | continue | endif
      if nextch == 't' | result ..= "\t" | i += 2 | continue | endif
      if nextch == '/' | result ..= '/' | i += 2 | continue | endif
    elseif ch == '"'
      return result
    endif
    result ..= ch
    i += 1
  endwhile
  return result
enddef

def RouteResponse(text: string): void
  if empty(text) | return | endif

  var has_fences: bool = (stridx(text, '```') >= 0)
  var lines: list<string> = split(text, "\n")
  var line_count: number = len(lines)
  var short_response: bool = (line_count <= 2 && !has_fences)

  var file_line_pattern: string = '^\S\+:\d\+:'
  var file_line_count: number = 0
  for ln in lines
    if ln =~ file_line_pattern | file_line_count += 1 | endif
  endfor
  var is_qfix: bool = (file_line_count >= 2 || (file_line_count >= 1 && line_count <= 3))

  if is_qfix
    var qflist: list<dict<any>> = []
    for ln in lines
      if ln =~ file_line_pattern
        var parts: list<string> = split(ln, ':')
        if len(parts) >= 3
          qflist->add({filename: parts[0], lnum: str2nr(parts[1]), text: join(parts[2 : ], ':')})
        endif
      endif
    endfor
    if !empty(qflist)
      setqflist([], ' ', {items: qflist, title: 'vproj_ai AI response'})
      if exists('*vproj#SwitchMode') | vproj#SwitchMode('qfix') | endif
      return
    endif
  endif

  if has_fences
    var pv_bufnr: number = CreateView(text, 'markdown')
    if pv_bufnr > 0 | return | endif
  endif

  if short_response
    echom 'AI: ' .. substitute(lines[0], "\r", '', 'g')
    return
  endif

  var pv_bufnr: number = CreateView(text, 'markdown')
  if pv_bufnr <= 0
    for ln in lines[ : 10]
      echom ln
    endfor
    if line_count > 10
      echom '... (' .. (line_count - 10) .. ' more lines)'
    endif
  endif
enddef

def CreateView(text: string, filetype: string): number
  if exists('*vproj#IsPaneVisible') && !vproj#IsPaneVisible()
    vproj#PaneOpen()
  endif
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  var pane_wid: number = 0
  if pane > 0 && bufexists(pane)
    pane_wid = win_getid(bufwinnr(pane))
  endif
  for info in getwininfo()
    if info.winid != pane_wid
      win_gotoid(info.winid)
      break
    endif
  endfor
  botright vnew
  var bufnr: number = bufnr('%')
  setbufvar(bufnr, '&buftype', 'nofile')
  setbufvar(bufnr, '&bufhidden', 'wipe')
  setbufvar(bufnr, '&swapfile', 0)
  setbufvar(bufnr, '&modified', 0)
  if !empty(filetype) | setbufvar(bufnr, '&syntax', filetype) | endif
  setline(1, split(text, "\n"))
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> a <Cmd>call vproj_ai#AiApplyCode()<CR>
  cursor(1, 1)
  return bufnr
enddef

def CreateConversationView(prompt: string, response: string): number
  if exists('*vproj#IsPaneVisible') && !vproj#IsPaneVisible()
    vproj#PaneOpen()
  endif
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  var pane_wid: number = 0
  if pane > 0 && bufexists(pane)
    pane_wid = win_getid(bufwinnr(pane))
  endif
  for info in getwininfo()
    if info.winid != pane_wid
      win_gotoid(info.winid)
      break
    endif
  endfor
  botright vnew
  var bufnr: number = bufnr('%')
  setbufvar(bufnr, '&buftype', 'nofile')
  setbufvar(bufnr, '&bufhidden', 'wipe')
  setbufvar(bufnr, '&swapfile', 0)
  setbufvar(bufnr, '&modified', 0)
  setbufvar(bufnr, '&modifiable', 0)

  var sep: string = repeat('=', 79)
  var subsep: string = repeat('-', 79)
  var header: list<string> = [sep, ' AI Assistant' .. repeat(' ', 65) .. 'q to close', subsep, '']

  var lines: list<string> = copy(header)
  lines->add('User: ' .. prompt)
  lines->add('')
  if stridx(response, "\n") >= 0
    lines->add('AI:')
    for rl in split(response, "\n")
      lines->add(rl)
    endfor
  else
    lines->add('AI: ' .. response)
  endif
  lines->add('')
  lines->add('> ')

  setbufvar(bufnr, '&modifiable', 1)
  setline(1, lines)
  setbufvar(bufnr, '&modifiable', 0)

  nnoremap <buffer> <silent> q <Cmd>call vproj_ai#AiCancelStream()<Bar>close<CR>
  nnoremap <buffer> <silent> a <Cmd>call vproj_ai#AiApplyCode()<CR>
  nnoremap <buffer> <silent> <C-c> <Cmd>call vproj_ai#AiCancelStream()<CR>
  nnoremap <buffer> <silent> <CR> <Cmd>call vproj_ai#AiSendFollowup()<CR>

  cursor(line('$'), 3)
  return bufnr
enddef

export def AiCancelStream(): void
  if stream_job != v:null
    job_stop(stream_job)
    stream_job = v:null
  endif
  silent! delete(stream_tmpfile)
  stream_tmpfile = ''

  if bufexists(ai_conversation_bufnr)
    setbufvar(ai_conversation_bufnr, '&modifiable', 1)
    var last_lnum: number = line('$', ai_conversation_bufnr)
    if last_lnum > 0
      var last_line: string = getbufline(ai_conversation_bufnr, last_lnum)[0]
      if last_line == '> '
        silent! deletebufline(ai_conversation_bufnr, last_lnum)
      endif
    endif
    appendbufline(ai_conversation_bufnr, line('$', ai_conversation_bufnr), '')
    appendbufline(ai_conversation_bufnr, line('$', ai_conversation_bufnr), '(cancelled)')
    appendbufline(ai_conversation_bufnr, line('$', ai_conversation_bufnr), '')
    appendbufline(ai_conversation_bufnr, line('$', ai_conversation_bufnr), '> ')
    setbufvar(ai_conversation_bufnr, '&modifiable', 0)
  endif
enddef

export def AiSendFollowup(): void
  if bufnr('%') != ai_conversation_bufnr
    return
  endif
  var last_line: string = getline('$')
  var prompt: string = substitute(last_line, '^>\s*', '', '')
  if empty(trim(prompt))
    return
  endif

  ai_conversation_ctx.history = copy(ai_history)
  ai_last_prompt = prompt
  echom 'vproj_ai: thinking...'

  # Append placeholder, delete >, start streaming
  setbufvar(ai_conversation_bufnr, '&modifiable', 1)
  execute '$delete _'
  var placeholders: list<string> = ['', 'User: ' .. prompt, '', 'AI: ...']
  append(line('$'), placeholders)
  setbufvar(ai_conversation_bufnr, '&modifiable', 0)

  AiCallStream(prompt, ai_conversation_ctx, ai_conversation_bufnr)
enddef

export def AiPrompt(): void
  var ctx: dict<any> = GatherContext()
  var prompt: string = input('AI: ')
  if empty(prompt) | return | endif

  echom 'vproj_ai: thinking...'

  # Wipe stale conversation buffer if it exists
  if ai_conversation_bufnr > 0 && bufexists(ai_conversation_bufnr)
    execute 'bdelete! ' .. ai_conversation_bufnr
  endif
  ai_conversation_ctx = ctx
  ai_last_prompt = prompt

  # Create buffer with placeholder, then stream — callbacks fill response
  ai_conversation_bufnr = CreateConversationView(prompt, '...')
  setbufvar(ai_conversation_bufnr, '&modifiable', 1)
  AiCallStream(prompt, ctx, ai_conversation_bufnr)
enddef

# Apply AI-generated code from the conversation or markdown view buffer.
export def AiApplyCode(): void
  var blocks: list<dict<any>> = FindCodeBlocks()
  if empty(blocks)
    echom 'vproj_ai: no code blocks found in buffer'
    return
  endif

  var nearest: dict<any> = FindNearestBlock(blocks, line('.'))
  if empty(nearest)
    echom 'vproj_ai: could not find a code block'
    return
  endif

  var target_file: string
  var target_ctx: dict<any> = {}
  if bufnr('%') == ai_conversation_bufnr && !empty(ai_conversation_ctx)
    target_file = get(ai_conversation_ctx, 'file', '')
    target_ctx = ai_conversation_ctx
  else
    target_file = expand('%:p')
  endif

  if empty(target_file)
    echohl ErrorMsg | echom 'vproj_ai: no target file known — use from conversation buffer' | echohl None
    return
  endif

  var lang: string = get(nearest, 'language', 'code')
  var code: string = get(nearest, 'code', '')
  if empty(code)
    echom 'vproj_ai: empty code block'
    return
  endif

  var confirm: string = input('Apply (' .. lang .. ') code block to ' .. fnamemodify(target_file, ':t') .. '? (y/N): ')
  if confirm !~? '^y\(es\)\?$'
    echom 'vproj_ai: cancelled'
    return
  endif

  ApplyCodeToFile(target_file, code, target_ctx)
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
        if trim(getline(i)) == '```'
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

def ApplyCodeToFile(file: string, code: string, ctx: dict<any>): void
  var target_buf: number = bufnr(file)
  var target_win: number = 0
  if target_buf > 0
    target_win = bufwinnr(target_buf)
  endif

  if target_win > 0
    win_gotoid(win_getid(target_win))
  elseif target_buf > 0
    execute 'sbuffer ' .. target_buf
  else
    execute 'edit ' .. fnameescape(file)
    target_buf = bufnr('%')
  endif

  var vis_start: any = get(ctx, 'visual_range', [])
  var cursor_line: number = get(ctx, 'cursor_line', 1)

  if type(vis_start) == v:t_list && len(vis_start) == 2
    # Strategy 1: replace visual selection
    var start_lnum: number = vis_start[0]
    var end_lnum: number = vis_start[1]
    execute start_lnum .. ',' .. end_lnum .. 'delete _'
    call append(start_lnum - 1, split(code, "\n"))
  elseif cursor_line > 0
    # Strategy 2: insert after cursor line
    call append(cursor_line, split(code, "\n"))
    echom 'vproj_ai: code inserted after line ' .. cursor_line .. ' in ' .. fnamemodify(file, ':t')
  else
    # Strategy 3: append at end
    call append(line('$'), split(code, "\n"))
    echom 'vproj_ai: code appended at end of ' .. fnamemodify(file, ':t')
  endif

  setbufvar(bufnr('%'), '&modified', 1)
enddef
