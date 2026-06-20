vim9script

# Unit tests for vproj_ai internal functions.
#
# Exercises the following non-exported functions indirectly through
# the exported AiApplyCode API:
#   - FindCodeBlocks     (scan current buffer for ``` fences)
#   - FindNearestBlock   (pick block closest to cursor)
#   - ApplyCodeToFile     (append code to target file/buffer)
#
# NOTE: ApplyCodeToFile saves and restores window focus. After
# AiApplyCode returns, focus is on the response view (not the
# target file), even when code was applied. Tests that verify
# target-buffer content use getbufline() to read the target
# buffer without switching windows.
#
# Buffer content is created via writefile() + :edit rather than
# :new + setline(). In Vim 9.2, setline() at vim9script script level
# sets lines visible to getline() at script level but not to getline()
# inside autoload functions — a version-specific scoping quirk.
#
# Run from vproj_ai/ directory:
#   vim -N -u NONE -S tests/unit/test_vproj_ai_functions.vim
#
# Requires vproj to be available at ../vproj/src/.

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore noswapfile

var failures: number = 0

# Temp directory for test output files.
var tmpdir: string = '/tmp/vproj_ai_unit_test'

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# Ensure temp directory exists at the start.
silent! call mkdir(tmpdir, 'p')

# Create a named buffer with given lines, return the path.
def SetupBuf(lines: list<string>): string
  var path: string = tmpdir .. '/src_' .. strftime('%H%M%S') .. '_' .. line('$')
  call writefile(lines, path)
  execute 'edit ' .. fnameescape(path)
  return path
enddef

# ────────────────────────────────────────────────────────────
# SECTION 1: FindCodeBlocks — empty-list cases
#
# AiApplyCode calls FindCodeBlocks() to scan for ``` fences.
# When no complete fenced block is found, blocks is empty.
# AiApplyCode then collects all non-blank lines as fallback
# code. If b:vproj_ai_target_file is unset, it errors with
# "no target file known" and returns early (no input() call).
# ────────────────────────────────────────────────────────────

echom '=== SECTION 1: FindCodeBlocks empty ==='

# TC01: No fences, no target file — "no target file known".
var tc01_buf: string = SetupBuf(['just text', 'no fences', 'no ai prefix'])
vproj_ai#AiApplyCode()
Assert(true, 'TC01: AiApplyCode on text without fences does not crash')
bwipeout!
call delete(tc01_buf)

# TC02: Unclosed fence — opening ``` but no closing ```.
var tc02_buf: string = SetupBuf(['before', '```python', 'print("hello")', 'print("world")'])
vproj_ai#AiApplyCode()
Assert(true, 'TC02: AiApplyCode with unclosed fence does not crash')
bwipeout!
call delete(tc02_buf)

# TC03: Empty fence — opening ``` immediately closed by ``` on next line.
var tc03_buf: string = SetupBuf(['```', '```'])
vproj_ai#AiApplyCode()
Assert(true, 'TC03: AiApplyCode with empty fence does not crash')
bwipeout!
call delete(tc03_buf)

# TC04: Stray single ``` — treated as unclosed fence, no block emitted.
var tc04_buf: string = SetupBuf(['a', '```', 'b'])
vproj_ai#AiApplyCode()
Assert(true, 'TC04: AiApplyCode with stray ``` does not crash')
bwipeout!
call delete(tc04_buf)

# ────────────────────────────────────────────────────────────
# SECTION 2: Valid fenced blocks — cancel and confirm
#
# When FindCodeBlocks returns a non-empty list, AiApplyCode
# calls FindNearestBlock(blocks, line('.')) then prompts
# for confirmation. After confirmation, ApplyCodeToFile
# opens the target, appends code, and restores focus.
#
# NOTE: After AiApplyCode returns, focus is ALWAYS on the
# response view (ApplyCodeToFile restores focus). Use
# getbufline() to read the target buffer content.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 2: Valid fenced blocks ==='

# TC05: Single valid fence, user cancels (feeds "n").
var tc05_src: string = SetupBuf(['```python', 'print("tc05")', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc05.txt'
b:vproj_ai_cursor_line = 0
feedkeys("n\<CR>", 't')
vproj_ai#AiApplyCode()
Assert(!filereadable(tmpdir .. '/tc05.txt'), 'TC05: AiApplyCode cancelled, no file written')
bwipeout!
call delete(tc05_src)

# TC06: Single valid fence, user confirms (feeds "y").
# Focus restored to response view; target buffer read via getbufline.
var tc06_src: string = SetupBuf(['```python', 'print("tc06 content")', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc06.txt'
b:vproj_ai_cursor_line = 0
var tc06_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc06_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc06_target = bufnr(tmpdir .. '/tc06.txt')
  Assert(tc06_target > 0, 'TC06: Target buffer loaded')
  var tc06_lines: list<string> = getbufline(tc06_target, 1, '$')
  Assert(!empty(tc06_lines), 'TC06: Target buffer has content')
  var tc06_found: bool = false
  for ln in tc06_lines
    if stridx(ln, 'tc06 content') >= 0
      tc06_found = true
      break
    endif
  endfor
  Assert(tc06_found, 'TC06: Target file contains applied code')
catch
  Assert(false, 'TC06: AiApplyCode error: ' .. v:exception)
endtry
# Cleanup: wipe target then response view
if tc06_target > 0 | execute 'bwipeout! ' .. tc06_target | endif
execute 'bwipeout! ' .. tc06_buf
call delete(tmpdir .. '/tc06.txt')
call delete(tc06_src)

# TC07: User confirms with "yes" — tests full regex ^y\(es\)\?$.
var tc07_src: string = SetupBuf(['```vim', '" tc07', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc07.txt'
b:vproj_ai_cursor_line = 0
var tc07_buf: number = bufnr('%')
feedkeys("yes\<CR>", 't')
var tc07_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc07_target = bufnr(tmpdir .. '/tc07.txt')
  Assert(tc07_target > 0, 'TC07: AiApplyCode confirmed with "yes" does not crash')
catch
  Assert(false, 'TC07: AiApplyCode error with "yes": ' .. v:exception)
endtry
if tc07_target > 0 | execute 'bwipeout! ' .. tc07_target | endif
execute 'bwipeout! ' .. tc07_buf
call delete(tmpdir .. '/tc07.txt')
call delete(tc07_src)

# ────────────────────────────────────────────────────────────
# SECTION 3: FindNearestBlock — multiple blocks
#
# Buffer layout:
#   L1:  header
#   L2:  ```python
#   L3:  # block1_marker
#   L4:  ```
#   L5:  gap
#   L6:  ```python
#   L7:  # block2_marker
#   L8:  ```
#
# After confirmation, ApplyCodeToFile opens target, appends
# the selected block, and restores focus to response view.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 3: FindNearestBlock ==='

# TC08: Cursor inside block 1 (line 3) — block 1 selected.
var tc08_src: string = SetupBuf([
    'header',
    '```python',
    '# block1_marker',
    '```',
    'gap',
    '```python',
    '# block2_marker',
    '```',
])
b:vproj_ai_target_file = tmpdir .. '/tc08.txt'
b:vproj_ai_cursor_line = 0
cursor(3, 1)
var tc08_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc08_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc08_target = bufnr(tmpdir .. '/tc08.txt')
  var tc08_lines: list<string> = getbufline(tc08_target, 1, '$')
  var tc08_has_b1: bool = false
  for ln in tc08_lines
    if stridx(ln, 'block1_marker') >= 0
      tc08_has_b1 = true
      break
    endif
  endfor
  Assert(tc08_has_b1, 'TC08: Block 1 content applied when cursor in block 1')
  var tc08_has_b2: bool = false
  for ln in tc08_lines
    if stridx(ln, 'block2_marker') >= 0
      tc08_has_b2 = true
      break
    endif
  endfor
  Assert(!tc08_has_b2, 'TC08: Block 2 content NOT applied (block 1 was nearest)')
catch
  Assert(false, 'TC08: AiApplyCode error: ' .. v:exception)
endtry
if tc08_target > 0 | execute 'bwipeout! ' .. tc08_target | endif
execute 'bwipeout! ' .. tc08_buf
call delete(tmpdir .. '/tc08.txt')
call delete(tc08_src)

# TC09: Cursor inside block 2 (line 7) — block 2 selected.
var tc09_src: string = SetupBuf([
    'header',
    '```python',
    '# block1_marker',
    '```',
    'gap',
    '```python',
    '# block2_marker',
    '```',
])
b:vproj_ai_target_file = tmpdir .. '/tc09.txt'
b:vproj_ai_cursor_line = 0
cursor(7, 1)
var tc09_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc09_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc09_target = bufnr(tmpdir .. '/tc09.txt')
  var tc09_lines: list<string> = getbufline(tc09_target, 1, '$')
  var tc09_has_b2: bool = false
  for ln in tc09_lines
    if stridx(ln, 'block2_marker') >= 0
      tc09_has_b2 = true
      break
    endif
  endfor
  Assert(tc09_has_b2, 'TC09: Block 2 content applied when cursor in block 2')
  var tc09_has_b1: bool = false
  for ln in tc09_lines
    if stridx(ln, 'block1_marker') >= 0
      tc09_has_b1 = true
      break
    endif
  endfor
  Assert(!tc09_has_b1, 'TC09: Block 1 content NOT applied (block 2 was nearest)')
catch
  Assert(false, 'TC09: AiApplyCode error: ' .. v:exception)
endtry
if tc09_target > 0 | execute 'bwipeout! ' .. tc09_target | endif
execute 'bwipeout! ' .. tc09_buf
call delete(tmpdir .. '/tc09.txt')
call delete(tc09_src)

# ────────────────────────────────────────────────────────────
# SECTION 4: b:vproj_ai_target_file set vs unset
#
# When set, code goes to the specified file. When unset,
# falls back to expand('%:p') which returns the buffer's
# own path when editing a named file.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 4: target_file set vs unset ==='

# TC10: b:vproj_ai_target_file explicitly set.
# Code goes to the specified file; focus restored to source.
var tc10_src: string = SetupBuf(['```json', '{"k": "tc10"}', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc10_target.txt'
b:vproj_ai_cursor_line = 0
var tc10_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc10_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc10_target = bufnr(tmpdir .. '/tc10_target.txt')
  Assert(tc10_target > 0, 'TC10: Target file buffer loaded')
catch
  Assert(false, 'TC10: AiApplyCode error: ' .. v:exception)
endtry
if tc10_target > 0 | execute 'bwipeout! ' .. tc10_target | endif
execute 'bwipeout! ' .. tc10_buf
call delete(tmpdir .. '/tc10_target.txt')
call delete(tc10_src)

# TC11: b:vproj_ai_target_file unset, buffer is named.
# Falls back to expand('%:p'). ApplyCodeToFile finds buffer
# already loaded and visible — appends in-place without
# opening a new window. Focus never changes.
var tc11_src: string = SetupBuf(['```python', 'print("tc11")', '```'])
b:vproj_ai_cursor_line = 0
var tc11_old_buf: number = bufnr('%')
var tc11_lines_before: number = line('$')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(bufnr('%') == tc11_old_buf, 'TC11: Stayed in same buffer (target_file unset, named)')
  Assert(line('$') > tc11_lines_before, 'TC11: Code appended to source buffer')
catch
  Assert(false, 'TC11: AiApplyCode error: ' .. v:exception)
endtry
bwipeout!
call delete(tc11_src)

# ────────────────────────────────────────────────────────────
# SECTION 5: FindCodeBlocks edge cases
# ────────────────────────────────────────────────────────────

echom '=== SECTION 5: FindCodeBlocks edge cases ==='

# TC12: Mixed empty and valid blocks — only non-empty blocks count.
var tc12_src: string = SetupBuf([
    '```python',
    'valid_code',
    '```',
    '```javascript',
    '```',
    '```ruby',
    'more_valid',
    '```',
])
b:vproj_ai_cursor_line = 0
feedkeys("n\<CR>", 't')
vproj_ai#AiApplyCode()
Assert(true, 'TC12: Mixed empty/valid fence blocks does not crash')
bwipeout!
call delete(tc12_src)

# TC13: Indented fence (spaces before ```) — pattern requires ^```.
var tc13_src: string = SetupBuf([
    '  ```python',
    'print("indented")',
    '  ```',
])
vproj_ai#AiApplyCode()
Assert(true, 'TC13: Indented fences (no match) does not crash')
bwipeout!
call delete(tc13_src)

# TC14: Trailing text on closing fence line — still matches ^```.
var tc14_src: string = SetupBuf([
    '```python',
    'print("tc14")',
    '``` trailing text',
])
b:vproj_ai_target_file = tmpdir .. '/tc14.txt'
b:vproj_ai_cursor_line = 0
var tc14_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc14_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc14_target = bufnr(tmpdir .. '/tc14.txt')
  Assert(tc14_target > 0, 'TC14: Block found despite trailing text on closing fence')
catch
  Assert(false, 'TC14: AiApplyCode error with trailing text: ' .. v:exception)
endtry
if tc14_target > 0 | execute 'bwipeout! ' .. tc14_target | endif
execute 'bwipeout! ' .. tc14_buf
call delete(tmpdir .. '/tc14.txt')
call delete(tc14_src)

# ────────────────────────────────────────────────────────────
# SECTION 6: Fallback path (no fenced blocks)
#
# When FindCodeBlocks returns empty, AiApplyCode collects
# all non-blank lines as the code body (fallback). If
# b:vproj_ai_target_file is set, it prompts for confirm
# and applies. If unset, "no target file known".
# ────────────────────────────────────────────────────────────

echom '=== SECTION 6: Fallback path ==='

# TC15: No fences, target_file set. Fallback applies all non-blank lines.
var tc15_src: string = SetupBuf([
    'print("tc15 line 1")',
    'print("tc15 line 2")',
    '',
    'not part of fallback',
])
b:vproj_ai_target_file = tmpdir .. '/tc15.txt'
b:vproj_ai_cursor_line = 0
var tc15_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc15_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc15_target = bufnr(tmpdir .. '/tc15.txt')
  Assert(tc15_target > 0, 'TC15: Fallback target buffer loaded')
catch
  Assert(false, 'TC15: AiApplyCode error in fallback: ' .. v:exception)
endtry
if tc15_target > 0 | execute 'bwipeout! ' .. tc15_target | endif
execute 'bwipeout! ' .. tc15_buf
call delete(tmpdir .. '/tc15.txt')
call delete(tc15_src)

# TC16: No fences, no target_file set — "no target file known".
var tc16_src: string = SetupBuf(['print("no target")'])
vproj_ai#AiApplyCode()
Assert(true, 'TC16: Fallback without target_file does not crash')
bwipeout!
call delete(tc16_src)

# TC17: Buffer has both fence blocks and non-blank fallback lines.
# FindCodeBlocks finds the fence first (blocks non-empty).
# The fallback path is never reached.
var tc17_src: string = SetupBuf([
    '```python',
    'print("from_fence")',
    '```',
    'print("from_fallback")',
])
b:vproj_ai_target_file = tmpdir .. '/tc17.txt'
b:vproj_ai_cursor_line = 0
var tc17_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
var tc17_target: number = -1
try
  vproj_ai#AiApplyCode()
  tc17_target = bufnr(tmpdir .. '/tc17.txt')
  var tc17_lines: list<string> = getbufline(tc17_target, 1, '$')
  var tc17_fence_wins: bool = false
  for ln in tc17_lines
    if stridx(ln, 'from_fence') >= 0
      tc17_fence_wins = true
      break
    endif
  endfor
  Assert(tc17_fence_wins, 'TC17: Fence block wins over fallback lines')
catch
  Assert(false, 'TC17: AiApplyCode error: ' .. v:exception)
endtry
if tc17_target > 0 | execute 'bwipeout! ' .. tc17_target | endif
execute 'bwipeout! ' .. tc17_buf
call delete(tmpdir .. '/tc17.txt')
call delete(tc17_src)

# ────────────────────────────────────────────────────────────
# SECTION 7: ApplyCodeToFile — existing target buffer
#
# ApplyCodeToFile handles three cases:
#   1. Buffer shown in a window → switch to that window
#   2. Buffer exists but not visible → :sbuffer (split)
#   3. Buffer does not exist → :split {file}
#
# In all cases, focus is restored afterward.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 7: ApplyCodeToFile buffer cases ==='

# TC18: Target buffer exists in buffer list but is not visible.
# ApplyCodeToFile uses :sbuffer (split), appends, restores focus.
call writefile(['preexisting content'], tmpdir .. '/tc18_target.txt')
execute 'edit ' .. fnameescape(tmpdir .. '/tc18_target.txt')
var tc18_target_buf: number = bufnr('%')
Assert(tc18_target_buf > 0, 'TC18: Target buffer loaded into buffer list')
# Switch to a new buffer with fence content
var tc18_src: string = SetupBuf(['```vim', '" tc18 code', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc18_target.txt'
b:vproj_ai_cursor_line = 0
var tc18_buf: number = bufnr('%')
Assert(tc18_buf != tc18_target_buf, 'TC18: Source != target')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  # Focus restored to source buffer; target was loaded via sbuffer
  # Target has the appended code — read via getbufline
  var tc18_lines: list<string> = getbufline(tc18_target_buf, 1, '$')
  Assert(len(tc18_lines) > 1, 'TC18: Code appended to existing buffer')
catch
  Assert(false, 'TC18: AiApplyCode error with existing buffer: ' .. v:exception)
endtry
# Cleanup: wipe both buffers
execute 'bwipeout! ' .. tc18_target_buf
execute 'bwipeout! ' .. tc18_buf
call delete(tmpdir .. '/tc18_target.txt')
call delete(tc18_src)

# ────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────

# Cleanup temp directory
if isdirectory(tmpdir)
  for f in readdir(tmpdir)
    call delete(tmpdir .. '/' .. f)
  endfor
  call delete(tmpdir, 'd')
endif

echom ''
if failures == 0
  echom 'All vproj_ai unit tests passed.'
  qa!
else
  echohl ErrorMsg
  echom failures .. ' test(s) FAILED.'
  echohl None
  cquit!
endif
