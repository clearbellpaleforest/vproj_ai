vim9script

# autoload/vproj_ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) and natural-language
# coding assistance via OpenAI-compatible API.

# State
var ai_api_url: string = ''
var ai_api_key: string = ''
var ai_model: string = ''
var ai_conversation_bufnr: number = -1
var ai_conversation_history: list<dict<any>> = []
var ai_conversation_ctx: dict<any> = {}

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
  nnoremap <buffer> <silent> A :call vproj_ai#AiPrompt()<CR>
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
    writefile(['Authorization: Bearer ' .. ai_api_key], hdrfile)
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
  return ''
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

export def AiPrompt(): void
  # If conversation is already active, close old buffer and reset
  if ai_conversation_bufnr > 0 && bufexists(ai_conversation_bufnr)
    execute 'bwipeout! ' .. ai_conversation_bufnr
  endif
  ai_conversation_bufnr = -1
  ai_conversation_history = []
  ai_conversation_ctx = {}

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

  var prompt: string = input('AI: ')
  if empty(prompt)
    return
  endif

  var ctx_file: string = get(ctx, 'file', '')
  var ctx_lines: number = has_key(ctx, 'file_lines') ? len(ctx.file_lines) : 0
  var display_file: string = empty(ctx_file) ? 'unknown' : fnamemodify(ctx_file, ':t')
  echom 'vproj_ai: sending ' .. display_file .. ' (' .. ctx_lines .. ' lines)...'

  var response: string = AiCall(prompt, ctx)
  if empty(response)
    return
  endif

  # Record first exchange
  ai_conversation_history->add({prompt: prompt, response: response})

  # Create conversation buffer and render the first exchange
  ai_conversation_bufnr = CreateConversationView(ctx)
  if ai_conversation_bufnr <= 0
    return
  endif
  RenderConversation(ai_conversation_bufnr)

  # Follow-up loop
  var loop_count: number = 0
  while true
    var followup: string = input('> ')
    if empty(followup) | break | endif
    if !bufexists(ai_conversation_bufnr) | break | endif

    echom 'vproj_ai: sending follow-up...'
    ai_conversation_ctx.history = copy(ai_conversation_history)
    response = AiCall(followup, ai_conversation_ctx)
    if empty(response) | break | endif

    ai_conversation_history->add({prompt: followup, response: response})
    RenderConversation(ai_conversation_bufnr)
    loop_count += 1
  endwhile

  # Ensure conversation buffer has focus and normal mode.
  if ai_conversation_bufnr > 0 && bufexists(ai_conversation_bufnr)
    var conv_win: number = bufwinnr(ai_conversation_bufnr)
    if conv_win > 0
      win_gotoid(win_getid(conv_win))
      stopinsert
    endif
  endif
enddef

export def CreateConversationView(ctx: dict<any>): number
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    botright new
  finally
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
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

  nnoremap <buffer> <silent> q :close<CR>
  nnoremap <buffer> <silent> a :call vproj_ai#AiApplyCode()<CR>
  nnoremap <buffer> <silent> A :call vproj_ai#AiApplyCode()<CR>
  nnoremap <buffer> <silent> <CR> :call vproj_ai#SendFollowup()<CR>
  inoremap <buffer> <silent> a <Esc>:call vproj_ai#AiApplyCode()<CR>

  return bufnr
enddef

def RenderConversation(bufnr: number): void
  if !bufexists(bufnr) | return | endif

  var lines: list<string> = []
  lines->add(repeat('=', 79))
  lines->add(' AI Assistant' .. repeat(' ', 79 - 14 - 10) .. 'q to close')
  lines->add(repeat('-', 79))
  lines->add('')

  for entry in ai_conversation_history
    lines->add('User: ' .. get(entry, 'prompt', ''))
    lines->add('')
    var resp: string = get(entry, 'response', '')
    if stridx(resp, "\n") >= 0
      lines->add('AI:')
      for ln in split(resp, "\n")
        lines->add(ln)
      endfor
    else
      lines->add('AI: ' .. resp)
    endif
    lines->add('')
  endfor

  var cur_win: number = bufwinnr(bufnr)
  if cur_win > 0
    win_gotoid(win_getid(cur_win))
    setbufvar(bufnr, '&modifiable', 1)
    deletebufline(bufnr, 1, '$')
    setline(1, lines)
    setbufvar(bufnr, '&modifiable', 0)
    set nomodified
    stopinsert
    cursor(line('$'), 1)
  endif
enddef

export def SendFollowup(): void
  if ai_conversation_bufnr <= 0 || !bufexists(ai_conversation_bufnr)
    echom 'vproj_ai: no active conversation'
    return
  endif
  if bufnr('%') != ai_conversation_bufnr
    var conv_win: number = bufwinnr(ai_conversation_bufnr)
    if conv_win > 0
      win_gotoid(win_getid(conv_win))
    endif
  endif

  var prompt: string = input('> ')
  if empty(prompt) | return | endif
  if !bufexists(ai_conversation_bufnr) | return | endif

  echom 'vproj_ai: sending follow-up...'
  ai_conversation_ctx.history = copy(ai_conversation_history)
  var response: string = AiCall(prompt, ai_conversation_ctx)
  if empty(response) | return | endif

  ai_conversation_history->add({prompt: prompt, response: response})
  RenderConversation(ai_conversation_bufnr)
enddef

export def HandleConvBufWipeout(wiped_bufnr: number): void
  if ai_conversation_bufnr > 0 && ai_conversation_bufnr == wiped_bufnr
    ai_conversation_bufnr = -1
    ai_conversation_history = []
    ai_conversation_ctx = {}
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
