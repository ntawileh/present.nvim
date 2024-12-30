local M = {}

---@class present.Slides
---@field slides present.Slide[]: The slides in the buffer

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide
---@field blocks present.Block[]: A code block inside of a slide
---
---@class present.Block
---@field language string: The language of the block
---@field body string: The body of the code block
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
  ---@type boolean
  show_help = false,
}

---@param program string: The binary to run
---@return fun(present.Block): string[]
M.create_system_executor = function(program)
  ---@param block present.Block: The block to execute
  return function(block)
    local tempfile = vim.fn.tempname()
    vim.fn.writefile(vim.split(block.body, "\n"), tempfile)
    local result = vim.system({ program, tempfile }, { text = true }):wait()
    return vim.split(result.stdout, "\n")
  end
end

--- Default executor for Rust code
---@param block present.Block
local execute_rust_code = function(block)
  local tempfile = vim.fn.tempname() .. ".rs"
  local outputfile = tempfile:sub(1, -4)
  vim.fn.writefile(vim.split(block.body, "\n"), tempfile)
  local result = vim.system({ "rustc", tempfile, "-o", outputfile }, { text = true }):wait()
  if result.code ~= 0 then
    local output = vim.split(result.stderr, "\n")
    return output
  end
  result = vim.system({ outputfile }, { text = true }):wait()
  return vim.split(result.stdout, "\n")
end

---@param block present.Block: The block to execute
---@return string[]: The output of the code block
local function execute_lua_code(block)
  local original_print = print
  local output = { "" }

  ---@diagnostic disable-next-line: missing-global-doc
  print = function(...)
    local args = { ... }
    local message = table.concat(vim.tbl_map(tostring, args), "\t")
    table.insert(output, message)
  end

  local chunk = loadstring(block.body)
  pcall(function()
    if not chunk then
      table.insert(output, "Error: Could not load code chunk")
      return
    end
    chunk()
  end)
  print = original_print
  return output
end

local options = {
  ---@type table<string, fun(present.Block): string[]>
  executors = {
    lua = execute_lua_code,
    javascript = M.create_system_executor("node"),
    python = M.create_system_executor("python3"),
    rust = execute_rust_code,
  },
}
M.setup = function(opts)
  opts = opts or {}
  opts.executors = opts.executors or {}

  opts.executors.lua = opts.executors.lua or execute_lua_code
  opts.executors.javascript = opts.executors.javascript or M.create_system_executor("node")
  opts.executors.python = opts.executors.python or M.create_system_executor("python3")
  opts.executors.rust = opts.executors.rust or execute_rust_code
  options = opts
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
    footer_pos = opts.footer_pos or "left",
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
  local slides = {
    ---@type present.Slide[]
    slides = {},
  }
  ---@type present.Slide
  local current_slide = {
    title = "",
    body = {},
    blocks = {},
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
        blocks = {},
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  for _, slide in ipairs(slides.slides) do
    ---@type present.Block | {}
    local block = {
      language = "",
      body = "",
    }
    local inside_block = false
    for _, line in ipairs(slide.body) do
      if vim.startswith(vim.trim(line), "```") then
        if not inside_block then
          inside_block = true
          block.language = string.sub(line, 4)
        else
          inside_block = false
          block.body = vim.trim(block.body)
          table.insert(slide.blocks, block)
          block = { language = "", body = "" }
        end
      else
        if inside_block then
          block.body = block.body .. line .. "\n"
        end
      end
    end
  end

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
  return state.name .. " | " .. tostring(current_slide) .. "/" .. tostring(total_slides) .. " | (?) help"
end

local function open_current_slide()
  local command_help = "n: next slide, p: previous slide, X: execute code block, q: quit"
  state.footer = state.show_help and command_help or make_footer(state.current_slide, #state.parsed.slides)
  set_slide_content(state.windows, state.parsed.slides[state.current_slide], state.footer)
end

---@param block present.Block: The block to execute
local function execute_block(block)
  local slide = state.parsed.slides[state.current_slide]
  local executor = options.executors[block.language]
  local output = { "", "# Code", "```" .. block.language }
  vim.list_extend(output, vim.split(block.body, "\n"))
  table.insert(output, "```")

  table.insert(output, "")
  table.insert(output, "# Output ")
  table.insert(output, "")

  local temp_height = math.floor(vim.o.lines * 0.6)
  local temp_width = math.floor(vim.o.columns * 0.6)

  local code_window = create_floating_window({
    style = "minimal",
    title = block.language,
    width = temp_width,
    height = temp_height,
    row = math.floor((vim.o.lines - temp_height) / 2),
    col = math.floor((vim.o.columns - temp_width) / 2),
    border = "rounded",
    footer = "q: close",
    footer_pos = "center",
    text = "Executing...",
  })

  if not executor then
    table.insert(
      output,
      block.language ~= "" and "No code executor for " .. block.language .. ""
        or "Code block does not specify a language.  Nothing to execute."
    )
  else
    table.insert(output, "```")
    vim.list_extend(output, executor(block))
    table.insert(output, "```")
  end
  set_window_content(code_window.buf, output)
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
    state.show_help = not state.show_help
    open_current_slide()
  end)

  present_keymap("n", "X", function()
    local slide = state.parsed.slides[state.current_slide]
    local block = slide.blocks[1]
    if not block then
      print("No code block found")
      return
    end

    if #slide.blocks == 1 then
      execute_block(block)
      return
    end

    vim.ui.select(slide.blocks, {
      prompt = "Select code block to execute: ",
      format_item = function(b)
        return b.language .. " "
      end,
    }, function(b)
      if b then
        execute_block(b)
      end
    end)
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

M.start_presentation({ bufnr = 11 })
-- vim.print(parse_slides({
--   "# Slide 1",
--   "something in slide 1",
--   "# Slide 2",
--   "something in slide 2",
-- }))
--

M._parse_slides = parse_slides

return M
