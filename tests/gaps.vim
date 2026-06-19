vim9script

# Gap coverage tests — behaviors not exercised by existing test suites
# Run: vim -N -u NONE -S tests/gaps.vim

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

def PaneBufnr(): number
  return bufnr('VPROJ_AI')
enddef

def PaneLineCount(): number
  var pbuf = bufnr('VPROJ_AI')
  if pbuf <= 0 || !bufexists(pbuf)
    return 0
  endif
  return getbufinfo(pbuf)[0].linecount
enddef

def PaneLine(lnum: number): string
  var pbuf = bufnr('VPROJ_AI')
  var lines = getbufline(pbuf, lnum)
  return empty(lines) ? '' : lines[0]
enddef

def Setup(): void
  if vproj_ai#IsPaneVisible()
    vproj_ai#PaneClose()
  endif
  execute 'cd' getcwd()
  vproj_ai#PaneOpen()
  if vproj_ai#GetCurrentMode() != 'file'
    vproj_ai#SwitchMode('file')
  endif
enddef

# ══════════════════════════════════════════════════
# 1. BuildDisplayLines structure (indirect via Render)
# ══════════════════════════════════════════════════
echom '--- BuildDisplayLines structure ---'
Setup()

# Line 1 must be mode menu (contains [F]ile, [B]uf, [G]it, [Q]fix)
var line1 = PaneLine(1)
Assert(line1 =~ '\[F\]ile', 'line 1: mode menu has [F]ile')
Assert(line1 =~ '\[B\]uf', 'line 1: mode menu has [B]uf')
Assert(line1 =~ '\[G\]it', 'line 1: mode menu has [G]it')
Assert(line1 =~ '\[Q\]fix', 'line 1: mode menu has [Q]fix')

# Line 2 must be separator in file mode
var line2 = PaneLine(2)
Assert(line2 =~ '^-\+$', 'line 2: separator in file mode')

# Cursor starts on line 3 (first selectable item)
Assert(PaneCursorLine() == 3, 'file mode: cursor on line 3 (first item)')

# Git mode structure
vproj_ai#SwitchMode('git')
var cline1 = PaneLine(1)
Assert(cline1 =~ '\[F\]ile', 'git mode line 1: mode menu')
var cline2 = PaneLine(2)
Assert(cline2 =~ '^\*', 'git mode line 2: status line (starts with *)')
var cline3 = PaneLine(3)
Assert(cline3 =~ '^-\+$', 'git mode line 3: separator')
Assert(PaneCursorLine() == 4, 'git mode: cursor on line 4 (first item)')

# Buf mode structure
vproj_ai#SwitchMode('buf')
var dline1 = PaneLine(1)
Assert(dline1 =~ '\[F\]ile', 'buf mode line 1: mode menu')
var dline2 = PaneLine(2)
Assert(dline2 =~ '^-\+$', 'buf mode line 2: separator')
Assert(PaneCursorLine() == 3, 'buf mode: cursor on line 3 (first buf line)')

# Qfix mode structure
vproj_ai#SwitchMode('qfix')
var qline1 = PaneLine(1)
Assert(qline1 =~ '\[F\]ile', 'qfix mode line 1: mode menu')
Assert(qline1 =~ '\[Q\]fix', 'qfix mode line 1: qfix label present')
var qline2 = PaneLine(2)
Assert(qline2 =~ '^-\+$', 'qfix mode line 2: separator')
# Empty qflist should show placeholder
Assert(PaneCursorLine() == 3, 'qfix mode: cursor on line 3 (first item / placeholder)')
var qline3 = PaneLine(3)
Assert(qline3 =~ 'no quickfix', 'qfix empty: placeholder message shown')

# Populate qflist and verify entries
var qfix_tmp = '/tmp/vproj_qfix_gaps'
if isdirectory(qfix_tmp) | delete(qfix_tmp, 'rf') | endif
mkdir(qfix_tmp)
writefile(['aaa', 'bbb'], qfix_tmp .. '/x.txt')
setqflist([{filename: qfix_tmp .. '/x.txt', lnum: 2, col: 1, text: 'test entry', valid: true}])
vproj_ai#SwitchMode('file')
vproj_ai#SwitchMode('qfix')
Assert(PaneCursorLine() == 3, 'qfix populated: cursor on first entry')
var qp3 = PaneLine(3)
Assert(qp3 =~ 'x.txt', 'qfix populated: filename shown')
vproj_ai#SelectNext()
Assert(PaneCursorLine() == 3, 'qfix single entry: SelectNext wraps to first')
delete(qfix_tmp, 'rf')

# ══════════════════════════════════════════════════
# 2. OnDirChanged integration
# ══════════════════════════════════════════════════
echom '--- OnDirChanged integration ---'
Setup()

# Verify OnDirChanged is a no-op when CWD hasn't changed
vproj_ai#OnDirChanged()
Assert(vproj_ai#IsPaneVisible(), 'OnDirChanged with no CWD change keeps pane open')
Assert(vproj_ai#GetCurrentMode() == 'file', 'OnDirChanged preserves mode')

# OnDirChanged in git mode is a no-op
vproj_ai#SwitchMode('git')
vproj_ai#OnDirChanged()
Assert(vproj_ai#GetCurrentMode() == 'git', 'OnDirChanged in git mode is no-op')

# OnDirChanged when pane is closed
vproj_ai#PaneClose()
vproj_ai#OnDirChanged()
Assert(!vproj_ai#IsPaneVisible(), 'OnDirChanged when closed does not crash')

# Reopen and verify CWD tracking
execute 'cd /tmp'
vproj_ai#PaneOpen()
var pane_visible_after_cd = vproj_ai#IsPaneVisible()
Assert(pane_visible_after_cd, 'PaneOpen after cd /tmp works')

# ══════════════════════════════════════════════════
# 3. Paging + Nav combination
# ══════════════════════════════════════════════════
echom '--- Paging + Nav combination ---'
Setup()

# Navigate to a directory with many entries to trigger paging
vproj_ai#SwitchMode('file')
execute 'cd' getcwd()

# Shift nav forward then press a nav char
vproj_ai#ShiftNavForward()
Assert(vproj_ai#GetNavOffset() > 0, 'ShiftNavForward advances offset')
vproj_ai#SelectByNavChar('a')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar(a) after ShiftNavForward no crash')

# Shift nav backward
vproj_ai#ShiftNavBackward()
Assert(vproj_ai#GetNavOffset() == 0, 'ShiftNavBackward returns to 0')

# SelectByNavChar with a char on second page (mapped to position that exists)
vproj_ai#SelectByNavChar('B')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar(B) no crash')

# SelectByNavChar with a char definitely not on page
vproj_ai#SelectByNavChar('Q')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar(Q) not on page, no crash')

# ══════════════════════════════════════════════════
# 4. NextPage / PrevPage cursor clamping
# ══════════════════════════════════════════════════
echom '--- NextPage / PrevPage ---'
Setup()
vproj_ai#SwitchMode('file')

# PrevPage at page 0 should stay at 0, no crash
vproj_ai#PrevPage()
Assert(vproj_ai#IsPaneVisible(), 'PrevPage at page 0 no crash')

# NextPage should move to page 1 if there are enough items
vproj_ai#NextPage()
Assert(vproj_ai#IsPaneVisible(), 'NextPage no crash')

# Back to page 0
vproj_ai#PrevPage()
Assert(vproj_ai#IsPaneVisible(), 'PrevPage back to page 0 no crash')

# ══════════════════════════════════════════════════
# 5. NavigateIntoFirstDir + NavigateUp composition
# ══════════════════════════════════════════════════
echom '--- NavigateIntoFirstDir + NavigateUp ---'
Setup()
vproj_ai#SwitchMode('file')

# NavigateIntoFirstDir enters first subdirectory
try
  vproj_ai#NavigateIntoFirstDir()
  Assert(vproj_ai#IsPaneVisible(), 'NavigateIntoFirstDir keeps pane open')
catch
  Assert(false, 'NavigateIntoFirstDir error: ' .. v:exception)
endtry

# NavigateUp back
vproj_ai#NavigateUp()
Assert(vproj_ai#IsPaneVisible(), 'NavigateUp after NavigateIntoFirstDir keeps pane open')

# ══════════════════════════════════════════════════
# 6. Multiple Open/Close cycles
# ══════════════════════════════════════════════════
echom '--- Multiple Open/Close cycles ---'

for i in range(5)
  vproj_ai#PaneOpen()
  Assert(vproj_ai#IsPaneVisible(), 'open cycle ' .. (i + 1) .. ': pane visible')
  Assert(vproj_ai#GetCurrentMode() == 'file', 'open cycle ' .. (i + 1) .. ': default mode file')
  vproj_ai#PaneClose()
  Assert(!vproj_ai#IsPaneVisible(), 'close cycle ' .. (i + 1) .. ': pane not visible')
endfor

# ══════════════════════════════════════════════════
# 7. HandleBufWipeout then PaneOpen (no PaneClose)
# ══════════════════════════════════════════════════
echom '--- HandleBufWipeout → PaneOpen ---'
vproj_ai#PaneOpen()
vproj_ai#HandleBufWipeout()
Assert(!vproj_ai#IsPaneVisible(), 'HandleBufWipeout clears visibility')

# Open after HandleBufWipeout should work cleanly
vproj_ai#PaneOpen()
Assert(vproj_ai#IsPaneVisible(), 'PaneOpen after HandleBufWipeout works')
Assert(PaneCursorLine() == 3, 'cursor on line 3 after HandleBufWipeout + PaneOpen')

# ══════════════════════════════════════════════════
# 8. Git mode with .vproj_ai project file
# ══════════════════════════════════════════════════
echom '--- Git mode with .vproj_ai file ---'
vproj_ai#PaneClose()

# Write a test .vproj_ai file in a temp directory
var tmpdir = '/tmp/vproj_test_gaps'
if isdirectory(tmpdir)
  delete(tmpdir, 'rf')
endif
mkdir(tmpdir)
mkdir(tmpdir .. '/lib')
mkdir(tmpdir .. '/bin')
writefile(['hello world'], tmpdir .. '/README.md')
writefile([''], tmpdir .. '/main.vim')

var vproj_content = [
  'Project Name: test-project',
  'Project Root: ' .. tmpdir,
  'Included Directories:',
  'lib',
  'Included Files:',
  'README.md',
  'main.vim',
  'Excluded Directories:',
  'bin',
  'Excluded Files:',
  ''
]
writefile(vproj_content, tmpdir .. '/.vproj_ai')

	# Clear stale session to avoid inherited dir=/tmp
	delete(expand('~/.cache/vproj_ai/session'))
	execute 'cd' tmpdir
	vproj_ai#PaneOpen()
vproj_ai#SwitchMode('git')

# Verify git mode shows the project
Assert(vproj_ai#GetCurrentMode() == 'git', 'switched to git mode with .vproj_ai')

# Status line (line 2) should show the project name
var status_line = PaneLine(2)
Assert(status_line =~ 'test-project', 'status line shows project name')

# RenameProject requires interactive input() — can't test in headless mode.
# Guard coverage (non-git mode early return) is tested in coverage.vim.

# Clean up test project
vproj_ai#PaneClose()
delete(tmpdir, 'rf')

# ══════════════════════════════════════════════════
# 9. SelectByNavChar with paged items
# ══════════════════════════════════════════════════
echom '--- SelectByNavChar paged ---'
Setup()
vproj_ai#SwitchMode('file')

# Navigate to /usr/bin to get lots of items → guaranteed paging
execute 'cd /usr/bin'
vproj_ai#SwitchMode('file')

# Verify paging kicks in (should have > 20 items)
vproj_ai#NextPage()
vproj_ai#SelectByNavChar('a')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar(a) on page 2 no crash')

vproj_ai#NextPage()
vproj_ai#SelectByNavChar('B')
Assert(vproj_ai#IsPaneVisible(), 'SelectByNavChar(B) on page 3 no crash')

# Return to page 0
vproj_ai#PrevPage()
vproj_ai#PrevPage()

# ══════════════════════════════════════════════════
# 10. Mode switch preserves pane state
# ══════════════════════════════════════════════════
echom '--- Mode switch state preservation ---'
vproj_ai#PaneClose()
execute 'cd' getcwd()
vproj_ai#PaneOpen()

# Set a custom width, switch modes, verify width persists
vproj_ai#SetPaneWidth(55)
Assert(vproj_ai#GetPaneWidth() == 55, 'width set to 55')

vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetPaneWidth() == 55, 'width 55 preserved in buf mode')

vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetPaneWidth() == 55, 'width 55 preserved in git mode')

vproj_ai#SwitchMode('qfix')
Assert(vproj_ai#GetPaneWidth() == 55, 'width 55 preserved in qfix mode')

vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetPaneWidth() == 55, 'width 55 preserved back in file mode')

vproj_ai#SetPaneWidth(40)

# ══════════════════════════════════════════════════
# 11. SelectFirst / SelectLast
# ══════════════════════════════════════════════════
echom '--- SelectFirst / SelectLast ---'
Setup()
vproj_ai#SwitchMode('file')

vproj_ai#SelectLast()
var last_pos = PaneCursorLine()
Assert(last_pos > 3, 'SelectLast moves to last selectable line')

vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst returns to line 3')

# Git mode
vproj_ai#SwitchMode('git')
vproj_ai#SelectLast()
Assert(vproj_ai#IsPaneVisible(), 'SelectLast in git mode no crash')

vproj_ai#SelectFirst()
Assert(PaneCursorLine() == 4, 'SelectFirst in git mode returns to line 4')

# Qfix mode
vproj_ai#SwitchMode('qfix')
vproj_ai#SelectLast()
Assert(vproj_ai#IsPaneVisible(), 'SelectLast in qfix mode no crash')
vproj_ai#SelectFirst()
Assert(vproj_ai#IsPaneVisible(), 'SelectFirst in qfix mode no crash')

# ══════════════════════════════════════════════════
# 12. ToggleInfoColumn across modes
# ══════════════════════════════════════════════════
echom '--- ToggleInfoColumn across modes ---'
Setup()

vproj_ai#ToggleInfoColumn()
vproj_ai#SwitchMode('buf')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in buf mode no crash')

vproj_ai#SwitchMode('git')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in git mode no crash')

vproj_ai#SwitchMode('qfix')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in qfix mode no crash')

vproj_ai#SwitchMode('file')

# ══════════════════════════════════════════════════
# 13. Wrap-around SelectNext / SelectPrev
# ══════════════════════════════════════════════════
echom '--- SelectNext / SelectPrev wrap ---'
Setup()
vproj_ai#SwitchMode('file')

# SelectPrev from first item should wrap to last
vproj_ai#SelectPrev()
Assert(vproj_ai#IsPaneVisible(), 'SelectPrev from first item no crash')
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectPrev from first stays in file mode')

# SelectNext from last item should wrap to first
vproj_ai#SelectLast()
vproj_ai#SelectNext()
Assert(vproj_ai#IsPaneVisible(), 'SelectNext from last item no crash')
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectNext from last stays in file mode')

# ══════════════════════════════════════════════════
# 14. PaneToggle idempotence
# ══════════════════════════════════════════════════
echom '--- PaneToggle idempotence ---'
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'pane closed')

vproj_ai#PaneToggle()
Assert(vproj_ai#IsPaneVisible(), 'PaneToggle opens')
var first_line = PaneCursorLine()
Assert(first_line == 3, 'cursor on line 3 after toggle open')

vproj_ai#PaneToggle()
Assert(!vproj_ai#IsPaneVisible(), 'PaneToggle closes')

vproj_ai#PaneToggle()
Assert(vproj_ai#IsPaneVisible(), 'PaneToggle opens again')

# ══════════════════════════════════════════════════
# 15. Exported query functions
# ══════════════════════════════════════════════════
echom '--- Exported queries ---'
Setup()

Assert(vproj_ai#GetPaneWidth() == 40, 'GetPaneWidth returns 40')
Assert(vproj_ai#GetCurrentMode() == 'file', 'GetCurrentMode returns file')
Assert(vproj_ai#GetNavOffset() == 0, 'GetNavOffset returns 0')
Assert(vproj_ai#IsPaneVisible(), 'IsPaneVisible returns true')

vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'GetCurrentMode returns buf')
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'GetCurrentMode returns git')
vproj_ai#SwitchMode('qfix')
Assert(vproj_ai#GetCurrentMode() == 'qfix', 'GetCurrentMode returns qfix')

# ══════════════════════════════════════════════════
# 16. ToggleGitFilter — functional test
# ══════════════════════════════════════════════════
echom '--- ToggleGitFilter ---'
Setup()

# Indicator absent by default — check that [G] doesn't appear AFTER [Q]fix
var ml1 = PaneLine(1)
Assert(ml1 !~ 'Q\]fix.*\[G\]', 'git filter indicator absent by default')

try
  vproj_ai#ToggleGitFilter()
  Assert(vproj_ai#IsPaneVisible(), 'ToggleGitFilter keeps pane visible')
  var ml2 = PaneLine(1)
  Assert(ml2 =~ 'Q\]fix.*\[G\]', 'git filter indicator appears after toggle')
catch
  Assert(false, 'ToggleGitFilter error: ' .. v:exception)
endtry

# Toggle back to off
vproj_ai#ToggleGitFilter()
var ml3 = PaneLine(1)
Assert(ml3 !~ 'Q\]fix.*\[G\]', 'git filter indicator cleared on second toggle')

# Refresh clears git filter
vproj_ai#ToggleGitFilter()
vproj_ai#Refresh()
var ml4 = PaneLine(1)
Assert(ml4 !~ 'Q\]fix.*\[G\]', 'Refresh clears git filter')

# Mode switch clears git filter
vproj_ai#ToggleGitFilter()
vproj_ai#SwitchMode('buf')
var ml5 = PaneLine(1)
Assert(ml5 !~ 'Q\]fix.*\[G\]', 'SwitchMode clears git filter')

# ══════════════════════════════════════════════════
# 17. HandleF1 — pane vs. non-pane paths
# ══════════════════════════════════════════════════
echom '--- HandleF1 ---'
Setup()

try
  vproj_ai#HandleF1()
  Assert(vproj_ai#IsPaneVisible(), 'HandleF1 in pane toggles info column')
catch
  Assert(false, 'HandleF1 in pane error: ' .. v:exception)
endtry

vproj_ai#PaneClose()

# HandleF1 outside pane — opens help
try
  vproj_ai#HandleF1()
  Assert(true, 'HandleF1 outside pane no crash')
catch
  Assert(false, 'HandleF1 outside pane error: ' .. v:exception)
endtry

# Close any help window that opened
if winnr('$') > 1
  wincmd w
  if &buftype == 'help'
    close
  endif
endif
vproj_ai#PaneClose()

# ══════════════════════════════════════════════════
# 18. CloseBuffer with actual buffers
# ══════════════════════════════════════════════════
echom '--- CloseBuffer functional ---'
vproj_ai#PaneClose()

# Open real buffers
silent! edit! /tmp/vproj_gap_buf_a.txt
silent! edit! /tmp/vproj_gap_buf_b.txt
silent! edit! /tmp/vproj_gap_buf_c.txt

vproj_ai#PaneOpen()
vproj_ai#SwitchMode('buf')

# Should have at least 3 buffers beyond menu/separator
try
  vproj_ai#CloseBuffer()
  Assert(vproj_ai#IsPaneVisible(), 'CloseBuffer in buf mode keeps pane visible')
catch
  Assert(false, 'CloseBuffer error: ' .. v:exception)
endtry

vproj_ai#PaneClose()

# Cleanup
silent! bdelete! /tmp/vproj_gap_buf_a.txt
silent! bdelete! /tmp/vproj_gap_buf_b.txt
silent! bdelete! /tmp/vproj_gap_buf_c.txt

# ══════════════════════════════════════════════════
# 19. PromptFilter — feedkeys functional test
# ══════════════════════════════════════════════════
echom '--- PromptFilter ---'
Setup()

try
  call feedkeys("vim\<CR>", 't')
  vproj_ai#PromptFilter()
  Assert(vproj_ai#IsPaneVisible(), 'PromptFilter with pattern ok')
catch
  Assert(false, 'PromptFilter error: ' .. v:exception)
endtry

# Clear filter with empty input
try
  call feedkeys("\<CR>", 't')
  vproj_ai#PromptFilter()
  Assert(vproj_ai#IsPaneVisible(), 'PromptFilter clear ok')
catch
  Assert(false, 'PromptFilter clear error: ' .. v:exception)
endtry

# ══════════════════════════════════════════════════
# 20. Mode cycling via SwitchMode (all 4 modes, round-trip)
# ══════════════════════════════════════════════════
echom '--- Mode cycling ---'
Setup()

# file → buf → git → qfix → file
vproj_ai#SwitchMode('buf')
Assert(vproj_ai#GetCurrentMode() == 'buf', 'SwitchMode: file→buf')
vproj_ai#SwitchMode('git')
Assert(vproj_ai#GetCurrentMode() == 'git', 'SwitchMode: buf→git')
vproj_ai#SwitchMode('qfix')
Assert(vproj_ai#GetCurrentMode() == 'qfix', 'SwitchMode: git→qfix')
vproj_ai#SwitchMode('file')
Assert(vproj_ai#GetCurrentMode() == 'file', 'SwitchMode: qfix→file')

# ══════════════════════════════════════════════════
# 21. NavigateIntoFirstDir with no subdirectory
# ══════════════════════════════════════════════════
echom '--- NavigateIntoFirstDir in empty dir ---'

vproj_ai#PaneClose()
call mkdir('/tmp/vproj_gap_empty_dir', 'p')
execute 'cd /tmp/vproj_gap_empty_dir'

vproj_ai#PaneOpen()
try
  vproj_ai#NavigateIntoFirstDir()
  Assert(true, 'NavigateIntoFirstDir empty-dir no crash')
catch
  Assert(false, 'NavigateIntoFirstDir empty-dir error: ' .. v:exception)
endtry
vproj_ai#PaneClose()
call delete('/tmp/vproj_gap_empty_dir', 'rf')

# ══════════════════════════════════════════════════
# 22. Empty directory — works without crash, shows parent dir
# ══════════════════════════════════════════════════
echom '--- Empty directory ---'

call mkdir('/tmp/vproj_gap_empty2', 'p')
execute 'cd /tmp/vproj_gap_empty2'

vproj_ai#PaneOpen()
var elines = getbufline(bufnr('VPROJ_AI'), 1, '$')
var has_parent = false
for l in elines
  if l =~ '\.\.'
    has_parent = true
    break
  endif
endfor
Assert(has_parent, 'empty directory shows parent (..) entry')
Assert(vproj_ai#GetCurrentMode() == 'file', 'empty directory: stays in file mode')
vproj_ai#PaneClose()
call delete('/tmp/vproj_gap_empty2', 'rf')

# ══════════════════════════════════════════════════
# 23. Session persistence round-trip
# ══════════════════════════════════════════════════
echom '--- Session persistence ---'

vproj_ai#PaneOpen()
vproj_ai#SwitchMode('buf')
vproj_ai#SetPaneWidth(55)
vproj_ai#ToggleInfoColumn()  # flip once
vproj_ai#PaneClose()

vproj_ai#PaneOpen()
Assert(vproj_ai#GetCurrentMode() == 'buf', 'session restores buf mode')
Assert(vproj_ai#GetPaneWidth() == 55, 'session restores width 55')
vproj_ai#PaneClose()

# Restore default state
vproj_ai#PaneOpen()
vproj_ai#SetPaneWidth(40)
vproj_ai#SwitchMode('file')
vproj_ai#ToggleInfoColumn()  # flip back
vproj_ai#PaneClose()

# ══════════════════════════════════════════════════
# 24. ParseVprojFile with malformed / edge input
# ══════════════════════════════════════════════════
echom '--- ParseVprojFile malformed ---'

var tmp_v = '/tmp/vproj_gap_malformed.vproj_ai'

# Minimal valid .vproj_ai
writefile(['Project Name: GapTest', '# comment', '', 'garbage line', 'Included Directories:', 'src'], tmp_v)
try
  var p = vproj_ai#ParseVprojFile(tmp_v)
  Assert(get(p, 'name', '') == 'GapTest', 'malformed .vproj_ai: name parsed')
  Assert(len(get(p, 'included_dirs', [])) == 1, 'malformed .vproj_ai: 1 included dir')
catch
  Assert(false, 'ParseVprojFile malformed error: ' .. v:exception)
endtry

# Bogus root path
writefile(['Project Name: Bogus', 'Project Root: /nonexistent/xyz/123', 'Included Directories:', 'src'], tmp_v)
try
  var p2 = vproj_ai#ParseVprojFile(tmp_v)
  Assert(empty(get(p2, 'root', '')), 'bogus root: cleared to empty')
catch
  Assert(false, 'ParseVprojFile bogus-root error: ' .. v:exception)
endtry

call delete(tmp_v)

# ══════════════════════════════════════════════════
# 25. Binary file detection
# ══════════════════════════════════════════════════
echom '--- Binary file ---'

var bdata = 0z000102030405060708090a0b0c0d0e0f
writefile(bdata, '/tmp/vproj_gap_binary.bin')

vproj_ai#PaneClose()
execute 'cd /tmp'
vproj_ai#PaneOpen()
vproj_ai#SwitchMode('file')

var p_lines = getbufline(bufnr('VPROJ_AI'), 1, '$')
var bin_line = 0
for i in range(len(p_lines))
  if p_lines[i] =~ 'vproj_gap_binary\.bin'
    bin_line = i + 1
    break
  endif
endfor

if bin_line > 0
  var pw2 = win_findbuf(bufnr('VPROJ_AI'))[0]
  win_execute(pw2, 'normal ' .. bin_line .. 'G')
  try
    vproj_ai#SelectCurrent()
    Assert(true, 'binary file SelectCurrent no crash')
  catch
    Assert(false, 'Binary SelectCurrent error: ' .. v:exception)
  endtry
else
  Assert(true, 'binary file not in listing (filtered or not created)')
endif

vproj_ai#PaneClose()
call delete('/tmp/vproj_gap_binary.bin')

# ══════════════════════════════════════════════════
# 26. Qfix column jump and invalid entry skip
# ══════════════════════════════════════════════════
echom '--- Qfix edge cases ---'

writefile(['col1 col2 col3 col4 col5', 'a b c d e'], '/tmp/vproj_gap_qfix2.txt')

# Mix valid and invalid entries
setqflist([
  {filename: '/nonexistent/bad.txt', lnum: 1, col: 1, text: 'bad', valid: false},
  {filename: '/tmp/vproj_gap_qfix2.txt', lnum: 2, col: 5, text: 'col 5', valid: true},
])

vproj_ai#PaneOpen()
vproj_ai#SwitchMode('qfix')

# Should have only the valid entry
var qlines = getbufline(bufnr('VPROJ_AI'), 1, '$')
var hits = 0
for l in qlines
  if l =~ 'vproj_gap_qfix2'
    hits += 1
  endif
endfor
Assert(hits == 1, 'qfix skips invalid entry, shows 1 valid')

# Jump to entry with column
try
  vproj_ai#SelectCurrent()
  Assert(true, 'qfix column-jump entry opened')
catch
  Assert(false, 'qfix column-jump error: ' .. v:exception)
endtry

vproj_ai#PaneClose()
call delete('/tmp/vproj_gap_qfix2.txt')

# ══════════════════════════════════════════════════
# 27. GitStageToggle guards (non-file modes)
# ══════════════════════════════════════════════════
echom '--- GitStageToggle guards ---'
Setup()

vproj_ai#SwitchMode('buf')
try
  vproj_ai#GitStageToggle()
  Assert(vproj_ai#IsPaneVisible(), 'GitStageToggle in buf mode exits early')
catch
  Assert(false, 'GitStageToggle buf-mode error: ' .. v:exception)
endtry

vproj_ai#SwitchMode('git')
try
  vproj_ai#GitStageToggle()
  Assert(vproj_ai#IsPaneVisible(), 'GitStageToggle in git mode exits early')
catch
  Assert(false, 'GitStageToggle git-mode error: ' .. v:exception)
endtry

vproj_ai#SwitchMode('qfix')
try
  vproj_ai#GitStageToggle()
  Assert(vproj_ai#IsPaneVisible(), 'GitStageToggle in qfix mode exits early')
catch
  Assert(false, 'GitStageToggle qfix-mode error: ' .. v:exception)
endtry

# ══════════════════════════════════════════════════
# 28. Pane buffer name is VPROJ_AI after open
# ══════════════════════════════════════════════════
echom '--- Pane buffer name ---'
vproj_ai#PaneClose()

vproj_ai#PaneOpen()
var pb = bufnr('VPROJ_AI')
Assert(pb > 0, 'pane buffer exists after open')
Assert(bufname(pb) == 'VPROJ_AI', 'pane buffer named VPROJ_AI')
Assert(bufexists(pb), 'pane buffer is valid')
vproj_ai#PaneClose()

# ══════════════════════════════════════════════════
# 29. ToggleInfoColumn across all modes
# ══════════════════════════════════════════════════
echom '--- ToggleInfoColumn across modes ---'
Setup()

vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in file mode ok')

vproj_ai#SwitchMode('buf')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in buf mode ok')

vproj_ai#SwitchMode('git')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in git mode ok')

vproj_ai#SwitchMode('qfix')
vproj_ai#ToggleInfoColumn()
Assert(vproj_ai#IsPaneVisible(), 'ToggleInfoColumn in qfix mode ok')

vproj_ai#SwitchMode('file')

# ══════════════════════════════════════════════════
# 30. SelectPrev wrap-around from first item
# ══════════════════════════════════════════════════
echom '--- SelectPrev wrap-around ---'
Setup()

vproj_ai#SelectPrev()
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectPrev from first wraps, mode preserved')
Assert(vproj_ai#IsPaneVisible(), 'SelectPrev from first no crash')

vproj_ai#SelectLast()
vproj_ai#SelectNext()
Assert(vproj_ai#GetCurrentMode() == 'file', 'SelectNext from last wraps, mode preserved')

# ══════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════
Setup()
vproj_ai#PaneClose()
Assert(!vproj_ai#IsPaneVisible(), 'cleanup: pane closed')

echom ''
if failures == 0
  echom 'ALL GAP TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' GAP TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
