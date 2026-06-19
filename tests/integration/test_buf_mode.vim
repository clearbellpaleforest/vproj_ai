vim9script

# Integration test: Buf mode — buffers, modification flags, selection
# Run: vim -N -u NONE -S tests/integration/test_buf_mode.vim

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

echom '=== Buf Mode Integration Tests ==='

# ── Setup: open some buffers first ──
edit! /tmp/vproj_test_a.txt
edit! /tmp/vproj_test_b.txt
edit! /tmp/vproj_test_c.txt

# ── Open pane in buf mode ──
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('buf')

Assert(vproj_ai#GetCurrentMode() == 'buf', 'buf mode active')
Assert(PaneCursorLine() == 3, 'buf mode: cursor on first item (line 3)')

# ── Navigate through buffers ──
vproj_ai#SelectNext()
Assert(PaneCursorLine() == 4, 'buf mode: SelectNext to line 4')

vproj_ai#SelectPrev()
Assert(PaneCursorLine() == 3, 'buf mode: SelectPrev to line 3')

# ── Switch to buf mode from another mode ──
vproj_ai#SwitchMode('file')
vproj_ai#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'buf mode after round-trip: cursor on line 3')

# ── Jump to first/last ──
vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 3, 'buf mode: SelectFirst to line 3')

# ── NavigateUp in buf mode ──
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp in buf mode does not crash')

# ── Cleanup ──
vproj_ai#PaneClose()
bwipeout! /tmp/vproj_test_a.txt
bwipeout! /tmp/vproj_test_b.txt
bwipeout! /tmp/vproj_test_c.txt

echom ''
if failures == 0
  echom 'ALL BUF MODE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' BUF MODE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
