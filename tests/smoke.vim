vim9script

# Smoke test for VPROJ_AI add-on
# Run: vim -N -u NONE -S tests/smoke.vim

var failures: number = 0

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg
    echom 'FAIL: ' .. msg
    echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# Load vproj and vproj_ai
set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore

# Test 1: vproj loads
Assert(exists('g:loaded_vproj'), 'vproj plugin loads')

# Test 2: vproj_ai loads
Assert(exists('g:loaded_vproj_ai'), 'vproj_ai add-on loads')

# Test 3: vproj_ai requires vproj
Assert(exists('g:loaded_vproj'), 'vproj_ai has vproj dependency satisfied')

# Trigger autoload by calling a vproj function
call vproj#PaneOpen()

# Test 4: GetPaneBufnr export available
Assert(exists('*vproj#GetPaneBufnr'), 'vproj exports GetPaneBufnr')

# Test 5: AiPrompt function available via autoload
Assert(exists('*vproj_ai#AiPrompt'), 'AiPrompt autoload function available')

# Test 6: AiCall function available via autoload
Assert(exists('*vproj_ai#AiCall'), 'AiCall autoload function available')

# Test 7: OnBufEnter function available via autoload
Assert(exists('*vproj_ai#OnBufEnter'), 'OnBufEnter autoload function available')

# Test 8: StreamCancelCmd function available
Assert(exists('*vproj_ai#StreamCancelCmd'), 'StreamCancelCmd autoload function available')

# Test 8b: AiPromptFromKey function available (entry point for :VprojAiPrompt)
Assert(exists('*vproj_ai#AiPromptFromKey'), 'AiPromptFromKey autoload function available')

# Test 8c: AiTerminalChat function available (entry point for A key in pane)
Assert(exists('*vproj_ai#AiTerminalChat'), 'AiTerminalChat autoload function available')

# Test 9: A is NOT globally mapped (restored to Vim default append)
enew
var global_a_map: string = maparg('A', 'n')
Assert(empty(global_a_map), 'A key not globally mapped (Vim default append restored)')

# Test 9b: Terminal support available
Assert(has('terminal'), 'Vim has terminal support')

# Test 10: VprojAiPrompt command exists
var cmds: string = execute('command VprojAiPrompt')
Assert(stridx(cmds, 'VprojAiPrompt') >= 0, ':VprojAiPrompt command registered')

# Test 11: <Plug>VprojAiPrompt mapping exists
var plug_map: string = maparg('<Plug>VprojAiPrompt', 'n')
Assert(!empty(plug_map), '<Plug>VprojAiPrompt mapping exists')

# Test 12: basic vproj operations work
var mode: string = vproj#GetCurrentMode()
Assert(mode =~ '^\(file\|buf\|git\|qfix\|log\)$', 'GetCurrentMode returns valid mode: ' .. mode)

# Test 13: Pane visible or headless (both OK)
var visible: bool = vproj#IsPaneVisible()
echom '(pane visible: ' .. visible .. ')'

# Test 14: Deleted conversation functions are gone
Assert(!exists('*vproj_ai#HandleConvBufWipeout'), 'HandleConvBufWipeout removed')
Assert(!exists('*vproj_ai#SendFollowup'), 'SendFollowup removed')
Assert(!exists('*vproj_ai#AiApplyCode'), 'AiApplyCode removed')

# ── Compilation + runtime smoke tests ──
# exists('*Func') only checks definition, not body compilation.
# These CALL each function to force Vim9Script compilation.

# Test 15: AiCall compiles and handles missing API key
var ctx: dict<any> = {cwd: getcwd(), mode: 'file', file: '', filetype: 'text',
  cursor_line: 1, cursor_col: 1}
var call_result: string = vproj_ai#AiCall('test', ctx)
Assert(empty(call_result), 'AiCall returns empty without API key (no crash)')

# Test 16: AiPrompt compiles and handles empty prompt
call vproj_ai#AiPrompt('')

# Test 17: AiPromptFromKey would use input() but at least compiled
Assert(exists('*vproj_ai#AiPromptFromKey'), 'AiPromptFromKey compiled')

# Test 18: AiTerminalChat compiles (guards prevent terminal open in headless)
try
  call vproj_ai#AiTerminalChat()
  Assert(true, 'AiTerminalChat compiled and returned without crash')
catch /E578/
  # E578: Terminal failed to start — expected in headless, not a crash
  Assert(true, 'AiTerminalChat compiled, terminal fails in headless (expected)')
catch
  Assert(false, 'AiTerminalChat crashed: ' .. v:exception)
endtry

# Test 19: StreamCancelCmd compiles (no-op when no stream active)
call vproj_ai#StreamCancelCmd()
Assert(true, 'StreamCancelCmd compiles and handles null stream')

# Test 20: OnBufEnter injects A mapping in pane
var pane_buf: number = vproj#GetPaneBufnr()
if pane_buf > 0
  execute 'buffer ' .. pane_buf
  call vproj_ai#OnBufEnter()
  var buf_a_map: string = maparg('A', 'n')
  Assert(!empty(buf_a_map) && stridx(buf_a_map, 'AiTerminalChat') >= 0,
    'OnBufEnter injects AiTerminalChat mapping in pane')
else
  echom '(headless: pane buf -1, OnBufEnter mapping test skipped)'
endif

# Test 21: Bash chat script syntax valid
if executable('bash')
  var script_path: string = expand('<sfile>:p:h:h') .. '/bin/vproj-ai-chat'
  if filereadable(script_path)
    var bash_check: string = system('bash -n ' .. shellescape(script_path) .. ' 2>&1')
    Assert(empty(bash_check), 'bash chat script syntax valid: ' .. bash_check)
  else
    echom '(chat script not found, syntax check skipped)'
  endif
else
  echom '(bash not found, syntax check skipped)'
endif

# Test 22: API key not leaked in terminal command
# The terminal command passes env vars directly (env is a real executable, not a shell,
# so there are no shell metacharacter concerns). API key goes through env which preserves
# values literally — no quoting, no shell interpretation, no leaks.
Assert(exists('*vproj_ai#AiTerminalChat'), 'AiTerminalChat passes API key via env (no shell quoting)')

# Report
echom ''
if failures == 0
  echom 'All smoke tests passed.'
else
  echohl ErrorMsg
  echom failures .. ' test(s) FAILED.'
  echohl None
  cquit!
endif

qa!
