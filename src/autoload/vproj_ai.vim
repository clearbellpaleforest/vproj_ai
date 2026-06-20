vim9script

# autoload/vproj_ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) and natural-language
# coding assistance via OpenAI-compatible API.

# State
var ai_api_url: string = ''
var ai_api_key: string = ''

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
  return ctx
enddef

def BuildRequestBody(prompt: string, ctx: dict<any>, stream: bool): string
  var system_msg: string = 'You are a coding assistant embedded in Vim. '
  system_msg ..= 'The user is editing ' .. get(ctx, 'file', 'unknown')
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
    var cmd: string = 'curl -s -m 60 -X POST ' .. shellescape(ai_api_url)
    cmd ..= ' -H ' .. shellescape('Content-Type: application/json')
    cmd ..= ' -H ' .. shellescape('Authorization: Bearer ' .. ai_api_key)
    cmd ..= ' -d @' .. shellescape(tmpfile)

    var output: string = system(cmd)

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
  catch
    echohl ErrorMsg | echom 'vproj_ai: request failed' | echohl None
    return ''
  finally
    if filereadable(tmpfile) | delete(tmpfile) | endif
  endtry
  return ''
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
    # Non-string value: number, bool, null, object, or array.
    # For objects/arrays, track depth to find the matching close.
    if rest[0] == '{' || rest[0] == '['
      var open_ch: string = rest[0]
      var close_ch: string = (open_ch == '{') ? '}' : ']'
      var depth: number = 1
      var i: number = 1
      var in_string: bool = false
      while i < len(rest) && depth > 0
        var ch: string = rest[i]
        if in_string
          if ch == '\\' && i + 1 < len(rest) | i += 2 | continue | endif
          if ch == '"' | in_string = false | endif
        else
          if ch == '"' | in_string = true
          elseif ch == open_ch | depth += 1
          elseif ch == close_ch | depth -= 1
          endif
        endif
        i += 1
      endwhile
      return rest[ : i - 1]
    endif
    # Scalar: find first terminator.
    var end_chars: list<number> = [stridx(rest, ','), stridx(rest, '}'), stridx(rest, ']'), stridx(rest, "\n")]
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

def RouteResponse(text: string, ctx: dict<any>): void
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
    var pv_bufnr: number = CreateView(text, 'markdown', ctx)
    if pv_bufnr > 0 | return | endif
  endif

  if short_response
    echom 'AI: ' .. substitute(lines[0], "\r", '', 'g')
    return
  endif

  var pv_bufnr: number = CreateView(text, 'markdown', ctx)
  if pv_bufnr <= 0
    for ln in lines[ : 10]
      echom ln
    endfor
    if line_count > 10
      echom '... (' .. (line_count - 10) .. ' more lines)'
    endif
  endif
enddef

def CreateView(text: string, filetype: string, ctx: dict<any>): number
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    botright vnew
  finally
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  var bufnr: number = bufnr('%')
  setbufvar(bufnr, '&buftype', 'nofile')
  setbufvar(bufnr, '&bufhidden', 'wipe')
  setbufvar(bufnr, '&swapfile', 0)
  if !empty(filetype) | setbufvar(bufnr, '&syntax', filetype) | endif
  setline(1, split(text, "\n"))
  setbufvar(bufnr, '&modified', 0)
  # Store target file context for AiApplyCode
  b:vproj_ai_target_file = get(ctx, 'file', '')
  b:vproj_ai_cursor_line = get(ctx, 'cursor_line', 1)
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> a <Cmd>call vproj_ai#AiApplyCode()<CR>
  imap <buffer> <silent> a <Esc><Cmd>call vproj_ai#AiApplyCode()<CR>
  cursor(1, 1)
  return bufnr
enddef

export def AiPrompt(): void
  # If called from the pane buffer (via A mapping), switch to the
  # last non-pane window so GatherContext captures the user's file.
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  if pane > 0 && bufnr('%') == pane
    for info in getwininfo()
      if info.bufnr != pane
        win_gotoid(info.winid)
        break
      endif
    endfor
  endif
  var ctx: dict<any> = GatherContext()
  var prompt: string = input('AI: ')
  if empty(prompt) | return | endif

  echom 'vproj_ai: thinking...'

  var response: string = AiCall(prompt, ctx)
  if empty(response)
    return
  endif

  RouteResponse(response, ctx)
enddef

# Apply AI-generated code from the markdown view buffer.
export def AiApplyCode(): void
  var blocks: list<dict<any>> = FindCodeBlocks()
  if empty(blocks)
    # No fenced blocks. Try to extract the AI response body as a fallback.
    var code_lines: list<string> = []
    var in_ai: bool = false
    for ln in getline(1, '$')
      if in_ai
        if ln == '' && !empty(code_lines)
          break
        endif
        code_lines->add(ln)
      elseif ln =~ '^AI:'
        in_ai = true
        var rest: string = substitute(ln, '^AI:\s*', '', '')
        if !empty(rest) | code_lines->add(rest) | endif
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

    var confirm: string = input('Apply (' .. lang .. ') to ' .. fnamemodify(target_file, ':t') .. '? (y/N): ')
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

  if target_win > 0
    win_gotoid(win_getid(target_win))
  elseif target_buf > 0
    execute 'sbuffer ' .. target_buf
  else
    execute 'edit ' .. fnameescape(file)
    target_buf = bufnr('%')
  endif

  if cursor_line > 0
    call append(cursor_line, split(code, "\n"))
  else
    call append(line('$'), split(code, "\n"))
  endif

  setbufvar(bufnr('%'), '&modified', 1)
enddef
