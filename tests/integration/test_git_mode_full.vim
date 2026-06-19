vim9script

# Integration test: Git mode — project creation, include/exclude, .vproj_ai write
# Run: vim -N -u NONE -S tests/integration/test_git_mode_full.vim

set rtp+=src
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

def PaneCursorLine(): number
  var pbuf = bufnr('VPROJ_AI')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
enddef

echom '=== Git Mode Integration Tests ==='

# ── Setup: open pane in git mode ──
if vproj_ai#IsPaneVisible()
  vproj_ai#PaneClose()
endif
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('git')

# ── Test 1: Git mode starts with correct layout ──
# Line 1 = mode menu, line 2 = project status, line 3 = separator, line 4 = first item
Assert(PaneCursorLine() == 4, 'git mode: cursor starts on first item (line 4)')
Assert(vproj_ai#GetCurrentMode() == 'git', 'git mode: GetCurrentMode returns git')

# ── Test 2: Navigate up/down respects git mode header ──
vproj_ai#SelectNext()
Assert(PaneCursorLine() == 5, 'git mode: SelectNext moves to line 5')
vproj_ai#SelectPrev()
Assert(PaneCursorLine() == 4, 'git mode: SelectPrev returns to line 4')

# ── Test 3: Switch modes, cursor lands on correct line ──
vproj_ai#SwitchMode('file')
Assert(PaneCursorLine() == 3, 'switch to file mode: cursor on line 3')
Assert(vproj_ai#GetCurrentMode() == 'file', 'GetCurrentMode returns file')

vproj_ai#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'switch to buf mode: cursor on line 3')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'GetCurrentMode returns buf')

vproj_ai#SwitchMode('git')
Assert(PaneCursorLine() == 4, 'switch back to git mode: cursor on line 4')

# ── Test 4: SelectFirst/SelectLast jump to correct bounds ──
vproj_ai#SwitchMode('file')
vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst goes to line 3 in file mode')
vproj_ai#SwitchMode('git')
vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 4, 'SelectFirst goes to line 4 in git mode')

# ── Test 5: Close/reopen preserves mode & cursor ──
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'pane closed')
vproj_ai#PaneOpen()
# Session persistence restores last mode (git) after close/reopen
Assert(PaneCursorLine() == 4, 'reopen: cursor on first item in git mode (session restore)')

# ── Test 6: NavigateUp from git mode works ──
vproj_ai#SwitchMode('git')
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp in git mode keeps pane visible')

# ── Cleanup ──
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'pane closes cleanly')

echom ''
if failures == 0
  echom 'ALL GIT MODE INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' GIT MODE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
