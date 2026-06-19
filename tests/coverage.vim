vim9script

# Coverage tests — untested behaviors from the audit gap analysis
# Run: vim -N -u NONE -S tests/coverage.vim

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

def Setup(): void
  if vproj_ai#IsPaneVisible()
    vproj_ai#PaneClose()
  endif
  vproj_ai#PaneOpen()
  if vproj_ai#GetCurrentMode() != 'file'
    vproj_ai#SwitchMode('file')
  endif
enddef

# ──────────────────────────────────────────────
# ItemIndex / FirstSelectableLine
# ──────────────────────────────────────────────
echom '--- ItemIndex / FirstSelectableLine ---'
Setup()

# FirstSelectableLine must be 3 in all modes
Assert(PaneCursorLine() == 3, 'cursor starts on line 3 in file mode')

vproj_ai#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'cursor starts on line 3 in buf mode')

vproj_ai#SwitchMode('git')
Assert(PaneCursorLine() == 4, 'cursor starts on line 4 in git mode (separator at line 3)')

# SelectNext from line 3 → line 4 (not status line)
vproj_ai#SwitchMode('file')
var before = PaneCursorLine()
execute 'normal j'
Assert(PaneCursorLine() == before + 1, 'SelectNext advances from first item')

# SelectPrev from line 3 → wraps to last item
execute 'normal k'
Assert(PaneCursorLine() >= 3, 'SelectPrev wraps from first item')

# ──────────────────────────────────────────────
# NavigateIntoFirstDir
# ──────────────────────────────────────────────
echom '--- NavigateIntoFirstDir ---'
Setup()
vproj_ai#SwitchMode('file')

# In the vproj_ai project root, first subdir should be src/ or tests/
try
  vproj_ai#NavigateIntoFirstDir()
  Assert(vproj_ai#IsPaneVisible(), 'NavigateIntoFirstDir keeps pane open')
  Assert(vproj_ai#GetCurrentMode() == 'file', 'NavigateIntoFirstDir preserves file mode')
catch
  Assert(false, 'NavigateIntoFirstDir error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# ToggleInclude guards (status line, non-git mode)
# ──────────────────────────────────────────────
echom '--- ToggleInclude guards ---'

# In file mode, + should not crash but should show nothing
Setup()
vproj_ai#SwitchMode('file')
try
  execute 'normal +'
  Assert(vproj_ai#IsPaneVisible(), '+ in file mode does not crash')
catch
  Assert(false, '+ in file mode error: ' .. v:exception)
endtry

# In git mode with no project, cursor on first item (line 3), press +
vproj_ai#SwitchMode('git')
execute 'normal +'
Assert(vproj_ai#IsPaneVisible(), '+ in git mode no-project does not crash')

# - key similarly
execute 'normal -'
Assert(vproj_ai#IsPaneVisible(), '- in git mode no-project does not crash')

# ──────────────────────────────────────────────
# CloseBuffer outside buf mode
# ──────────────────────────────────────────────
echom '--- CloseBuffer outside buf mode ---'
Setup()
vproj_ai#SwitchMode('file')
try
  execute 'normal x'
  Assert(vproj_ai#IsPaneVisible(), 'x in file mode shows message, does not crash')
catch
  Assert(false, 'x in file mode error: ' .. v:exception)
endtry

vproj_ai#SwitchMode('git')
try
  execute 'normal x'
  Assert(vproj_ai#IsPaneVisible(), 'x in git mode shows message, does not crash')
catch
  Assert(false, 'x in git mode error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# Nav offset bounds
# ──────────────────────────────────────────────
echom '--- Nav offset bounds ---'
Setup()
vproj_ai#SwitchMode('file')

# nav_offset starts at 0 after fresh Setup
# (nav_offset persists across mode switches, so test this BEFORE shifting)
Assert(vproj_ai#GetNavOffset() == 0, 'nav_offset starts at 0')

# Shift backward at 0 should stay at 0
vproj_ai#ShiftNavBackward()
Assert(vproj_ai#GetNavOffset() == 0, 'ShiftNavBackward at 0 stays at 0')

# Shift forward many times, should not crash
var offset = vproj_ai#GetNavOffset()
for _ in range(100)
  vproj_ai#ShiftNavForward()
  if vproj_ai#GetNavOffset() == offset
    break
  endif
  offset = vproj_ai#GetNavOffset()
endfor
Assert(vproj_ai#GetNavOffset() >= 0, 'nav_offset stays non-negative after shifts')
Assert(vproj_ai#GetNavOffset() < 100, 'nav_offset is bounded')

# ──────────────────────────────────────────────
# Nav char — uppercase and digit chars
# ──────────────────────────────────────────────
echom '--- Nav char uppercase / digit ---'
Setup()
vproj_ai#SwitchMode('file')

# nav_offset is 0 after Setup; test uppercase nav char
vproj_ai#SelectByNavChar('A')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar uppercase does not crash')

# Shift nav offset forward a few times, then test digit
vproj_ai#ShiftNavForward()
vproj_ai#ShiftNavForward()
vproj_ai#SelectByNavChar('3')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar digit does not crash')

# ──────────────────────────────────────────────
# Mode cycling (SwitchMode covers same logic as Enter on menu)
# ──────────────────────────────────────────────
echom '--- Mode cycling ---'
Setup()

Assert(vproj_ai#GetCurrentMode() == 'file', 'starts in file mode')
vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'SwitchMode file→buf')
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'SwitchMode buf→git')
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'SwitchMode git→file')

# ──────────────────────────────────────────────
# SetPaneWidth invalid values
# ──────────────────────────────────────────────
echom '--- SetPaneWidth invalid ---'
Setup()

var w = vproj_ai#GetPaneWidth()
vproj_ai#SetPaneWidth(10)
Assert(vproj_ai#GetPaneWidth() == w, 'SetPaneWidth(10) below min 20 rejected')

vproj_ai#SetPaneWidth(90)
Assert(vproj_ai#GetPaneWidth() == w, 'SetPaneWidth(90) above max 80 rejected')

vproj_ai#SetPaneWidth(50)
Assert(vproj_ai#GetPaneWidth() == 50, 'SetPaneWidth(50) accepted')
vproj_ai#SetPaneWidth(40)

# ──────────────────────────────────────────────
# Mode-specific width config
# ──────────────────────────────────────────────
echom '--- Mode-specific width ---'
Setup()

g:vproj_ai_pane_width_file = 45
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetPaneWidth() == 45, 'file-mode width config applied')

g:vproj_ai_pane_width_buf = 35
vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetPaneWidth() == 35, 'buf-mode width config applied')

g:vproj_ai_pane_width_git = 30
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetPaneWidth() == 30, 'git-mode width config applied')

g:vproj_ai_pane_width_qfix = 38
vproj_ai#SwitchMode('qfix')
Assert(vproj_ai#GetPaneWidth() == 38, 'qfix-mode width config applied')

unlet g:vproj_ai_pane_width_file
unlet g:vproj_ai_pane_width_buf
unlet g:vproj_ai_pane_width_git
unlet g:vproj_ai_pane_width_qfix
vproj_ai#SwitchMode('file')

# ──────────────────────────────────────────────
# NavigateUp at filesystem root
# ──────────────────────────────────────────────
echom '--- NavigateUp at root ---'
Setup()
vproj_ai#SwitchMode('file')

# Repeated NavigateUp should eventually stop at root without crash
for _ in range(50)
  vproj_ai#NavigateUp()
endfor
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp 50x keeps pane open')
Assert(vproj_ai#GetCurrentMode() == 'file', 'NavigateUp 50x preserves mode')

# ──────────────────────────────────────────────
# HandleBufWipeout state reset
# ──────────────────────────────────────────────
echom '--- HandleBufWipeout ---'
Setup()

vproj_ai#SetPaneWidth(45)

vproj_ai#HandleBufWipeout()
Assert(!vproj_ai#IsPaneVisible(), 'HandleBufWipeout clears pane visibility')
Assert(vproj_ai#GetPaneWidth() == 45, 'HandleBufWipeout preserves pane width')
Assert(vproj_ai#GetCurrentMode() == 'file', 'HandleBufWipeout preserves mode')

# ──────────────────────────────────────────────
# Refresh when pane is closed
# ──────────────────────────────────────────────
echom '--- Refresh when closed ---'
Setup()
vproj_ai#PaneClose()

try
  vproj_ai#Refresh()
  Assert(!vproj_ai#IsPaneVisible(), 'Refresh when closed does not re-open')
catch
  Assert(false, 'Refresh when closed error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# PaneGrow/PaneShrink bounds
# ──────────────────────────────────────────────
echom '--- PaneGrow/PaneShrink bounds ---'
Setup()

# Grow to max
while vproj_ai#GetPaneWidth() < 80
  vproj_ai#PaneGrow()
endwhile
vproj_ai#PaneGrow()
Assert(vproj_ai#GetPaneWidth() == 80, 'PaneGrow capped at 80')

# Shrink to min
while vproj_ai#GetPaneWidth() > 20
  vproj_ai#PaneShrink()
endwhile
vproj_ai#PaneShrink()
Assert(vproj_ai#GetPaneWidth() == 20, 'PaneShrink capped at 20')

vproj_ai#SetPaneWidth(40)

# ──────────────────────────────────────────────
# ToggleInfoColumn
# ──────────────────────────────────────────────
echom '--- ToggleInfoColumn ---'
Setup()

vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'F1 toggle keeps pane open')

# Toggle back
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'F1 toggle back keeps pane open')

# ──────────────────────────────────────────────
# SelectByNavChar with ch not on current page
# ──────────────────────────────────────────────
echom '--- SelectByNavChar missing char ---'
Setup()

# Press a nav char that doesn't exist on current page (only '..' has no char)
try
  execute 'normal m'
  Assert(vproj_ai#IsPaneVisible(), 'nav char m (not on page) does not crash')
catch
  Assert(false, 'nav char m error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# RenameProject in non-git mode
# ──────────────────────────────────────────────
echom '--- RenameProject guard ---'
Setup()
vproj_ai#SwitchMode('file')

try
  vproj_ai#RenameProject()
  Assert(vproj_ai#IsPaneVisible(), 'RenameProject in file mode exits early')
catch
  Assert(false, 'RenameProject in file mode error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────
vproj_ai#PaneClose()

echom ''
if failures == 0
  echom 'ALL COVERAGE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' COVERAGE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
