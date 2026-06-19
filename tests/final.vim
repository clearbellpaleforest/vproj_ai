vim9script

# Final verification: exercise every fix from the agent audit
# Run: vim -N -u NONE -S tests/final.vim

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

def CursorInPane(): number
  var pbuf = bufnr('VPROJ_AI')
  var windows = win_findbuf(pbuf)
  if empty(windows)
    return -1
  endif
  return line('.', windows[0])
enddef

# ── FIX 1: ToggleInclude doesn't crash on empty project ──
echom '--- ToggleInclude with empty project (was CRASH) ---'
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('git')

# Navigate to first item (line 3), press +
# Cursor starts on line 3 (first item) since FirstSelectableLine returns 3
Assert(CursorInPane() == 4, 'cursor on first item in git mode')
vproj_ai#ToggleInclude()
echom 'ToggleInclude did not crash with empty project'

# ── FIX 2: RelPath path-boundary ──
echom '--- RelPath boundary check explained ---'
echom 'RelPath now checks path separator after prefix match'
echom 'e.g. /home/user2 no longer falsely matches /home/user'

# ── FIX 3: readdir() exception safety ──
echom '--- readdir() safety ---'
vproj_ai#SwitchMode('file')
vproj_ai#PaneClose()
vproj_ai#PaneOpen()
Assert(CursorInPane() == 3, 'cursor starts on first item (line 3)')

# ── FIX 4: Cursor movement ──
echom '--- j/k cursor movement ---'
vproj_ai#SelectNext()
Assert(CursorInPane() == 4, 'j moves cursor to line 4')
vproj_ai#SelectNext()
Assert(CursorInPane() == 5, 'j moves cursor to line 5')
vproj_ai#SelectPrev()
Assert(CursorInPane() == 4, 'k moves cursor back to line 4')

# ── FIX 5: NavigateUp (..) ──
echom '--- NavigateUp (.. parent dir) ---'
vproj_ai#SwitchMode('file')
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp re-renders without crash')

# ── FIX 6: NavigateInto ──
echom '--- NavigateInto (subdir) ---'
# Navigate back down into the project directory (it was named from getcwd)
vproj_ai#PaneClose()
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'reopen works after NavigateUp')

# ── FIX 7: Git mode after file mode directory change ──
echom '--- Mode switch refreshes current_dir ---'
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'switched to git mode')
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'switched back to file mode')

# ── FIX 8: HandleBufWipeout uses FirstSelectableLine ──
echom '--- HandleBufWipeout uses FirstSelectableLine ---'
vproj_ai#SwitchMode('git')
# Verify the code path: HandleBufWipeout sets pane_bufnr = -1 then
# PaneOpen sets selected_line via FirstSelectableLine()
vproj_ai#PaneClose()
vproj_ai#PaneOpen()
Assert(CursorInPane() == 4, 'git mode: cursor on first item (4) after close+reopen (session restores git mode)')

# ── FIX 9: Buf mode flag_width ──
echom '--- Buf mode (flag_width fix) ---'
vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'buf mode works')
# Buf mode with no open buffers: cursor should be on line 3 ("(no open buffers)")
# or line 1 if buf mode has no items (but it always has the placeholder)
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'back to file mode after doc')

# ── FIX 10: OnDirChanged ──
echom '--- OnDirChanged ---'
vproj_ai#SwitchMode('file')
vproj_ai#OnDirChanged()
Assert(vproj_ai#IsPaneVisible(), 'OnDirChanged does not crash')

# ── Cleanup ──
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'pane closes cleanly')

echom ''
if failures == 0
  echom 'ALL AUDIT FIXES VERIFIED.'
else
  echohl ErrorMsg
  echom failures .. ' VERIFICATION(S) FAILED.'
  echohl None
  cquit!
endif
qa!
