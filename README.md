<h1 align="center">🤖 aiignore.nvim</h1>

<p align="center">
<a href="https://github.com/ozars/aiignore.nvim/actions/workflows/actions.yml">
<img alt="Github Actions Build" src="https://img.shields.io/github/actions/workflow/status/ozars/aiignore.nvim/actions.yml?style=for-the-badge&logo=github-actions">
</a>
</p>

A small Neovim extension to prevent AI coding plugins (e.g. [`copilot.lua`])
from attaching to files and directories specified in an `.aiignore` file.

## ✨ Features

* Respects `.aiignore` files in your project root and subdirectories.
* Uses the same `.gitignore` format and semantics with git.
* Caches `.aiignore` files for better performance.

## ⚙️ Installation

You can install this plugin using your favorite package manager.

To use this extension, you need to require it and use its `should_ignore`
function in your AI extension setup. 

See below for an example setup with [`copilot.lua`]:

[`copilot.lua`]: https://github.com/zbirenbaum/copilot.lua

### lazy.nvim

```lua
{
  -- Example with "zbirenbaum/copilot.lua"
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  event = "InsertEnter",
  dependencies = { "ozars/aiignore.nvim" }, -- Ensure aiignore is loaded before copilot.lua
  config = function()
    require("copilot").setup({
      -- Other copilot.lua settings

      should_attach = function(bufnr)
        local aiignore = require("aiignore")
        return not aiignore.should_ignore(bufnr, {
          -- File and directory names configurations.
          aiignore_filename = ".aiignore", -- The name of the .aiignore file.
          git_dirname = ".git",            -- The name of the directory which will be used for finding a repository root.

          -- Logging and notifications configurations.
          warn_ignored = false,     -- Whether to notify the user if the file is ignored.
          warn_not_ignored = false, -- Whether to notify the user if the file is not ignored.
          debug_log = false,        -- Whether to log debug messages.
          quiet = false,            -- Whether to ignore errors silently.

          -- Buffer configurations.
          should_ignore_invalid_buffers = true, -- Whether to ignore invalid buffers.
          should_ignore_unnamed_buffers = true, -- Whether to ignore unnamed buffers.
        })
      end,
    })
  end,
}
```

## 📝 The `.aiignore` file

Create an `.aiignore` file in the root of your project (the same directory that
contains your `.git` folder). The format is identical to `.gitignore`. Similar to
`.gitignore`, you can have `.aiignore` files in subdirectories of the repository,
which will only affect those directories.

If a file is not in a git repository, the extension checks for any `.aiignore`
files in the same directory as the buffer path.

### Example `.aiignore`

```
# Ignore secrets and environment files
.env
*.secret
credentials.json
/config/private.yml

# Ignore specific files
/src/legacy/do_not_touch.js
```

With the configuration above, (a configured) AI extension will not attach to or
provide suggestions for any files or directories matching these patterns.
