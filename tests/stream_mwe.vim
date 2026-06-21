vim9script

# Minimal Working Example: job_start + mode:raw + SSE streaming
# Run: vim -N -u NONE -S tests/stream_mwe.vim
# Must complete in under 10s.

var result_bufnr: number = -1
var stream_accum: string = ''
var tokens: list<string> = []
var done: bool = false

# Avoid getbufline-after-setbufline (stale reads in headless Vim).
# Track the current line state in script-local vars instead.
var cur_line_nr: number = 1
var cur_line_text: string = ''

def AppendToken(bufnr: number, text: string)
  if !bufexists(bufnr) | return | endif
  var parts = split(text, "\n", 1)
  cur_line_text ..= parts[0]
  setbufline(bufnr, cur_line_nr, cur_line_text)
  if len(parts) > 1
    for i in range(1, len(parts) - 1)
      cur_line_nr += 1
      cur_line_text = parts[i]
      appendbufline(bufnr, cur_line_nr - 1, [cur_line_text])
    endfor
  endif
  redraw
enddef

def ProcessChunk(chan: channel, msg: string, bufnr: number)
  stream_accum ..= msg
  while stridx(stream_accum, "\n\n") >= 0
    var parts = split(stream_accum, "\n\n", 1)
    var frame = parts[0]
    stream_accum = join(parts[1 :], "\n\n")
    for line in split(frame, "\n")
      if line =~ '^data:\s*'
        var json_str = substitute(line, '^data:\s*', '', '')
        if json_str == '[DONE]'
          done = true
          return
        endif
        try
          var data = json_decode(json_str)
          if has_key(data, 'delta') && has_key(data.delta, 'text')
            var token = data.delta.text
            add(tokens, token)
            AppendToken(bufnr, token)
          endif
        catch
          # Partial frame — ignore
        endtry
      endif
    endfor
  endwhile
enddef

def JobExit(job: job, status: number)
  # Accumulator may have residual data after last \n\n
enddef

def RunMWE(): void
  # Create a fresh buffer to receive streamed text
  new
  setlocal buftype=nofile bufhidden=hide noswapfile
  result_bufnr = bufnr('%')

  # Mock SSE stream: emits 4 tokens over 2s with deliberate fragmentation.
  # First token split across two chunks; third token contains \n (newline).
  # Escape chain: Vim '' → bash "" → printf format → JSON string
  #   Vim \\\\ → bash \\\\ → bash DQ \\ → printf \\ → literal backslash
  #   Vim \\n\\n → bash \\n\\n → bash DQ \n\n → printf newline+newline
  # So for JSON content \\n:  Vim \\\\\\\\n → bash \\\\\\\\n → bash DQ \\\\n → printf \\n → JSON \n
  var script = [
    'bash', '-c',
    'printf "%s" "data: {\"delta\": {\"text\": \"Hel" >&1; ' ..
    'sleep 0.3; ' ..
    'printf "lo\"}}\\n\\n" >&1; ' ..
    'sleep 0.3; ' ..
    'printf "data: {\"delta\": {\"text\": \" world\"}}\\n\\n" >&1; ' ..
    'sleep 0.3; ' ..
    'printf "data: {\"delta\": {\"text\": \"\\\\nfrom\"}}\\n\\n" >&1; ' ..
    'sleep 0.3; ' ..
    'printf "data: {\"delta\": {\"text\": \" Vim9Script!\"}}\\n\\n" >&1; ' ..
    'sleep 0.3; ' ..
    'printf "data: [DONE]\\n\\n" >&1'
  ]

  var opts = {
    out_cb: (chan, msg) => ProcessChunk(chan, msg, result_bufnr),
    exit_cb: JobExit,
    mode: 'raw',
    timeout: 10000
  }

  var job = job_start(script, opts)
  if job_status(job) != 'run'
    echohl ErrorMsg
    echom 'MWE FAILED: job_start returned non-running job'
    echohl None
    qa!
  endif

  # Poll until done (max 10s). Vim processes channel callbacks during input/sleep.
  var waited: number = 0
  while !done && waited < 100
    sleep 100m
    waited += 1
  endwhile

  # Verify
  var content = join(getbufline(result_bufnr, 1, '$'), "\n")
  var expected = "Hello world\nfrom Vim9Script!"
  if content == expected
    echom 'MWE PASSED: ' .. string(content)
  else
    echohl ErrorMsg
    echom 'MWE FAILED: got ' .. string(content) .. ' expected ' .. string(expected)
    echom 'Tokens received: ' .. string(tokens)
    echohl None
  endif
  qa!
enddef

RunMWE()
