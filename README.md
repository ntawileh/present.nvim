# present.nvim

A plugin for presenting markdown content in Neovim.

## Credits

[teej_dv](https://github.com/teej_dv): [present.nvim](https://github.com/teej_dv/present.nvim) and his amazing [Advent of Neovim](https://www.youtube.com/watch?v=VGid4aN25iI) video series

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'ntawileh/present.nvim'
     dependencies = { "folke/snacks.nvim" },
}
```

## Usage

````lua
```require("present").start_presentation {}`
````

or `:PresentStart` in normal mode.

## Configuration

```lua
require("present").setup({
    executors = {
        javascript = require("present").create_system_executor("node"),
        python = require("present").create_system_executor("python3"),
    },
})
```

`executors` is a table of functions that will be used to execute code blocks. The keys are the language names and the values are functions that take a `present.Block` and return a list of strings as output.

The default/built-in executors are:

- lua: executes the code block using `loadstring` and `pcall`
- javascript: executes the code block using `vim.system` and `node`
- python: executes the code block using `vim.system` and `python3`
- rust: executes the code block using `vim.system` and `rustc`

You can create your own executors by using `present.create_system_executor` and passing in the binary to run.

For example, to create an executor for a language called `mylang` that runs the code using `mylang`:

```lua
local mylang_executor = require("present").create_system_executor("mylang")
```

Then you can add it to the `executors` table:

```lua
require("present").setup({
    executors = {
        javascript = require("present").create_system_executor("node"),
        python = require("present").create_system_executor("python3"),
        mylang = mylang_executor,
```
