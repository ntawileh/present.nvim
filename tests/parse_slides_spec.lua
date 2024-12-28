---@diagnostic disable: undefined-field, no-unknown
local parse = require("present")._parse_slides
local eq = assert.are.same
describe("present.parse_slides", function()
  it("should parse an empty file", function()
    eq(parse({}), { slides = { {
      title = "",
      body = {},
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
          },
        },
      }
    )
  end)
end)
