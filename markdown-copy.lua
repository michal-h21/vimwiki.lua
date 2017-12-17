-- 
-- Copyright (C) 2009-2017 John MacFarlane, Hans Hagen
-- 
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- 
-- Copyright (C) 2017 Vít Novotný
-- 
-- This work may be distributed and/or modified under the
-- conditions of the LaTeX Project Public License, either version 1.3
-- of this license or (at your option) any later version.
-- The latest version of this license is in
-- 
--     http://www.latex-project.org/lppl.txt
-- 
-- and version 1.3 or later is part of all distributions of LaTeX
-- version 2005/12/01 or later.
-- 
-- This work has the LPPL maintenance status `maintained'.
-- The Current Maintainer of this work is Vít Novotný.
-- 
-- Send bug reports, requests for additions and questions
-- either to the GitHub issue tracker at
-- 
--     https://github.com/witiko/markdown/issues
-- 
-- or to the e-mail address <witiko@mail.muni.cz>.
-- 
-- MODIFICATION ADVICE:
-- 
-- If you want to customize this file, it is best to make a copy of
-- the source file(s) from which it was produced. Use a different
-- name for your copy(ies) and modify the copy(ies); this will ensure
-- that your modifications do not get overwritten when you install a
-- new release of the standard system. You should also ensure that
-- your modified source file does not generate any modified file with
-- the same name as a standard file.
-- 
-- You will also need to produce your own, suitably named, .ins file to
-- control the generation of files from your source file; this file
-- should contain your own preambles for the files it generates, not
-- those in the standard .ins files.
-- 
local metadata = {
    version   = "2.5.4",
    comment   = "A module for the conversion from markdown to plain TeX",
    author    = "John MacFarlane, Hans Hagen, Vít Novotný",
    copyright = "2009-2017 John MacFarlane, Hans Hagen; " ..
                "2016-2017 Vít Novotný",
    license   = "LPPL 1.3"
}
if not modules then modules = { } end
modules['markdown'] = metadata
local lpeg = require("lpeg")
local unicode = require("unicode")
local md5 = require("md5")
local M = {}
local defaultOptions = {}
defaultOptions.cacheDir = "."
defaultOptions.outputDir = "."
defaultOptions.blankBeforeBlockquote = false
defaultOptions.blankBeforeCodeFence = false
defaultOptions.blankBeforeHeading = false
defaultOptions.breakableBlockquotes = false
defaultOptions.citationNbsps = true
defaultOptions.citations = false
defaultOptions.codeSpans = true
defaultOptions.contentBlocks = false
defaultOptions.contentBlocksLanguageMap = "markdown-languages.json"
defaultOptions.definitionLists = false
defaultOptions.fencedCode = false
defaultOptions.footnotes = false
defaultOptions.hashEnumerators = false
defaultOptions.html = false
defaultOptions.hybrid = false
defaultOptions.inlineFootnotes = false
defaultOptions.preserveTabs = false
defaultOptions.smartEllipses = false
defaultOptions.startNumber = true
defaultOptions.tightLists = true
defaultOptions.underscores = true
local upper, gsub, format, length =
  string.upper, string.gsub, string.format, string.len
local concat = table.concat
local P, R, S, V, C, Cg, Cb, Cmt, Cc, Ct, B, Cs, any =
  lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Cg, lpeg.Cb,
  lpeg.Cmt, lpeg.Cc, lpeg.Ct, lpeg.B, lpeg.Cs, lpeg.P(1)
local util = {}
function util.err(msg, exit_code)
  io.stderr:write("markdown.lua: " .. msg .. "\n")
  os.exit(exit_code or 1)
end
function util.cache(dir, string, salt, transform, suffix)
  local digest = md5.sumhexa(string .. (salt or ""))
  local name = util.pathname(dir, digest .. suffix)
  local file = io.open(name, "r")
  if file == nil then -- If no cache entry exists, then create a new one.
    local file = assert(io.open(name, "w"))
    local result = string
    if transform ~= nil then
      result = transform(result)
    end
    assert(file:write(result))
    assert(file:close())
  end
  return name
end
function util.table_copy(t)
  local u = { }
  for k, v in pairs(t) do u[k] = v end
  return setmetatable(u, getmetatable(t))
end
function util.expand_tabs_in_line(s, tabstop)
  local tab = tabstop or 4
  local corr = 0
  return (s:gsub("()\t", function(p)
            local sp = tab - (p - 1 + corr) % tab
            corr = corr - 1 + sp
            return string.rep(" ", sp)
          end))
end
function util.walk(t, f)
  local typ = type(t)
  if typ == "string" then
    f(t)
  elseif typ == "table" then
    local i = 1
    local n
    n = t[i]
    while n do
      util.walk(n, f)
      i = i + 1
      n = t[i]
    end
  elseif typ == "function" then
    local ok, val = pcall(t)
    if ok then
      util.walk(val,f)
    end
  else
    f(tostring(t))
  end
end
function util.flatten(ary)
  local new = {}
  for _,v in ipairs(ary) do
    if type(v) == "table" then
      for _,w in ipairs(util.flatten(v)) do
        new[#new + 1] = w
      end
    else
      new[#new + 1] = v
    end
  end
  return new
end
function util.rope_to_string(rope)
  local buffer = {}
  util.walk(rope, function(x) buffer[#buffer + 1] = x end)
  return table.concat(buffer)
end
function util.rope_last(rope)
  if #rope == 0 then
    return nil
  else
    local l = rope[#rope]
    if type(l) == "table" then
      return util.rope_last(l)
    else
      return l
    end
  end
end
function util.intersperse(ary, x)
  local new = {}
  local l = #ary
  for i,v in ipairs(ary) do
    local n = #new
    new[n + 1] = v
    if i ~= l then
      new[n + 2] = x
    end
  end
  return new
end
function util.map(ary, f)
  local new = {}
  for i,v in ipairs(ary) do
    new[i] = f(v)
  end
  return new
end
function util.escaper(char_escapes, string_escapes)
  local char_escapes_list = ""
  for i,_ in pairs(char_escapes) do
    char_escapes_list = char_escapes_list .. i
  end
  local escapable = S(char_escapes_list) / char_escapes
  if string_escapes then
    for k,v in pairs(string_escapes) do
      escapable = P(k) / v + escapable
    end
  end
  local escape_string = Cs((escapable + any)^0)
  return function(s)
    return lpeg.match(escape_string, s)
  end
end
function util.pathname(dir, file)
  if #dir == 0 then
    return file
  else
    return dir .. "/" .. file
  end
end
local entities = {}

local character_entities = {
  ["quot"] = 0x0022,
  ["amp"] = 0x0026,
  ["apos"] = 0x0027,
  ["lt"] = 0x003C,
  ["gt"] = 0x003E,
  ["nbsp"] = 160,
  ["iexcl"] = 0x00A1,
  ["cent"] = 0x00A2,
  ["pound"] = 0x00A3,
  ["curren"] = 0x00A4,
  ["yen"] = 0x00A5,
  ["brvbar"] = 0x00A6,
  ["sect"] = 0x00A7,
  ["uml"] = 0x00A8,
  ["copy"] = 0x00A9,
  ["ordf"] = 0x00AA,
  ["laquo"] = 0x00AB,
  ["not"] = 0x00AC,
  ["shy"] = 173,
  ["reg"] = 0x00AE,
  ["macr"] = 0x00AF,
  ["deg"] = 0x00B0,
  ["plusmn"] = 0x00B1,
  ["sup2"] = 0x00B2,
  ["sup3"] = 0x00B3,
  ["acute"] = 0x00B4,
  ["micro"] = 0x00B5,
  ["para"] = 0x00B6,
  ["middot"] = 0x00B7,
  ["cedil"] = 0x00B8,
  ["sup1"] = 0x00B9,
  ["ordm"] = 0x00BA,
  ["raquo"] = 0x00BB,
  ["frac14"] = 0x00BC,
  ["frac12"] = 0x00BD,
  ["frac34"] = 0x00BE,
  ["iquest"] = 0x00BF,
  ["Agrave"] = 0x00C0,
  ["Aacute"] = 0x00C1,
  ["Acirc"] = 0x00C2,
  ["Atilde"] = 0x00C3,
  ["Auml"] = 0x00C4,
  ["Aring"] = 0x00C5,
  ["AElig"] = 0x00C6,
  ["Ccedil"] = 0x00C7,
  ["Egrave"] = 0x00C8,
  ["Eacute"] = 0x00C9,
  ["Ecirc"] = 0x00CA,
  ["Euml"] = 0x00CB,
  ["Igrave"] = 0x00CC,
  ["Iacute"] = 0x00CD,
  ["Icirc"] = 0x00CE,
  ["Iuml"] = 0x00CF,
  ["ETH"] = 0x00D0,
  ["Ntilde"] = 0x00D1,
  ["Ograve"] = 0x00D2,
  ["Oacute"] = 0x00D3,
  ["Ocirc"] = 0x00D4,
  ["Otilde"] = 0x00D5,
  ["Ouml"] = 0x00D6,
  ["times"] = 0x00D7,
  ["Oslash"] = 0x00D8,
  ["Ugrave"] = 0x00D9,
  ["Uacute"] = 0x00DA,
  ["Ucirc"] = 0x00DB,
  ["Uuml"] = 0x00DC,
  ["Yacute"] = 0x00DD,
  ["THORN"] = 0x00DE,
  ["szlig"] = 0x00DF,
  ["agrave"] = 0x00E0,
  ["aacute"] = 0x00E1,
  ["acirc"] = 0x00E2,
  ["atilde"] = 0x00E3,
  ["auml"] = 0x00E4,
  ["aring"] = 0x00E5,
  ["aelig"] = 0x00E6,
  ["ccedil"] = 0x00E7,
  ["egrave"] = 0x00E8,
  ["eacute"] = 0x00E9,
  ["ecirc"] = 0x00EA,
  ["euml"] = 0x00EB,
  ["igrave"] = 0x00EC,
  ["iacute"] = 0x00ED,
  ["icirc"] = 0x00EE,
  ["iuml"] = 0x00EF,
  ["eth"] = 0x00F0,
  ["ntilde"] = 0x00F1,
  ["ograve"] = 0x00F2,
  ["oacute"] = 0x00F3,
  ["ocirc"] = 0x00F4,
  ["otilde"] = 0x00F5,
  ["ouml"] = 0x00F6,
  ["divide"] = 0x00F7,
  ["oslash"] = 0x00F8,
  ["ugrave"] = 0x00F9,
  ["uacute"] = 0x00FA,
  ["ucirc"] = 0x00FB,
  ["uuml"] = 0x00FC,
  ["yacute"] = 0x00FD,
  ["thorn"] = 0x00FE,
  ["yuml"] = 0x00FF,
  ["OElig"] = 0x0152,
  ["oelig"] = 0x0153,
  ["Scaron"] = 0x0160,
  ["scaron"] = 0x0161,
  ["Yuml"] = 0x0178,
  ["fnof"] = 0x0192,
  ["circ"] = 0x02C6,
  ["tilde"] = 0x02DC,
  ["Alpha"] = 0x0391,
  ["Beta"] = 0x0392,
  ["Gamma"] = 0x0393,
  ["Delta"] = 0x0394,
  ["Epsilon"] = 0x0395,
  ["Zeta"] = 0x0396,
  ["Eta"] = 0x0397,
  ["Theta"] = 0x0398,
  ["Iota"] = 0x0399,
  ["Kappa"] = 0x039A,
  ["Lambda"] = 0x039B,
  ["Mu"] = 0x039C,
  ["Nu"] = 0x039D,
  ["Xi"] = 0x039E,
  ["Omicron"] = 0x039F,
  ["Pi"] = 0x03A0,
  ["Rho"] = 0x03A1,
  ["Sigma"] = 0x03A3,
  ["Tau"] = 0x03A4,
  ["Upsilon"] = 0x03A5,
  ["Phi"] = 0x03A6,
  ["Chi"] = 0x03A7,
  ["Psi"] = 0x03A8,
  ["Omega"] = 0x03A9,
  ["alpha"] = 0x03B1,
  ["beta"] = 0x03B2,
  ["gamma"] = 0x03B3,
  ["delta"] = 0x03B4,
  ["epsilon"] = 0x03B5,
  ["zeta"] = 0x03B6,
  ["eta"] = 0x03B7,
  ["theta"] = 0x03B8,
  ["iota"] = 0x03B9,
  ["kappa"] = 0x03BA,
  ["lambda"] = 0x03BB,
  ["mu"] = 0x03BC,
  ["nu"] = 0x03BD,
  ["xi"] = 0x03BE,
  ["omicron"] = 0x03BF,
  ["pi"] = 0x03C0,
  ["rho"] = 0x03C1,
  ["sigmaf"] = 0x03C2,
  ["sigma"] = 0x03C3,
  ["tau"] = 0x03C4,
  ["upsilon"] = 0x03C5,
  ["phi"] = 0x03C6,
  ["chi"] = 0x03C7,
  ["psi"] = 0x03C8,
  ["omega"] = 0x03C9,
  ["thetasym"] = 0x03D1,
  ["upsih"] = 0x03D2,
  ["piv"] = 0x03D6,
  ["ensp"] = 0x2002,
  ["emsp"] = 0x2003,
  ["thinsp"] = 0x2009,
  ["ndash"] = 0x2013,
  ["mdash"] = 0x2014,
  ["lsquo"] = 0x2018,
  ["rsquo"] = 0x2019,
  ["sbquo"] = 0x201A,
  ["ldquo"] = 0x201C,
  ["rdquo"] = 0x201D,
  ["bdquo"] = 0x201E,
  ["dagger"] = 0x2020,
  ["Dagger"] = 0x2021,
  ["bull"] = 0x2022,
  ["hellip"] = 0x2026,
  ["permil"] = 0x2030,
  ["prime"] = 0x2032,
  ["Prime"] = 0x2033,
  ["lsaquo"] = 0x2039,
  ["rsaquo"] = 0x203A,
  ["oline"] = 0x203E,
  ["frasl"] = 0x2044,
  ["euro"] = 0x20AC,
  ["image"] = 0x2111,
  ["weierp"] = 0x2118,
  ["real"] = 0x211C,
  ["trade"] = 0x2122,
  ["alefsym"] = 0x2135,
  ["larr"] = 0x2190,
  ["uarr"] = 0x2191,
  ["rarr"] = 0x2192,
  ["darr"] = 0x2193,
  ["harr"] = 0x2194,
  ["crarr"] = 0x21B5,
  ["lArr"] = 0x21D0,
  ["uArr"] = 0x21D1,
  ["rArr"] = 0x21D2,
  ["dArr"] = 0x21D3,
  ["hArr"] = 0x21D4,
  ["forall"] = 0x2200,
  ["part"] = 0x2202,
  ["exist"] = 0x2203,
  ["empty"] = 0x2205,
  ["nabla"] = 0x2207,
  ["isin"] = 0x2208,
  ["notin"] = 0x2209,
  ["ni"] = 0x220B,
  ["prod"] = 0x220F,
  ["sum"] = 0x2211,
  ["minus"] = 0x2212,
  ["lowast"] = 0x2217,
  ["radic"] = 0x221A,
  ["prop"] = 0x221D,
  ["infin"] = 0x221E,
  ["ang"] = 0x2220,
  ["and"] = 0x2227,
  ["or"] = 0x2228,
  ["cap"] = 0x2229,
  ["cup"] = 0x222A,
  ["int"] = 0x222B,
  ["there4"] = 0x2234,
  ["sim"] = 0x223C,
  ["cong"] = 0x2245,
  ["asymp"] = 0x2248,
  ["ne"] = 0x2260,
  ["equiv"] = 0x2261,
  ["le"] = 0x2264,
  ["ge"] = 0x2265,
  ["sub"] = 0x2282,
  ["sup"] = 0x2283,
  ["nsub"] = 0x2284,
  ["sube"] = 0x2286,
  ["supe"] = 0x2287,
  ["oplus"] = 0x2295,
  ["otimes"] = 0x2297,
  ["perp"] = 0x22A5,
  ["sdot"] = 0x22C5,
  ["lceil"] = 0x2308,
  ["rceil"] = 0x2309,
  ["lfloor"] = 0x230A,
  ["rfloor"] = 0x230B,
  ["lang"] = 0x27E8,
  ["rang"] = 0x27E9,
  ["loz"] = 0x25CA,
  ["spades"] = 0x2660,
  ["clubs"] = 0x2663,
  ["hearts"] = 0x2665,
  ["diams"] = 0x2666,
}
function entities.dec_entity(s)
  return unicode.utf8.char(tonumber(s))
end
function entities.hex_entity(s)
  return unicode.utf8.char(tonumber("0x"..s))
end
function entities.char_entity(s)
  local n = character_entities[s]
  return unicode.utf8.char(n)
end
M.writer = {}
function M.writer.new(options)
  local self = {}
  options = options or {}
  setmetatable(options, { __index = function (_, key)
    return defaultOptions[key] end })
  self.suffix = ".tex"
  self.space = " "
  self.nbsp = "\\markdownRendererNbsp{}"
  function self.plain(s)
    return s
  end
  function self.paragraph(s)
    return s
  end
  function self.pack(name)
    return [[\input"]] .. name .. [["\relax]]
  end
  self.interblocksep = "\\markdownRendererInterblockSeparator\n{}"
  self.eof = [[\relax]]
  self.linebreak = "\\markdownRendererLineBreak\n{}"
  self.ellipsis = "\\markdownRendererEllipsis{}"
  self.hrule = "\\markdownRendererHorizontalRule{}"
  local escaped_chars = {
     ["{"] = "\\markdownRendererLeftBrace{}",
     ["}"] = "\\markdownRendererRightBrace{}",
     ["$"] = "\\markdownRendererDollarSign{}",
     ["%"] = "\\markdownRendererPercentSign{}",
     ["&"] = "\\markdownRendererAmpersand{}",
     ["_"] = "\\markdownRendererUnderscore{}",
     ["#"] = "\\markdownRendererHash{}",
     ["^"] = "\\markdownRendererCircumflex{}",
     ["\\"] = "\\markdownRendererBackslash{}",
     ["~"] = "\\markdownRendererTilde{}",
     ["|"] = "\\markdownRendererPipe{}",
   }
   local escaped_uri_chars = {
     ["{"] = "\\markdownRendererLeftBrace{}",
     ["}"] = "\\markdownRendererRightBrace{}",
     ["%"] = "\\markdownRendererPercentSign{}",
     ["\\"] = "\\markdownRendererBackslash{}",
   }
   local escaped_citation_chars = {
     ["{"] = "\\markdownRendererLeftBrace{}",
     ["}"] = "\\markdownRendererRightBrace{}",
     ["%"] = "\\markdownRendererPercentSign{}",
     ["#"] = "\\markdownRendererHash{}",
     ["\\"] = "\\markdownRendererBackslash{}",
   }
   local escaped_minimal_strings = {
     ["^^"] = "\\markdownRendererCircumflex\\markdownRendererCircumflex ",
   }
  local escape = util.escaper(escaped_chars)
  local escape_citation = util.escaper(escaped_citation_chars,
    escaped_minimal_strings)
  local escape_uri = util.escaper(escaped_uri_chars, escaped_minimal_strings)
  if options.hybrid then
    self.string = function(s) return s end
    self.citation = function(c) return c end
    self.uri = function(u) return u end
  else
    self.string = escape
    self.citation = escape_citation
    self.uri = escape_uri
  end
  function self.code(s)
    return {"\\markdownRendererCodeSpan{",escape(s),"}"}
  end
  function self.link(lab,src,tit)
    return {"\\markdownRendererLink{",lab,"}",
                          "{",self.string(src),"}",
                          "{",self.uri(src),"}",
                          "{",self.string(tit or ""),"}"}
  end
  function self.image(lab,src,tit)
    return {"\\markdownRendererImage{",lab,"}",
                           "{",self.string(src),"}",
                           "{",self.uri(src),"}",
                           "{",self.string(tit or ""),"}"}
  end
local languages_json = (function()
  local kpse = require('kpse')
  kpse.set_program_name('luatex')
  local base, prev, curr
  for _, file in ipairs{kpse.lookup(options.contentBlocksLanguageMap,
                                    { all=true })} do
    json = assert(io.open(file, "r")):read("*all")
                                     :gsub('("[^\n]-"):','[%1]=')
    curr = (function()
      local _ENV={ json=json, load=load } -- run in sandbox
      return load("return "..json)()
    end)()
    if type(curr) == "table" then
      if base == nil then
        base = curr
      else
        setmetatable(prev, { __index = curr })
      end
      prev = curr
    end
  end
  return base or {}
end)()
  function self.contentblock(src,suf,type,tit)
    src = src.."."..suf
    suf = suf:lower()
    if type == "onlineimage" then
      return {"\\markdownRendererContentBlockOnlineImage{",suf,"}",
                             "{",self.string(src),"}",
                             "{",self.uri(src),"}",
                             "{",self.string(tit or ""),"}"}
    elseif languages_json[suf] then
      return {"\\markdownRendererContentBlockCode{",suf,"}",
                             "{",self.string(languages_json[suf]),"}",
                             "{",self.string(src),"}",
                             "{",self.uri(src),"}",
                             "{",self.string(tit or ""),"}"}
    else
      return {"\\markdownRendererContentBlock{",suf,"}",
                             "{",self.string(src),"}",
                             "{",self.uri(src),"}",
                             "{",self.string(tit or ""),"}"}
    end
  end
  local function ulitem(s)
    return {"\\markdownRendererUlItem ",s,
            "\\markdownRendererUlItemEnd "}
  end

  function self.bulletlist(items,tight)
    local buffer = {}
    for _,item in ipairs(items) do
      buffer[#buffer + 1] = ulitem(item)
    end
    local contents = util.intersperse(buffer,"\n")
    if tight and options.tightLists then
      return {"\\markdownRendererUlBeginTight\n",contents,
        "\n\\markdownRendererUlEndTight "}
    else
      return {"\\markdownRendererUlBegin\n",contents,
        "\n\\markdownRendererUlEnd "}
    end
  end
  local function olitem(s,num)
    if num ~= nil then
      return {"\\markdownRendererOlItemWithNumber{",num,"}",s,
              "\\markdownRendererOlItemEnd "}
    else
      return {"\\markdownRendererOlItem ",s,
              "\\markdownRendererOlItemEnd "}
    end
  end

  function self.orderedlist(items,tight,startnum)
    local buffer = {}
    local num = startnum
    for _,item in ipairs(items) do
      buffer[#buffer + 1] = olitem(item,num)
      if num ~= nil then
        num = num + 1
      end
    end
    local contents = util.intersperse(buffer,"\n")
    if tight and options.tightLists then
      return {"\\markdownRendererOlBeginTight\n",contents,
        "\n\\markdownRendererOlEndTight "}
    else
      return {"\\markdownRendererOlBegin\n",contents,
        "\n\\markdownRendererOlEnd "}
    end
  end
  function self.inline_html(html)  return "" end
  function self.display_html(html) return "" end
  local function dlitem(term, defs)
    local retVal = {"\\markdownRendererDlItem{",term,"}"}
    for _, def in ipairs(defs) do
      retVal[#retVal+1] = {"\\markdownRendererDlDefinitionBegin ",def,
                           "\\markdownRendererDlDefinitionEnd "}
    end
    retVal[#retVal+1] = "\\markdownRendererDlItemEnd "
    return retVal
  end

  function self.definitionlist(items,tight)
    local buffer = {}
    for _,item in ipairs(items) do
      buffer[#buffer + 1] = dlitem(item.term, item.definitions)
    end
    if tight and options.tightLists then
      return {"\\markdownRendererDlBeginTight\n", buffer,
        "\n\\markdownRendererDlEndTight"}
    else
      return {"\\markdownRendererDlBegin\n", buffer,
        "\n\\markdownRendererDlEnd"}
    end
  end
  function self.emphasis(s)
    return {"\\markdownRendererEmphasis{",s,"}"}
  end
  function self.strong(s)
    return {"\\markdownRendererStrongEmphasis{",s,"}"}
  end
  function self.blockquote(s)
    return {"\\markdownRendererBlockQuoteBegin\n",s,
      "\n\\markdownRendererBlockQuoteEnd "}
  end
  function self.verbatim(s)
    local name = util.cache(options.cacheDir, s, nil, nil, ".verbatim")
    return {"\\markdownRendererInputVerbatim{",name,"}"}
  end
  function self.fencedCode(i, s)
    local name = util.cache(options.cacheDir, s, nil, nil, ".verbatim")
    return {"\\markdownRendererInputFencedCode{",name,"}{",i,"}"}
  end
  function self.heading(s,level)
    local cmd
    if level == 1 then
      cmd = "\\markdownRendererHeadingOne"
    elseif level == 2 then
      cmd = "\\markdownRendererHeadingTwo"
    elseif level == 3 then
      cmd = "\\markdownRendererHeadingThree"
    elseif level == 4 then
      cmd = "\\markdownRendererHeadingFour"
    elseif level == 5 then
      cmd = "\\markdownRendererHeadingFive"
    elseif level == 6 then
      cmd = "\\markdownRendererHeadingSix"
    else
      cmd = ""
    end
    return {cmd,"{",s,"}"}
  end
  function self.note(s)
    return {"\\markdownRendererFootnote{",s,"}"}
  end
  function self.citations(text_cites, cites)
    local buffer = {"\\markdownRenderer", text_cites and "TextCite" or "Cite",
      "{", #cites, "}"}
    for _,cite in ipairs(cites) do
      buffer[#buffer+1] = {cite.suppress_author and "-" or "+", "{",
        cite.prenote or "", "}{", cite.postnote or "", "}{", cite.name, "}"}
    end
    return buffer
  end

  return self
end
local parsers                  = {}
parsers.percent                = P("%")
parsers.at                     = P("@")
parsers.comma                  = P(",")
parsers.asterisk               = P("*")
parsers.dash                   = P("-")
parsers.plus                   = P("+")
parsers.underscore             = P("_")
parsers.period                 = P(".")
parsers.hash                   = P("#")
parsers.ampersand              = P("&")
parsers.backtick               = P("`")
parsers.less                   = P("<")
parsers.more                   = P(">")
parsers.space                  = P(" ")
parsers.squote                 = P("'")
parsers.dquote                 = P('"')
parsers.lparent                = P("(")
parsers.rparent                = P(")")
parsers.lbracket               = P("[")
parsers.rbracket               = P("]")
parsers.circumflex             = P("^")
parsers.slash                  = P("/")
parsers.equal                  = P("=")
parsers.colon                  = P(":")
parsers.semicolon              = P(";")
parsers.exclamation            = P("!")
parsers.tilde                  = P("~")
parsers.tab                    = P("\t")
parsers.newline                = P("\n")
parsers.tightblocksep          = P("\001")

parsers.digit                  = R("09")
parsers.hexdigit               = R("09","af","AF")
parsers.letter                 = R("AZ","az")
parsers.alphanumeric           = R("AZ","az","09")
parsers.keyword                = parsers.letter
                               * parsers.alphanumeric^0
parsers.citation_chars         = parsers.alphanumeric
                               + S("#$%&-+<>~/_")
parsers.internal_punctuation   = S(":;,.?")

parsers.doubleasterisks        = P("**")
parsers.doubleunderscores      = P("__")
parsers.fourspaces             = P("    ")

parsers.any                    = P(1)
parsers.fail                   = parsers.any - 1

parsers.escapable              = S("\\`*_{}[]()+_.!<>#-~:^@;")
parsers.anyescaped             = P("\\") / "" * parsers.escapable
                               + parsers.any

parsers.spacechar              = S("\t ")
parsers.spacing                = S(" \n\r\t")
parsers.nonspacechar           = parsers.any - parsers.spacing
parsers.optionalspace          = parsers.spacechar^0

parsers.specialchar            = S("*_`&[]<!\\.@-^")

parsers.normalchar             = parsers.any - (parsers.specialchar
                                                + parsers.spacing
                                                + parsers.tightblocksep)
parsers.eof                    = -parsers.any
parsers.nonindentspace         = parsers.space^-3 * - parsers.spacechar
parsers.indent                 = parsers.space^-3 * parsers.tab
                               + parsers.fourspaces / ""
parsers.linechar               = P(1 - parsers.newline)

parsers.blankline              = parsers.optionalspace
                               * parsers.newline / "\n"
parsers.blanklines             = parsers.blankline^0
parsers.skipblanklines         = (parsers.optionalspace * parsers.newline)^0
parsers.indentedline           = parsers.indent    /""
                               * C(parsers.linechar^1 * parsers.newline^-1)
parsers.optionallyindentedline = parsers.indent^-1 /""
                               * C(parsers.linechar^1 * parsers.newline^-1)
parsers.sp                     = parsers.spacing^0
parsers.spnl                   = parsers.optionalspace
                               * (parsers.newline * parsers.optionalspace)^-1
parsers.line                   = parsers.linechar^0 * parsers.newline
                               + parsers.linechar^1 * parsers.eof
parsers.nonemptyline           = parsers.line - parsers.blankline

parsers.chunk                  = parsers.line * (parsers.optionallyindentedline
                                                - parsers.blankline)^0

-- block followed by 0 or more optionally
-- indented blocks with first line indented.
parsers.indented_blocks = function(bl)
  return Cs( bl
         * (parsers.blankline^1 * parsers.indent * -parsers.blankline * bl)^0
         * (parsers.blankline^1 + parsers.eof) )
end
parsers.bulletchar = C(parsers.plus + parsers.asterisk + parsers.dash)

parsers.bullet = ( parsers.bulletchar * #parsers.spacing
                                      * (parsers.tab + parsers.space^-3)
                 + parsers.space * parsers.bulletchar * #parsers.spacing
                                 * (parsers.tab + parsers.space^-2)
                 + parsers.space * parsers.space * parsers.bulletchar
                                 * #parsers.spacing
                                 * (parsers.tab + parsers.space^-1)
                 + parsers.space * parsers.space * parsers.space
                                 * parsers.bulletchar * #parsers.spacing
                 )
parsers.openticks   = Cg(parsers.backtick^1, "ticks")

local function captures_equal_length(s,i,a,b)
  return #a == #b and i
end

parsers.closeticks  = parsers.space^-1
                    * Cmt(C(parsers.backtick^1)
                         * Cb("ticks"), captures_equal_length)

parsers.intickschar = (parsers.any - S(" \n\r`"))
                    + (parsers.newline * -parsers.blankline)
                    + (parsers.space - parsers.closeticks)
                    + (parsers.backtick^1 - parsers.closeticks)

parsers.inticks     = parsers.openticks * parsers.space^-1
                    * C(parsers.intickschar^0) * parsers.closeticks
local function captures_geq_length(s,i,a,b)
  return #a >= #b and i
end

parsers.infostring     = (parsers.linechar - (parsers.backtick
                       + parsers.space^1 * (parsers.newline + parsers.eof)))^0

local fenceindent
parsers.fencehead    = function(char)
  return               C(parsers.nonindentspace) / function(s) fenceindent = #s end
                     * Cg(char^3, "fencelength")
                     * parsers.optionalspace * C(parsers.infostring)
                     * parsers.optionalspace * (parsers.newline + parsers.eof)
end

parsers.fencetail    = function(char)
  return               parsers.nonindentspace
                     * Cmt(C(char^3) * Cb("fencelength"), captures_geq_length)
                     * parsers.optionalspace * (parsers.newline + parsers.eof)
                     + parsers.eof
end

parsers.fencedline   = function(char)
  return               C(parsers.line - parsers.fencetail(char))
                     / function(s)
                         i = 1
                         remaining = fenceindent
                         while true do
                           c = s:sub(i, i)
                           if c == " " and remaining > 0 then
                             remaining = remaining - 1
                             i = i + 1
                           elseif c == "\t" and remaining > 3 then
                             remaining = remaining - 4
                             i = i + 1
                           else
                             break
                           end
                         end
                         return s:sub(i)
                       end
end
parsers.leader      = parsers.space^-3

-- content in balanced brackets, parentheses, or quotes:
parsers.bracketed   = P{ parsers.lbracket
                       * ((parsers.anyescaped - (parsers.lbracket
                                                + parsers.rbracket
                                                + parsers.blankline^2)
                          ) + V(1))^0
                       * parsers.rbracket }

parsers.inparens    = P{ parsers.lparent
                       * ((parsers.anyescaped - (parsers.lparent
                                                + parsers.rparent
                                                + parsers.blankline^2)
                          ) + V(1))^0
                       * parsers.rparent }

parsers.squoted     = P{ parsers.squote * parsers.alphanumeric
                       * ((parsers.anyescaped - (parsers.squote
                                                + parsers.blankline^2)
                          ) + V(1))^0
                       * parsers.squote }

parsers.dquoted     = P{ parsers.dquote * parsers.alphanumeric
                       * ((parsers.anyescaped - (parsers.dquote
                                                + parsers.blankline^2)
                          ) + V(1))^0
                       * parsers.dquote }

-- bracketed tag for markdown links, allowing nested brackets:
parsers.tag         = parsers.lbracket
                    * Cs((parsers.alphanumeric^1
                         + parsers.bracketed
                         + parsers.inticks
                         + (parsers.anyescaped
                           - (parsers.rbracket + parsers.blankline^2)))^0)
                    * parsers.rbracket

-- url for markdown links, allowing nested brackets:
parsers.url         = parsers.less * Cs((parsers.anyescaped
                                        - parsers.more)^0)
                                   * parsers.more
                    + Cs((parsers.inparens + (parsers.anyescaped
                                             - parsers.spacing
                                             - parsers.rparent))^1)

-- quoted text, possibly with nested quotes:
parsers.title_s     = parsers.squote * Cs(((parsers.anyescaped-parsers.squote)
                                           + parsers.squoted)^0)
                                     * parsers.squote

parsers.title_d     = parsers.dquote * Cs(((parsers.anyescaped-parsers.dquote)
                                           + parsers.dquoted)^0)
                                     * parsers.dquote

parsers.title_p     = parsers.lparent
                    * Cs((parsers.inparens + (parsers.anyescaped-parsers.rparent))^0)
                    * parsers.rparent

parsers.title       = parsers.title_d + parsers.title_s + parsers.title_p

parsers.optionaltitle
                    = parsers.spnl * parsers.title * parsers.spacechar^0
                    + Cc("")
parsers.contentblock_tail
                    = parsers.optionaltitle
                    * (parsers.newline + parsers.eof)

-- case insensitive online image suffix:
parsers.onlineimagesuffix
                    = (function(...)
                        local parser = nil
                        for _,suffix in ipairs({...}) do
                          local pattern=nil
                          for i=1,#suffix do
                            local char=suffix:sub(i,i)
                            char = S(char:lower()..char:upper())
                            if pattern == nil then
                              pattern = char
                            else
                              pattern = pattern * char
                            end
                          end
                          if parser == nil then
                            parser = pattern
                          else
                            parser = parser + pattern
                          end
                        end
                        return parser
                      end)("png", "jpg", "jpeg", "gif", "tif", "tiff")

-- online image url for iA Writer content blocks with mandatory suffix,
-- allowing nested brackets:
parsers.onlineimageurl
                    = (parsers.less
                      * Cs((parsers.anyescaped
                           - parsers.more
                           - #(parsers.period
                              * parsers.onlineimagesuffix
                              * parsers.more
                              * parsers.contentblock_tail))^0)
                      * parsers.period
                      * Cs(parsers.onlineimagesuffix)
                      * parsers.more
                      + (Cs((parsers.inparens
                            + (parsers.anyescaped
                              - parsers.spacing
                              - parsers.rparent
                              - #(parsers.period
                                 * parsers.onlineimagesuffix
                                 * parsers.contentblock_tail)))^0)
                        * parsers.period
                        * Cs(parsers.onlineimagesuffix))
                      ) * Cc("onlineimage")

-- filename for iA Writer content blocks with mandatory suffix:
parsers.localfilepath
                    = parsers.slash
                    * Cs((parsers.anyescaped
                         - parsers.tab
                         - parsers.newline
                         - #(parsers.period
                            * parsers.alphanumeric^1
                            * parsers.contentblock_tail))^1)
                    * parsers.period
                    * Cs(parsers.alphanumeric^1)
                    * Cc("localfile")
parsers.citation_name = Cs(parsers.dash^-1) * parsers.at
                      * Cs(parsers.citation_chars
                          * (((parsers.citation_chars + parsers.internal_punctuation
                              - parsers.comma - parsers.semicolon)
                             * -#((parsers.internal_punctuation - parsers.comma
                                  - parsers.semicolon)^0
                                 * -(parsers.citation_chars + parsers.internal_punctuation
                                    - parsers.comma - parsers.semicolon)))^0
                            * parsers.citation_chars)^-1)

parsers.citation_body_prenote
                    = Cs((parsers.alphanumeric^1
                         + parsers.bracketed
                         + parsers.inticks
                         + (parsers.anyescaped
                           - (parsers.rbracket + parsers.blankline^2))
                         - (parsers.spnl * parsers.dash^-1 * parsers.at))^0)

parsers.citation_body_postnote
                    = Cs((parsers.alphanumeric^1
                         + parsers.bracketed
                         + parsers.inticks
                         + (parsers.anyescaped
                           - (parsers.rbracket + parsers.semicolon
                             + parsers.blankline^2))
                         - (parsers.spnl * parsers.rbracket))^0)

parsers.citation_body_chunk
                    = parsers.citation_body_prenote
                    * parsers.spnl * parsers.citation_name
                    * ((parsers.internal_punctuation - parsers.semicolon)
                      * parsers.spnl)^-1
                    * parsers.citation_body_postnote

parsers.citation_body
                    = parsers.citation_body_chunk
                    * (parsers.semicolon * parsers.spnl
                      * parsers.citation_body_chunk)^0

parsers.citation_headless_body_postnote
                    = Cs((parsers.alphanumeric^1
                         + parsers.bracketed
                         + parsers.inticks
                         + (parsers.anyescaped
                           - (parsers.rbracket + parsers.at
                             + parsers.semicolon + parsers.blankline^2))
                         - (parsers.spnl * parsers.rbracket))^0)

parsers.citation_headless_body
                    = parsers.citation_headless_body_postnote
                    * (parsers.sp * parsers.semicolon * parsers.spnl
                      * parsers.citation_body_chunk)^0
local function strip_first_char(s)
  return s:sub(2)
end

parsers.RawNoteRef = #(parsers.lbracket * parsers.circumflex)
                   * parsers.tag / strip_first_char
-- case-insensitive match (we assume s is lowercase). must be single byte encoding
parsers.keyword_exact = function(s)
  local parser = P(0)
  for i=1,#s do
    local c = s:sub(i,i)
    local m = c .. upper(c)
    parser = parser * S(m)
  end
  return parser
end

parsers.block_keyword =
    parsers.keyword_exact("address") + parsers.keyword_exact("blockquote") +
    parsers.keyword_exact("center") + parsers.keyword_exact("del") +
    parsers.keyword_exact("dir") + parsers.keyword_exact("div") +
    parsers.keyword_exact("p") + parsers.keyword_exact("pre") +
    parsers.keyword_exact("li") + parsers.keyword_exact("ol") +
    parsers.keyword_exact("ul") + parsers.keyword_exact("dl") +
    parsers.keyword_exact("dd") + parsers.keyword_exact("form") +
    parsers.keyword_exact("fieldset") + parsers.keyword_exact("isindex") +
    parsers.keyword_exact("ins") + parsers.keyword_exact("menu") +
    parsers.keyword_exact("noframes") + parsers.keyword_exact("frameset") +
    parsers.keyword_exact("h1") + parsers.keyword_exact("h2") +
    parsers.keyword_exact("h3") + parsers.keyword_exact("h4") +
    parsers.keyword_exact("h5") + parsers.keyword_exact("h6") +
    parsers.keyword_exact("hr") + parsers.keyword_exact("script") +
    parsers.keyword_exact("noscript") + parsers.keyword_exact("table") +
    parsers.keyword_exact("tbody") + parsers.keyword_exact("tfoot") +
    parsers.keyword_exact("thead") + parsers.keyword_exact("th") +
    parsers.keyword_exact("td") + parsers.keyword_exact("tr")

-- There is no reason to support bad html, so we expect quoted attributes
parsers.htmlattributevalue
                          = parsers.squote * (parsers.any - (parsers.blankline
                                                            + parsers.squote))^0
                                           * parsers.squote
                          + parsers.dquote * (parsers.any - (parsers.blankline
                                                            + parsers.dquote))^0
                                           * parsers.dquote

parsers.htmlattribute     = parsers.spacing^1
                          * (parsers.alphanumeric + S("_-"))^1
                          * parsers.sp * parsers.equal * parsers.sp
                          * parsers.htmlattributevalue

parsers.htmlcomment       = P("<!--") * (parsers.any - P("-->"))^0 * P("-->")

parsers.htmlinstruction   = P("<?")   * (parsers.any - P("?>" ))^0 * P("?>" )

parsers.openelt_any = parsers.less * parsers.keyword * parsers.htmlattribute^0
                    * parsers.sp * parsers.more

parsers.openelt_exact = function(s)
  return parsers.less * parsers.sp * parsers.keyword_exact(s)
       * parsers.htmlattribute^0 * parsers.sp * parsers.more
end

parsers.openelt_block = parsers.sp * parsers.block_keyword
                      * parsers.htmlattribute^0 * parsers.sp * parsers.more

parsers.closeelt_any = parsers.less * parsers.sp * parsers.slash
                     * parsers.keyword * parsers.sp * parsers.more

parsers.closeelt_exact = function(s)
  return parsers.less * parsers.sp * parsers.slash * parsers.keyword_exact(s)
       * parsers.sp * parsers.more
end

parsers.emptyelt_any = parsers.less * parsers.sp * parsers.keyword
                     * parsers.htmlattribute^0 * parsers.sp * parsers.slash
                     * parsers.more

parsers.emptyelt_block = parsers.less * parsers.sp * parsers.block_keyword
                       * parsers.htmlattribute^0 * parsers.sp * parsers.slash
                       * parsers.more

parsers.displaytext = (parsers.any - parsers.less)^1

-- return content between two matched HTML tags
parsers.in_matched = function(s)
  return { parsers.openelt_exact(s)
         * (V(1) + parsers.displaytext
           + (parsers.less - parsers.closeelt_exact(s)))^0
         * parsers.closeelt_exact(s) }
end

local function parse_matched_tags(s,pos)
  local t = string.lower(lpeg.match(C(parsers.keyword),s,pos))
  return lpeg.match(parsers.in_matched(t),s,pos-1)
end

parsers.in_matched_block_tags = parsers.less
                              * Cmt(#parsers.openelt_block, parse_matched_tags)

parsers.displayhtml = parsers.htmlcomment
                    + parsers.emptyelt_block
                    + parsers.openelt_exact("hr")
                    + parsers.in_matched_block_tags
                    + parsers.htmlinstruction

parsers.inlinehtml  = parsers.emptyelt_any
                    + parsers.htmlcomment
                    + parsers.htmlinstruction
                    + parsers.openelt_any
                    + parsers.closeelt_any
parsers.hexentity = parsers.ampersand * parsers.hash * S("Xx")
                  * C(parsers.hexdigit^1) * parsers.semicolon
parsers.decentity = parsers.ampersand * parsers.hash
                  * C(parsers.digit^1) * parsers.semicolon
parsers.tagentity = parsers.ampersand * C(parsers.alphanumeric^1)
                  * parsers.semicolon
-- parse a reference definition:  [foo]: /bar "title"
parsers.define_reference_parser = parsers.leader * parsers.tag * parsers.colon
                                * parsers.spacechar^0 * parsers.url
                                * parsers.optionaltitle * parsers.blankline^1
parsers.Inline       = V("Inline")

-- parse many p between starter and ender
parsers.between = function(p, starter, ender)
  local ender2 = B(parsers.nonspacechar) * ender
  return (starter * #parsers.nonspacechar * Ct(p * (p - ender2)^0) * ender2)
end

parsers.urlchar      = parsers.anyescaped - parsers.newline - parsers.more
parsers.Block        = V("Block")

parsers.OnlineImageURL
                     = parsers.leader
                     * parsers.onlineimageurl
                     * parsers.optionaltitle

parsers.LocalFilePath
                     = parsers.leader
                     * parsers.localfilepath
                     * parsers.optionaltitle

parsers.TildeFencedCode
                     = parsers.fencehead(parsers.tilde)
                     * Cs(parsers.fencedline(parsers.tilde)^0)
                     * parsers.fencetail(parsers.tilde)

parsers.BacktickFencedCode
                     = parsers.fencehead(parsers.backtick)
                     * Cs(parsers.fencedline(parsers.backtick)^0)
                     * parsers.fencetail(parsers.backtick)

parsers.lineof = function(c)
    return (parsers.leader * (P(c) * parsers.optionalspace)^3
           * (parsers.newline * parsers.blankline^1
             + parsers.newline^-1 * parsers.eof))
end
parsers.defstartchar = S("~:")
parsers.defstart     = ( parsers.defstartchar * #parsers.spacing
                                              * (parsers.tab + parsers.space^-3)
                     + parsers.space * parsers.defstartchar * #parsers.spacing
                                     * (parsers.tab + parsers.space^-2)
                     + parsers.space * parsers.space * parsers.defstartchar
                                     * #parsers.spacing
                                     * (parsers.tab + parsers.space^-1)
                     + parsers.space * parsers.space * parsers.space
                                     * parsers.defstartchar * #parsers.spacing
                     )

parsers.dlchunk = Cs(parsers.line * (parsers.indentedline - parsers.blankline)^0)
-- parse Atx heading start and return level
parsers.HeadingStart = #parsers.hash * C(parsers.hash^-6)
                     * -parsers.hash / length

parsers.WikiHeadingStart = #parsers.equal * C(parsers.equal^-6)
                     * -parsers.equal / length

-- parse setext header ending and return level
parsers.HeadingLevel = parsers.equal^1 * Cc(1) + parsers.dash^1 * Cc(2)

local function strip_atx_end(s)
  return s:gsub("[#%s]*\n$","")
end
M.reader = {}
function M.reader.new(writer, options)
  local self = {}
  options = options or {}
  setmetatable(options, { __index = function (_, key)
    return defaultOptions[key] end })
  local function normalize_tag(tag)
    return unicode.utf8.lower(
      gsub(util.rope_to_string(tag), "[ \n\r\t]+", " "))
  end
  local expandtabs
  if options.preserveTabs then
    expandtabs = function(s) return s end
  else
    expandtabs = function(s)
                   if s:find("\t") then
                     return s:gsub("[^\n]*", util.expand_tabs_in_line)
                   else
                     return s
                   end
                 end
  end
  local larsers    = {}
  local function create_parser(name, grammar)
    return function(str)
      local res = lpeg.match(grammar(), str)
      if res == nil then
        error(format("%s failed on:\n%s", name, str:sub(1,20)))
      else
        return res
      end
    end
  end

  local parse_blocks
    = create_parser("parse_blocks",
                    function()
                      return larsers.blocks
                    end)

  local parse_blocks_toplevel
    = create_parser("parse_blocks_toplevel",
                    function()
                      return larsers.blocks_toplevel
                    end)

  local parse_inlines
    = create_parser("parse_inlines",
                    function()
                      return larsers.inlines
                    end)

  local parse_inlines_no_link
    = create_parser("parse_inlines_no_link",
                    function()
                      return larsers.inlines_no_link
                    end)

  local parse_inlines_no_inline_note
    = create_parser("parse_inlines_no_inline_note",
                    function()
                      return larsers.inlines_no_inline_note
                    end)

  local parse_inlines_nbsp
    = create_parser("parse_inlines_nbsp",
                    function()
                      return larsers.inlines_nbsp
                    end)
  if options.hashEnumerators then
    larsers.dig = parsers.digit + parsers.hash
  else
    larsers.dig = parsers.digit
  end

  larsers.enumerator = C(larsers.dig^3 * parsers.period) * #parsers.spacing
                     + C(larsers.dig^2 * parsers.period) * #parsers.spacing
                                       * (parsers.tab + parsers.space^1)
                     + C(larsers.dig * parsers.period) * #parsers.spacing
                                     * (parsers.tab + parsers.space^-2)
                     + parsers.space * C(larsers.dig^2 * parsers.period)
                                     * #parsers.spacing
                     + parsers.space * C(larsers.dig * parsers.period)
                                     * #parsers.spacing
                                     * (parsers.tab + parsers.space^-1)
                     + parsers.space * parsers.space * C(larsers.dig^1
                                     * parsers.period) * #parsers.spacing
  -- strip off leading > and indents, and run through blocks
  larsers.blockquote_body = ((parsers.leader * parsers.more * parsers.space^-1)/""
                             * parsers.linechar^0 * parsers.newline)^1
                            * (-(parsers.leader * parsers.more
                                + parsers.blankline) * parsers.linechar^1
                              * parsers.newline)^0

  if not options.breakableBlockquotes then
    larsers.blockquote_body = larsers.blockquote_body
                            * (parsers.blankline^0 / "")
  end
  larsers.citations = function(text_cites, raw_cites)
      local function normalize(str)
          if str == "" then
              str = nil
          else
              str = (options.citationNbsps and parse_inlines_nbsp or
                parse_inlines)(str)
          end
          return str
      end

      local cites = {}
      for i = 1,#raw_cites,4 do
          cites[#cites+1] = {
              prenote = normalize(raw_cites[i]),
              suppress_author = raw_cites[i+1] == "-",
              name = writer.citation(raw_cites[i+2]),
              postnote = normalize(raw_cites[i+3]),
          }
      end
      return writer.citations(text_cites, cites)
  end
  local rawnotes = {}

  -- like indirect_link
  local function lookup_note(ref)
    return function()
      local found = rawnotes[normalize_tag(ref)]
      if found then
        return writer.note(parse_blocks_toplevel(found))
      else
        return {"[", parse_inlines("^" .. ref), "]"}
      end
    end
  end

  local function register_note(ref,rawnote)
    rawnotes[normalize_tag(ref)] = rawnote
    return ""
  end

  larsers.NoteRef    = parsers.RawNoteRef / lookup_note

  larsers.NoteBlock  = parsers.leader * parsers.RawNoteRef * parsers.colon
                     * parsers.spnl * parsers.indented_blocks(parsers.chunk)
                     / register_note

  larsers.InlineNote = parsers.circumflex
                     * (parsers.tag / parse_inlines_no_inline_note) -- no notes inside notes
                     / writer.note
  -- List of references defined in the document
  local references

  -- add a reference to the list
  local function register_link(tag,url,title)
      references[normalize_tag(tag)] = { url = url, title = title }
      return ""
  end

  -- lookup link reference and return either
  -- the link or nil and fallback text.
  local function lookup_reference(label,sps,tag)
      local tagpart
      if not tag then
          tag = label
          tagpart = ""
      elseif tag == "" then
          tag = label
          tagpart = "[]"
      else
          tagpart = {"[", parse_inlines(tag), "]"}
      end
      if sps then
        tagpart = {sps, tagpart}
      end
      local r = references[normalize_tag(tag)]
      if r then
        return r
      else
        return nil, {"[", parse_inlines(label), "]", tagpart}
      end
  end

  -- lookup link reference and return a link, if the reference is found,
  -- or a bracketed label otherwise.
  local function indirect_link(label,sps,tag)
    return function()
      local r,fallback = lookup_reference(label,sps,tag)
      if r then
        return writer.link(parse_inlines_no_link(label), r.url, r.title)
      else
        return fallback
      end
    end
  end

  -- lookup image reference and return an image, if the reference is found,
  -- or a bracketed label otherwise.
  local function indirect_image(label,sps,tag)
    return function()
      local r,fallback = lookup_reference(label,sps,tag)
      if r then
        return writer.image(writer.string(label), r.url, r.title)
      else
        return {"!", fallback}
      end
    end
  end
  larsers.Str      = parsers.normalchar^1 / writer.string

  larsers.Symbol   = (parsers.specialchar - parsers.tightblocksep)
                   / writer.string

  larsers.Ellipsis = P("...") / writer.ellipsis

  larsers.Smart    = larsers.Ellipsis

  larsers.Code     = parsers.inticks / writer.code

  if options.blankBeforeBlockquote then
    larsers.bqstart = parsers.fail
  else
    larsers.bqstart = parsers.more
  end

  if options.blankBeforeHeading then
    larsers.headerstart = parsers.fail
  else
    larsers.headerstart = parsers.hash
                        + (parsers.line * (parsers.equal^1 + parsers.dash^1)
                        * parsers.optionalspace * parsers.newline)
  end

  if not options.fencedCode or options.blankBeforeCodeFence then
    larsers.fencestart = parsers.fail
  else
    larsers.fencestart = parsers.fencehead(parsers.backtick)
                       + parsers.fencehead(parsers.tilde)
  end

  larsers.Endline   = parsers.newline * -( -- newline, but not before...
                        parsers.blankline -- paragraph break
                      + parsers.tightblocksep  -- nested list
                      + parsers.eof       -- end of document
                      + larsers.bqstart
                      + larsers.headerstart
                      + larsers.fencestart
                    ) * parsers.spacechar^0 / writer.space

  larsers.Space      = parsers.spacechar^2 * larsers.Endline / writer.linebreak
                     + parsers.spacechar^1 * larsers.Endline^-1 * parsers.eof / ""
                     + parsers.spacechar^1 * larsers.Endline^-1
                                           * parsers.optionalspace / writer.space

  larsers.NonbreakingEndline
                    = parsers.newline * -( -- newline, but not before...
                        parsers.blankline -- paragraph break
                      + parsers.tightblocksep  -- nested list
                      + parsers.eof       -- end of document
                      + larsers.bqstart
                      + larsers.headerstart
                      + larsers.fencestart
                    ) * parsers.spacechar^0 / writer.nbsp

  larsers.NonbreakingSpace
                  = parsers.spacechar^2 * larsers.Endline / writer.linebreak
                  + parsers.spacechar^1 * larsers.Endline^-1 * parsers.eof / ""
                  + parsers.spacechar^1 * larsers.Endline^-1
                                        * parsers.optionalspace / writer.nbsp

  if options.underscores then
    larsers.Strong = ( parsers.between(parsers.Inline, parsers.doubleasterisks,
                                       parsers.doubleasterisks)
                     + parsers.between(parsers.Inline, parsers.doubleunderscores,
                                       parsers.doubleunderscores)
                     ) / writer.strong

    larsers.Emph   = ( parsers.between(parsers.Inline, parsers.asterisk,
                                       parsers.asterisk)
                     + parsers.between(parsers.Inline, parsers.underscore,
                                       parsers.underscore)
                     ) / writer.emphasis
  else
    larsers.Strong = ( parsers.between(parsers.Inline, parsers.doubleasterisks,
                                       parsers.doubleasterisks)
                     ) / writer.strong

    larsers.Emph   = ( parsers.between(parsers.Inline, parsers.asterisk,
                                       parsers.asterisk)
                     ) / writer.emphasis
  end

  larsers.AutoLinkUrl    = parsers.less
                         * C(parsers.alphanumeric^1 * P("://") * parsers.urlchar^1)
                         * parsers.more
                         / function(url)
                             return writer.link(writer.string(url), url)
                           end

  larsers.AutoLinkEmail = parsers.less
                        * C((parsers.alphanumeric + S("-._+"))^1
                        * P("@") * parsers.urlchar^1)
                        * parsers.more
                        / function(email)
                            return writer.link(writer.string(email),
                                               "mailto:"..email)
                          end

  larsers.DirectLink    = (parsers.tag / parse_inlines_no_link)  -- no links inside links
                        * parsers.spnl
                        * parsers.lparent
                        * (parsers.url + Cc(""))  -- link can be empty [foo]()
                        * parsers.optionaltitle
                        * parsers.rparent
                        / writer.link

  larsers.IndirectLink  = parsers.tag * (C(parsers.spnl) * parsers.tag)^-1
                        / indirect_link

  -- parse a link or image (direct or indirect)
  larsers.Link          = larsers.DirectLink + larsers.IndirectLink

  larsers.DirectImage   = parsers.exclamation
                        * (parsers.tag / parse_inlines)
                        * parsers.spnl
                        * parsers.lparent
                        * (parsers.url + Cc(""))  -- link can be empty [foo]()
                        * parsers.optionaltitle
                        * parsers.rparent
                        / writer.image

  larsers.IndirectImage = parsers.exclamation * parsers.tag
                        * (C(parsers.spnl) * parsers.tag)^-1 / indirect_image

  larsers.Image         = larsers.DirectImage + larsers.IndirectImage

  larsers.TextCitations = Ct(Cc("")
                        * parsers.citation_name
                        * ((parsers.spnl
                            * parsers.lbracket
                            * parsers.citation_headless_body
                            * parsers.rbracket) + Cc("")))
                        / function(raw_cites)
                            return larsers.citations(true, raw_cites)
                          end

  larsers.ParenthesizedCitations
                        = Ct(parsers.lbracket
                        * parsers.citation_body
                        * parsers.rbracket)
                        / function(raw_cites)
                            return larsers.citations(false, raw_cites)
                          end

  larsers.Citations     = larsers.TextCitations + larsers.ParenthesizedCitations

  -- avoid parsing long strings of * or _ as emph/strong
  larsers.UlOrStarLine  = parsers.asterisk^4 + parsers.underscore^4
                        / writer.string

  larsers.EscapedChar   = S("\\") * C(parsers.escapable) / writer.string

  larsers.InlineHtml    = C(parsers.inlinehtml) / writer.inline_html

  larsers.HtmlEntity    = parsers.hexentity / entities.hex_entity  / writer.string
                        + parsers.decentity / entities.dec_entity  / writer.string
                        + parsers.tagentity / entities.char_entity / writer.string
  larsers.ContentBlock = parsers.leader
                       * (parsers.localfilepath + parsers.onlineimageurl)
                       * parsers.contentblock_tail
                       / writer.contentblock

  larsers.DisplayHtml  = C(parsers.displayhtml)
                       / expandtabs / writer.display_html

  larsers.Verbatim     = Cs( (parsers.blanklines
                           * ((parsers.indentedline - parsers.blankline))^1)^1
                           ) / expandtabs / writer.verbatim

  larsers.FencedCode   = (parsers.TildeFencedCode
                         + parsers.BacktickFencedCode)
                       / function(infostring, code)
                           return writer.fencedCode(writer.string(infostring),
                                                    expandtabs(code))
                         end

  larsers.Blockquote   = Cs(larsers.blockquote_body^1)
                       / parse_blocks_toplevel / writer.blockquote

  larsers.HorizontalRule = ( parsers.lineof(parsers.asterisk)
                           + parsers.lineof(parsers.dash)
                           + parsers.lineof(parsers.underscore)
                           ) / writer.hrule

  larsers.Reference    = parsers.define_reference_parser / register_link

  larsers.Paragraph    = parsers.nonindentspace * Ct(parsers.Inline^1)
                       * parsers.newline
                       * ( parsers.blankline^1
                         + #parsers.hash
                         + #(parsers.leader * parsers.more * parsers.space^-1)
                         )
                       / writer.paragraph

  larsers.ToplevelParagraph
                       = parsers.nonindentspace * Ct(parsers.Inline^1)
                       * ( parsers.newline
                       * ( parsers.blankline^1
                         + #parsers.hash
                         + #(parsers.leader * parsers.more * parsers.space^-1)
                         + parsers.eof
                         )
                       + parsers.eof )
                       / writer.paragraph

  larsers.Plain        = parsers.nonindentspace * Ct(parsers.Inline^1)
                       / writer.plain
  larsers.starter = parsers.bullet + larsers.enumerator

  -- we use \001 as a separator between a tight list item and a
  -- nested list under it.
  larsers.NestedList            = Cs((parsers.optionallyindentedline
                                     - larsers.starter)^1)
                                / function(a) return "\001"..a end

  larsers.ListBlockLine         = parsers.optionallyindentedline
                                - parsers.blankline - (parsers.indent^-1
                                                      * larsers.starter)

  larsers.ListBlock             = parsers.line * larsers.ListBlockLine^0

  larsers.ListContinuationBlock = parsers.blanklines * (parsers.indent / "")
                                * larsers.ListBlock

  larsers.TightListItem = function(starter)
      return -larsers.HorizontalRule
             * (Cs(starter / "" * larsers.ListBlock * larsers.NestedList^-1)
               / parse_blocks)
             * -(parsers.blanklines * parsers.indent)
  end

  larsers.LooseListItem = function(starter)
      return -larsers.HorizontalRule
             * Cs( starter / "" * larsers.ListBlock * Cc("\n")
               * (larsers.NestedList + larsers.ListContinuationBlock^0)
               * (parsers.blanklines / "\n\n")
               ) / parse_blocks
  end

  larsers.BulletList = ( Ct(larsers.TightListItem(parsers.bullet)^1) * Cc(true)
                       * parsers.skipblanklines * -parsers.bullet
                       + Ct(larsers.LooseListItem(parsers.bullet)^1) * Cc(false)
                       * parsers.skipblanklines )
                     / writer.bulletlist

  local function ordered_list(items,tight,startNumber)
    if options.startNumber then
      startNumber = tonumber(startNumber) or 1  -- fallback for '#'
    else
      startNumber = nil
    end
    return writer.orderedlist(items,tight,startNumber)
  end

  larsers.OrderedList = Cg(larsers.enumerator, "listtype") *
                      ( Ct(larsers.TightListItem(Cb("listtype"))
                          * larsers.TightListItem(larsers.enumerator)^0)
                      * Cc(true) * parsers.skipblanklines * -larsers.enumerator
                      + Ct(larsers.LooseListItem(Cb("listtype"))
                          * larsers.LooseListItem(larsers.enumerator)^0)
                      * Cc(false) * parsers.skipblanklines
                      ) * Cb("listtype") / ordered_list

  local function definition_list_item(term, defs, tight)
    return { term = parse_inlines(term), definitions = defs }
  end

  larsers.DefinitionListItemLoose = C(parsers.line) * parsers.skipblanklines
                                  * Ct((parsers.defstart
                                       * parsers.indented_blocks(parsers.dlchunk)
                                       / parse_blocks_toplevel)^1)
                                  * Cc(false) / definition_list_item

  larsers.DefinitionListItemTight = C(parsers.line)
                                  * Ct((parsers.defstart * parsers.dlchunk
                                       / parse_blocks)^1)
                                  * Cc(true) / definition_list_item

  larsers.DefinitionList = ( Ct(larsers.DefinitionListItemLoose^1) * Cc(false)
                           + Ct(larsers.DefinitionListItemTight^1)
                           * (parsers.skipblanklines
                             * -larsers.DefinitionListItemLoose * Cc(true))
                           ) / writer.definitionlist
  larsers.Blank        = parsers.blankline / ""
                       + larsers.NoteBlock
                       + larsers.Reference
                       + (parsers.tightblocksep / "\n")
  -- parse atx header
  larsers.AtxHeading = Cg(parsers.HeadingStart,"level")
                     * parsers.optionalspace
                     * (C(parsers.line) / strip_atx_end / parse_inlines)
                     * Cb("level")
                     / writer.heading

  -- parse setext header
  larsers.SetextHeading = #(parsers.line * S("=-"))
                        * Ct(parsers.line / parse_inlines)
                        * parsers.HeadingLevel
                        * parsers.optionalspace * parsers.newline
                        / writer.heading

  larsers.Heading = larsers.AtxHeading + larsers.SetextHeading
  -- larsers.Ahoj = P "@" + Ct(parsers.line / parse_inlines) * parsers.newline / writer.hello
  local function strip_wiki_head_end(s)
    return s:gsub("[%s%=]*$", "")
  end
  larsers.Ahoj = Cg(parsers.WikiHeadingStart, "level")
                    * parsers.optionalspace
                    * (C(parsers.line) / strip_wiki_head_end / parse_inlines)
                    * Cb("level")
                    / writer.hello

  local syntax =
    { "Blocks",

      Blocks                = larsers.Blank^0 * parsers.Block^-1
                            * (larsers.Blank^0 / function()
                                                   return writer.interblocksep
                                                 end
                              * parsers.Block)^0
                            * larsers.Blank^0 * parsers.eof,

      Blank                 = larsers.Blank,

      Block                 = V("ContentBlock")
                            + V("Blockquote")
                            + V("Verbatim")
                            + V("FencedCode")
                            + V("HorizontalRule")
                            + V("BulletList")
                            + V("OrderedList")
                            + V("Heading")
                            + V("Ahoj")
                            + V("DefinitionList")
                            + V("DisplayHtml")
                            + V("Paragraph")
                            + V("Plain"),

      ContentBlock          = larsers.ContentBlock,
      Blockquote            = larsers.Blockquote,
      Verbatim              = larsers.Verbatim,
      FencedCode            = larsers.FencedCode,
      HorizontalRule        = larsers.HorizontalRule,
      BulletList            = larsers.BulletList,
      OrderedList           = larsers.OrderedList,
      Heading               = larsers.Heading,
      Ahoj                  = larsers.Ahoj,
      DefinitionList        = larsers.DefinitionList,
      DisplayHtml           = larsers.DisplayHtml,
      Paragraph             = larsers.Paragraph,
      Plain                 = larsers.Plain,

      Inline                = V("Str")
                            + V("Space")
                            + V("Endline")
                            + V("UlOrStarLine")
                            + V("Strong")
                            + V("Emph")
                            + V("InlineNote")
                            + V("NoteRef")
                            + V("Citations")
                            + V("Link")
                            + V("Image")
                            + V("Code")
                            + V("AutoLinkUrl")
                            + V("AutoLinkEmail")
                            + V("InlineHtml")
                            + V("HtmlEntity")
                            + V("EscapedChar")
                            + V("Smart")
                            + V("Symbol"),

      Str                   = larsers.Str,
      Space                 = larsers.Space,
      Endline               = larsers.Endline,
      UlOrStarLine          = larsers.UlOrStarLine,
      Strong                = larsers.Strong,
      Emph                  = larsers.Emph,
      InlineNote            = larsers.InlineNote,
      NoteRef               = larsers.NoteRef,
      Citations             = larsers.Citations,
      Link                  = larsers.Link,
      Image                 = larsers.Image,
      Code                  = larsers.Code,
      AutoLinkUrl           = larsers.AutoLinkUrl,
      AutoLinkEmail         = larsers.AutoLinkEmail,
      InlineHtml            = larsers.InlineHtml,
      HtmlEntity            = larsers.HtmlEntity,
      EscapedChar           = larsers.EscapedChar,
      Smart                 = larsers.Smart,
      Symbol                = larsers.Symbol,
    }

  if not options.citations then
    syntax.Citations = parsers.fail
  end

  if not options.contentBlocks then
    syntax.ContentBlock = parsers.fail
  end

  if not options.codeSpans then
    syntax.Code = parsers.fail
  end

  if not options.definitionLists then
    syntax.DefinitionList = parsers.fail
  end

  if not options.fencedCode then
    syntax.FencedCode = parsers.fail
  end

  if not options.footnotes then
    syntax.NoteRef = parsers.fail
  end

  if not options.html then
    syntax.DisplayHtml = parsers.fail
    syntax.InlineHtml = parsers.fail
    syntax.HtmlEntity  = parsers.fail
  end

  if not options.inlineFootnotes then
    syntax.InlineNote = parsers.fail
  end

  if not options.smartEllipses then
    syntax.Smart = parsers.fail
  end

  local blocks_toplevel_t = util.table_copy(syntax)
  blocks_toplevel_t.Paragraph = larsers.ToplevelParagraph
  larsers.blocks_toplevel = Ct(blocks_toplevel_t)

  larsers.blocks = Ct(syntax)

  local inlines_t = util.table_copy(syntax)
  inlines_t[1] = "Inlines"
  inlines_t.Inlines = parsers.Inline^0 * (parsers.spacing^0 * parsers.eof / "")
  larsers.inlines = Ct(inlines_t)

  local inlines_no_link_t = util.table_copy(inlines_t)
  inlines_no_link_t.Link = parsers.fail
  larsers.inlines_no_link = Ct(inlines_no_link_t)

  local inlines_no_inline_note_t = util.table_copy(inlines_t)
  inlines_no_inline_note_t.InlineNote = parsers.fail
  larsers.inlines_no_inline_note = Ct(inlines_no_inline_note_t)

  local inlines_nbsp_t = util.table_copy(inlines_t)
  inlines_nbsp_t.Endline = larsers.NonbreakingEndline
  inlines_nbsp_t.Space = larsers.NonbreakingSpace
  larsers.inlines_nbsp = Ct(inlines_nbsp_t)
  function self.convert(input)
    references = {}
    local opt_string = {}
    for k,_ in pairs(defaultOptions) do
      local v = options[k]
      if k ~= "cacheDir" then
        opt_string[#opt_string+1] = k .. "=" .. tostring(v)
      end
    end
    table.sort(opt_string)
    local salt = table.concat(opt_string, ",") .. "," .. metadata.version
    local name = util.cache(options.cacheDir, input, salt, function(input)
        return util.rope_to_string(parse_blocks_toplevel(input)) .. writer.eof
      end, ".md" .. writer.suffix)
    return writer.pack(name)
  end
  function self.parse(input)
    return util.rope_to_string(parse_blocks_toplevel(input)) 
  end
  return self
end
function M.new(options)
  local writer = M.writer.new(options)
  local reader = M.reader.new(writer, options)
  return reader.convert
end

return M
