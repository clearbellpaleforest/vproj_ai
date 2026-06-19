" Shared test helpers for vproj_ai tests — legacy Vimscript so it can be
" source'd from vim9script test files without hanging.
"
" Usage at the top of each test file:
"   vim9script
"   source tests/test_helpers.vim

let g:test_failures = 0

function! Assert(cond, msg)
  if !a:cond
    echohl ErrorMsg | echom 'FAIL: ' . a:msg | echohl None
    let g:test_failures += 1
  else
    echom 'PASS: ' . a:msg
  endif
endfunction

function! PaneCursorLine()
  let pbuf = bufnr('VPROJ_AI')
  let wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
endfunction

function! PaneWinID()
  let pbuf = bufnr('VPROJ_AI')
  let wins = win_findbuf(pbuf)
  return empty(wins) ? 0 : wins[0]
endfunction

function! SetupPane()
  if vproj_ai#IsPaneVisible()
    call vproj_ai#PaneClose()
  endif
  call vproj_ai#PaneOpen()
  if vproj_ai#GetCurrentMode() != 'file'
    call vproj_ai#SwitchMode('file')
  endif
endfunction

function! Summary()
  echom ''
  if g:test_failures == 0
    echom 'ALL TESTS PASSED.'
  else
    echohl ErrorMsg
    echom g:test_failures . ' TEST(S) FAILED.'
    echohl None
    cquit!
  endif
  qa!
endfunction
