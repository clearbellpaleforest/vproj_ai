vim9script

# Integration tests for vproj_ai add-on
# Run: vim -N -u NONE -S tests/integration/test_ai_addon.vim

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore

var failures: number = 0

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

echom '=== vproj_ai Add-on Integration Tests ==='

# ── Plugin Coexistence ──
Assert(exists('g:loaded_vproj'), 'vproj loaded')
Assert(exists('g:loaded_vproj_ai'), 'vproj_ai loaded')

# Trigger vproj autoload by toggling
call vproj#PaneToggle()
call vproj#PaneToggle()

Assert(exists('*vproj#GetPaneBufnr'), 'vproj exports GetPaneBufnr')

# Trigger vproj_ai autoload
call vproj_ai#OnBufEnter()

Assert(exists('*vproj_ai#AiPrompt'), 'vproj_ai AiPrompt function exists')
Assert(exists('*vproj_ai#AiCall'), 'vproj_ai AiCall function exists')
Assert(exists('*vproj_ai#OnBufEnter'), 'vproj_ai OnBufEnter function exists')

# ── A mapping injection ──
call vproj#PaneToggle()
var pb: number = vproj#GetPaneBufnr()
if pb > 0
  execute 'buffer ' .. pb
  call vproj_ai#OnBufEnter()
  var a_map: string = maparg('A', 'n')
  Assert(!empty(a_map), 'A mapping injected in pane buffer')
  Assert(stridx(a_map, 'vproj_ai#AiPrompt') >= 0, 'A mapping calls AiPrompt')
else
  echom '(headless: pane buf -1, A mapping tested via smoke test)'
endif

# ── Pane operation ──
if vproj#IsPaneVisible()
  Assert(vproj#GetCurrentMode() == 'file', 'Default mode is file')
  vproj#PaneToggle()
  Assert(!vproj#IsPaneVisible(), 'PaneToggle closes')
else
  echom '(headless: pane not visible)'
endif

# Report
echom ''
if failures == 0
  echom 'ALL AI ADD-ON INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' AI ADD-ON TEST(S) FAILED.'
  echohl None
  cquit!
endif

qa!
