local testik = "teda *ahoj* světe, jak se máš?"
local testik = "*ahoj*"

local wikireader = {}
wikireader.__index = wikireader

local inline_parsers = {}
--- Add inline matcher
-- the pattern must contain at least on capture
-- the function parameter fn is optional, it should return
-- table in the form {name = "item type", value = "text", other properties}
-- the function takes parameters from string.match executed on the matched text
-- with the pattern
local function add_inline(name, pattern, fn)
  local t = {name = name, pattern = pattern, fn = fn}
  -- for quick access to the matcher by name
  inline_parsers[name] = t
  table.insert(inline_parsers, t)
end

local function inline_element(name, value)
  return {name = name, value = value}
end


add_inline("inline_code", "`(.-)`")
add_inline("strong", "%*(.-)%*")
add_inline("italic", "_(.-)_")
add_inline("strikeout", "~~(.-)~~")
add_inline("subscript", ",,(.-),,")
add_inline("superscript", "%^(.-)%^")

add_inline("tag", ":(.+):", function(tags)
  -- tags are in the form of :tag1:tag2:
  -- we need to split them
  local t = {}
  for tag in tags:gmatch("([^:]+)") do
    t[#t+1] = tag
  end
  return {name = "tag", value = t}
end)

local url_schemes = {
  http = "url_link",
  https = "url_link",
  ftp = "url_link",
  mailto = "url_link",
  file = "file_link",
  ["local"] = "file_link"
}

add_inline("link", "%[%[(.-)%]%]", function(text)
  local link, title = text:match("([^|]+)|?(.*)")
  local name = "link"
  -- differentiate between inter-wiki links and links to files or urls
  local scheme = link:match("^([^:]+):")
  if scheme then
    name = url_schemes[scheme] or name
  end
  -- title may contain transclusion link, this is used for image thumbnails
  local thumbnail = title:match("{{(.-)}}")
  if thumbnail then title = nil end
  return {name = name, value = link, title = title, thumbnail = thumbnail}
end)

add_inline("transclusion", "{{(.-)}}", function(text)
  local link, title, style = text:match("([^|]+)|?([^|]*)|?(.*)")
  return {name = "transclusion", value = link, title = title,style = style}
end)


wikireader.new = function()
  local t = setmetatable({}, wikireader)
  -- wikireader.tree = {}
  -- wikireader.lines = {}
  -- initial state machine state
  -- wikireader.state = "line"
  t.block_patterns =  {}
  t:load_blocks()
  -- t.__index = t
  return t
end

function wikireader:add_block(name, pattern, fn)
  local block_patterns = self.block_patterns
  local t = {name = name, pattern = pattern, fn = fn}
  table.insert(block_patterns, t)
  block_patterns[name] = t
end

function wikireader:load_blocks()
  self:add_block("header","([%s]*)(=+)%s*(.-)=+", wikireader.header)
  self:add_block("enumerated_list", "^(%s*)([0-9a-z]+)[%.%)] (.+)", wikireader.enumerate)
  -- hash list is a special case of an enumerated list
  self:add_block("hash_list", "^(%s*)(%#) (.+)", wikireader.enumerate)
  self:add_block("bullet_list", "^(%s*)([%-%*]) (.+)", wikireader.bulleted)
end


--- Parse string for inline elements
function wikireader:parse_inlines(text)
  local matches = {}
  for _, parser in ipairs(inline_parsers) do
    -- each parser will add matched text to the matches table
    matches = self:match_inline(text, parser, matches)
  end
  -- matches must be sorted by their appearance in the matched text
  table.sort(matches, function(a,b) return a.start < b.start end)
  -- make AST from the matches
  return self:inline_ast(text, matches)
end

function wikireader:inline_ast(text, matches)
  local ast = {}
  local function add_to_ast(what)
    ast[#ast+1] = what
  end
  local function add_text(t)
     add_to_ast(inline_element("text", t))
  end
  local nextmatch = 1
  local last = string.len(text)
  for _,m in ipairs(matches) do
    local start, stop, name = m.start, m.stop, m.name
    -- if there is a text before the matched pattern
    if start - nextmatch > 0 then
      add_text(string.sub(text, nextmatch, start-1))
    end
    -- if two matchers match the same text, use the outer most one
    if start >= nextmatch then
      local substring = string.sub(text, start, stop)
      local matcher = inline_parsers[name] or {}
      local pattern = matcher.pattern or "(.*)"
      local fun = matcher.fn or function(t) return inline_element(name, t) end
      -- clean the matched substring using the matcher pattern, run the matcher
      -- function and add it to the ast
      add_to_ast(fun(string.match(substring, pattern)))
      nextmatch = stop + 1
    end
  end
  -- parse remaining text at the end
  if last - nextmatch > 0 then
    add_text(string.sub(text, nextmatch, last))
  end
  print(text)
  for _,v in ipairs(ast) do
    print("ast", v.name, v.value)
  end
  return ast
end

function wikireader:match_inline(text, parser, matches, pos)
  local pos = pos or 0
  local name = parser.name
  local pattern = parser.pattern
  local start, stop = text:find(pattern, pos)
  if start then
    -- add match t 
    local t = {name = name, start = start, stop=stop}
    table.insert(matches, t)
    -- recursively match the text
    return self:match_inline(text, parser, matches, stop+1)
  end
  return matches
end

-- parse lines from a string
local function parse_lines(str)
  return coroutine.wrap(function()
    for line in str:gmatch("([^\r^\n]*)") do
      coroutine.yield(line)
    end
  end)
end

function wikireader:parse_string(str)
  local iterator = parse_lines(str)
  return self:parse(iterator)
end

-- parse a file or standard input
local function io_lines(file)
  return coroutine.wrap(function()
    for line in io.lines(file) do
      coroutine.yield(line)
    end
  end)
end

function wikireader:parse_file(file)
  local iterator = io_lines(file)
  return self:parse(iterator)
end

-- local reader = wikireader.new()

function wikireader:read_line()
  local iterator = self.iterator
  if iterator then
    return iterator()
  end
end

function wikireader:process_line(line)
  local blocks = self.blocks
  local block_patterns = self.block_patterns
  local matched = false
  if not line:match("{{{") then
    for _, block_pattern in ipairs(block_patterns) do
      local pattern = block_pattern.pattern
      local match = {string.match(line, pattern)}
      -- if string.find(line, pattern)  then
      if #match > 0 then
        matched = true
        blocks[#blocks+1] = block_pattern.fn(self, table.unpack(match))
      end
    end
    if not matched then
      blocks[#blocks+1] = {name = "line", value = line}
    end
  else
    self.verbatim = true
    self.stopverbatim = "}}}"
  end
end

function wikireader:header(space, level, text)
  print("header je tady", space, level, text)
  local centered = string.len(space) > 3 and true or false
  return {name = "header", centered = centered, level = string.len(level), value = text}

end

function wikireader:enumerated(indent, counter, text)
  local indent = string.len(indent)
  return {name = "enumerate", indent = indent, counter = counter, value = text}
end

function wikireader:bulleted(indent, bullet, text)
  local indent = string.len(indent)
  print("bulleted list", indent, bullet, text)
  return {name = "bulleted", indent = indent, bullet = bullet, value = text}
end

function wikireader:process_verbatim(line, verbatim_block)
  local stopverbatim = self.stopverbatim
  local verbatim_block = verbatim_block or {}
  if not line:match(stopverbatim) then
    table.insert(verbatim_block, line)
    line = self:read_line()
    return self:process_verbatim(line, verbatim_block)
  end
  self.verbatim = false
  table.insert(self.blocks, {name = "verbatim", value = table.concat(verbatim_block, "\n")})
end

function wikireader:parse(iterator)
  self.blocks = {}
  self.iterator = iterator
  local line = self:read_line()
  while line do
    if not self.verbatim then
      self:process_line(line)
    else
      self:process_verbatim(line)
    end
    line = self:read_line()
  end
end

local m = {}
m.reader = wikireader

return m




