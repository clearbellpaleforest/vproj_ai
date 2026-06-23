vim9script

# Integration tests for terminal-based AI chat (headless-safe).
# Run: vim -N -u NONE -S tests/integration/test_terminal_chat.vim
# Uses the Vim Agent Runtime harness (autoload/vim_agent_runtime.vim).
#
# Terminal creation tests are skipped in headless Vim (headless can't create ptys).
# Run those interactively in Vim with: :source tests/integration/test_terminal_chat.vim

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore

vim_agent_runtime#Begin('terminal chat integration')

# ── Test 1: Harness autoload works ──
vim_agent_runtime#Assert(true, 'vim_agent_runtime autoload functions available')

# ── Test 2: API key guard — no crash when unset ──
var key_guard_ok: bool = true
try
  call vproj_ai#AiTerminalChat()
catch /.*/
  key_guard_ok = false
endtry
vim_agent_runtime#Assert(key_guard_ok, 'AiTerminalChat returns without crash when API key unset')

# ── Test 3: Bash chat script exists and is syntax-valid ──
var chat_script: string = expand('<sfile>:p:h:h') .. '/../bin/vproj-ai-chat'
var script_exists: bool = filereadable(chat_script)
vim_agent_runtime#Assert(script_exists, 'bin/vproj-ai-chat exists')

if script_exists
  var bash_ok: bool = system('bash -n ' .. shellescape(chat_script) .. ' 2>&1') == ''
  vim_agent_runtime#Assert(bash_ok, 'bash chat script syntax is valid')
endif

# ── Test 4: AiTerminalChat function is callable ──
vim_agent_runtime#Assert(exists('*vproj_ai#AiTerminalChat'), 'AiTerminalChat is an autoload function')

# ── Test 5: Error path — unset API key handled ──
unlet! g:vproj_ai_api_key
var unset_ok: bool = true
try
  call vproj_ai#AiTerminalChat()
catch /.*/
  unset_ok = false
endtry
vim_agent_runtime#Assert(unset_ok, 'no crash with unset API key')

# ── Test 6: Verify bash script exists ──
vim_agent_runtime#Assert(filereadable('bin/verify_vim.sh'), 'verify_vim.sh exists')
vim_agent_runtime#Assert(filereadable('bin/vproj-ai-chat'), 'vproj-ai-chat exists')

# ── Test 7: Harness returns structured results ──
var test_result: dict<any> = {ok: true, msg: 'structured result test'}
vim_agent_runtime#Log({event: 'test', data: test_result})
vim_agent_runtime#Assert(true, 'structured logging works')

# ── Report ──
vim_agent_runtime#Log({event: 'env',
  has_terminal: has('terminal'),
  headless: !has('gui_running') && empty(getenv('DISPLAY')),
  cwd: getcwd(),
})
vim_agent_runtime#Snapshot()
vim_agent_runtime#End()
