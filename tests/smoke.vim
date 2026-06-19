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

# Test 7b: AiSendFollowup function available via autoload
Assert(exists('*vproj_ai#AiSendFollowup'), 'AiSendFollowup autoload function available')

# Test 7c: AiApplyCode function available via autoload
Assert(exists('*vproj_ai#AiApplyCode'), 'AiApplyCode autoload function available')

# Test 8: VprojAiPrompt command exists
var cmds: string = execute('command VprojAiPrompt')
Assert(stridx(cmds, 'VprojAiPrompt') >= 0, ':VprojAiPrompt command registered')

# Test 9: <Plug>VprojAiPrompt mapping exists
var plug_map: string = maparg('<Plug>VprojAiPrompt', 'n')
Assert(!empty(plug_map), '<Plug>VprojAiPrompt mapping exists')

# Test 10: basic vproj operations work
var mode: string = vproj#GetCurrentMode()
Assert(mode =~ '^\(file\|buf\|git\|qfix\|log\)$', 'GetCurrentMode returns valid mode: ' .. mode)

# Test 11: Pane visible or headless (both OK)
var visible: bool = vproj#IsPaneVisible()
echom '(pane visible: ' .. visible .. ')'

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
