vim9script

# diagnostic.vim — capture EVERYTHING for remote debugging
# Run: vim -N -u NONE -S tests/diagnostic.vim
# Output written to /tmp/vproj-ai-diag.txt

set rtp+=../vproj/src
set rtp+=src
runtime! plugin/vproj.vim
runtime! plugin/vproj_ai.vim
set nomore

var logfile: string = '/tmp/vproj-ai-diag.txt'

def Log(msg: string): void
  writefile([msg], logfile, 'a')
  echom msg
enddef

# Clear previous log
writefile([], logfile)

Log('=== vproj_ai diagnostic ' .. strftime('%Y-%m-%d %H:%M:%S') .. ' ===')
Log('')

# ── Environment ──
Log('--- Environment ---')
Log('vproj loaded: ' .. (exists('g:loaded_vproj') ? 'yes' : 'NO'))
Log('vproj_ai loaded: ' .. (exists('g:loaded_vproj_ai') ? 'yes' : 'NO'))
Log('has(terminal): ' .. has('terminal'))
Log('Vim version: ' .. string(v:version))
Log('')

# ── API key status ──
Log('--- API Config ---')
var g_key: any = get(g:, 'vproj_ai_api_key', '')
var g_url: any = get(g:, 'vproj_ai_api_url', '')
var g_model: any = get(g:, 'vproj_ai_model', '')
var env_key: string = empty($DEEPSEEK_API_KEY) ? '(unset)' : '(set, ' .. strlen($DEEPSEEK_API_KEY) .. ' chars)'
Log('g:vproj_ai_api_key: ' .. (type(g_key) == v:t_string && !empty(g_key) ? '(set, ' .. strlen(g_key) .. ' chars)' : '(unset)'))
Log('g:vproj_ai_api_url: ' .. (type(g_url) == v:t_string && !empty(g_url) ? g_url : '(unset)'))
Log('g:vproj_ai_model: ' .. (type(g_model) == v:t_string && !empty(g_model) ? g_model : '(unset)'))
Log('$DEEPSEEK_API_KEY: ' .. env_key)
Log('')

# ── Script paths ──
Log('--- Paths ---')
var chat_script: string = expand('<sfile>:p:h:h') .. '/bin/vproj-ai-chat'
Log('chat script: ' .. chat_script)
Log('chat script readable: ' .. (filereadable(chat_script) ? 'yes' : 'NO'))
Log('')

# ── Pre-terminal window layout ──
Log('--- Window layout (before terminal) ---')
Log('winlayout(): ' .. string(winlayout()))
Log('winnr(): ' .. winnr())
Log('winheight(0): ' .. winheight(0))
Log('winwidth(0): ' .. winwidth(0))
Log('&lines: ' .. &lines)
Log('&columns: ' .. &columns)
Log('&cmdheight: ' .. &cmdheight)
Log('&winminheight: ' .. &winminheight)
Log('&winminwidth: ' .. &winminwidth)
Log('')

# Test command string that AiTerminalChat would build
Log('--- Terminal command preview ---')
var script_dir: string = expand('<sfile>:p:h:h') .. '/src/autoload'
var chat_path: string = expand('<sfile>:p:h:h') .. '/bin/vproj-ai-chat'
var fake_key: string = (type(g_key) == v:t_string && !empty(g_key)) ? g_key : 'sk-test-key'
var fake_url: string = (type(g_url) == v:t_string && !empty(g_url)) ? g_url : 'https://api.deepseek.com/v1/chat/completions'
var fake_model: string = (type(g_model) == v:t_string && !empty(g_model)) ? g_model : 'deepseek-chat'
var cmd: string = 'env'
cmd ..= ' VPROJ_AI_API_KEY=' .. fake_key
cmd ..= ' VPROJ_AI_API_URL=' .. fake_url
cmd ..= ' VPROJ_AI_MODEL=' .. fake_model
cmd ..= ' VPROJ_AI_TMPFILE=/tmp/vproj-ai-test'
cmd ..= ' bash ' .. chat_path
Log('full terminal command:')
Log('  ' .. substitute(cmd, 'VPROJ_AI_API_KEY=[^ ]*', 'VPROJ_AI_API_KEY=<hidden>', ''))
Log('command length: ' .. strlen(cmd))
Log('')

# ── Open pane ──
Log('--- Pane open ---')
var saved_cwd: string = getcwd()
cd /home/aldous/work/vproj/vproj
try
  call vproj#PaneOpen()
  var pbuf: number = vproj#GetPaneBufnr()
  Log('PaneOpen: buf=' .. pbuf .. ' visible=' .. vproj#IsPaneVisible())
catch
  Log('PaneOpen ERROR: ' .. v:exception .. ' at ' .. v:throwpoint)
endtry
execute 'cd' saved_cwd
Log('')

# ── Attempt terminal chat ──
Log('--- AiTerminalChat attempt ---')
Log('Window layout before: ' .. string(winlayout()))
Log('winnr() before: ' .. winnr())
Log('winheight(0) before: ' .. winheight(0))
Log('')

# Capture all output from the terminal call
redir @d
  try
    sil! call vproj_ai#AiTerminalChat()
    Log('AiTerminalChat: returned')
  catch
    Log('AiTerminalChat EXCEPTION: ' .. v:exception)
    Log('  throwpoint: ' .. v:throwpoint)
  endtry
redir END

var captured: string = @d
if !empty(captured)
  Log('Captured output: ' .. substitute(captured, "\n", ' | ', 'g'))
endif

Log('Window layout after: ' .. string(winlayout()))
Log('winnr() after: ' .. winnr())
Log('winheight(0) after: ' .. winheight(0))
Log('&lines: ' .. &lines)
Log('')

# ── Check terminal buffers ──
Log('--- Terminal buffer check ---')
var terminal_found: bool = false
for info in getbufinfo()
  if get(info, 'terminal', 0)
    terminal_found = true
    Log('Terminal buf ' .. info.bufnr .. ': ' .. info.name)
    Log('  windows: ' .. string(info.windows))
    Log('  linecount: ' .. info.linecount)
    # Check which windows show this buffer and their dimensions
    var wins: list<number> = win_findbuf(info.bufnr)
    for wnr in wins
      Log('  window ' .. wnr .. ': height=' .. winheight(wnr) .. ' width=' .. winwidth(wnr))
    endfor
  endif
endfor
if !terminal_found
  Log('No terminal buffer found (headless — terminal cannot create pty)')
endif
Log('')

# ── All Vim messages ──
Log('--- All Vim messages ---')
redir @d
  messages
redir END
Log(@d)

Log('=== END ===')
qa!
