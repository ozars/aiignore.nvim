local M = {}

--- Gets `target` path relative to `base`, or `nil` if `base` is not an ancestor.
---
--- @param base string Base path
--- @param target string Target path
--- @param opts table? Reserved for future use
--- @return string|nil path Relative path from `base` to `target`, or `nil` if `base` is not an ancestor of `target`.
function M.relpath(base, target, opts)
  if vim.fs and vim.fs.relpath then
    return vim.fs.relpath(base, target, opts)
  end

  local sep = '/'
  base, target = vim.fs.normalize(base), vim.fs.normalize(target)
  local blen = #base
  if target:sub(1, blen) ~= base then
    return nil -- base not ancestor
  end
  if base == sep then
    return target == sep and '.' or target:sub(2)
  end
  if #target == blen then
    return '.' -- same path
  end
  if target:sub(blen + 1, blen + 1) ~= sep then
    return nil -- base only partially matches
  end
  return target:sub(blen + 2)
end

return M
