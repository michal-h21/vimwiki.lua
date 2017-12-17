local vimwiki = require "vimwiki"
describe("basic inline parsing", function()
  local reader = vimwiki.reader.new()
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
  end)
  it("it should detect tags", function()
    local matches = reader:parse_inlines("some text :and:it:is:tagged: but only this")
    assert.same(#matches, 3)
    local tag = matches[2]
    -- there are four tags
    assert.same(4, #tag.value)
  end)
end)
