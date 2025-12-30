_G.vim = _G.vim or {}

function _G.vim.notify(msg, level, opts)
  print(string.format("Notify: %s (level: %s)", msg, level))
end

_G.vim.api = _G.vim.api or {}

function _G.vim.api.nvim_buf_is_valid(bufnr)
  return _G._TEST_VARS.file_paths[bufnr] ~= nil
end

function _G.vim.api.nvim_buf_get_name(bufnr)
  return _G._TEST_VARS.file_paths[bufnr]
end

function _G.vim.api.nvim_get_current_buf()
  return _G._TEST_VARS.current_buf
end

_G.vim.fs = _G.vim.fs or {}

function _G.vim.fs.root(path, marker)
  for parent in _G.vim.fs.parents(path) do
    if _G._TEST_VARS.mock_fs[parent .. "/" .. marker] then
      return parent
    end
  end
  return nil
end

_G.vim.loop = _G.vim.loop or {}

function _G.vim.loop.fs_stat(path)
  local file = _G._TEST_VARS.mock_fs[path]
  if not file then
    return nil
  end
  return {
    mtime = file.mtime,
    size = file.size,
    ino = file.inode_number,
    uid = file.uid,
    gid = file.gid,
    mode = file.mode,
  }
end

_G.io = _G.io or {}

function _G.io.open(path, mode)
  if mode == "r" and _G._TEST_VARS.mock_fs[path] then
    local content = _G._TEST_VARS.mock_fs[path].content
    local lines = {}
    for s in content:gmatch("[^\r\n]+") do
      table.insert(lines, s)
    end
    return {
      _lines = lines,
      lines = function(self)
        local index = 0
        return function()
          index = index + 1
          return self._lines[index]
        end
      end,
      close = function() end
    }
  end
  return nil
end

describe("aiignore", function()
  local aiignore

  -- Before each test, reset the environment
  before_each(function()
    -- Reset the module's cache by requiring it again
    package.loaded['aiignore'] = nil
    aiignore = require('aiignore')

    -- Global test state
    _G._TEST_VARS = {
      current_buf = nil,
      file_paths = {},
      mock_fs = {}
    }
  end)

  after_each(function()
    -- Clear the test state
    _G._TEST_VARS = nil
    package.loaded['aiignore_spec'] = nil
  end)

  local function mkfile(path, content)
    content = content or ""
    _G._TEST_VARS.mock_fs[path] = {
      content = content,
      mtime = { sec = os.time(), nsec = 12345 },
      size = #content,
      inode_number = 123,
      uid = 1357,
      gid = 2468,
      mode = 644,
    }
  end

  local function mkbuffer(path)
    local bufnr = #_G._TEST_VARS.file_paths + 1
    _G._TEST_VARS.file_paths[bufnr] = path
    _G._TEST_VARS.current_buf = bufnr
    return bufnr
  end

  local function mkfile_and_buffer(path, content)
    mkfile(path, content)
    return mkbuffer(path)
  end

  it("should not ignore when no .aiignore file exists", function()
    mkfile("/tmp/my-project/.git")
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should not ignore when no .aiignore file exists without git", function()
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should not ignore if .aiignore is not in the same directory without git", function()
    mkfile("/tmp/my-project/.aiignore", "*")
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should ignore for unnamed buffers", function()
    mkfile_and_buffer("")
    assert.is_true(aiignore.should_ignore(1, { should_ignore_unnamed_buffers = true }))
    assert.is_false(aiignore.should_ignore(1, { should_ignore_unnamed_buffers = false }))
    assert.is_true(aiignore.should_ignore(1))
  end)

  it("should ignore invalid buffers", function()
    assert.is_true(aiignore.should_ignore(1234, { should_ignore_invalid_buffers = true }))
    assert.is_false(aiignore.should_ignore(1234, { should_ignore_invalid_buffers = false }))
    assert.is_true(aiignore.should_ignore(1234))
  end)

  it("should not ignore when .aiignore file is empty", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore")
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should ignore for a directly specified file", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "credentials.json")

    mkfile_and_buffer("/tmp/my-project/credentials.json")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/test/credentials.json")
    assert.is_true(aiignore.should_ignore(2))
  end)

  it("should ignore for given aiignore filenames", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "keys.json")
    mkfile("/tmp/my-project/.aiexclude", "secrets.json")

    local config = { aiignore_filename = { ".aiignore", ".aiexclude" } }

    mkfile_and_buffer("/tmp/my-project/keys.json")
    assert.is_true(aiignore.should_ignore(1, config))

    mkfile_and_buffer("/tmp/my-project/secrets.json")
    assert.is_true(aiignore.should_ignore(2, config))

    mkfile_and_buffer("/tmp/my-project/config.json")
    assert.is_false(aiignore.should_ignore(3, config))
  end)

  it("should ignore non-git repositiory when force_disable_if_not_in_git is set", function()
    mkfile("/tmp/my-project/.aiignore", "*.js")

    mkfile_and_buffer("/tmp/my-project/test.js")
    assert.is_true(aiignore.should_ignore(1, { force_disable_if_not_in_git = false }))
    assert.is_true(aiignore.should_ignore(1, { force_disable_if_not_in_git = true }))

    mkfile_and_buffer("/tmp/my-project/test.lua")
    assert.is_false(aiignore.should_ignore(2, { force_disable_if_not_in_git = false }))
    assert.is_true(aiignore.should_ignore(2, { force_disable_if_not_in_git = true }))
  end)

  it("should ignore for a file in an ignored directory", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "dist/")

    mkfile_and_buffer("/tmp/my-project/dist/bundle.js")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/sub/dist/bundle.js")
    assert.is_true(aiignore.should_ignore(2))
  end)

  it("should ignore for files matching a wildcard", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "*.log")

    mkfile_and_buffer("/tmp/my-project/app.log")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/logs/test.log")
    assert.is_true(aiignore.should_ignore(2))

    mkfile_and_buffer("/tmp/my-project/logs/.log")
    assert.is_true(aiignore.should_ignore(3))

    mkfile_and_buffer("/tmp/my-project/logs/not.logs")
    assert.is_false(aiignore.should_ignore(4))
  end)

  it("should not ignore for files that do not match patterns", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "*.log\ndist/")
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should handle root-anchored patterns correctly", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "/config.yml")

    -- This should be ignored
    mkfile_and_buffer("/tmp/my-project/config.yml")
    assert.is_true(aiignore.should_ignore(1))

    -- This should NOT be ignored
    mkfile_and_buffer("/tmp/my-project/src/config.yml")
    assert.is_false(aiignore.should_ignore(2))
  end)

  it("should ignore comments and empty lines in .aiignore", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", [[
# This is a comment
*.tmp

/secrets.txt
# *.lua
    ]])
    mkfile_and_buffer("/tmp/my-project/data.tmp")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/secrets.txt")
    assert.is_true(aiignore.should_ignore(2))

    -- should not ignore because the pattern is commented out
    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(3))
  end)

  it("should not ignore negated patterns", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", [[
*
!important.txt
]])

    mkfile_and_buffer("/tmp/my-project/ignored.txt")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/important.txt")
    assert.is_false(aiignore.should_ignore(2))
  end)

  it("should not ignore negated patterns even if they are stated again", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", [[
*
!important.txt
*
]])

    mkfile_and_buffer("/tmp/my-project/ignored.txt")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/important.txt")
    assert.is_false(aiignore.should_ignore(2))
  end)

  it("should accept .aiignore in nested directories", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/src/.aiignore", "secret.json")

    mkfile_and_buffer("/tmp/my-project/src/secret.json")
    assert.is_true(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/src/sub/secret.json")
    assert.is_true(aiignore.should_ignore(2))

    mkfile_and_buffer("/tmp/my-project/src/main.lua")
    assert.is_false(aiignore.should_ignore(3))
  end)

  it("should not accept .aiignore negate if the directory is ignored", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/src/.aiignore", "secret/")
    mkfile_and_buffer("/tmp/my-project/src/secret/.aiignore", "!secret.json")

    mkfile_and_buffer("/tmp/my-project/src/secret/secret.json")
    assert.is_true(aiignore.should_ignore(1))
  end)

  it("should accept patterns only if they are in same or parent directory", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/src/.aiignore", "secret.json")

    mkfile_and_buffer("/tmp/my-project/secret.json")
    assert.is_false(aiignore.should_ignore(1))
  end)

  it("should accept globstar in the leading position", function()
    mkfile("/tmp/my-project/.git")
    mkfile("/tmp/my-project/.aiignore", "**/somedir/secret.json")

    mkfile_and_buffer("/tmp/my-project/src/secret.json")
    assert.is_false(aiignore.should_ignore(1))

    mkfile_and_buffer("/tmp/my-project/src/somedir/secret.json")
    assert.is_true(aiignore.should_ignore(2))

    mkfile_and_buffer("/tmp/my-project/src/another/somedir/secret.json")
    assert.is_true(aiignore.should_ignore(3))
  end)
end)
