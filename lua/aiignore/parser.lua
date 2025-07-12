--- This module parses .gitignore path patterns using [parsing expression grammar].
--- Output of the parser itself is also a parsing expression grammar that can be
--- used to match file paths corresponding to that particular path pattern. If
--- you find a bug in the parser, please report it. It's probably good idea to
--- check [the reference implementation] in git source code first.
---
--- [parsing expression grammar]: https://en.wikipedia.org/wiki/Parsing_expression_grammar
--- [the reference implementation]: https://github.com/git/git/blob/master/wildmatch.c

-- MIT License
--
-- Copyright (c) 2025 Omer Ozarslan
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

--- @class PathPattern
--- @field match fun(self: PathPattern, path: string): integer? Returns the whole string length if the path matches the pattern, or nil if it does not match.
---
--- @class PathPatternParser
--- @field match fun(self: PathPatternParser, pattern: string): PathPattern? Returns a pattern object if the pattern is valid, or nil if it is not.

local lpeg = require("lpeg")
local P, C, Ct, V, R, S = lpeg.P, lpeg.C, lpeg.Ct, lpeg.V, lpeg.R, lpeg.S

local SLASH = P("/")
local STAR = P("*")
local GLOB = P("**")
local WILDCARD = P("?")
local LEFT_BRACKET = P("[")
local RIGHT_BRACKET = P("]")
local DASH = P("-")
local ESCAPE = P("\\")
local CARET = P("^")
local END = P(-1)
local ANY = P(1)

local OP_NEGATE = "negate"
local CHAR_CLASSES = C("[[:" *
  (P("alnum") + "alpha" + "blank" + "cntrl" + "digit" + "graph" + "lower" + "print" + "punct" + "space" + "upper" + "xdigit") *
  ":]]")
local RANGE = C((ANY - RIGHT_BRACKET) * DASH * (ANY - RIGHT_BRACKET))
local ONEOF = CHAR_CLASSES + C(LEFT_BRACKET) * ((C(CARET) / OP_NEGATE) ^ -1 * (RANGE + C(ANY - RIGHT_BRACKET)) ^ 1) *
    C(RIGHT_BRACKET)
local NONSPECIAL = ANY - SLASH - STAR - WILDCARD - LEFT_BRACKET - ESCAPE
local NONGLOB = (C(STAR ^ 1) / "*" + C(WILDCARD) + ESCAPE * C(ANY) + C(NONSPECIAL ^ 1) + ONEOF) ^ 1

local PATTERN = Ct(C(SLASH) ^ -1 * P { "Pattern",
  Pattern =
      C(GLOB) * C(SLASH) ^ -1 * END +
      C(GLOB * SLASH) * V "Pattern" +
      NONGLOB * C(SLASH) ^ -1 * END +
      NONGLOB * C(SLASH) * V "Pattern",
})

local NONSLASH = 1 - SLASH

local function star_until(tail)
  return P { "S", S = tail + NONSLASH * V("S") }
end

local function glob_until(tail)
  return P { "G", G = tail + NONSLASH ^ 1 * SLASH * V("G") }
end

--- Compiles a list of tokens into a pattern that will match final paths.
---
--- @param toks string[]
--- @return PathPattern pattern Pattern that matches paths.
local function compile(toks)
  local MODE_NORMAL = "normal"
  local MODE_ONEOF = "oneof"
  --- @type "normal" | "oneof"
  local mode = MODE_NORMAL
  local patt = END
  local oneof_patt = nil

  for i = #toks, 1, -1 do
    local tok = toks[i]
    if mode == MODE_NORMAL then
      if tok == "**" then
        patt = ANY ^ 0 * patt -- This can happen only at the end
      elseif tok == "**/" then
        patt = glob_until(patt)
      elseif tok == "*" then
        patt = star_until(patt)
      elseif tok == "?" then
        patt = NONSLASH * patt
      elseif tok == "]" then
        mode = MODE_ONEOF
        oneof_patt = P(false)
      elseif tok == "[[:alnum:]]" then
        patt = R("az", "AZ", "09") * patt
      elseif tok == "[[:alpha:]]" then
        patt = R("az", "AZ") * patt
      elseif tok == "[[:blank:]]" then
        patt = S(" \t") * patt
      elseif tok == "[[:cntrl:]]" then
        patt = R("\0\031", "\127\127") * patt
      elseif tok == "[[:digit:]]" then
        patt = R("09") * patt
      elseif tok == "[[:graph:]]" then
        patt = R("\33\126") * patt
      elseif tok == "[[:lower:]]" then
        patt = R("az") * patt
      elseif tok == "[[:print:]]" then
        patt = R("\32\126") * patt
      elseif tok == "[[:punct:]]" then
        patt = R("\33\47", "\58\64", "\91\96", "\123\126") * patt
      elseif tok == "[[:space:]]" then
        patt = S(" \t\n\r\f\v") * patt
      elseif tok == "[[:upper:]]" then
        patt = R("AZ") * patt
      elseif tok == "[[:xdigit:]]" then
        patt = R("09", "af", "AF") * patt
      else
        assert(tok ~= nil, "Unexpected nil token in normal mode")
        patt = P(tok) * patt
      end
    elseif mode == MODE_ONEOF then
      if tok == "[" then
        patt = oneof_patt * patt
        oneof_patt = nil
        mode = MODE_NORMAL
      elseif tok == OP_NEGATE then
        oneof_patt = ANY - oneof_patt
      elseif tok:len() == 3 then
        assert(tok:sub(2, 2) == "-", "Invalid range token: " .. tok)
        oneof_patt = R(tok:sub(1, 1) .. tok:sub(3, 3)) + oneof_patt
      else
        assert(tok:len() == 1, "Invalid oneof token: " .. tok)
        oneof_patt = P(tok) + oneof_patt
      end
    else
      error("Unexpected mode: " .. mode)
    end
  end
  return patt * END
end

--- Compiles a glob pattern to a pattern that can be used to match file paths.
---
--- @type PathPatternParser
local PARSER = PATTERN / compile

return {
  PARSER = PARSER,
  PATTERN = PATTERN,
  compile = compile,
}
