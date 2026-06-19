vim9script

# Unit test: FirstSelectableLine mode-awareness
# Run: vim -N -u NONE -S tests/unit/test_first_selectable.vim

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

def SetupPane(): void
  if vproj_ai#IsPaneVisible()
    vproj_ai#PaneClose()
  endif
  vproj_ai#PaneOpen()
  if vproj_ai#GetCurrentMode() != 'file'
    vproj_ai#SwitchMode('file')
  endif
enddef

echom '--- FirstSelectableLine ---'

# File mode: menu at 1, separator at 2, first item at 3
SetupPane()
Assert(PaneCursorLine() == 3, 'file mode: cursor on line 3')

# Buf mode: menu at 1, separator at 2, first item at 3
vproj_ai#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'buf mode: cursor on line 3')

# Git mode: menu at 1, status at 2, separator at 3, first item at 4
vproj_ai#SwitchMode('git')
Assert(PaneCursorLine() == 4, 'git mode: cursor on line 4')

# Back to file mode: first item at line 3
vproj_ai#SwitchMode('file')
Assert(PaneCursorLine() == 3, 'back to file mode: cursor on line 3')

vproj_ai#PaneClose()

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
