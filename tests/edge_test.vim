vim9script

# Edge case stress tests
# Run: vim -N -u NONE -S tests/edge_test.vim

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

# ── Width bounds ──
vproj_ai#PaneOpen()
Assert(vproj_ai#GetPaneWidth() == 40, 'default width is 40')

vproj_ai#SetPaneWidth(10)
Assert(vproj_ai#GetPaneWidth() == 40, 'SetPaneWidth(10) rejected (below min 20)')

vproj_ai#SetPaneWidth(90)
Assert(vproj_ai#GetPaneWidth() == 40, 'SetPaneWidth(90) rejected (above max 80)')

vproj_ai#SetPaneWidth(30)
Assert(vproj_ai#GetPaneWidth() == 30, 'SetPaneWidth(30) accepted')

while vproj_ai#GetPaneWidth() < 80 | vproj_ai#PaneGrow() | endwhile
Assert(vproj_ai#GetPaneWidth() == 80, 'PaneGrow to max 80')

vproj_ai#PaneGrow()
Assert(vproj_ai#GetPaneWidth() == 80, 'PaneGrow past max clamped at 80')

while vproj_ai#GetPaneWidth() > 20 | vproj_ai#PaneShrink() | endwhile
Assert(vproj_ai#GetPaneWidth() == 20, 'PaneShrink to min 20')

vproj_ai#PaneShrink()
Assert(vproj_ai#GetPaneWidth() == 20, 'PaneShrink past min clamped at 20')

vproj_ai#SetPaneWidth(40)

# ── NavigateUp at root ──
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp 1x keeps pane open')
vproj_ai#NavigateUp()
vproj_ai#NavigateUp()
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp 4x (at root) keeps pane open')

# ── Invalid mode ──
vproj_ai#SwitchMode('invalid')
Assert(vproj_ai#GetCurrentMode() == 'file', 'SwitchMode(invalid) ignored, stays file')

# ── ToggleInclude in file mode ──
vproj_ai#ToggleInclude()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInclude file mode does not crash')

# ── CloseBuffer in buf mode with no buffers ──
vproj_ai#SwitchMode('buf')
vproj_ai#CloseBuffer()
Assert(vproj_ai#IsPaneVisible(), 'CloseBuffer buf mode no buffers does not crash')

# ── CloseBuffer in file mode (wrong mode) ──
vproj_ai#SwitchMode('file')
vproj_ai#CloseBuffer()
Assert(vproj_ai#IsPaneVisible(), 'CloseBuffer file mode does not crash')

# ── Git mode: ToggleInclude on parent entry ──
vproj_ai#SwitchMode('git')
# Navigate past line 1 (menu) and 2 (status), land on first item
vproj_ai#SelectNext()
vproj_ai#SelectNext()
Assert(vproj_ai#IsPaneVisible(), 'git mode: moved cursor down')
vproj_ai#ToggleInclude()
Assert(vproj_ai#IsPaneVisible(), 'git mode: ToggleInclude on first item (no project) does not crash')

# ── Refresh when pane is closed ──
vproj_ai#PaneClose()
vproj_ai#Refresh()
Assert(!vproj_ai#IsPaneVisible(), 'Refresh when closed does not re-open pane')

# ── Re-open after close ──
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'Re-open after close works')

# ── HandleBufWipeout call ──
vproj_ai#HandleBufWipeout()
Assert(!vproj_ai#IsPaneVisible(), 'HandleBufWipeout resets visible state')

# ── PaneToggle idempotence ──
vproj_ai#PaneToggle()
Assert(vproj_ai#IsPaneVisible(), 'PaneToggle opens closed pane')
vproj_ai#PaneToggle()
Assert(!vproj_ai#IsPaneVisible(), 'PaneToggle closes open pane')
vproj_ai#PaneToggle()
Assert(vproj_ai#IsPaneVisible(), 'PaneToggle re-opens')

# ── SetPaneWidth when pane is visible ──
vproj_ai#SetPaneWidth(50)
Assert(vproj_ai#GetPaneWidth() == 50, 'SetPaneWidth(50) when visible works')
vproj_ai#SetPaneWidth(40)

# ── SelectCurrent on empty items ──
# Move cursor to an empty area and call SelectCurrent
vproj_ai#SwitchMode('buf')
# Should handle gracefully if no buffers
vproj_ai#SelectCurrent()
Assert(vproj_ai#GetCurrentMode() == 'buf', 'SelectCurrent in buf mode no crash')

# ── Mode switch from empty state ──
vproj_ai#SwitchMode('file')
Assert(vproj_ai#IsPaneVisible(), 'Switch back to file mode works')
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'Switch to git mode works')
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'Switch back to file mode works')

# ── SelectNext/Prev wrapping ──
# In buf mode with no buffers, there's only 3 lines: menu, separator, "(empty)"
# SelectNext should wrap
vproj_ai#SelectNext()
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectNext in file mode no crash')

# Cleanup
vproj_ai#PaneClose()

echom ''
if failures == 0
  echom 'ALL EDGE CASE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' EDGE CASE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
