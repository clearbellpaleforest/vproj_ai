vim9script

# Integration test: Paging — activate paging with many items
# Run: vim -N -u NONE -S tests/integration/test_paging.vim

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

echom '=== Paging Integration Tests ==='

# ── Setup: create temp directory with many files ──
var tmpdir: string = '/tmp/vproj_paging_test'
silent! call delete(tmpdir, 'rf')
mkdir(tmpdir)
var f: number = 0
while f < 60
  writefile(['test'], printf('%s/file_%02d.txt', tmpdir, f))
  f += 1
endwhile

# ── Navigate to temp dir and open pane ──
execute 'cd' tmpdir
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('file')

Assert(vproj_ai#IsPaneVisible(), 'pane visible with 60-item directory')
Assert(PaneCursorLine() == 3, 'cursor starts on line 3')

# ── Navigate through items without crashing ──
vproj_ai#SelectNext()
Assert(PaneCursorLine() == 4, 'SelectNext to line 4')
vproj_ai#SelectNext()
Assert(PaneCursorLine() == 5, 'SelectNext to line 5')
vproj_ai#SelectPrev()
Assert(PaneCursorLine() == 4, 'SelectPrev back to line 4')

# ── Jump to first and last ──
vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst to line 3')

# ── NextPage/PrevPage don't crash ──
vproj_ai#NextPage()
Assert(vproj_ai#IsPaneVisible(), 'NextPage does not crash')

vproj_ai#PrevPage()
Assert(vproj_ai#IsPaneVisible(), 'PrevPage does not crash')

# ── Mode switch with paged items ──
vproj_ai#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'buf mode after paged file mode: cursor on line 3')

vproj_ai#SwitchMode('git')
Assert(PaneCursorLine() == 4, 'git mode after paged file mode: cursor on line 4')

# ── Nav offset doesn't leak between modes ──
vproj_ai#ShiftNavForward()
vproj_ai#SwitchMode('file')
vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 3, 'nav shifted then mode switched: SelectFirst still line 3')

# ── Cleanup ──
vproj_ai#PaneClose()
execute 'cd' '/home/aldous/Desktop/vproj_ai'
silent! call delete(tmpdir, 'rf')

Assert(!vproj_ai#IsPaneVisible(), 'pane closed cleanly')

echom ''
if failures == 0
  echom 'ALL PAGING TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' PAGING TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
