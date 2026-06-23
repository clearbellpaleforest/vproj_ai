vim9script

# plugin/vproj_ai.vim — AI add-on entry point.
# Requires vproj. Adds A key to the pane for AI-powered coding assistance.
#
# Commands:
#   :VprojAiPrompt — Open AI prompt

if exists('g:loaded_vproj_ai')
  finish
endif
if !exists('g:loaded_vproj')
  echoerr 'vproj_ai: requires vproj plugin (https://github.com/clearbellpaleforest/vproj)'
  finish
endif
g:loaded_vproj_ai = 1

command! -bar -nargs=? VprojAiPrompt call vproj_ai#AiPrompt(<q-args>)

nnoremap <silent> <Plug>VprojAiPrompt <Cmd>call vproj_ai#AiPromptFromKey()<CR>

# Global A intercept — when vproj is loaded, A opens AI prompt.
# Falls back to Vim's default A (append) when vproj is absent.
nnoremap <silent> A <Cmd>call vproj_ai#AiPromptFromKey()<CR>

# Inject A mapping when entering vproj pane buffer.
# BufEnter catches subsequent re-entries; User VprojPaneReady catches
# the initial pane open (BufEnter fires during :new, before pane_bufnr
# is assigned — see OnBufEnter guard).
augroup vproj_ai_pane
  autocmd!
  autocmd BufEnter * call vproj_ai#OnBufEnter()
  autocmd User VprojPaneReady call vproj_ai#OnBufEnter()
augroup END


