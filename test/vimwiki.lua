local vimwiki = require "vimwiki"
local reader = vimwiki.reader.new()
describe("basic inline parsing", function()
  it("should detect strong text", function()
    local matches = reader:parse_inlines("příliš *start* hello _world_ more ~~text~~ end")
    assert.same(#matches, 7)
    local strong = matches[2]
    assert.same(strong.name, "strong")
    assert.same(strong.value,  "start")
    local last = matches[#matches]
    assert.same(last.name, "text")
    assert.same(last.value, " end")
  end)
  it("should support inline code", function() 
    local matches = reader:parse_inlines("hello `print(world)`")
    assert.same(#matches, 2)
    assert.same(matches[2].name, "inline_code")
  end)
  it("should correctly support underscores and other characters in the code", function() 
    local matches = reader:parse_inlines("hello `world *ble* and function_with_underscores()`")
    assert.same(#matches,2)
    assert.same(matches[2].name, "inline_code")
  end)
  it("should support sub and super scripts", function()
    local matches = reader:parse_inlines("hello,,subscript,,, hello^superscript^")
    assert.same(#matches, 4)
  end)
  it("should detect tags", function()
    local matches = reader:parse_inlines("some text :and:it:is:tagged: but only this")
    assert.same(#matches, 3)
    local tag = matches[2]
    -- there are four tags
    assert.same(4, #tag.value)
    assert.same(tag.value[3], "is")
  end)
  it("should support links", function()
    local matches = reader:parse_inlines("hello [[world]], this [[link|has a title]]")
    assert.same(#matches,4)
    local simple = matches[2]
    local titled = matches[4]
    assert.same(simple.name, "link")
    assert.same(simple.value, "world")
    assert.same(titled.value, "link")
    assert.same(titled.title, "has a title")
  end)
  it("should detect urls in links", function()
    local matches = reader:parse_inlines("hello [[http://sample.com]], [[file:~/sample.tex|title]]")
    assert.same(#matches, 4)
    local url = matches[2]
    local filelink = matches[4]
    assert.same(url.name, "url_link")
    assert.same(filelink.name, "file_link")
    assert.same(filelink.value,"file:~/sample.tex")
  end)
  it("should support file transclusion", function()
    local matches = reader:parse_inlines("{{file:hello.png}}, {{http://sample.com/hello.png|title|width:122px}}")
    assert.same(#matches, 3)
    local second = matches[3]
    assert.same(second.title, "title")
    assert.same(second.value,"http://sample.com/hello.png")
    assert.same(second.style, "width:122px")
  end)
  it("should support thumbnails", function()
    local matches = reader:parse_inlines("[[sample.png|{{hello.jpg}}]]")
    assert.same(#matches, 1)
    local sample = matches[1]
    assert.truthy(sample.thumbnail)
    assert.same(sample.title, nil)
  end)
end)

describe("Block parsing should work", function()
  local test = [[
= hello world =

- item
- another item
  - sub item

{{{
verbatim block
just a few 
  lines
}}}

paragraph
still paragraph
]]

  it("should parse a string", function()
    reader:parse_string(test)
    assert.truthy(#reader.blocks > 0)
    for _,v in ipairs(reader.blocks) do
      print(v.name, v.value)
    end
  end)
end)
