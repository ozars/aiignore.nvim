local parser = require("aiignore.parser")
local PARSER = parser.PARSER

describe("PathPatternParser", function()
  local function assert_matches(pattern_str, path)
    local pattern = PARSER:match(pattern_str)
    assert.truthy(pattern, "Pattern '" .. pattern_str .. "' should be valid")
    assert.truthy(pattern:match(path),
      "Pattern '" .. pattern_str .. "' should match path '" .. path .. "'")
  end

  local function assert_not_matches(pattern_str, path)
    local pattern = PARSER:match(pattern_str)
    assert.truthy(pattern, "Pattern '" .. pattern_str .. "' should be valid")
    assert.falsy(pattern:match(path),
      "Pattern '" .. pattern_str .. "' should NOT match path '" .. path .. "'")
  end

  local function assert_invalid_pattern(pattern_str)
    assert.falsy(PARSER:match(pattern_str), "Pattern '" .. pattern_str .. "' should be invalid")
  end

  -- Test Suite for Basic Literal Matching
  describe("Basic Literal Matching", function()
    it("should match identical simple paths", function()
      assert_matches("a/b/c", "a/b/c")
    end)

    it("should not match different simple paths", function()
      assert_not_matches("a/b/c", "a/b/d")
    end)

    it("should not match if path is longer", function()
      assert_not_matches("a/b", "a/b/c")
    end)

    it("should not match if path is shorter", function()
      assert_not_matches("a/b/c", "a/b")
    end)

    it("should handle escaped characters", function()
      assert_matches("\\*/\\?/\\./\\[", "*/?/./[")
    end)
  end)

  -- Test Suite for '*' Wildcard
  describe("'*' Wildcard", function()
    it("should match any sequence of non-slash characters", function()
      assert_matches("a/*/c", "a/anything/c")
      assert_matches("a/b*", "a/b_and_more")
      assert_matches("*c", "abc")
    end)

    it("should not match across slashes", function()
      assert_not_matches("a/*/c", "a/b/d/c")
    end)

    it("should match empty segments", function()
      assert_matches("a/*/c", "a//c")
    end)

    it("should handle multiple stars", function()
      assert_matches("*/*", "a/b")
      assert_matches("a/*/*", "a/b/c")
      assert_not_matches("a/*/*", "a/b")
    end)
  end)

  -- Test Suite for '**' Glob
  describe("'**' Glob", function()
    it("should match zero or more directories", function()
      assert_matches("a/**/c", "a/c")
      assert_matches("a/**/c", "a/b/c")
      assert_matches("a/**/c", "a/x/y/z/c")
    end)

    it("should match everything if it is the only token", function()
      assert_matches("**", "a")
      assert_matches("**", "a/b/c")
      assert_matches("**", "")
    end)

    it("should match file prefixes", function()
      assert_matches("a/**", "a/b")
      assert_matches("a/**", "a/b/c.txt")
    end)

    it("should not match partial directory names", function()
      assert_not_matches("a/**/c", "a/b/cde")
      assert_matches("a/**/c", "a/bde/c")
    end)
  end)

  -- Test Suite for '?' Wildcard
  describe("'?' Wildcard", function()
    it("should match any single non-slash character", function()
      assert_matches("a/?/c", "a/b/c")
      assert_matches("a/b?", "a/bc")
    end)

    it("should not match a slash", function()
      assert_not_matches("?", "/")
    end)

    it("should not match an empty character", function()
      assert_not_matches("a/b?", "a/b")
    end)

    it("should handle multiple question marks", function()
      assert_matches("??", "ab")
      assert_matches("a/??/c", "a/xy/c")
      assert_not_matches("a/?/c", "a/xyz/c")
    end)
  end)

  -- Test Suite for Character Sets '[...]'
  describe("Character Sets '[...]'", function()
    it("should match any single character within the set", function()
      assert_matches("a/[abc]/c", "a/a/c")
      assert_matches("a/[abc]/c", "a/b/c")
      assert_matches("a/[abc]/c", "a/c/c")
    end)

    it("should not match characters outside the set", function()
      assert_not_matches("a/[abc]/c", "a/d/c")
    end)

    it("should handle ranges", function()
      assert_matches("[a-c]", "a")
      assert_matches("[a-c]", "b")
      assert_matches("[a-c]", "c")
      assert_not_matches("[a-c]", "d")
      assert_matches("file[0-9].txt", "file1.txt")
      assert_not_matches("file[0-9].txt", "filea.txt")
    end)

    it("should handle negated sets", function()
      assert_matches("[^abc]", "d")
      assert_not_matches("[^abc]", "a")
      assert_not_matches("[^abc]", "b")
    end)

    it("should handle negated ranges", function()
      assert_matches("[^a-c]", "d")
      assert_not_matches("[^a-c]", "b")
    end)

    it("should handle complex sets with multiple ranges and characters", function()
      assert_matches("[a-cx-z_!]", "a")
      assert_matches("[a-cx-z_!]", "y")
      assert_matches("[a-cx-z_!]", "_")
      assert_matches("[a-cx-z_!]", "!")
      assert_not_matches("[a-cx-z_!]", "d")
      assert_not_matches("[a-cx-z_!]", "w")
    end)
  end)

  -- Test Suite for POSIX-style Character Classes '[[:...:]]'
  describe("Character Classes '[[:...:]]'", function()
    it("should match alnum", function()
      assert_matches("[[:alnum:]]", "a")
      assert_matches("[[:alnum:]]", "5")
      assert_not_matches("[[:alnum:]]", "-")
    end)

    it("should match alpha", function()
      assert_matches("[[:alpha:]]", "Z")
      assert_not_matches("[[:alpha:]]", "9")
    end)

    it("should match digit", function()
      assert_matches("[[:digit:]]", "7")
      assert_not_matches("[[:digit:]]", "a")
    end)

    it("should match lower", function()
      assert_matches("[[:lower:]]", "x")
      assert_not_matches("[[:lower:]]", "X")
    end)

    it("should match upper", function()
      assert_matches("[[:upper:]]", "Y")
      assert_not_matches("[[:upper:]]", "y")
    end)

    it("should match space", function()
      assert_matches("a[[:space:]]b", "a b")
      assert_matches("a[[:space:]]b", "a\tb")
    end)

    it("should match xdigit", function()
      assert_matches("[[:xdigit:]]", "f")
      assert_matches("[[:xdigit:]]", "A")
      assert_matches("[[:xdigit:]]", "9")
      assert_not_matches("[[:xdigit:]]", "g")
    end)
  end)

  -- Test Suite for Mixed and Edge Cases
  describe("Mixed and Edge Cases", function()
    it("should handle complex combinations", function()
      assert_matches("src/**/*.[ch]", "src/core/main.c")
      assert_matches("src/**/*.[ch]", "src/utils/network/http.h")
      assert_not_matches("src/**/*.[ch]", "src/README.md")
      assert_matches("a/**b/c", "a/b/c")
    end)

    it("should handle patterns ending with a slash", function()
      assert_matches("a/", "a/")
      assert_matches("a/b/", "a/b/")
      assert_not_matches("a/b/", "a/b")
    end)

    it("should handle patterns starting with a slash", function()
      assert_matches("/a/b/c", "/a/b/c")
      assert_not_matches("/a/b/c", "a/b/c")
    end)

    it("should handle patterns with no slashes", function()
      assert_matches("a*c", "abc")
      assert_not_matches("a*c", "a/c")
    end)

    it("should correctly handle invalid patterns", function()
      assert_invalid_pattern("")
      assert_invalid_pattern("a[b") -- Unmatched bracket
    end)
  end)
end)
