package.path = "?.lua:".. package.path
local markdown = require "markdown-copy"

local writer = markdown.writer.new()

writer.hello = function(hello,level)
  return {"hello: ()", hello }
end

local reader = markdown.reader.new(writer)


print(reader.parse([[
=== no a toto ===


@*ahoj*

ble ble
]]))
