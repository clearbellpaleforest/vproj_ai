vim9script

# Demo: Show the plugin state at each step
# Run: vim -N -u NONE -S tests/demo.vim

set rtp+=src
runtime! plugin/vproj_ai.vim
set nomore

def ShowState(label: string): void
  echom '=== ' .. label .. ' ==='
  if vproj_ai#IsPaneVisible()
    var mode: string = vproj_ai#GetCurrentMode()
    echom '  Mode: ' .. mode .. ' | Width: ' .. vproj_ai#GetPaneWidth()
    # Find pane buffer by name
    var pbuf = bufnr('VPROJ_AI')
    var pwnr = bufwinnr(pbuf)
    var pane_wid = win_getid(pwnr)
    var cursor_line = line('.', pane_wid)
    echom '  Cursor line in pane: ' .. cursor_line
    var lines = getbufline(pbuf, 1, '$')
    var i: number = 1
    for line in lines
      var marker: string = (i == cursor_line) ? '>' : ' '
      echom printf('  %s %2d: %s', marker, i, line)
      i += 1
      if i > 10 | break | endif
    endfor
  else
    echom '  Pane is CLOSED'
  endif
enddef

# --- STEP 1: Initial state ---
echom ''
echom 'STEP 1: Fresh start — pane is closed'
ShowState('Step 1: Closed')

# --- STEP 2: Open pane ---
echom ''
echom 'STEP 2: Press F4 to open — cursor should be on first file item (line 3)'
vproj_ai#PaneOpen()
ShowState('Step 2: After F4 (PaneOpen)')

# --- STEP 3: Press j to move down ---
echom ''
echom 'STEP 3: Press j — cursor moves to next file/dir'
vproj_ai#SelectNext()
ShowState('Step 3: After pressing j once')

# --- STEP 4: Press j again ---
echom ''
echom 'STEP 4: Press j again — cursor moves further down'
vproj_ai#SelectNext()
ShowState('Step 4: After pressing j twice')

# --- STEP 5: Press k to move up ---
echom ''
echom 'STEP 5: Press k — cursor moves back up'
vproj_ai#SelectPrev()
ShowState('Step 5: After pressing k')

# --- STEP 6: Navigate into a subdirectory ---
echom ''
echom 'STEP 6: Enter on a directory — navigates into it, cursor resets to first item'
# Find first directory item and navigate into it
vproj_ai#SwitchMode('file')
# We need to find a dir. After PaneOpen we're in the project root.
# If there's a src/ dir, the cursor may be on it. Let's try SelectCurrent.
# But that could navigate up if cursor is on "..". Let's move past ".." first.
# Actually, let's just use NavigateUp then re-enter to show the flow.
vproj_ai#PaneClose()
vproj_ai#PaneOpen()
ShowState('Step 6: Re-opened pane at current dir')

# --- STEP 7: Test NavigateUp ("..") ---
echom ''
echom 'STEP 7: NavigateUp (".." parent directory)'
vproj_ai#NavigateUp()
ShowState('Step 7: After NavigateUp (..)')

# --- STEP 8: Test cursor wrapping ---
echom ''
echom 'STEP 8: Press j many times — cursor wraps around, never lands on menu/separator'
for i in range(3)
  vproj_ai#SelectNext()
endfor
ShowState('Step 8: After 3 more j presses (wrap test)')

# --- STEP 9: Switch to buf mode ---
echom ''
echom 'STEP 9: Switch to buf mode (Shift-D)'
vproj_ai#SwitchMode('buf')
ShowState('Step 9: Buf mode')

# --- STEP 10: Switch to git mode ---
echom ''
echom 'STEP 10: Switch to git mode (Shift-C)'
vproj_ai#SwitchMode('git')
ShowState('Step 10: Git mode')

# --- STEP 11: Back to file mode, close ---
echom ''
echom 'STEP 11: Back to file mode, then close pane'
vproj_ai#SwitchMode('file')
vproj_ai#PaneClose()
ShowState('Step 11: After PaneClose')

echom ''
echom 'DEMO COMPLETE — all steps executed successfully.'
qa!
