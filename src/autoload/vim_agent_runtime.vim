vim9script

# Vim Agent Runtime -- eyes, hands, and brain for headless Vim plugin testing.
#
# Every test file sources this with:
#   source tests/vim_agent_runtime.vim
#
# Then calls:
#   Begin('test suite name')
#   Assert(...) / AssertEqual(...) / Log(...) / etc.
#   End()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const LOG_FILE: string = '/tmp/vproj-test-output.log'
const PATTERNS_FILE: string = 'knowledge/error_patterns.jsonl'

# ---------------------------------------------------------------------------
# Test state (g: so values persist across :source calls)
# ---------------------------------------------------------------------------

g:var_failures = 0
g:var_test_count = 0

# ---------------------------------------------------------------------------
# Cached knowledge base (script-local, loaded on demand)
# ---------------------------------------------------------------------------

var cached_patterns: list<dict<any>> = []

# ===========================================================================
# Eyes (output capture)
# ===========================================================================

# Begin(name) -- clear log file, reset counters, write begin event
export def Begin(name: string)
  g:var_failures = 0
  g:var_test_count = 0
  writefile([], LOG_FILE)
  Log({event: 'begin', test_name: name})
enddef

# End() -- write summary event, exit 1 on failure, print pass/fail count
export def End()
  Log({event: 'end', failures: g:var_failures, total: g:var_test_count})
  if g:var_failures > 0
    echohl ErrorMsg
    echomsg $'FAIL: {g:var_failures} failure(s) out of {g:var_test_count} test(s)'
    echohl None
    cquit  # exit Vim with code 1
  else
    echomsg $'OK: {g:var_test_count} test(s) passed'
  endif
enddef

# Assert(cond, msg) -- increment counter, log pass/fail, diagnose on failure
export def Assert(cond: bool, msg: string)
  g:var_test_count += 1
  if cond
    Log({event: 'assert', result: 'pass', msg: msg})
  else
    g:var_failures += 1
    Log({event: 'assert', result: 'fail', msg: msg})
    Diagnose(msg)
  endif
enddef

# AssertEqual(actual, expected, msg) -- log both values on failure
export def AssertEqual(actual: any, expected: any, msg: string)
  g:var_test_count += 1
  if actual == expected
    Log({event: 'assert_equal', result: 'pass', msg: msg})
  else
    g:var_failures += 1
    var detail: string = $'{msg}: expected {json_encode(expected)}, got {json_encode(actual)}'
    Log({event: 'assert_equal', result: 'fail', msg: detail})
    Diagnose(detail)
  endif
enddef

# Log(entry) -- append a JSON line to the log file with a ts field
export def Log(entry: dict<any>)
  # Vim9Script function parameters are immutable; copy to local
  var log_entry: dict<any> = {
    ts: strftime('%Y-%m-%dT%H:%M:%S'),
  }
  for [key, val] in items(entry)
    log_entry[key] = val
  endfor
  if !has_key(log_entry, 'event')
    log_entry.event = 'log'
  endif
  writefile([json_encode(log_entry)], LOG_FILE, 'a')
enddef

# TermReadAll(buf) -- read every line from a terminal buffer, return as list
export def TermReadAll(buf: number): list<string>
  var lines: list<string> = []
  var row: number = 1
  while true
    var line: string = term_getline(buf, row)
    if empty(line)
      break
    endif
    add(lines, line)
    row += 1
  endwhile
  return lines
enddef

# Snapshot() -- capture window layout, buffer list, window dimensions, log it,
#               return the snapshot dict
export def Snapshot(): dict<any>
  var snap: dict<any> = {
    window_layout: winlayout(),
    buffers: getbufinfo(),
    columns: &columns,
    lines: &lines,
    timestamp: strftime('%Y-%m-%dT%H:%M:%S'),
  }
  Log({event: 'snapshot', data: snap})
  return snap
enddef

# CaptureMessages() -- return all Vim messages since last call as a string
export def CaptureMessages(): string
  var msgs: string = execute('messages')
  Log({event: 'capture_messages', messages: msgs})
  return msgs
enddef

# ===========================================================================
# Hands (programmatic control)
# ===========================================================================

# TermSend(buf, keys) -- send keys to a terminal buffer
export def TermSend(buf: number, keys: string)
  term_sendkeys(buf, keys)
enddef

# TermWait(buf, ms) -- wait for terminal activity
export def TermWait(buf: number, ms: number)
  term_wait(buf, ms)
enddef

# ===========================================================================
# Verify (agent feedback loop)
# ===========================================================================

# VerifyFile(path) — source a Vimscript file, capture all errors, diagnose them.
# Returns a dict with {ok: bool, errors: list<string>, diagnoses: list<dict<any>>,
# output: string} so agents can test edits atomically and get actionable feedback.
# This closes the loop that currently strands agents — they make an edit, get no
# visible error, and retry blindly.
export def VerifyFile(path: string): dict<any>
  var result: dict<any> = {ok: true, errors: [], diagnoses: [], output: ''}
  var before_count: number = len(split(execute('messages'), "\n"))
  try
    execute 'source' fnameescape(path)
  catch /.*/
    result.ok = false
    add(result.errors, v:exception)
  endtry
  # Capture any messages emitted during :source
  var all_msgs: string = execute('messages')
  var msg_lines: list<string> = split(all_msgs, "\n")
  var new_msgs: list<string> = []
  var i: number = before_count
  while i < len(msg_lines)
    if msg_lines[i] =~ '^Error detected' || msg_lines[i] =~ '^E\d\+:' || msg_lines[i] =~ '^Line\s\+\d\+:'
      add(result.errors, msg_lines[i])
      result.ok = false
    endif
    add(new_msgs, msg_lines[i])
    i += 1
  endwhile
  result.output = join(new_msgs, "\n")
  # Run diagnosis on any errors
  for err in result.errors
    Diagnose(err)
    # Re-read cached patterns to capture any new diagnoses
    LoadPatterns()
  endfor
  # Read diagnoses from log (simplified — in practice, Diagnose writes to log)
  Log({event: 'verify', path: path, ok: result.ok, error_count: len(result.errors)})
  return result
enddef

# VerifyCall(expr) — evaluate a Vim expression, capture result and errors.
# Agents can test single function calls and see return value + errors.
export def VerifyCall(expr: string): dict<any>
  var result: dict<any> = {ok: true, errors: [], value: '', diagnoses: []}
  try
    var val: any = eval(expr)
    result.value = string(val)
  catch /.*/
    result.ok = false
    add(result.errors, v:exception)
    Diagnose(v:exception)
  endtry
  Log({event: 'verify_call', expr: expr, ok: result.ok})
  return result
enddef

# ===========================================================================
# Brain (learning from known error patterns)
# ===========================================================================

# LoadPatterns() -- read knowledge/error_patterns.jsonl, cache, return list
export def LoadPatterns(): list<dict<any>>
  if empty(cached_patterns) && filereadable(PATTERNS_FILE)
    var raw: list<string> = readfile(PATTERNS_FILE)
    for line in raw
      if empty(line)
        continue
      endif
      try
        var pattern: dict<any> = json_decode(line)
        add(cached_patterns, pattern)
      catch
        # Skip malformed JSON lines silently
      endtry
    endfor
  endif
  return deepcopy(cached_patterns)
enddef

# Diagnose(msg) -- check msg against loaded patterns, log any matches
export def Diagnose(msg: string)
  if empty(cached_patterns)
    LoadPatterns()
  endif
  for pattern in cached_patterns
    var signature: string = get(pattern, 'signature', '')
    if !empty(signature) && stridx(msg, signature) >= 0
      Log({
        event: 'diagnosis',
        error_code: get(pattern, 'error_code', '?'),
        root_cause: get(pattern, 'root_cause', ''),
        fix: get(pattern, 'fix', ''),
        file: get(pattern, 'file', ''),
      })
    endif
  endfor
enddef
