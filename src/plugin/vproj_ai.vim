vim9script

# plugin/vproj_ai.vim — VPROJ_AI entry point.
#
# Loads the project pane and registers commands and default key mappings.
# Stage 1 (ADR-012): Pane Infrastructure — toggle, open, close via F4.
#
# Commands:
#   :VprojAiToggle  — Toggle the project pane open/closed.
#   :VprojAiOpen    — Open the project pane.
#   :VprojAiClose   — Close the project pane.
#   :VprojAiRefresh — Refresh the pane contents.

# Load guard
if exists('g:loaded_vproj')
  finish
endif
g:loaded_vproj = 1

# Define highlight groups (idempotent — uses highlight default)
vproj_ai#DefineHighlights()

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
command! -bar -nargs=0 VprojAiToggle  vproj_ai#PaneToggle()
command! -bar -nargs=0 VprojAiOpen    vproj_ai#PaneOpen()
command! -bar -nargs=0 VprojAiClose   vproj_ai#PaneClose()
command! -bar -nargs=0 VprojAiRefresh vproj_ai#Refresh()
command! -bar -nargs=0 VprojAiDiag    call vproj_ai#PaneDiagnose()

# ---------------------------------------------------------------------------
# Default key mapping: F4 toggles the project pane.
# Uses <Plug> indirection so users can remap in their vimrc without
# clobbering the default.
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>VprojAiToggle :VprojAiToggle<CR>

if !hasmapto('<Plug>VprojAiToggle', 'n')
  nmap <F4> <Plug>VprojAiToggle
endif

nnoremap <silent> <Plug>VprojAiF1 :call vproj_ai#HandleF1()<CR>

if !hasmapto('<Plug>VprojAiF1', 'n')
  nmap <F1> <Plug>VprojAiF1
  nmap <Help> <Plug>VprojAiF1
endif
