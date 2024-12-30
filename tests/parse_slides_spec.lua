---@diagnostic disable: undefined-field, no-unknown
local parse = require("present")._parse_slides
local eq = assert.are.same
describe("present.parse_slides", function()
  it("should parse an empty file", function()
    eq(parse({}), { slides = { {
      title = "",
      body = {},
      blocks = {},
    } } })
  end)

  it("should parse a file with one slide", function()
    eq(
      parse({
        "# Slide 1",
        "something in slide 1",
      }),
      {
        slides = {
          {
            title = "# Slide 1",
            body = {
              "something in slide 1",
            },
            blocks = {},
          },
        },
      }
    )
  end)

  it("should parse a file with one slide, and a code block", function()
    local result = parse({
      "# Slide 1",
      "something in slide 1",
      "```lua",
      "print('hello world')",
      "```",
    })
    local slide = result.slides[1]
    eq(1, #result.slides)
    eq(1, #slide.blocks)
    eq(slide.title, "# Slide 1")
    eq(slide.body, {
      "something in slide 1",
      "```lua",
      "print('hello world')",
      "```",
    })
    local block = vim.trim([[
print('hello world')
]])
    eq(slide.blocks[1].body, block)
    eq(slide.blocks[1].language, "lua")
  end)
end)
