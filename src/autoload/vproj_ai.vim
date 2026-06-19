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

export def AiCall(prompt: string, ctx: dict<any>): string
  AiConfigure()
  if empty(ai_api_key)
    echoerr 'vproj_ai: no API key. Set g:vproj_ai_api_key or $DEEPSEEK_API_KEY.'
    return ''
  endif
  if !executable('curl')
    echoerr 'vproj_ai: curl is required but not found'
    return ''
  endif

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

  var body: string = '{"model":"deepseek-chat","messages":' .. messages .. ',"stream":false}'

  var tmpfile: string = tempname()
  try
    writefile([body], tmpfile)
  catch
    echoerr 'vproj_ai: failed to write request'
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
    echoerr 'vproj_ai: API call failed'
    return ''
  endtry
  silent! delete(tmpfile)

  if v:shell_error != 0
    echoerr 'vproj_ai: curl error ' .. v:shell_error .. ' — ' .. substitute(output, '\n', ' ', 'g')
    return ''
  endif

  var content: string = ExtractJsonField(output, 'content')
  if empty(content)
    var err: string = ExtractJsonField(output, 'message')
    echoerr 'vproj_ai: API error — ' .. (empty(err) ? 'empty response' : err)
    return ''
  endif
  return content
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
  cursor(1, 1)
  return bufnr
enddef

export def AiPrompt(): void
  var ctx: dict<any> = GatherContext()
  var prompt: string = input('AI: ')
  if empty(prompt) | return | endif

  echom 'vproj_ai: thinking...'
  var response: string = AiCall(prompt, ctx)
  if empty(response) | return | endif

  ai_last_prompt = prompt
  ai_last_response = response
  ai_history->add({prompt: prompt, response: response})
  if len(ai_history) > 5
    ai_history = ai_history[-5 : ]
  endif

  RouteResponse(response)
enddef
