vim.api.nvim_create_user_command("PresentStart", function()
  require("present").start_presentation()
end, {
  desc = "Start presentating the markdown content in the current buffer",
})
