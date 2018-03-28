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
add_inline("latex_inline", "%$(.-)%$")

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
  t.document = {} -- the document AST will be saved here
  -- list of elements which should be processed for inline text elements 
  t.blocks_with_inlines = {
    enumerate=true,
    bulleted=true,
    definition=true,
    paragraph=true,
    blockquote=true,
    table_cell=true
  }
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
  self:add_block("enumerated_list", "^(%s*)([0-9a-z]+[%.%)]%s+)(.+)", wikireader.enumerated)
  -- hash list is a special case of an enumerated list
  self:add_block("hash_list", "^(%s*)(%#) (.+)", wikireader.enumerated)
  self:add_block("bullet_list", "^(%s*)([%-%*]) (.+)", wikireader.bulleted)
  self:add_block("verbatim", "^%s*{{{(.*)", wikireader.verbatim)
  self:add_block("definition_term", "^%s*(.+)::%s*(.*)", wikireader.definition_term)
  self:add_block("definition", "^%s*::(.+)", wikireader.definition)
  self:add_block("table_row", "^(%s*)|(.+)|%s*$", wikireader.table_row)
  self:add_block("latex", "^%s*{{$(.*)", wikireader.latex_block)
  self:add_block("comment", "^%s*%%%%(.*)", wikireader.comment)
  self:add_block("placeholder", "^%s*%%([^%s]+)%s*(.*)", wikireader.placeholder)
  self:add_block("hline", "^%s*%-%-%-%-", wikireader.hline)
  self:add_block("indented_line", "^(%s+)(.+)", wikireader.indented_line)
  self:add_block("blank_line", "^%s*$", wikireader.blank_line)
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
  for _, block_pattern in ipairs(block_patterns) do
    local pattern = block_pattern.pattern
    local match = {string.match(line, pattern)}
    -- if string.find(line, pattern)  then
    if #match > 0 then
      matched = true
      blocks[#blocks+1] = block_pattern.fn(self, table.unpack(match))
      break
    end
  end
  if not matched then
    blocks[#blocks+1] = {name = "line", value = line}
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

function wikireader:verbatim(style)
  self.stopverbatim = "}}}"
  local next_line = self:read_line()
  local content = self:process_verbatim(next_line)
  self.verbatim = false
  return {name = "verbatim", value = content, style = style}
end

function wikireader:process_verbatim(line, verbatim_block)
  local stopverbatim = self.stopverbatim
  local verbatim_block = verbatim_block or {}
  if not line:match(stopverbatim) then
    table.insert(verbatim_block, line)
    line = self:read_line()
    return self:process_verbatim(line, verbatim_block)
  end
  return table.concat(verbatim_block, "\n")
  -- self.verbatim = false
  -- table.insert(self.blocks, {name = "verbatim", value = table.concat(verbatim_block, "\n")})
end

function wikireader:definition_term(term, definition)
  return {name = "definition_term", term = term, value = definition}
end

function wikireader:definition(definition)
  return {name = "definition", value = definition}
end

function wikireader:table_row(indent,row)
  local cells = {}
  -- detect if the row is horizontal lines
  local letters = false
  for cell in row:gmatch("([^|]+)") do
    cells[#cells+1] = cell
    letters = letters or cell:match("^[%-%s]+$")
  end
  if letters then
    return {name = "table_hline", indent = indent}
  else
    return {name = "table_row", indent = indent, cells = cells}
  end
end

function wikireader:latex_block(environment)
  local environment = environment:match("%%(.+)%%")
  self.stopverbatim = "}}%$"
  local next_line = self:read_line()
  local content = self:process_verbatim(next_line)
  self.verbatim = false
  return {name = "latex_block", environment =environment, value = content}
end

function wikireader:placeholder(tag, text)
  return {name = "placeholder", tag = tag, value = text}
end

function wikireader:comment(text)
  return {name = "comment", value = text}
end

function wikireader:hline(rest)
  return {name = "hline"}
end

function wikireader:indented_line(indent, text)
  local indent = string.len(indent)
  return {name = "indented_line", indent = indent, value = text}
end

function wikireader:blank_line()
  return {name = "blank_line"}
end

function wikireader:parse(iterator)
  self.blocks = {}
  self.iterator = iterator
  local line = self:read_line()
  while line do
    self:process_line(line)
    line = self:read_line()
  end
  -- make ast from block lines
  self:block_ast()
end


function wikireader:block_ast()
  local blocks = self.blocks
  local pos = 0
  local function try_next_line()
    return blocks[pos+1]
  end
  -- return next block type
  local function try_next_type()
    local nextone =  try_next_line() or {}
    return nextone.name
  end
  local function get_line()
    pos = pos + 1
    return blocks[pos]
  end

  local function parse_list(block)
    -- table for list items
    local t = {}
    local current_text = block.value or ""
    local next_item_type ="list_item"
    local function get_indent(current) 
      return string.len(current.bullet or current.counter) + current.indent
    end
    local function add_list_item()
      table.insert(t, {name=next_item_type, children = self:parse_inlines(current_text)})
      current_text = ""
      next_item_type = "list_item"
    end
    local next_type = try_next_type()
    local current_type = block.name
    local current_indent = get_indent(block)
    while next_type == "bulleted" or next_type == "enumerate"  or next_type == "indented_line"  do
      local next_obj = try_next_line()
      if next_type == "indented_line" and (next_obj.indent or 0) >= current_indent then
        if current_text=="" then
          next_item_type= "list_item_continued"
        end
        current_text = current_text .. " " .. next_obj.value
      elseif next_type == current_type and block.indent == next_obj.indent then
        add_list_item()
        current_text = next_obj.value or ""
      elseif (next_type == "bulleted" or next_type == "enumerate" ) and next_obj.indent > block.indent then
        local next_obj = get_line()
        add_list_item()
        next_obj.children = parse_list(next_obj)
        table.insert(t, next_obj)
        pos = pos - 1
      else
        break
      end
      pos = pos + 1
      next_type = try_next_type()
    end
    if current_text and  current_text ~= "" then
      add_list_item()
    end
    return t
  end
  local function parse_blockquote(block)
    local t = {}
    local function add_line(s)
      local line = s:match("^%s*(.+)")
      table.insert(t, {name="line", children=self:parse_inlines(s)})
    end
    add_line(block.value)
    local next_type = try_next_type()
    local next_obj = try_next_line()
    while next_type == "indented_line" and next_obj.indent==4 do
      add_line(next_obj.value)
      pos = pos+1
      next_obj, next_type =try_next_line(), try_next_type()
    end
    return t
  end

  local function parse_table(block)
    block.name = "table"
    local t = {}
    local function add_row(x,typ)
      local typ = typ or "table_row"
      local new = {}
      local cells = {}
      -- copy all fields of the current object first, update necessary fields later
      for k,v in pairs(x) do new[k] = v end

      for k,v in ipairs(x.cells or {}) do cells[k] =  {name = "cell", children = self:parse_inlines(v)} end
      new.name = typ
      new.children = cells
      table.insert(t, new)
    end
    local next_type = try_next_type()

    if next_type == "table_hline" then
      add_row(block, "table_header")
    end
    while next_type == "table_row" or next_type == "table_hline" do
      local next_obj = get_line()
      add_row(next_obj, next_type)
      next_type = try_next_type()
    end
    return t
  end

  local function parse_blocks()
    local line = get_line()
    if not line then return nil, "end of document" end
    -- default block type
    local block = line--copy_table(line)
    block.children = {}
    local line_type = line.name
    if line_type == "bulleted"  or line_type == "enumerate" then
      block.children = parse_list(block)
    elseif line_type == "indented_line" and line.indent == 4 then
      block.name = "blockquote"
      block.children = parse_blockquote(block)
    elseif line_type == "blank_line" then
      -- skip blank lines
      return parse_blocks()
    elseif line_type == "table_row" then
      block.children = parse_table(block)
    elseif self.blocks_with_inlines[line_type] then
      block.children = self:parse_inlines(line.value)
    else
      block.children = {name="text", value = block.value}
      -- block.value = nil
    end
    return block
  end
  local document = {name="root", children = {}}
  local  block = parse_blocks()
  while block do
    table.insert(document.children, block)
    block = parse_blocks()
  end
  self.document = document
end

local m = {}
m.reader = wikireader

return m




