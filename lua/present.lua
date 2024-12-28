local M = {}

---@class present.Slides
---@field slides present.Slide[]: The slides in the buffer

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide
---
---@class present.Windows
---@field title snacks.win: The title window
---@field body snacks.win: The window containing the slide body

local state = {
  ---@type present.Slides | {}
  parsed = {},
  ---@type number
  current_slide = 1,
  ---@type present.Windows | {}
  windows = {},
  ---@type string
  footer = "",
  ---@type string
  name = "",
}

M.setup = function()
  -- nothing
end

---@param title string: The title to pad
---@param columns number: The columns to pad to
---@return string: The padded title
local function padded_title(title, columns)
  columns = columns or vim.o.columns
  local padding = math.floor((columns - #title) / 2)
  return string.rep(" ", padding) .. title
end

---@param opts snacks.win.Config: The options for the window
local function create_floating_window(opts)
  opts = opts or {}
  opts.text = opts.text or ""
  return Snacks.win({
    show = true,
    enter = true,
    position = "float",
    col = opts.col,
    row = opts.row,
    backdrop = 15,
    height = opts.height or 0.7,
    width = opts.width or 0.7,
    zindex = 50,
    border = opts.border or "double",
    ft = "markdown",
    footer = opts.footer or "",
    minimal = true,
    bo = {
      filetype = "markdown",
      modifiable = false,
    },
    text = opts.text,
    title = opts.title or "",
    title_pos = "center",
    footer_pos = "left",
    fixbuf = true,
    keys = opts.keys or {},
    actions = opts.actions or {},
  })
end

---@param buf number: The buffer to set the content
---@param lines string[]: The lines to set
local function set_window_content(buf, lines)
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

---@param windows present.Windows: The windows to set the content
---@param slide present.Slide: The lines to set
---@param footer string: The footer that will be set on body window
local function set_slide_content(windows, slide, footer)
  local title_columns = windows.title:size().width
  set_window_content(windows.body.buf, slide.body)
  set_window_content(windows.title.buf, { padded_title(slide.title, title_columns) })
  windows.body.opts.footer = footer
  windows.body:update()
end

--- Takes some lines and parses them in to slides
---@param lines string[]: The lines in the buffer
---@return present.Slides: The slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  ---@type present.Slide
  local current_slide = {
    title = "",
    body = {},
  }

  local separator = "^#"

  for _, line in ipairs(lines) do
    if line:find(separator) then
      if #current_slide.title > 0 then
        table.insert(slides.slides, current_slide)
      end
      current_slide = {
        title = line,
        body = {},
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  return slides
end

local foreach_window = function(cb)
  for name, window in pairs(state.windows) do
    cb(name, window)
  end
end

local function make_floating_windows()
  -- if we have existing windows, close them first
  foreach_window(function(_, window)
    if window ~= nil and window:valid() then
      window:close()
    end
  end)

  return {
    title = create_floating_window({
      row = 1,
      height = 1,
      width = 0.7,
      border = "rounded",
      keys = {},
    }),
    body = create_floating_window({
      row = 4,
      border = { " ", " ", " ", " ", " ", " ", " ", " " },
      height = vim.o.lines - 7,
      keys = {},
    }),
  }
end

local function present_keymap(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.windows.body.buf,
  })
end

---@param current_slide number: The current slide
---@param total_slides number: The total number of slides
---@return string: The footer string
local function make_footer(current_slide, total_slides)
  local command_help = "n: next slide, p: previous slide, q: quit"
  return state.name .. " | " .. tostring(current_slide) .. "/" .. tostring(total_slides)
end

local function open_current_slide()
  state.footer = make_footer(state.current_slide, #state.parsed.slides)
  set_slide_content(state.windows, state.parsed.slides[state.current_slide], state.footer)
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  state.name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")
  state.parsed = parse_slides(lines)
  state.windows = make_floating_windows()

  state.windows.body:add_padding()

  state.current_slide = 1
  open_current_slide()

  present_keymap("n", "n", function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    open_current_slide()
  end)

  present_keymap("n", "p", function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    open_current_slide()
  end)

  present_keymap("n", "q", function()
    state.windows.title:close()
    state.windows.body:close()
  end)

  present_keymap("n", "?", function()
    local command_help = "n: next slide, p: previous slide, q: quit"
    vim.print(command_help)
  end)

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present.nvim-resized", {}),
    callback = function()
      if state.windows.body == nil or not state.windows.body:valid() then
        return
      end
      state.windows.body.opts.height = vim.o.lines - 7
      state.windows.body:update()
      state.windows.title:update()
      local title_columns = state.windows.title:size().width
      set_window_content(
        state.windows.title.buf,
        { padded_title(state.parsed.slides[state.current_slide].title, title_columns) }
      )
      state.windows.title:update()
    end,
  })
end

-- M.start_presentation({ bufnr = 6 })
-- vim.print(parse_slides({
--   "# Slide 1",
--   "something in slide 1",
--   "# Slide 2",
--   "something in slide 2",
-- }))
--

M._parse_slides = parse_slides

return M
