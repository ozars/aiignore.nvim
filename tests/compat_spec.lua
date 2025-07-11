local M = require("aiignore.compat") -- adjust

describe("relpath", function()
  local cases = {
    { "/home/u/project", "/home/u/project",                  "." },
    { "/home/u/project", "/home/u/project/file.txt",         "file.txt" },
    { "/home/u/project", "/home/u/project/sub/dir/file.lua", "sub/dir/file.lua" },
    { "/home/u/project", "/home/u/other/file.txt",           nil },
    { "/home/u/project", "/home/u/project2/file.txt",        nil },
    { "/",               "/usr/bin/env",                     "usr/bin/env" },
    { "/a/b",            "/a/b",                             "." },
    { "/a/b",            "/a/bc",                            nil },
    { "/a/b",            "/a/b/c/d",                         "c/d" },
    { "/usr/",           "/usr/lib",                         "lib" },
    { "/usr/",           "/usr/",                            "." },
    { "/usr/",           "/usr/local/bin",                   "local/bin" },
  }

  for _, c in ipairs(cases) do
    local base, target, expected = c[1], c[2], c[3]
    it(string.format("%s -> %s => %s", base, target, tostring(expected)), function()
      assert.are.equal(expected, M.relpath(base, target))
    end)
  end
end)
