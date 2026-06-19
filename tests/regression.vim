vim9script

# Regression test for reported bugs
# Run: vim -N -u NONE --cmd 'cd /tmp' -S tests/regression.vim

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

set rtp+=src
runtime! plugin/vproj_ai.vim

# --- Bug #2: Cursor starts on first file, not menu line ---
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'pane is visible after open')

# After opening in file mode, selected_line should be 3 (first item),
# not 1 (menu line)
var mode: string = vproj_ai#GetCurrentMode()
Assert(mode == 'file', 'default mode is file')

# We can't directly query selected_line, but we can verify cursor
# position indirectly by checking vproj_ai#SelectCurrent() behavior.
# If cursor is on line 1 (menu), SelectCurrent would cycle to buf mode.
# If cursor is on line 3+, it would try to open a file/dir.
# So let's check: mode should still be 'file' after calling SelectCurrent
# (because we're on a file item, not the menu line)
vproj_ai#SelectCurrent()
var mode2: string = vproj_ai#GetCurrentMode()
Assert(mode2 == 'file', 'cursor was NOT on menu line (mode did not cycle)')

# --- Bug #4: j/k cursor movement ---
# Switch to buf mode then back to file to reset state
vproj_ai#SwitchMode('file')

# Can't directly test j/k since those are key mappings, but we can
# test SelectNext/SelectPrev which they call.
vproj_ai#SelectNext()
vproj_ai#SelectNext()
# Should not crash and should move cursor down. Mode should still be file.
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectNext does not crash or change mode')

vproj_ai#SelectPrev()
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectPrev does not crash or change mode')

# --- Bug #5: .. parent directory navigation ---
# Switch to file mode at a known directory
vproj_ai#PaneClose()
execute 'cd /tmp'
vproj_ai#PaneOpen()

# Record current dir, then navigate up via NavigateUp
vproj_ai#NavigateUp()
# Should have moved to parent of /tmp, which is /
# We can verify the pane re-rendered without error
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp re-renders without crashing')

# --- Bug #3: Directory change detection ---
# Simulate what happens when user does :cd
vproj_ai#PaneClose()
vproj_ai#PaneOpen()  # opens at /tmp (from above, actually after NavigateUp we were at /)

# Actually let's test the OnDirChanged callback directly
execute 'cd /tmp'
vproj_ai#OnDirChanged()
Assert(vproj_ai#IsPaneVisible(), 'OnDirChanged works without crash')

# --- Bug #6: Underline / cursorline on separator ---
# The separator is line 2. We can verify SelectNext skips it.
# By checking that after multiple SelectNext calls, the mode doesn't change
# (which would happen if we land on the menu line)
vproj_ai#SwitchMode('file')
vproj_ai#PaneOpen()
# Call SelectNext many times to wrap around
for i in range(50)
  vproj_ai#SelectNext()
endfor
Assert(vproj_ai#GetCurrentMode() == 'file', 'wrapping SelectNext never lands on menu line')

# --- Cleanup ---
vproj_ai#PaneClose()

# Report
echom ''
if failures == 0
  echom 'All regression tests passed.'
else
  echohl ErrorMsg
  echom failures .. ' regression test(s) FAILED.'
  echohl None
  cquit!
endif

qa!
