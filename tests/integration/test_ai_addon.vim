vim9script

# Integration tests for vproj_ai add-on
# Run: vim -N -u NONE -S tests/integration/test_ai_addon.vim

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
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

echom '=== vproj_ai Add-on Integration Tests ==='

# ── Plugin Coexistence ──
Assert(exists('g:loaded_vproj'), 'vproj loaded')
Assert(exists('g:loaded_vproj_ai'), 'vproj_ai loaded')

# Trigger vproj autoload by toggling
call vproj#PaneToggle()
call vproj#PaneToggle()

Assert(exists('*vproj#GetPaneBufnr'), 'vproj exports GetPaneBufnr')

# Trigger vproj_ai autoload
call vproj_ai#OnBufEnter()

Assert(exists('*vproj_ai#AiPrompt'), 'vproj_ai AiPrompt function exists')
Assert(exists('*vproj_ai#AiCall'), 'vproj_ai AiCall function exists')
Assert(exists('*vproj_ai#OnBufEnter'), 'vproj_ai OnBufEnter function exists')

# ── A mapping injection ──
call vproj#PaneToggle()
var pb: number = vproj#GetPaneBufnr()
if pb > 0
  execute 'buffer ' .. pb
  call vproj_ai#OnBufEnter()
  var a_map: string = maparg('A', 'n')
  Assert(!empty(a_map), 'A mapping injected in pane buffer')
  Assert(stridx(a_map, 'vproj_ai#AiPrompt') >= 0, 'A mapping calls AiPrompt')
else
  echom '(headless: pane buf -1, A mapping tested via smoke test)'
endif

# ── Conversation buffer creation ──
# Simulate what AiPrompt does: open pane, gather context, create conversation view
call vproj#PaneOpen()
var pb2: number = vproj#GetPaneBufnr()
if pb2 > 0
  # Switch to pane so we can test from the right context
  execute 'buffer ' .. pb2
  # Build minimal context (simulating GatherContext)
  var test_ctx: dict<any> = {}
  test_ctx.cwd = getcwd()
  test_ctx.mode = 'file'
  test_ctx.file = expand('%:p')
  test_ctx.filetype = &filetype
  test_ctx.cursor_line = 1
  test_ctx.cursor_col = 1
  test_ctx.file_lines = ['line1', 'line2']
  test_ctx.file_line_offset = 1
  test_ctx.file_total_lines = 2

  # Test AiCall with empty API key (should fail gracefully, no crash)
  var result: string = vproj_ai#AiCall('hello', test_ctx)
  Assert(empty(result), 'AiCall returns empty with no API key configured')

  # Verify AiPrompt doesn't crash when called (returns early on empty input in
  # non-interactive mode, or handles gracefully)
  # We can't fully test AiPrompt (requires input()), but function is callable
  echom '(AiPrompt requires interactive input, not tested headless)'
else
  echom '(headless: pane buf -1, conversation tests skipped)'
endif

# Close pane between tests
call vproj#PaneToggle()

# ── Apply AI-Generated Code ──
# AiApplyCode function must exist (mapping injected in conversation/markdown view buffers)
Assert(exists('*vproj_ai#AiApplyCode'), 'AiApplyCode autoload function exists')

# Close pane between tests
call vproj#PaneToggle()

# ── Pane operation ──
if vproj#IsPaneVisible()
  Assert(vproj#GetCurrentMode() == 'file', 'Default mode is file')
  vproj#PaneToggle()
  Assert(!vproj#IsPaneVisible(), 'PaneToggle closes')
else
  echom '(headless: pane not visible)'
endif

# Report
echom ''
if failures == 0
  echom 'ALL AI ADD-ON INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' AI ADD-ON TEST(S) FAILED.'
  echohl None
  cquit!
endif

qa!
