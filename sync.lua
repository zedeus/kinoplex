-- syncplayintf.lua -- An interface for communication between mpv and Syncplay
-- Author: Etoh, utilising repl.lua code by James Ross-Gowan (see below)
-- Thanks: RiCON, James Ross-Gowan, Argon-, wm4, uau

-- Includes code copied/adapted from repl.lua -- A graphical REPL for mpv input commands
--
-- c 2016, James Ross-Gowan
--
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
-- OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
-- CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-- See https://github.com/rossy/mpv-repl for a copy of repl.lua

local CANVAS_WIDTH = 1920
local CANVAS_HEIGHT = 1080
local chat_format = "{\\fs50}{\an1}"
local WORDWRAPIFY_MAGICWORD = "{\\\\fscx0}  {\\\\fscx100}"

local HINT_TEXT_COLOUR = "8499a8" -- RBG
local COLOR_NEUTRAL = "8499a8"
local COLOR_BAD = "0000FF"
local COLOR_GOOD = "00FF00"
local FONT_MULTI = 2

local chat_log = {}
local last_chat_time = 0
local line = ''
local cursor = 1
local repl_active = false
local key_hints_enabled = false

local assdraw = require "mp.assdraw"
local opt = require 'mp.options'

function send_quit()
  mp.commandv("script-message", "quit")
end

function format_chat(text)
  return string.format(chat_format .. text:gsub('%%','%%%%') .."\\N\\n")
end

function clear_chat()
  chat_log = {}
  update()
end

mp.register_script_message('clear', clear_chat)

function add_chat(chat_message, mood)
  last_chat_time = mp.get_time()
  local entry = #chat_log+1
  for i = 1, #chat_log do
    if chat_log[i].text == '' then
      entry = i
      break
    end
  end
  if entry-1 > opts['chatMaxLines'] then
    table.remove(chat_log, 1)
    entry = entry - 1
  end
  chat_log[entry] = { xpos=CANVAS_WIDTH, timecreated=mp.get_time(),
                      text=tostring(chat_message), row=row, color=mood }
end

function chat_update()
  local ass = assdraw.ass_new()
  local chat_ass = ''
  local rowsAdded = 0
  local to_add = ''
  local incrementRow = 0
  if chat_log ~= {} then
    local timedelta = mp.get_time() - last_chat_time
    if timedelta >= opts['chatTimeout'] then
      clear_chat()
    end
  end

  if #chat_log > 0 then
    for i = 1, #chat_log do
      local to_add = process_chat_item(i,rowsAdded)
      if to_add ~= nil and to_add ~= "" then
        chat_ass = chat_ass .. to_add
      end
    end
  end

  local xpos = opts['chatLeftMargin']
  local ypos = opts['chatTopMargin']
  chat_ass = "\n".."{\\pos("..xpos..","..ypos..")}".. chat_ass

  if opts['chatInputPosition'] == "Top" then
    ass:append(chat_ass)
    ass:append(input_ass())
  else
    ass:append(input_ass())
    ass:append(chat_ass)
  end
  mp.set_osd_ass(CANVAS_WIDTH,CANVAS_HEIGHT, ass.text)
end

function process_chat_item(i, startRow)
  local text = chat_log[i].text
  if text ~= '' then
    local text = wordwrapify_string(text)
    local rowNumber = i+startRow-1
    return(format_chat("{\\1c&H"..chat_log[i].color.."}"..text))
  end
end

chat_timer=mp.add_periodic_timer(0.01, chat_update)

mp.register_script_message('chat', function(e)
  add_chat(e, opts["chatOutputFontColor"])
end)

-- Chat OSD

mp.register_script_message('chat-osd-neutral', function(e)
  add_chat(e, COLOR_NEUTRAL)
end)

mp.register_script_message('chat-osd-bad', function(e)
  add_chat(e, COLOR_BAD)
end)

mp.register_script_message('chat-osd-good', function(e)
  add_chat(e, COLOR_GOOD)
end)

--

mp.register_script_message('set_syncplayintf_options', function(e)
  set_syncplayintf_options(e)
end)

-- Default options
local utils = require 'mp.utils'
local options = require 'mp.options'
opts = {
  -- All drawing is scaled by this value, including the text borders and the
  -- cursor. Change it if you have a high-DPI display.
  scale = 1,
  -- Set the font used for the REPL and the console. This probably doesn't
  -- have to be a monospaced font.
  ['chatFontFamily'] = 'monospace',
  -- Enable/Disable
  ['chatInputEnabled'] = true,
  ['chatOutputEnabled'] = true,
  -- Set the font size used for the REPL and the console. This will be
  -- multiplied by "scale."
  ['chatFontSize'] = 10,
  ['chatFontWeight'] = 1,
  ['chatInputPosition'] = "Top",
  ['chatInputFontColor'] = "8499A8",
  ['chatOutputFontColor'] = "8499A8",
  ['chatMaxMessageLength'] = 500,
  ['chatMaxLines'] = 7,
  ['chatTopMargin'] = 7,
  ['chatLeftMargin'] = 12,
  --
  ['chatTimeout'] = 7,
  --
  ['inputPromptStartCharacter'] = ">",
  ['backslashSubstituteCharacter'] = "|",
  --Lang:
  ['mpv-key-hint'] = "[ENTER] to send message. [ESC] to escape chat mode.",
}

function detect_platform()
  local o = {}
  -- Kind of a dumb way of detecting the platform but whatever
  if mp.get_property_native('options/vo-mmcss-profile', o) ~= o then
    return 'windows'
  elseif mp.get_property_native('options/input-app-events', o) ~= o then
    return 'macos'
  end
  return 'linux'
end

-- Pick a better default font for Windows and macOS
local platform = detect_platform()
if platform == 'windows' then
  opts["chatFont"] = 'Consolas'
elseif platform == 'macos' then
  opts["chatFont"] = 'Menlo'
end

-- Apply user-set options
options.read_options(opts)

-- Escape a string for verbatim display on the OSD
function ass_escape(str)
  -- There is no escape for '\' in ASS (I think?) but '\' is used verbatim if
  -- it isn't followed by a recognised character, so add a zero-width
  -- non-breaking space
  str = str:gsub('\\', '\\\239\187\191')
  str = str:gsub('{', '\\{')
  str = str:gsub('}', '\\}')
  -- Precede newlines with a ZWNBSP to prevent ASS's weird collapsing of
  -- consecutive newlines
  str = str:gsub('\n', '\239\187\191\n')
  return str
end

function update()
  return
end

function input_ass()
  if not repl_active then
    return ""
  end
  last_chat_time = mp.get_time() -- to keep chat messages showing while entering input
  local bold
  if opts['chatFontWeight'] < 75 then
    bold = 0
  else
    bold = 1
  end
  local fontColor = opts['chatInputFontColor']
  local style = '{\\r' ..
    '\\1a&H00&\\3a&H00&\\4a&H99&' ..
    '\\1c&H'..fontColor..'&\\3c&H111111&\\4c&H000000&' ..
    '\\fn' .. opts['chatFontFamily'] .. '\\fs' .. (opts['chatFontSize']*FONT_MULTI) .. '\\b' .. bold ..
    '\\bord2\\xshad0\\yshad1\\fsp0\\q1}'

  local before_cur = wordwrapify_string(ass_escape(line:sub(1, cursor - 1)))
  local after_cur = wordwrapify_string(ass_escape(line:sub(cursor)))
  local secondary_pos = "10,"..tostring(10+(opts['chatFontSize']*FONT_MULTI))

  local alignment = 7
  local position = "5,5"
  local start_marker = opts['inputPromptStartCharacter']
  local end_marker = ""
  if opts['chatInputPosition'] == "Bottom" then
    alignment = 1
    position = tostring(5)..","..tostring(CANVAS_HEIGHT-5)
    secondary_pos = "10,"..tostring(CANVAS_HEIGHT-(20+(opts['chatFontSize']*FONT_MULTI)))
  end

  local osd_help_message = opts['mpv-key-hint']
  local help_prompt = '\\N\\n{\\an'..alignment..'\\pos('..secondary_pos..')\\fn' .. opts['chatFontFamily'] .. '\\fs' .. ((opts['chatFontSize']*FONT_MULTI)/1.25) .. '\\1c&H'..HINT_TEXT_COLOUR..'}' .. osd_help_message

  local firststyle = "{\\an"..alignment.."}{\\pos("..position..")}"
  if opts['chatOutputEnabled'] and opts['chatInputPosition'] == "Top" then
    firststyle = get_output_style().."{'\\1c&H'"..fontColor.."}"
    before_cur = before_cur .. firststyle
    after_cur =  after_cur .. firststyle
    help_prompt = '\\N\\n'..firststyle..'{\\1c&H'..HINT_TEXT_COLOUR..'}' .. osd_help_message .. '\\N\\n'
  end
  if key_hints_enabled == false then help_prompt = "" end

  return firststyle..style..start_marker.." "..before_cur..style..'_'..style..after_cur..end_marker..help_prompt

end

function get_output_style()
  local bold
  if opts['chatFontWeight'] < 75 then
    bold = 0
  else
    bold = 1
  end
  local underline = opts['chatOutputFontUnderline'] and 1 or 0
  local fontColor = opts['chatOutputFontColor']
  local style = '{\\r' ..
    '\\1a&H00&\\3a&H00&\\4a&H99&' ..
    '\\1c&H'..fontColor..'&\\3c&H111111&\\4c&H000000&' ..
    '\\fn' .. opts['chatFontFamily'] .. '\\fs' .. (opts['chatFontSize']*FONT_MULTI) .. '\\b' .. bold ..
    '\\u'  .. underline .. '\\a5\\MarginV=500' .. '}'

  --mp.osd_message("",0)
  return style

end

function escape()
  set_active(false)
  clear()
end

-- Set the REPL visibility (`, Esc)
function set_active(active)
  if active == repl_active then return end
  if active then
    repl_active = true
    mp.enable_key_bindings('repl-input', 'allow-hide-cursor+allow-vo-dragging')
  else
    repl_active = false
    mp.disable_key_bindings('repl-input')
  end
end

-- Naive helper function to find the next UTF-8 character in 'str' after 'pos'
-- by skipping continuation bytes. Assumes 'str' contains valid UTF-8.
function next_utf8(str, pos)
  if pos > str:len() then return pos end
  repeat
    pos = pos + 1
  until pos > str:len() or str:byte(pos) < 0x80 or str:byte(pos) > 0xbf
  return pos
end

-- Naive helper function to find the next UTF-8 character in 'str' after 'pos'
-- by skipping continuation bytes. Assumes 'str' contains valid UTF-8.


-- As above, but finds the previous UTF-8 charcter in 'str' before 'pos'
function prev_utf8(str, pos)
  if pos <= 1 then return pos end
  repeat
    pos = pos - 1
  until pos <= 1 or str:byte(pos) < 0x80 or str:byte(pos) > 0xbf
  return pos
end

function trim_string(line,maxCharacters)
  -- Naive helper function to find the next UTF-8 character in 'str' after 'pos'
  -- by skipping continuation bytes. Assumes 'str' contains valid UTF-8.
  local str = line
  if str == nil or str == "" or str:len() <= maxCharacters then
    return str, ""
  end
  local pos = 0
  local oldPos = -1
  local chars = 0

  repeat
    oldPos = pos
    pos = next_utf8(str, pos)
    chars = chars + 1
  until pos == oldPos or chars > maxCharacters
  return str:sub(1,pos-1), str:sub(pos)
end

function wordwrapify_string(line)
  -- Used to ensure characters wrap on a per-character rather than per-word basis
  -- to avoid issues with long filenames, etc.
  local str = line
  if str == nil or str == "" then
    return ""
  end
  local newstr = ""
  local currentChar = 0
  local nextChar = 0
  local chars = 0
  local maxChars = str:len()

  repeat
    nextChar = next_utf8(str, currentChar)
    if nextChar == currentChar then
      return newstr
    end
    local charToTest = str:sub(currentChar,nextChar-1)
    if charToTest ~= "\\" and charToTest ~= "{"  and charToTest ~= "}" and charToTest ~= "%" then
      newstr = newstr .. WORDWRAPIFY_MAGICWORD .. str:sub(currentChar,nextChar-1)
    else
      newstr = newstr .. str:sub(currentChar,nextChar-1)
    end
    currentChar = nextChar
  until currentChar > maxChars
  newstr = string.gsub(newstr,opts['backslashSubstituteCharacter'], '\\\239\187\191') -- Workaround for \ escape issues
  return newstr
end


function trim_input()
  -- Naive helper function to find the next UTF-8 character in 'str' after 'pos'
  -- by skipping continuation bytes. Assumes 'str' contains valid UTF-8.
  local str = line
  if str == nil or str == "" or str:len() <= opts['chatMaxMessageLength'] then
    return
  end
  local pos = 0
  local oldPos = -1
  local chars = 0

  repeat
    oldPos = pos
    pos = next_utf8(str, pos)
    chars = chars + 1
  until pos == oldPos or chars > opts['chatMaxMessageLength']
  line = line:sub(1,pos-1)
  if cursor > pos then
    cursor = pos
  end
  return
end

-- Insert a character at the current cursor position (' '-'~', Shift+Enter)
function handle_char_input(c)
  if c == nil then return end
  if c == "\\" then c = opts['backslashSubstituteCharacter'] end
  if key_hints_enabled and (string.len(line) > 0) then
    key_hints_enabled = false
  end
  set_active(true)
  line = line:sub(1, cursor - 1) .. c .. line:sub(cursor)
  cursor = cursor + c:len()
  trim_input()
  update()
end

-- Remove the character behind the cursor (Backspace)
function handle_backspace()
  if cursor <= 1 then return end
  local prev = prev_utf8(line, cursor)
  line = line:sub(1, prev - 1) .. line:sub(cursor)
  cursor = prev
  update()
end

-- Remove the character in front of the cursor (Del)
function handle_del()
  if cursor > line:len() then return end
  line = line:sub(1, cursor - 1) .. line:sub(next_utf8(line, cursor))
  update()
end

-- Move the cursor to the next character (Right)
function next_char(amount)
  cursor = next_utf8(line, cursor)
  update()
end

-- Move the cursor to the previous character (Left)
function prev_char(amount)
  cursor = prev_utf8(line, cursor)
  update()
end

-- Clear the current line (Ctrl+C)
function clear()
  line = ''
  cursor = 1
  update()
end

-- Close the REPL if the current line is empty, otherwise do nothing (Ctrl+D)
function maybe_exit()
  if line == '' then
    set_active(false)
  end
end

-- Run the current command and clear the line (Enter)
function handle_enter()
  if not repl_active then
    set_active(true)
    return
  end
  set_active(false)

  if line == '' then
    return
  end
  key_hints_enabled = false
  line = string.gsub(line,"\\", "\\\\")
  line = string.gsub(line,"\"", "\\\"")
  mp.commandv("script-message", "msg", line)
  clear()
end

-- Move the cursor to the beginning of the line (HOME)
function go_home()
  cursor = 1
  update()
end

-- Move the cursor to the end of the line (END)
function go_end()
  cursor = line:len() + 1
  update()
end

-- Delete from the cursor to the end of the line (Ctrl+K)
function del_to_eol()
  line = line:sub(1, cursor - 1)
  update()
end

-- Delete from the cursor back to the start of the line (Ctrl+U)
function del_to_start()
  line = line:sub(cursor)
  cursor = 1
  update()
end

function get_clipboard(clip)
  if platform == 'linux' then
    local res = utils.subprocess({ args = {
                                     'xclip', '-selection', clip and 'clipboard' or 'primary', '-out'
    }, cancellable=false })
    print(res.error)
    print(res.stdout)
    print(res.status)
    if not res.error then
      return res.stdout
    end
  elseif platform == 'windows' then
    local res = utils.subprocess({ args = {
      'powershell', '-NoProfile', '-Command', [[& {
        Trap {
          Write-Error -ErrorRecord $_
          Exit 1
        }
        $clip = ""
        if (Get-Command "Get-Clipboard" -errorAction SilentlyContinue) {
          $clip = Get-Clipboard -Raw -Format Text -TextFormatType UnicodeText
        } else {
          Add-Type -AssemblyName PresentationCore
          $clip = [Windows.Clipboard]::GetText()
        }
        $clip = $clip -Replace "`r",""
        $u8clip = [System.Text.Encoding]::UTF8.GetBytes($clip)
        [Console]::OpenStandardOutput().Write($u8clip, 0, $u8clip.Length)
      }]]
    } })
    if not res.error then
      return res.stdout
    end
  elseif platform == 'macos' then
    local res = utils.subprocess({ args = { 'pbpaste' } })
    if not res.error then
      return res.stdout
    end
  end
  return ''
end

-- Paste text from the window-system's clipboard. 'clip' determines whether the
-- clipboard or the primary selection buffer is used (on X11 only.)
function paste(clip)
  local text = get_clipboard(clip)
  local before_cur = line:sub(1, cursor - 1)
  local after_cur = line:sub(cursor)
  line = before_cur .. text .. after_cur
  cursor = cursor + text:len()
  trim_input()
  update()
end

function add_paste()
  mp.commandv("script-message", "add", get_clipboard(true))
end

-- The REPL has pretty specific requirements for key bindings that aren't
-- really satisified by any of mpv's helper methods, since they must be in
-- their own input section, but they must also raise events on key-repeat.
-- Hence, this function manually creates an input section and puts a list of
-- bindings in it.
function add_repl_bindings(bindings)
  local cfg = ''
  for i, binding in ipairs(bindings) do
    local key = binding[1]
    local fn = binding[2]
    local name = '__repl_binding_' .. i
    mp.add_forced_key_binding(nil, name, fn, 'repeatable')
    cfg = cfg .. key .. ' script-binding ' .. mp.script_name .. '/' ..
      name .. '\n'
  end
  mp.commandv('define-section', 'repl-input', cfg, 'force')
end

-- Mapping from characters to mpv key names
local binding_name_map = {
  [' '] = 'SPACE',
  ['#'] = 'SHARP',
}

-- List of input bindings. This is a weird mashup between common GUI text-input
-- bindings and readline bindings.
local bindings = {
  { 'esc',         function() escape() end     },
  { 'bs',          handle_backspace            },
  { 'shift+bs',    handle_backspace            },
  { 'del',         handle_del                  },
  { 'shift+del',   handle_del                  },
  { 'left',        function() prev_char() end  },
  { 'right',       function() next_char() end  },
  { 'up',          function() clear() end      },
  { 'home',        go_home                     },
  { 'end',         go_end                      },
  { 'ctrl+c',      clear                       },
  { 'ctrl+d',      maybe_exit                  },
  { 'ctrl+k',      del_to_eol                  },
  { 'ctrl+l',      clear_chat                  },
  { 'ctrl+u',      del_to_start                },
  { 'ctrl+v',      function() paste(true) end  },
  { 'meta+v',      function() paste(false) end },
  { 'shift+ins',   function() paste(false) end },
}
-- Add bindings for all the printable US-ASCII characters from ' ' to '~'
-- inclusive. Note, this is a pretty hacky way to do text input. mpv's input
-- system was designed for single-key key bindings rather than text input, so
-- things like dead-keys and non-ASCII input won't work. This is probably okay
-- though, since all mpv's commands and properties can be represented in ASCII.
for b = (' '):byte(), ('~'):byte() do
  local c = string.char(b)
  local binding = binding_name_map[c] or c
  bindings[#bindings + 1] = {binding, function() handle_char_input(c) end}
end

add_repl_bindings(bindings)

local syncplayintfSet = false
mp.command('print-text "<get_syncplayintf_options>"')

function readyMpvAfterSettingsKnown()
  if syncplayintfSet == false then
    mp.add_forced_key_binding('enter', handle_enter)
    mp.add_forced_key_binding('kp_enter', handle_enter)
    mp.add_forced_key_binding('ctrl+l', clear_chat)
    mp.add_forced_key_binding('ctrl+q', send_quit)
    mp.add_forced_key_binding('ctrl+v', add_paste)
    key_hints_enabled = true
    syncplayintfSet = true
  end
end

function set_syncplayintf_options(input)
  --mp.command('print-text "<chat>...'..input..'</chat>"')
  for option, value in string.gmatch(input, "([^ ,=]+)=([^,]+)") do
    local valueType = type(opts[option])
    if valueType == "number" then
      value = tonumber(value)
    elseif valueType == "boolean" then
      if value == "True" then
        value = true
      else
        value = false
      end
    end
    opts[option] = value
    --mp.command('print-text "<chat>'..option.."="..tostring(value).." - "..valueType..'</chat>"')
  end
  chat_format = get_output_style()
  readyMpvAfterSettingsKnown()
end
chat_format = get_output_style()
readyMpvAfterSettingsKnown()
