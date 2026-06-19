vim9script

# Smoke test for VPROJ_AI plugin
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

# Load the plugin
set rtp+=src
runtime! plugin/vproj_ai.vim
set nomore

# Clear stale session so tests start from known state
call delete(expand('~/.cache/vproj_ai/session'))

# Test 1: Plugin loaded
Assert(exists('g:loaded_vproj'), 'Plugin loads without errors')

# Test 2: Pane starts closed
Assert(!vproj_ai#IsPaneVisible(), 'Pane starts closed')

# Test 3: Open pane
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'Pane opens')

# Test 4: Default mode is file
Assert(vproj_ai#GetCurrentMode() == 'file', 'Default mode is file')

# Test 5: Switch to buf mode
vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'Switch to buf mode')

# Test 6: Switch to file mode
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'Switch back to file mode')

# Test 7: Pane width is default 40
Assert(vproj_ai#GetPaneWidth() == 40, 'Default pane width is 40')

# Test 8: Grow and shrink
vproj_ai#PaneGrow()
Assert(vproj_ai#GetPaneWidth() == 41, 'PaneGrow increases width')
vproj_ai#PaneShrink()
Assert(vproj_ai#GetPaneWidth() == 40, 'PaneShrink decreases width')

# Test 9: Switch to git mode
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'Switch to git mode')

# Test 10: Switch back to file mode
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'Switch back from git mode')

# Test 11: Close pane
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'Pane closes')

# Test 12: Toggle open
vproj_ai#PaneToggle()
Assert(vproj_ai#IsPaneVisible(), 'PaneToggle opens')
vproj_ai#PaneToggle()
Assert(!vproj_ai#IsPaneVisible(), 'PaneToggle closes')

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
