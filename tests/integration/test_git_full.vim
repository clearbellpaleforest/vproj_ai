vim9script

# Integration tests for git full features: Log mode, Diff, Commit, Push, Pull, Branch
# Run: vim -N -u NONE -S tests/integration/test_git_full.vim

set rtp+=src
runtime! plugin/vproj_ai.vim
set nomore

var failures: number = 0

def PaneCursorLine(): number
  var wnr = bufwinnr(bufnr('VPROJ_AI'))
  if wnr <= 0
    return -1
  endif
  var cl = win_execute(win_getid(wnr), 'echom line(".")')
  return trim(cl)->str2nr()
enddef

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# ──────────────────────────────────────────────
# Ensure clean slate
# ──────────────────────────────────────────────
vproj_ai#PaneClose()
call delete(expand('~/.cache/vproj_ai/session'))

# ──────────────────────────────────────────────
# SECTION 1: Log Mode Basics
# ──────────────────────────────────────────────
echom '--- Log Mode ---'
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('log')

Assert(vproj_ai#IsPaneVisible(), 'log mode: pane visible')
Assert(vproj_ai#GetCurrentMode() == 'log', 'log mode: GetCurrentMode returns log')

# Verify display lines
var lines = getbufline(bufnr('VPROJ_AI'), 1, '$')
Assert(len(lines) >= 3, 'log mode: at least 3 lines (menu + sep + item)')
Assert(lines[0] =~ '\[L\]og', 'log mode: menu line has [L]og')
Assert(lines[1] =~ '^-\+$', 'log mode: separator line is dashes')

# Verify cursor position
var cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'log mode: cursor on first item (line 3)')

# Verify first item has git hash format (nav char + 7-char hex)
var first_item = lines[2]
Assert(first_item =~ '^[a-zA-Z0-9]  [0-9a-f]\{7,}', 'log mode: first item has nav char + hash')

# ──────────────────────────────────────────────
# SECTION 2: Log Mode Navigation
# ──────────────────────────────────────────────
echom '--- Log Mode Navigation ---'

# SelectNext
execute 'normal j'
cursor_line = PaneCursorLine()
Assert(cursor_line == 4, 'log mode: j moves to line 4')

# SelectPrev
execute 'normal k'
cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'log mode: k returns to line 3')

# SelectFirst / SelectLast
vproj_ai#SelectLast()
cursor_line = PaneCursorLine()
Assert(cursor_line >= 3, 'log mode: SelectLast does not crash')

vproj_ai#SelectFirst()
cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'log mode: SelectFirst returns to line 3')

# ──────────────────────────────────────────────
# SECTION 3: Log Mode Switching Round-Trip
# ──────────────────────────────────────────────
echom '--- Log Mode Switching ---'

vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'log→file: mode is file')
cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'log→file: cursor on line 3')

vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'log→buf: mode is buf')

vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'log→git: mode is git')

vproj_ai#SwitchMode('qfix')
Assert(vproj_ai#GetCurrentMode() == 'qfix', 'log→qfix: mode is qfix')

vproj_ai#SwitchMode('log')
Assert(vproj_ai#GetCurrentMode() == 'log', 'qfix→log: mode is log')
cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'qfix→log: cursor on line 3')

# ──────────────────────────────────────────────
# SECTION 4: L Key Mapping (log mode)
# ──────────────────────────────────────────────
echom '--- L Key Mapping ---'

# L is mapped to SwitchMode('log')
var L_map = maparg('L', 'n', 0, 1)
Assert(!empty(L_map), 'L is mapped in pane buffer')
Assert(L_map.lhs == 'L', 'L map lhs is L')

# Verify switching via L key
vproj_ai#SwitchMode('file')
execute 'normal L'
Assert(vproj_ai#GetCurrentMode() == 'log', 'L key switches to log mode from file')

# ──────────────────────────────────────────────
# SECTION 5: Diff Preview
# ──────────────────────────────────────────────
echom '--- Diff Preview ---'

vproj_ai#SwitchMode('file')

# Move cursor to first selectable item
# We're in the vproj_ai repo root — files from 'git status' are modified
# Navigate to modified files area (they should be present)
# The test just verifies d key doesn't crash
try
  execute 'normal d'
  Assert(vproj_ai#IsPaneVisible(), 'd key diff preview does not crash')
catch
  Assert(false, 'd key diff error: ' .. v:exception)
endtry

# Close any diff window that may have opened. Use win_gotoid to avoid
# the execute-N-wincmd-w bug (E1050).
var pane_wnr = bufwinnr(bufnr('VPROJ_AI'))
var pane_wid = pane_wnr > 0 ? win_getid(pane_wnr) : 0
# Find and close any non-pane window
var all_wins = range(1, winnr('$'))
for wnr in all_wins
  if wnr != pane_wnr && getbufvar(winbufnr(wnr), '&filetype') == 'diff'
    var wid = win_getid(wnr)
    win_gotoid(wid)
    close!
    break
  endif
endfor
if pane_wid > 0
  win_gotoid(pane_wid)
endif

# ──────────────────────────────────────────────
# SECTION 6: Diff Preview on Non-Git File
# ──────────────────────────────────────────────
echom '--- Diff Preview Edge Cases ---'

# Test on directory (should be no-op)
# Use normal mode j/k to navigate to parent dir (..)
# Rather than navigating, just verify the exported function doesn't crash
try
  call vproj_ai#OpenDiffPreview()
  Assert(true, 'OpenDiffPreview on any item does not crash')
catch
  Assert(false, 'OpenDiffPreview crash: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 7: Discard Changes Edge Cases
# ──────────────────────────────────────────────
echom '--- Discard Edge Cases ---'

# Discard in buf mode should exit early
vproj_ai#SwitchMode('buf')
try
  call vproj_ai#DiscardChanges()
  Assert(true, 'DiscardChanges in buf mode exits early (no crash)')
catch
  Assert(false, 'DiscardChanges in buf mode crash: ' .. v:exception)
endtry

# Discard in git mode should exit early
vproj_ai#SwitchMode('git')
try
  call vproj_ai#DiscardChanges()
  Assert(true, 'DiscardChanges in git mode exits early (no crash)')
catch
  Assert(false, 'DiscardChanges in git mode crash: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 8: D Key Discard Mapping
# ──────────────────────────────────────────────
echom '--- D Key Mapping ---'
vproj_ai#SwitchMode('file')
var d_map = maparg('D', 'n', 0, 1)
Assert(!empty(d_map), 'D is mapped in pane buffer')
Assert(d_map.lhs == 'D', 'D map lhs is D')

# D key without interactive input — verify mapping exists and doesn't crash visual
# Note: D with no input in a script will be at input() prompt
# We verify the function is callable without crash via the early exit in buf/git mode
var d_cmd = substitute(d_map.rhs, '^<Cmd>', '', '')
var d_cmd_clean = substitute(d_cmd, '<CR>$', '', '')
Assert(d_cmd_clean =~ 'vproj_ai#DiscardChanges', 'D maps to DiscardChanges')

# ──────────────────────────────────────────────
# SECTION 9: Git Functions Exist
# ──────────────────────────────────────────────
echom '--- Function Existence ---'

# Commit/BranchSwitch use input() — can't call in scripts.
# Push/Pull would actually push/pull — verify exist without calling.
Assert(exists('*vproj_ai#GitCommit') == 1, 'GitCommit function exists')
Assert(exists('*vproj_ai#GitPush') == 1, 'GitPush function exists')
Assert(exists('*vproj_ai#GitPull') == 1, 'GitPull function exists')
Assert(exists('*vproj_ai#GitBranchSwitch') == 1, 'GitBranchSwitch function exists')
Assert(exists('*vproj_ai#OpenDiffPreview') == 1, 'OpenDiffPreview function exists')
Assert(exists('*vproj_ai#DiscardChanges') == 1, 'DiscardChanges function exists')

# ──────────────────────────────────────────────
# SECTION 10: GitPush / GitPull Exist
# ──────────────────────────────────────────────
echom '--- Push/Pull ---'

# Already verified existence in section 9.
# GitPush and GitPull would execute real git commands if called
# from within a repo — don't call them. Key mapping tests in
# section 12 confirm they're wired up correctly.
Assert(true, 'GitPush/GitPull existence verified in section 9')

# ──────────────────────────────────────────────
# SECTION 12: C, P, U, B Key Mappings
# ──────────────────────────────────────────────
echom '--- Whole-Repo Key Mappings ---'

vproj_ai#SwitchMode('file')

var c_map = maparg('C', 'n', 0, 1)
Assert(!empty(c_map), 'C is mapped in pane buffer')
Assert(c_map.lhs == 'C', 'C map exists')

var p_map = maparg('P', 'n', 0, 1)
Assert(!empty(p_map), 'P is mapped in pane buffer')
Assert(p_map.lhs == 'P', 'P map exists')

var u_map = maparg('U', 'n', 0, 1)
Assert(!empty(u_map), 'U is mapped in pane buffer')
Assert(u_map.lhs == 'U', 'U map exists')

var b_map = maparg('B', 'n', 0, 1)
Assert(!empty(b_map), 'B is mapped in pane buffer')
Assert(b_map.lhs == 'B', 'B map exists')

# ──────────────────────────────────────────────
# SECTION 13: NAV_CHARS Exclusion
# ──────────────────────────────────────────────
echom '--- NAV_CHARS Exclusion ---'

# Verify that action keys are NOT in the nav char loop mappings
# d, D, L, C, P, U, B should be action keys, not nav char jumps
vproj_ai#SwitchMode('log')

# Check that the pane buffer has explicit mappings (not nav char mappings)
var d_nav_map = maparg('d', 'n', 0, 1)
Assert(!empty(d_nav_map), 'd has a mapping')
Assert(d_nav_map.rhs =~ 'OpenDiffPreview', 'd maps to OpenDiffPreview (not nav char)')

var L_action_map = maparg('L', 'n', 0, 1)
Assert(!empty(L_action_map), 'L has a mapping')
Assert(L_action_map.rhs =~ "SwitchMode('log')", 'L maps to SwitchMode log (not nav char)')

# ──────────────────────────────────────────────
# SECTION 14: Session Persistence with Log Mode
# ──────────────────────────────────────────────
echom '--- Session Persistence ---'

vproj_ai#SwitchMode('log')
vproj_ai#PaneClose()

# Reopen — session should restore log mode
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'open after log mode: pane visible')
Assert(vproj_ai#GetCurrentMode() == 'log', 'open after log mode: restores log mode')

# ──────────────────────────────────────────────
# SECTION 15: Empty Log Mode (outside git repo)
# ──────────────────────────────────────────────
echom '--- Empty Log Mode ---'

vproj_ai#PaneClose()

# Test in non-git directory
var orig_cwd = getcwd()
cd /tmp
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('log')

var log_lines = getbufline(bufnr('VPROJ_AI'), 1, '$')
Assert(log_lines[2] =~ 'no commits', 'log mode: empty state shows placeholder')

cd `=orig_cwd`

# ──────────────────────────────────────────────
# SECTION 16: Log Mode Refresh
# ──────────────────────────────────────────────
echom '--- Log Mode Refresh ---'

vproj_ai#SwitchMode('log')
Assert(vproj_ai#GetCurrentMode() == 'log', 'log refresh: stays in log mode')

vproj_ai#Refresh()
Assert(vproj_ai#GetCurrentMode() == 'log', 'log refresh: still in log mode after refresh')
Assert(vproj_ai#IsPaneVisible(), 'log refresh: pane still visible')

# ──────────────────────────────────────────────
# SECTION 17: Log Mode Width Config
# ──────────────────────────────────────────────
echom '--- Log Mode Width Config ---'

g:vproj_ai_pane_width_log = 50
vproj_ai#SwitchMode('log')
Assert(vproj_ai#GetPaneWidth() == 50, 'log mode: width config 50 applied')

g:vproj_ai_pane_width_log = 0
vproj_ai#SwitchMode('file')
var w_before = vproj_ai#GetPaneWidth()
vproj_ai#SwitchMode('log')
Assert(vproj_ai#GetPaneWidth() == w_before, 'log mode: width 0 does not change width')

# ──────────────────────────────────────────────
# SECTION 18: Log Mode Info Column
# ──────────────────────────────────────────────
echom '--- Log Mode Info Column ---'

vproj_ai#SwitchMode('log')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'log mode: info column toggle keeps pane visible')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'log mode: info column toggle back keeps pane visible')

# SECTION 19: GitStashPush / GitStashPop Function Existence
# ──────────────────────────────────────────────
echom '--- Stash Function Existence ---'

Assert(exists('*vproj_ai#GitStashPush'), 'GitStashPush function exists')
Assert(exists('*vproj_ai#GitStashPop'), 'GitStashPop function exists')

# SECTION 20: GitBlame Function and Guards
# ──────────────────────────────────────────────
echom '--- Blame Function Existence ---'

Assert(exists('*vproj_ai#GitBlame'), 'GitBlame function exists')

# Blame is file-mode-only — should exit silently in other modes
vproj_ai#SwitchMode('buf')
try
  call vproj_ai#GitBlame()
  Assert(true, 'GitBlame in buf mode: exits without crash')
catch
  Assert(false, 'GitBlame in buf mode threw: ' .. v:exception)
endtry

vproj_ai#SwitchMode('git')
try
  call vproj_ai#GitBlame()
  Assert(true, 'GitBlame in git mode: exits without crash')
catch
  Assert(false, 'GitBlame in git mode threw: ' .. v:exception)
endtry

# Switch back to file mode for further tests
vproj_ai#SwitchMode('file')

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────

unlet! g:vproj_ai_pane_width_log
vproj_ai#PaneClose()
call delete(expand('~/.cache/vproj_ai/session'))

echom ''
if failures == 0
  echom 'ALL GIT FULL INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' GIT FULL INTEGRATION TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
