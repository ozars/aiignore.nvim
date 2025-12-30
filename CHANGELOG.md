# Changelog

## 0.1.3 (dev)

- Fix handling of trailing slash following a glob in the parser.
- Added a new configuration option `force_disable_if_not_in_git` to control
  whether to automatically ignore buffers not in a git repository.

## 0.1.2 (2025-07-13)

- Added support for priving an array of filenames for `aiignore_filename`
  configuration, e.g. `aiignore_filename = { ".aiexclude", ".aiignore" }`. When
  an array is provided, all of them will be checked while matching buffer
  paths. If there are any matches in any files, the buffer should be ignored.

## 0.1.1 (2025-07-12)

- Fixed typo in log when warning files not ignored.
- Small refactor in caching equivalence.

## 0.1.0 (2025-07-11)

- Initial release
