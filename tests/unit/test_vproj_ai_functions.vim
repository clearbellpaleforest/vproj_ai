vim9script

# Unit tests for vproj_ai internal functions.
#
# Exercises the following non-exported functions indirectly through
# the exported AiApplyCode API:
#   - FindCodeBlocks     (scan current buffer for ``` fences)
#   - FindNearestBlock   (pick block closest to cursor)
#   - ApplyCodeToFile     (append code to target file/buffer)
#
# Functions that require a live API key and curl (AiCall,
# BuildRequestBody, JsonEscape, ExtractJsonField) cannot be tested
# indirectly in headless mode. AiCall itself has a pre-existing
# Vim9Script compilation issue (E1027: Missing return statement)
# caused by the compiler not recognizing `return ''` after `endtry`
# as reachable. Attempting to call AiCall triggers this compile-time
# error, so its child functions remain indirectly untestable here.
#
# NOTE: Buffer content is created via writefile() + :edit rather than
# :new + setline(). In Vim 9.2, setline() at vim9script script level
# sets lines visible to getline() at script level but not to getline()
# inside autoload functions — a version-specific scoping quirk.
# writefile() + :edit works reliably across all Vim 9.x versions.
#
# Run from vproj_ai/ directory:
#   vim -N -u NONE -S tests/unit/test_vproj_ai_functions.vim
#
# Requires vproj to be available at ../vproj/src/.

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore

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
# Uses writefile + :edit to avoid the Vim 9.2 setline() quirk.
def SetupBuf(lines: list<string>): string
  var path: string = tmpdir .. '/src_' .. strftime('%H%M%S') .. '_' .. line('$')
  call writefile(lines, path)
  execute 'edit ' .. fnameescape(path)
  return path
enddef

# ────────────────────────────────────────────────────────────
# SECTION 1: FindCodeBlocks — FindCodeBlocks returns empty
#
# AiApplyCode first calls FindCodeBlocks() which scans the
# current buffer for ``` fences. When no complete fenced
# block is found, it returns an empty list.
#
# AiApplyCode then falls through to a fallback path that
# looks for "AI:" prefixed lines. If none are found either,
# it echoes "vproj_ai: no code found" and returns early.
#
# These tests never reach input(), so no feedkeys needed.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 1: FindCodeBlocks empty ==='

# TC01: No fences, no AI: prefix — path: FindCodeBlocks empty → fallback
# finds nothing → "no code found".
var tc01_buf: string = SetupBuf(['just text', 'no fences', 'no ai prefix'])
# target_file unset, no fences + no AI: lines = "no code found"
vproj_ai#AiApplyCode()
Assert(true, 'TC01: AiApplyCode on text without fences or AI: lines does not crash')
bwipeout!
call delete(tc01_buf)

# TC02: Unclosed fence — opening ``` but no closing ```.
# Inner while loop in FindCodeBlocks reaches end-of-buffer
# without finding the closing marker. blocks stays empty.
var tc02_buf: string = SetupBuf(['before', '```python', 'print("hello")', 'print("world")'])
vproj_ai#AiApplyCode()
Assert(true, 'TC02: AiApplyCode with unclosed fence does not crash')
bwipeout!
call delete(tc02_buf)

# TC03: Empty fence — opening ``` immediately closed by ``` on next line.
# code_lines is empty, so no block is added to the list.
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
# SECTION 2: Valid fenced blocks
#
# When FindCodeBlocks returns a non-empty list, AiApplyCode
# calls FindNearestBlock(blocks, line('.')) to pick the
# block closest to the cursor. It then reads target file
# context from buffer variables and prompts for confirmation.
#
# These tests use feedkeys() to supply the confirmation input.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 2: Valid fenced blocks ==='

# TC05: Single valid fence, user cancels (feeds "n").
# File should NOT be created when cancelled.
var tc05_src: string = SetupBuf(['```python', 'print("tc05")', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc05.txt'
b:vproj_ai_cursor_line = 0
feedkeys("n\<CR>", 't')
vproj_ai#AiApplyCode()
Assert(!filereadable(tmpdir .. '/tc05.txt'), 'TC05: AiApplyCode cancelled, no file written')
bwipeout!
call delete(tc05_src)

# TC06: Single valid fence, user confirms (feeds "y").
# ApplyCodeToFile does `edit {target}` and appends code.
# After the call, current buffer is the target file buffer.
var tc06_src: string = SetupBuf(['```python', 'print("tc06 content")', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc06.txt'
b:vproj_ai_cursor_line = 0
var tc06_buf_before: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(bufnr('%') != tc06_buf_before, 'TC06: Switched to target file buffer')
  Assert(line('$') > 0, 'TC06: Target buffer has content')
catch
  Assert(false, 'TC06: AiApplyCode error: ' .. v:exception)
endtry
# Write the buffer to disk and verify content
writefile(getline(1, '$'), tmpdir .. '/tc06.txt')
var tc06_post: list<string> = readfile(tmpdir .. '/tc06.txt')
var tc06_found: bool = false
for ln in tc06_post
  if stridx(ln, 'tc06 content') >= 0
    tc06_found = true
    break
  endif
endfor
Assert(tc06_found, 'TC06: Target file contains applied code')
bwipeout!
execute 'bwipeout! ' .. tc06_buf_before
call delete(tmpdir .. '/tc06.txt')
call delete(tc06_src)

# TC07: User confirms with "yes" — tests full regex ^y\(es\)\?$.
var tc07_src: string = SetupBuf(['```vim', '" tc07', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc07.txt'
b:vproj_ai_cursor_line = 0
var tc07_buf_before: number = bufnr('%')
feedkeys("yes\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(true, 'TC07: AiApplyCode confirmed with "yes" does not crash')
catch
  Assert(false, 'TC07: AiApplyCode error with "yes": ' .. v:exception)
endtry
bwipeout!
execute 'bwipeout! ' .. tc07_buf_before
call delete(tmpdir .. '/tc07.txt')
call delete(tc07_src)

# ────────────────────────────────────────────────────────────
# SECTION 3: FindNearestBlock — multiple blocks
#
# FindNearestBlock picks the block closest to cursor.
# When cursor is inside a block, distance is 0 and that
# block wins.
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
# ────────────────────────────────────────────────────────────

echom '=== SECTION 3: FindNearestBlock ==='

# TC08: Cursor inside block 1 (line 3) — block 1 is selected.
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
var tc08_buf_before: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
catch
  Assert(false, 'TC08: AiApplyCode error: ' .. v:exception)
endtry
writefile(getline(1, '$'), tmpdir .. '/tc08.txt')
var tc08_post: list<string> = readfile(tmpdir .. '/tc08.txt')
var tc08_has_b1: bool = false
for ln in tc08_post
  if stridx(ln, 'block1_marker') >= 0
    tc08_has_b1 = true
    break
  endif
endfor
Assert(tc08_has_b1, 'TC08: Block 1 content applied when cursor in block 1')
var tc08_has_b2: bool = false
for ln in tc08_post
  if stridx(ln, 'block2_marker') >= 0
    tc08_has_b2 = true
    break
  endif
endfor
Assert(!tc08_has_b2, 'TC08: Block 2 content NOT applied (block 1 was nearest)')
bwipeout!
execute 'bwipeout! ' .. tc08_buf_before
call delete(tmpdir .. '/tc08.txt')
call delete(tc08_src)

# TC09: Cursor inside block 2 (line 7) — block 2 is selected.
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
var tc09_buf_before: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
catch
  Assert(false, 'TC09: AiApplyCode error: ' .. v:exception)
endtry
writefile(getline(1, '$'), tmpdir .. '/tc09.txt')
var tc09_post: list<string> = readfile(tmpdir .. '/tc09.txt')
var tc09_has_b2: bool = false
for ln in tc09_post
  if stridx(ln, 'block2_marker') >= 0
    tc09_has_b2 = true
    break
  endif
endfor
Assert(tc09_has_b2, 'TC09: Block 2 content applied when cursor in block 2')
var tc09_has_b1: bool = false
for ln in tc09_post
  if stridx(ln, 'block1_marker') >= 0
    tc09_has_b1 = true
    break
  endif
endfor
Assert(!tc09_has_b1, 'TC09: Block 1 content NOT applied (block 2 was nearest)')
bwipeout!
execute 'bwipeout! ' .. tc09_buf_before
call delete(tmpdir .. '/tc09.txt')
call delete(tc09_src)

# ────────────────────────────────────────────────────────────
# SECTION 4: b:vproj_ai_target_file set vs unset
#
# AiApplyCode reads b:vproj_ai_target_file from the current
# buffer. When set, it uses that path directly. When unset,
# it falls back to expand('%:p') which returns the buffer's
# own path when editing a named file.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 4: target_file set vs unset ==='

# TC10: b:vproj_ai_target_file explicitly set.
# Code goes to the specified file, not to the source buffer.
var tc10_src: string = SetupBuf(['```json', '{"k": "tc10"}', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc10_target.txt'
b:vproj_ai_cursor_line = 0
var tc10_buf_before: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(bufnr('%') != tc10_buf_before, 'TC10: Switched to target file buffer')
catch
  Assert(false, 'TC10: AiApplyCode error: ' .. v:exception)
endtry
bwipeout!
execute 'bwipeout! ' .. tc10_buf_before
call delete(tmpdir .. '/tc10_target.txt')
call delete(tc10_src)

# TC11: b:vproj_ai_target_file unset, buffer is named.
# Falls back to expand('%:p') which returns the buffer's own path.
# ApplyCodeToFile finds the buffer already loaded and appends
# in-place (no :edit switch).
var tc11_src: string = SetupBuf(['```python', 'print("tc11")', '```'])
# Do NOT set b:vproj_ai_target_file
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
#
# Exercising edge conditions of the fenced-block parser.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 5: FindCodeBlocks edge cases ==='

# TC12: Mixed empty and valid blocks — only non-empty blocks count,
# so FindCodeBlocks returns at least the valid blocks.
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
# target_file unset, named buffer → should apply one of the valid blocks
b:vproj_ai_cursor_line = 0
feedkeys("n\<CR>", 't')
vproj_ai#AiApplyCode()
Assert(true, 'TC12: Mixed empty/valid fence blocks does not crash')
bwipeout!
call delete(tc12_src)

# TC13: Indented fence (spaces before ```) — pattern requires ^```.
# Leading whitespace means the pattern does NOT match, so no fence
# is detected.
var tc13_src: string = SetupBuf([
    '  ```python',
    'print("indented")',
    '  ```',
])
vproj_ai#AiApplyCode()
Assert(true, 'TC13: Indented fences (no match) does not crash')
bwipeout!
call delete(tc13_src)

# TC14: Trailing text on closing fence line.
# Pattern `getline(i) =~ '^```'` matches lines starting with ```.
# Trailing text after ``` does not prevent match detection.
var tc14_src: string = SetupBuf([
    '```python',
    'print("tc14")',
    '``` trailing text',
])
b:vproj_ai_target_file = tmpdir .. '/tc14.txt'
b:vproj_ai_cursor_line = 0
var tc14_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(bufnr('%') != tc14_buf, 'TC14: Block found despite trailing text on closing fence')
catch
  Assert(false, 'TC14: AiApplyCode error with trailing text: ' .. v:exception)
endtry
bwipeout!
execute 'bwipeout! ' .. tc14_buf
call delete(tmpdir .. '/tc14.txt')
call delete(tc14_src)

# ────────────────────────────────────────────────────────────
# SECTION 6: AI: fallback path
#
# When FindCodeBlocks returns empty, AiApplyCode scans for
# lines starting with "AI:" as a fallback. If found, those
# lines form the code body. The fallback then reads
# b:vproj_ai_target_file — if unset, it errors
# "no target file known".
# ────────────────────────────────────────────────────────────

echom '=== SECTION 6: AI: fallback ==='

# TC15: Buffer with "AI:" lines, target_file set.
# Fallback extracts AI: lines and applies code to target.
var tc15_src: string = SetupBuf([
    'AI: print("tc15")',
    'AI: print("second")',
    'not part of fallback',
])
b:vproj_ai_target_file = tmpdir .. '/tc15.txt'
b:vproj_ai_cursor_line = 0
var tc15_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(true, 'TC15: AI: fallback did not crash')
catch
  Assert(false, 'TC15: AiApplyCode error with AI: lines: ' .. v:exception)
endtry
bwipeout!
execute 'bwipeout! ' .. tc15_buf
call delete(tmpdir .. '/tc15.txt')
call delete(tc15_src)

# TC16: Buffer with "AI:" lines but no target_file set.
# Falls through to "no target file known" error.
var tc16_src: string = SetupBuf(['AI: print("no target")'])
vproj_ai#AiApplyCode()
Assert(true, 'TC16: AI: lines without target_file does not crash')
bwipeout!
call delete(tc16_src)

# TC17: Buffer has both "AI:" lines and fenced blocks.
# FindCodeBlocks finds the fence first. AI: fallback never reached.
var tc17_src: string = SetupBuf([
    '```python',
    'print("from_fence")',
    '```',
    'AI: print("from_fallback")',
])
b:vproj_ai_target_file = tmpdir .. '/tc17.txt'
b:vproj_ai_cursor_line = 0
var tc17_buf: number = bufnr('%')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  writefile(getline(1, '$'), tmpdir .. '/tc17.txt')
  var tc17_content: list<string> = readfile(tmpdir .. '/tc17.txt')
  var tc17_fence_wins: bool = false
  for ln in tc17_content
    if stridx(ln, 'from_fence') >= 0
      tc17_fence_wins = true
      break
    endif
  endfor
  Assert(tc17_fence_wins, 'TC17: Fence block wins over AI: lines')
catch
  Assert(false, 'TC17: AiApplyCode error: ' .. v:exception)
endtry
bwipeout!
execute 'bwipeout! ' .. tc17_buf
call delete(tmpdir .. '/tc17.txt')
call delete(tc17_src)

# ────────────────────────────────────────────────────────────
# SECTION 7: ApplyCodeToFile — existing target buffer
#
# ApplyCodeToFile handles three cases for the target:
#   1. Buffer shown in a window → switch to that window
#   2. Buffer exists but not visible → :sbuffer
#   3. Buffer does not exist → :edit {file}
#
# Cases 1 and 3 are exercised in earlier sections.
# Case 2 is tested here.
# ────────────────────────────────────────────────────────────

echom '=== SECTION 7: ApplyCodeToFile buffer cases ==='

# TC18: Target buffer exists in buffer list but is not visible.
# ApplyCodeToFile finds it via bufnr(), then :sbuffer to display it.
call writefile(['preexisting content'], tmpdir .. '/tc18_target.txt')
# Open the target once so it enters the buffer list
execute 'edit ' .. fnameescape(tmpdir .. '/tc18_target.txt')
var tc18_target_buf: number = bufnr('%')
Assert(tc18_target_buf > 0, 'TC18: Target buffer loaded into buffer list')
# Switch to a new buffer with fence content (target is still in list)
var tc18_src: string = SetupBuf(['```vim', '" tc18 code', '```'])
b:vproj_ai_target_file = tmpdir .. '/tc18_target.txt'
b:vproj_ai_cursor_line = 0
Assert(bufnr('%') != tc18_target_buf, 'TC18: Target not current in buffer list')
feedkeys("y\<CR>", 't')
try
  vproj_ai#AiApplyCode()
  Assert(bufnr('%') == tc18_target_buf, 'TC18: Switched to existing target via :sbuffer')
  Assert(line('$') > 1, 'TC18: Code appended to existing buffer')
catch
  Assert(false, 'TC18: AiApplyCode error with existing buffer: ' .. v:exception)
endtry
bwipeout!
# The target buffer was already wiped by bwipeout! above (it was current),
# so guard against E517: the fence buffer is different and still exists.
if bufexists(tc18_target_buf)
  execute 'bwipeout! ' .. tc18_target_buf
endif
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
