# Changelog

## 0.1.3 (dev)

## 0.1.2 (2025-07-13)

- Added support for priving an array of filenames for `aiignore_filename`
  configuration, e.g. `aiignore_filename = { ".aiexclude", ".aiignore" }`. When
  an array is provided, all of them will be checked while matching buffer
  paths. If any of the files exist, the buffer should be ignored.

## 0.1.1 (2025-07-12)

- Fixed typo in log when warning files not ignored.
- Small refactor in caching equivalence.

## 0.1.0 (2025-07-11)

- Initial release
