--- aiignore.nvim
---
--- A Neovim extension to prevent AI extensions from attaching to files listed in .aiignore.

local M = {}
local compat = require("aiignore.compat")
local parser = require("aiignore.parser")

--- Configuration for the plugin.
---
--- @class M.Config
--- @field aiignore_filename string|string[] The name(s) of the .aiignore file. Defaults to `.aiignore`. Also supports multiple names like `{ ".aiignore", ".aiiexclude", ".cursorignore" }`.
--- @field git_dirname string The name of the directory which will be used for finding a repository root. Defaults to `.git`.
--- @field warn_ignored boolean Whether to notify the user if the file is ignored. Defaults to `false`.
--- @field warn_not_ignored boolean Whether to notify the user if the file is not ignored. Defaults to `false`.
--- @field debug_log boolean Whether to log debug messages. Defaults to `false`.
--- @field quiet boolean Whether to ignore errors silently. Defaults to `false`.
--- @field should_ignore_invalid_buffers boolean Whether to ignore invalid buffers. Defaults to `true`.
--- @field should_ignore_unnamed_buffers boolean Whether to ignore unreadable buffers. Defaults to `true`.
M.Config = {}

--- Creates a new configuration object with default values.
---
--- @return M.Config config A new configuration object with default values.
function M.Config:new()
  --- @type M.Config
  local config = {
    aiignore_filename = ".aiignore",
    git_dirname = ".git",
    warn_ignored = false,
    warn_not_ignored = false,
    debug_log = false,
    quiet = false,
    should_ignore_invalid_buffers = true,
    should_ignore_unnamed_buffers = true,
  }
  setmetatable(config, self)
  self.__index = self
  return config
end

--- Merges another configuration object into this one.
---
--- @param other? M.Config The other configuration object to merge.
--- @return M.Config config A new configuration object with merged values.
function M.Config:merge(other)
  if not other then
    return self -- No other config to merge, return self
  end
  for k, v in pairs(other) do
    self[k] = v
  end
  return self
end

--- A pattern object representing a single line in the .aiignore file.
---
--- @class M.Pattern
--- @field path string The path to the .aiignore file this pattern references to.
--- @field lineno integer The line number of the pattern.
--- @field line string The original line string.
--- @field pattern PathPattern The parsed pattern expression.
--- @field negate boolean Whether the pattern is negated (i.e. starts with an exclamation mark '!').
--- @field only_directory boolean Whether the pattern matches only directories (i.e. ends with a slash '/').
--- @field no_directory boolean Whether the pattern matches only file names (i.e. does not contain any non-trailing slashes '/').
M.Pattern = {}

--- Creates a new pattern object from the given line in the .aiignore file.
---
--- @param path string The path to the .aiignore file.
--- @param lineno integer The line number in the .aiignore file.
--- @param line string The line from the .aiignore file.
--- @return M.Pattern?,string? pattern A new pattern object with the given properties, or nil if the line is empty or a comment. Second argument is an error message if the pattern could not be parsed.
function M.Pattern:new(path, lineno, line)
  if not line or line:match("^%s*$") then
    return nil -- Ignore empty lines
  end
  if line:match("^#") then
    return nil -- Ignore comments
  end

  local negate = false
  local pattern = line

  pattern = pattern:gsub("([^\\])%s*$", "%1")   -- Remove trailing spaces unless escaped
  pattern = pattern:gsub("\\(%s*)$", "%1")      -- Remove slash before trailing spaces

  local only_directory = pattern:sub(-1) == "/" -- Check if the pattern ends with a slash
  local no_directory =
      pattern:sub(1, -2):find("/") == nil       -- Check if the pattern does not contain any non-trailing slashes

  if pattern:sub(1, 1) == "!" then
    negate = true
    pattern = pattern:sub(2) -- Remove leading '!' for negated patterns
  elseif pattern:sub(1, 2) == "\\!" or pattern:sub(1, 2) == "\\#" then
    pattern = pattern:sub(2) -- Remove leading backslash for escaped '!' or '#'
  end

  pattern = pattern:gsub("^/", "") -- Remove the leading slash for relative patterns
  pattern = pattern:gsub("/$", "") -- Remove the trailing slash for directory patterns

  local parsed = parser.PARSER:match(pattern)
  if not parsed then
    return nil, "Failed to parse pattern: '" .. pattern .. "'"
  end

  --- @type M.Pattern
  local ret = {
    path = path,
    lineno = lineno,
    line = line,
    pattern = parsed,
    negate = negate,
    only_directory = only_directory,
    no_directory = no_directory,
  }
  setmetatable(ret, self)
  self.__index = self
  return ret
end

function M.Pattern:__tostring()
  return "Pattern@" ..
      self.path ..
      ":" ..
      self.lineno ..
      ": '" ..
      self.line ..
      "'" ..
      (self.negate and " [negated]" or "") ..
      (self.only_directory and " [only directory]" or "") ..
      (self.no_directory and " [no directory]" or "")
end

--- Checks the path against the pattern.
---
--- @param path string The path to check against the pattern.
--- @param is_directory boolean Whether the path is a directory (used to determine if the pattern matches only directories).
--- @param debug_log? boolean Whether to log debug messages. Defaults to false.
--- @return boolean match Returns true if the path matches the pattern, false otherwise.
function M.Pattern:match(path, is_directory, debug_log)
  if debug_log then
    vim.notify("Matching path '" .. path .. "' against pattern " .. tostring(self),
      vim.log.levels.DEBUG)
  end
  if self.only_directory and not is_directory then
    if debug_log then
      vim.notify("Path '" .. path .. "' is not a directory", vim.log.levels.DEBUG)
    end
    return false -- If the pattern matches only directories, the path must end with a slash
  end
  if self.no_directory then
    local basename = vim.fs.basename(path)
    local ret = self.pattern:match(basename) ~= nil
    if debug_log then
      vim.notify("Path '" .. path .. "' match result with basename '" .. basename .. "': " .. tostring(ret),
        vim.log.levels.DEBUG)
    end
    return ret
  end
  local relpath = compat.relpath(vim.fs.dirname(self.path), path)
  if relpath == nil then
    if debug_log then
      vim.notify("Failed to get relative path from '" .. self.path .. "' to '" .. path .. "'", vim.log.levels.DEBUG)
    end
    return false
  end
  local ret = self.pattern:match(relpath) ~= nil
  if debug_log then
    vim.notify("Path '" .. path .. "' match result with relative path '" .. relpath .. "': " .. tostring(ret),
      vim.log.levels.DEBUG)
  end
  return ret
end

--- A table to hold the parsed patterns from the .aiignore file.
---
--- @class CacheEntry
--- @field patterns M.Pattern[] A list of patterns parsed from the .aiignore file.
--- @field mtime_sec integer The last modification time in seconds.
--- @field mtime_nsec? integer The last modification time in nanoseconds (optional).
--- @field size integer The size of the file in bytes.
--- @field inode_number integer The inode number of the file.
--- @field uid integer The user ID of the file owner.
--- @field gid integer The group ID of the file owner.
--- @field mode integer The file mode.
local CacheEntry = {}

--- Creates a new cache entry with the given patterns and modification time.
---
--- @param patterns M.Pattern[] The list of patterns to cache.
--- @param mtime_sec integer The last modification time in seconds.
--- @param mtime_nsec integer? The last modification time in nanoseconds (optional).
--- @param size integer The size of the file in bytes.
--- @param inode_number integer The inode number of the file.
--- @param uid integer The user ID of the file owner.
--- @param gid integer The group ID of the file owner.
--- @param mode integer The file mode.
--- @return CacheEntry entry A new cache entry object with the given properties.
function CacheEntry:new(patterns, mtime_sec, mtime_nsec, size, inode_number, uid, gid, mode)
  --- @type CacheEntry
  local ret = {
    patterns = patterns,
    mtime_sec = mtime_sec,
    mtime_nsec = mtime_nsec,
    size = size,
    inode_number = inode_number,
    uid = uid,
    gid = gid,
    mode = mode,
  }
  setmetatable(ret, self)
  self.__index = self
  return ret
end

--- @class Timespec
--- @field sec integer The seconds part of the time.
--- @field nsec? integer The nanoseconds part of the time (optional).

--- @class FileStat
--- @field dev integer The device ID.
--- @field mode integer The file mode (permissions).
--- @field nlink integer The number of hard links.
--- @field uid integer The user ID of the file owner.
--- @field gid integer The group ID of the file owner.
--- @field rdev? integer The device ID (if special file).
--- @field ino integer The inode number.
--- @field size integer The size of the file in bytes.
--- @field blksize integer The block size for filesystem I/O.
--- @field blocks integer The number of blocks allocated for the file.
--- @field flags integer The file flags.
--- @field gen? integer The generation number (if applicable).
--- @field atime Timespec The last access time.
--- @field mtime Timespec The last modification time.
--- @field ctime Timespec The last status change time.
--- @field birthtime? Timespec The creation time (if available).
--- @field type string The file type (e.g., "file", "directory", etc.).

--- Checks if the cache entry matches the given file stat.
---
--- @param stat FileStat The file stat to compare against.
--- @return boolean match Returns true if the cache entry matches the file stat, false otherwise.
function CacheEntry:eq_stat(stat)
  return self.mtime_sec == stat.mtime.sec and
      self.mtime_nsec == stat.mtime.nsec and
      self.size == stat.size and
      self.inode_number == stat.ino and
      self.uid == stat.uid and
      self.gid == stat.gid and
      self.mode == stat.mode
end

--- Cache for loaded .aiignore patterns to avoid repeated file I/O.
---
--- @type { [string]: CacheEntry? }
local _global_cache = {}

--- Given a path, checks if the `.aiignore` file exists and returns its patterns.
---
--- @param path string The path to the directory where the .aiignore file is expected.
--- @return M.Pattern[]? patterns Returns a list of patterns from the .aiignore file, or nil if the file does not exist or the cache is outdated.
local function _check_cache(path)
  local entry = _global_cache[path]
  if not entry then
    return nil -- No cache entry found
  end
  --- @type FileStat?
  local file = vim.loop.fs_stat(path)
  if not file then
    return nil -- File does not exist or is not accessible
  end
  if not entry:eq_stat(file)
  then -- Invalidate cache if any of the file attributes have changed
    _global_cache[path] = nil
    return nil
  end
  return entry.patterns -- Return cached patterns otherwise
end

--- Adds a new entry to the cache or updates an existing one.
---
--- @param path string The path to the .aiignore file.
--- @param patterns M.Pattern[] The list of patterns to cache.
--- @param config M.Config The configuration object.
--- @return M.Pattern[]? patterns Returns the cached patterns if successful, or nil if the file does not exist.
local function _add_to_cache(path, patterns, config)
  local file = vim.loop.fs_stat(path)
  if not file then
    if not config.quiet then
      vim.notify(".aiignore file '" .. path .. "' does not exist or is not accessible", vim.log.levels.ERROR)
    end
    return nil
  end
  _global_cache[path] = CacheEntry:new(
    patterns, file.mtime.sec, file.mtime.nsec, file.size, file.ino, file.uid, file.gid, file.mode)
  return patterns
end

--- Given a path, returns the list of patterns from the .aiignore file.
---
--- @param path string The path to the .aiignore file.
--- @param config M.Config The configuration object.
--- @return M.Pattern[]? patterns A list of patterns from the .aiignore file, or nil if the file does not exist or is not readable.
local function _parse_aiignore_file(path, config)
  local patterns = _check_cache(path)
  if patterns then
    return patterns -- Return cached patterns if available
  end
  if not vim.fn.filereadable(path) then
    return nil -- File does not exist or is not readable
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  patterns = {}
  local lineno = 0
  for line in file:lines() do
    lineno = lineno + 1
    local pattern, err = M.Pattern:new(path, lineno, line)
    if pattern then
      table.insert(patterns, pattern)
    elseif err ~= nil and not config.quiet then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
  file:close()
  return _add_to_cache(path, patterns, config)
end

--- Matches a path against the patterns parsed from a .aiignore file.
---
--- @param path string The path to the file or directory to check.
--- @param is_directory boolean Whether the path is a directory (used to determine if the pattern matches only directories).
--- @param patterns M.Pattern[] The list of patterns to match against.
--- @param config M.Config The configuration object.
--- @return M.Pattern? pattern Returns the first matching pattern if the path should be ignored, nil otherwise.
local function _match_path_against_patterns(path, is_directory, patterns, config)
  local first_match = nil
  for _, pattern in ipairs(patterns) do
    if pattern:match(path, is_directory, config.debug_log) then
      if pattern.negate then
        if config.debug_log then
          vim.notify("Path '" .. path .. "' matches the negated pattern: " .. tostring(pattern),
            vim.log.levels.DEBUG)
        end
        return nil -- Negated pattern, do not ignore
      end
      if first_match == nil or pattern.lineno < first_match.lineno then
        if config.debug_log then
          vim.notify("Path '" .. path .. "' matches the pattern: " .. tostring(pattern), vim.log.levels.DEBUG)
        end
        first_match = pattern -- Found a matching pattern, keep the first one
      end
    end
  end
  return first_match -- Return the first matching pattern or nil if none matched
end

--- Returns if the path should be ignored based on the `.aiignore` patterns.
---
--- @param path string The (absolute) path to the file or directory to check.
--- @param config M.Config The configuration.
--- @return M.Pattern? pattern Returns the first matching pattern if the path should be ignored, nil otherwise.
function M.match_path(path, config)
  --- @type string[]
  local aiignore_filenames -- Coalesce to a list of filenames
  if type(config.aiignore_filename) == "string" then
    aiignore_filenames = { config.aiignore_filename --[[ @as string ]] }
  elseif type(config.aiignore_filename) == "table" then
    aiignore_filenames = config.aiignore_filename --[[ @as string[] ]]
  else
    if not config.quiet then
      vim.notify("Invalid aiignore_filename configuration: " .. vim.inspect(config.aiignore_filename),
        vim.log.levels.ERROR)
    end
    return nil -- Invalid configuration, do not ignore
  end

  --- @type string?
  local git_root = vim.fs.root(path, config.git_dirname)

  if config.debug_log then
    vim.notify("Inferred git root: '" .. (git_root or "none") .. "' for path '" .. path .. "'",
      vim.log.levels.DEBUG)
  end

  --- A list of paths to check, including necessary parent directories.
  --- @type string[]
  local paths = {}

  table.insert(paths, path) -- Start with the current path

  if not git_root then      -- If no git root is found, check the current directory only
    table.insert(paths, vim.fs.dirname(path))
  else
    if path:sub(1, #git_root) ~= git_root then
      if not config.quiet then
        vim.notify("Path '" .. path .. "' is not prefixed by the inferred git repository path '" .. git_root .. "'",
          vim.log.levels.ERROR)
      end
      return nil
    end

    for parent in vim.fs.parents(path) do -- Iterate through parent directories
      table.insert(paths, parent)
      if parent == git_root then          -- Stop at the git root
        break
      end
    end

    if paths[#paths] ~= git_root then -- Ensure that the last path is the git root
      if not config.quiet then
        vim.notify("The last path '" .. paths[#paths] .. "' is not the git root '" .. git_root .. "'",
          vim.log.levels.ERROR)
      end
      return nil
    end
  end

  if config.debug_log then
    vim.notify("Checking paths: " .. vim.inspect(paths) .. " for .aiignore patterns", vim.log.levels.DEBUG)
  end

  for i = #paths, 2, -1 do -- Iterate from the root until (and excluding) the current path
    for _, aiignore_filename in ipairs(aiignore_filenames) do
      local aiignore_path = paths[i] .. "/" .. aiignore_filename
      local patterns = _parse_aiignore_file(aiignore_path, config)
      if patterns then
        for j = i - 1, 1, -1 do -- Check all descendant paths against patterns
          if config.debug_log then
            vim.notify("Checking path '" .. paths[j] .. "' against patterns from '" .. aiignore_path .. "'",
              vim.log.levels.DEBUG)
          end
          local is_directory = j ~= 1
          local match = _match_path_against_patterns(paths[j], is_directory, patterns, config)
          if match then
            return match -- Return the first matching pattern found
          end
        end
      end
    end
  end

  if config.debug_log then
    vim.notify("No matching patterns found for path '" .. path .. "'", vim.log.levels.DEBUG)
  end

  return nil -- No patterns matched, do not ignore
end

--- The main function for determining if an AI extension should ignore a buffer.
---
--- Iterates through the buffer's directory and parents until it finds a git repository root.
--- Collects patterns from `.aiignore` files found in the git repository root or any subdirectories
--- leading to the buffer's path, and returns true if the buffer's path matches any patterns.
---
--- If the file opened in the buffer isn't in a git repository, only the `.aiignore` file in the
--- same directory with the buffer path is checked, if there is one.
---
--- The pattern rules follow [those used by `.gitignore`][pattern-format].
---
--- [pattern-format]: https://github.com/git/git/blob/v2.50.0/Documentation/gitignore.adoc#pattern-format
---
--- @param bufnr? integer The buffer number. Defaults to the current buffer if nil.
--- @param config? M.Config The configuration.
--- @return boolean should_ignore Returns true if AI extension should ignore buffer, false otherwise.
function M.should_ignore(bufnr, config)
  config = M.Config:new():merge(config)

  if not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    if (config.should_ignore_invalid_buffers and config.warn_ignored) or
        (not config.should_ignore_invalid_buffers and config.warn_not_ignored) then
      vim.notify("Buffer " .. bufnr .. " is not valid, " .. (config.should_ignore_invalid_buffers and "" or "NOT ")
        .. "ignored by aiignore", vim.log.levels.ERROR)
    end
    return config.should_ignore_invalid_buffers
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    if (config.should_ignore_unnamed_buffers and config.warn_ignored) or
        (not config.should_ignore_unnamed_buffers and config.warn_not_ignored) then
      vim.notify("Buffer " .. bufnr .. " has no path, " .. (config.should_ignore_unnamed_buffers and "" or "NOT ") ..
        "ignored by aiignore", vim.log.levels.WARN)
    end
    return config.should_ignore_unnamed_buffers
  end

  local match = M.match_path(path, config)
  if match then
    if config.warn_ignored then
      vim.notify("Buffer " .. bufnr .. " with path '" .. path .. "' is ignored by aiignore due to " .. tostring(match),
        vim.log.levels.WARN)
    end
    return true
  end

  if config.warn_not_ignored then
    vim.notify("Buffer " .. bufnr .. " with path '" .. path .. "' is NOT ignored by aiignore.", vim.log.levels.WARN)
  end
  return false
end

return M
