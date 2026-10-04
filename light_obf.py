r"""light_obf.py - reproducer of the Vanta "light obf" build.

    python light_obf.py <input.lua> [-o out.lua] [--prefix _JS] [--check ref.lua]

The build is token preserving: the output has exactly the same code tokens as
the input, in the same order (1:1).  Only three things change:

  * every comment is dropped, and a generated header comment takes their place;
  * every local variable, `local function` name and function parameter becomes
    `<prefix><n>` with one contiguous 0..N-1 numbering;
  * every string literal is re-encoded as a double quoted run of lowercase hex
    escapes ("\xNN\xNN...") after the original escapes were decoded to bytes.

Numbering order is (rank, then declaration order inside the rank):

  rank 0  `local function f`   - numbered first, in order of appearance
  rank 1  every other binding  - `local x`, both forms of `for` variable
  rank 2  function parameters  - in order of appearance

Only bindings that are referenced somewhere take a number; an unused local or
loop variable consumes no slot.  A declaration counts as a reference to itself
(so `local f = function() end` still gets a number even if `f` is never called),
which is what the reference builds do.

Standard library only.
"""
import argparse
import re
import sys

# --------------------------------------------------------------------------
# lexer
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(r"""
    (?P<ws>[ \t\r\n\f\v]+)
  | (?P<lcomment>--\[(?P<eq1>=*)\[(?:.|\n)*?\](?P=eq1)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<eq2>=*)\[(?:.|\n)*?\](?P=eq2)\])
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<interp>`(?:\\.|[^`\\])*`)
  | (?P<num>0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?
           |\d+\.?\d*(?:[eE][+-]?\d+)?
           |\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>[-+*/%^#=~<>{}()\[\];:,.?&|@!]+)
  | (?P<other>.)
""", re.X | re.S)

TRIVIA = ("ws", "comment", "lcomment")

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
    "until", "while", "continue", "export", "type",
}
BLOCK_ENDERS = {"end", "else", "elseif", "until"}
EXPR_STOP = {"then", "do", "end", "else", "elseif", "until"}
STARTERS = {"local", "if", "while", "for", "repeat", "return", "break",
            "continue", "do", "function"}
# Tokens that may legitimately begin an *expression*.  Statement starters such
# as `if`, `local`, `return` are deliberately absent: `if` is only an expression
# where a value is expected (see value_position()).
WANT_VALUES = {"function", "nil", "true", "false", "not", "...", "-", "#",
               "(", "{", "[", "..."}
WANT_KINDS = ("name", "num", "string", "lstring", "interp")


def wants_expression(tok):
    if tok is None:
        return False
    if tok.kind == "name":
        return tok.value in WANT_VALUES or tok.value not in KEYWORDS
    return True                         # a literal / string is always a value
NOT_A_NAME = {"_", "nil", "true", "false"}
# tokens an expression may continue with across a line break
BINARY_CONT = {
    "+", "-", "*", "/", "//", "%", "^", "..", "==", "~=", "<", ">", "<=", ">=",
    "and", "or", "?", "..=", "+=", "-=", "*=", "/=", "%=", "^=", "|", "&",
}
OPENERS = {"(": ")", "[": "]", "{": "}"}
CLOSERS = {")", "]", "}"}


class Tok:
    __slots__ = ("kind", "value", "start", "end", "line")

    def __init__(self, kind, value, start, end, line):
        self.kind = kind
        self.value = value
        self.start = start
        self.end = end
        self.line = line

    def __repr__(self):
        return "Tok(%s,%r@%d)" % (self.kind, self.value, self.line)


def tokenize(src):
    """Every token, trivia included."""
    toks = []
    line = 1
    for m in TOKEN_RE.finditer(src):
        kind = m.lastgroup
        text = m.group(0)
        toks.append(Tok(kind, text, m.start(), m.end(), line))
        line += text.count("\n")
    return toks


def code_only(toks):
    return [t for t in toks if t.kind not in TRIVIA]


# --------------------------------------------------------------------------
# comment removal
# --------------------------------------------------------------------------

def strip_comments(src):
    """Drop every comment, together with the line a standalone comment owns.

    A comment that owns its physical line (nothing but whitespace before it on
    that line) also removes the line break in front of it, so the whole line
    disappears.  A trailing comment removes only itself and keeps its line
    break.  That is what makes vanta_wh.lua lose exactly 13 line breaks.
    """
    toks = tokenize(src)
    keep = bytearray(b"\x01") * len(src)
    for i, t in enumerate(toks):
        if t.kind not in ("comment", "lcomment"):
            continue
        prev_code = next((toks[j] for j in range(i - 1, -1, -1)
                          if toks[j].kind not in TRIVIA), None)
        prev_ws = toks[i - 1] if i > 0 and toks[i - 1].kind == "ws" else None
        last_break = None
        if prev_ws is not None:
            for m in re.finditer(r"\r\n|\n|\r", prev_ws.value):
                last_break = (prev_ws.start + m.start(), prev_ws.start + m.end())
        standalone = last_break is not None and (
            prev_code is None or prev_code.end <= last_break[0])
        keep[t.start:t.end] = b"\x00" * (t.end - t.start)
        if standalone:
            line_start = src.rfind("\n", 0, t.start) + 1
            keep[line_start:t.end] = b"\x00" * (t.end - line_start)
    out = []
    run = None
    for i, k in enumerate(keep):
        if k:
            if run is None:
                run = i
        elif run is not None:
            out.append(src[run:i])
            run = None
    if run is not None:
        out.append(src[run:])
    return "".join(out)


# --------------------------------------------------------------------------
# strings
# --------------------------------------------------------------------------

SIMPLE_ESC = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11,
              "\\": 92, '"': 34, "'": 39, "\n": 10}


def decode_short_string(text):
    body = text[1:-1]
    out = bytearray()
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if c != "\\":
            out.extend(c.encode("utf-8"))
            i += 1
            continue
        i += 1
        if i >= n:
            out.append(92)
            break
        e = body[i]
        if e in SIMPLE_ESC:
            out.append(SIMPLE_ESC[e])
            i += 1
        elif e == "x":
            m = re.match(r"[0-9a-fA-F]{1,2}", body[i + 1:])
            if not m:
                out.append(ord("x"))
                i += 1
                continue
            out.append(int(m.group(0), 16) & 0xFF)
            i += 1 + len(m.group(0))
        elif e == "z":
            i += 1
            while i < n and body[i] in " \t\r\n\f\v":
                i += 1
        elif e.isdigit():
            m = re.match(r"\d{1,3}", body[i:])
            out.append(int(m.group(0)) & 0xFF)
            i += len(m.group(0))
        elif e == "u" and body[i + 1:i + 2] == "{":
            j = body.find("}", i)
            if j < 0:
                out.extend(b"u")
                i += 1
            else:
                out.extend(chr(int(body[i + 2:j], 16)).encode("utf-8"))
                i = j + 1
        else:
            out.extend(e.encode("utf-8"))
            i += 1
    return bytes(out)


def decode_long_string(text):
    m = re.match(r"\[(=*)\[", text)
    eq = m.group(1)
    inner = text[2 + len(eq):len(text) - 2 - len(eq)]
    if inner.startswith("\r\n"):
        inner = inner[2:]
    elif inner.startswith("\n"):
        inner = inner[1:]
    return inner.encode("utf-8")


def encode_string(data):
    if not data:
        return '""'
    return '"' + "".join("\\x%02x" % b for b in data) + '"'


# --------------------------------------------------------------------------
# scope model
# --------------------------------------------------------------------------

class Binding:
    __slots__ = ("name", "rank", "order", "num", "used")

    def __init__(self, name, rank, order):
        self.name = name
        self.rank = rank
        self.order = order
        self.num = None
        self.used = False


class Scope:
    __slots__ = ("vars", "parent")

    def __init__(self, parent):
        self.vars = {}
        self.parent = parent

    def set(self, name, binding):
        self.vars[name] = binding

    def lookup(self, name):
        s = self
        while s is not None:
            b = s.vars.get(name)
            if b is not None:
                return b
            s = s.parent
        return None


# --------------------------------------------------------------------------
# parser
# --------------------------------------------------------------------------

class Parser:
    def __init__(self, toks):
        """`toks` must be comment/whitespace free (code_only)."""
        self.t = toks
        self.n = len(toks)
        self.i = 0
        self.bindings = []
        self.ref_map = {}           # id(token) -> Binding
        self.order = 0
        self.scopes = [Scope(None)]

    # ---- cursor ---------------------------------------------------------
    @property
    def scope(self):
        return self.scopes[-1]

    def peek(self, k=0):
        j = self.i + k
        return self.t[j] if j < self.n else None

    def val(self, k=0):
        t = self.peek(k)
        return t.value if t is not None else None

    def at(self, value, k=0):
        t = self.peek(k)
        return t is not None and t.value == value

    def next(self):
        t = self.t[self.i]
        self.i += 1
        self.note(t)
        return t

    def skip(self):
        """Advance without resolving (used for declarations and field names)."""
        t = self.t[self.i]
        self.i += 1
        return t

    # ---- bindings -------------------------------------------------------
    def note(self, tok):
        if tok.kind != "name" or tok.value in KEYWORDS or tok.value in NOT_A_NAME:
            return
        b = self.scope.lookup(tok.value)
        if b is None:
            return
        b.used = True
        self.ref_map[id(tok)] = b

    def new_binding(self, tok, rank, scope):
        b = Binding(tok.value, rank, self.order)
        self.order += 1
        self.bindings.append(b)
        scope.set(tok.value, b)
        self.ref_map[id(tok)] = b
        b.used = True               # a declaration references its own binding
        self.i += 1
        return b

    # ---- block ----------------------------------------------------------
    def parse_chunk(self):
        self.parse_block(self.scopes[0], set())

    def parse_block(self, scope, enders):
        self.scopes.append(scope)
        try:
            while True:
                t = self.peek()
                if t is None or t.value in enders or t.value in BLOCK_ENDERS:
                    return
                before = self.i
                self.parse_stmt(scope)
                if self.i <= before:        # defensive: never spin on one token
                    self.next()
        finally:
            self.scopes.pop()

    # ---- statements -----------------------------------------------------
    def parse_stmt(self, scope):
        t = self.peek()
        v = t.value
        if v == ";":
            self.next()
        elif v == "::":
            self.next()
            if self.peek() is not None and not self.at("::"):
                self.skip()                 # the label name
            if self.at("::"):
                self.next()
        elif v == "local":
            self.parse_local(scope)
        elif v == "function":
            self.parse_function_stmt(scope)
        elif v == "if":
            self.parse_if(scope)
        elif v == "while":
            self.next()
            self.read_expr({"do"})
            if self.at("do"):
                self.next()
            self.parse_block(Scope(scope), {"end"})
            if self.at("end"):
                self.next()
        elif v == "for":
            self.parse_for(scope)
        elif v == "repeat":
            self.next()
            inner = Scope(scope)
            self.parse_block(inner, {"until"})
            if self.at("until"):
                self.next()
            self.skip_expr()
        elif v == "do":
            self.next()
            self.parse_block(Scope(scope), {"end"})
            if self.at("end"):
                self.next()
        elif v == "return":
            self.next()
            nxt = self.peek()
            if nxt is None or nxt.value in BLOCK_ENDERS or nxt.value == ";":
                return
            self.read_expr(set())
            while self.at(","):
                self.next()
                self.read_expr(set())
        elif v in ("break", "continue"):
            self.next()
        elif v == "goto":
            self.next()
            if self.peek() is not None and self.peek().kind == "name":
                self.skip()
        else:
            self.skip_expr()

    def parse_local(self, scope):
        self.next()                         # local
        if self.at("function"):
            self.next()                     # function
            nt = self.peek()
            if nt is not None and nt.kind == "name":
                self.new_binding(nt, 0, scope)
            self.parse_function_body(scope)
            return
        names = []
        while True:
            t = self.peek()
            if t is None or t.kind != "name":
                break
            names.append(t)
            self.next()
            if self.at(":"):
                self.next()
                self.skip_type()
            if self.at(","):
                self.next()
                continue
            break
        for nt in names:
            if nt.value in NOT_A_NAME:
                continue
            self.new_binding(nt, 1, scope)
        if self.at("="):
            self.next()
            self.read_expr(set())
            while self.at(","):
                self.next()
                self.read_expr(set())

    def parse_function_stmt(self, scope):
        self.next()                         # function
        t = self.peek()
        if t is not None and t.kind == "name":
            self.skip()                     # the (global) function name
        while self.at(".") or self.at(":"):
            self.next()
            if self.peek() is not None:
                self.skip()                 # field / method part of the name
        self.parse_function_body(scope)

    def parse_function_body(self, parent):
        scope = Scope(parent)
        self.scopes.append(scope)
        try:
            if self.at("("):
                self.next()
                self.parse_params(scope)
            if self.at(":"):
                self.next()
                self.skip_type()
            self.parse_block(scope, {"end"})
            if self.at("end"):
                self.next()
        finally:
            self.scopes.pop()

    def parse_params(self, scope):
        while True:
            t = self.peek()
            if t is None or t.value == ")":
                break
            if t.kind == "name":
                if t.value in NOT_A_NAME:
                    self.next()
                else:
                    self.new_binding(t, 2, scope)
                if self.at(":"):
                    self.next()
                    self.skip_type()
            elif t.value == "...":
                self.next()
            else:
                self.next()
            if self.at(","):
                self.next()
        if self.at(")"):
            self.next()

    def parse_if(self, scope):
        self.next()                         # if
        self.read_expr({"then"})
        if self.at("then"):
            self.next()
        self.parse_block(scope, {"end", "else", "elseif"})
        while True:
            if self.at("elseif"):
                self.next()
                self.read_expr({"then"})
                if self.at("then"):
                    self.next()
                self.parse_block(scope, {"end", "else", "elseif"})
                continue
            if self.at("else"):
                self.next()
                self.parse_block(scope, {"end"})
            break
        if self.at("end"):
            self.next()

    def parse_for(self, scope):
        self.next()                         # for
        head = Scope(scope)
        names = []
        while True:
            t = self.peek()
            if t is None or t.kind != "name":
                break
            names.append(t)
            self.next()
            if self.at(":"):
                self.next()
                self.skip_type()
            if self.at(","):
                self.next()
                continue
            break
        for nt in names:
            if nt.value in NOT_A_NAME:
                continue
            self.new_binding(nt, 1, head)
        if self.at("=") or self.at("in"):
            self.next()
            self.read_expr({"do"})
            while self.at(","):
                self.next()
                self.read_expr({"do"})
        if self.at("do"):
            self.next()
        self.parse_block(head, {"end"})
        if self.at("end"):
            self.next()

    # ---- type annotations ----------------------------------------------
    def skip_type(self):
        """Consume a type annotation up to `=`, `,` or `)`."""
        while True:
            t = self.peek()
            if t is None:
                return
            if t.kind == "name":
                if t.value in ("and", "or", "not"):
                    return
                self.next()
                continue
            if t.kind == "op":
                if t.value.startswith("->"):
                    self.next()
                    continue
                if t.value in ("=", ",", ")", "}", ";"):
                    return
                self.next()
                continue
            if t.kind in ("string", "lstring"):
                self.next()
                continue
            return

    # ---- expressions ----------------------------------------------------
    def skip_expr(self):
        self.read_expr(set())

    def value_position(self, k=0):
        """True when the token at `k` sits where a value is expected.

        This is what tells a statement `if` apart from a Luau inline
        conditional expression (`x = if c then a else b`).
        """
        t = self.peek(k)
        if t is None:
            return False
        j = self.i + k - 1
        while j >= 0:
            prev = self.t[j]
            if prev.kind != "name":
                break
            if prev.value in ("return", "do", "then", "else", "elseif", "in"):
                return True
            break
        else:
            return True                     # very start of the chunk
        p = self.t[j] if j >= 0 else None
        if p is None:
            return True
        if p.kind == "op":
            if p.value.startswith(".") and not p.value.startswith(".."):
                return True
            if p.value.endswith(("=", "(", "[", "{", ",")) and p.value != "==":
                return True
            return False
        return False

    def read_expr(self, stop):
        """Read one expression.  `stop` lists the context keywords that end it."""
        stop = set(stop)
        first = self.peek()
        if not wants_expression(first):
            return                          # nothing expression-like here
        if first.value == "if" and not self.value_position():
            return                          # a statement `if`, not an expression
        depth = 0
        line = None
        while True:
            t = self.peek()
            if t is None:
                return
            if t.kind == "op":
                run = t.value
                if depth == 0:
                    if run[0] in ")]}," or ";" in run:
                        return              # the caller's closer / separator
                    if run[0] in OPENERS:
                        self.next()
                        for ch in run:
                            if ch in OPENERS:
                                depth += 1
                            elif ch in CLOSERS and depth:
                                depth -= 1
                        line = t.line
                        continue
                    if run[0] == "." and not run.startswith(".."):
                        self.next()         # field access: `.name` stays as is
                        nt = self.peek()
                        if nt is not None and nt.kind in ("name", "num"):
                            self.skip()
                        line = t.line
                        continue
                    if run[0] == ":" and not run.startswith("::"):
                        self.next()         # method call: `:name` stays as is
                        nt = self.peek()
                        if nt is not None and nt.kind == "name":
                            self.skip()
                        line = t.line
                        continue
                    self.next()
                    line = t.line
                    continue
                self.next()                 # an operator inside brackets
                for ch in run:
                    if ch in OPENERS:
                        depth += 1
                    elif ch in CLOSERS and depth:
                        depth -= 1
                line = t.line
                continue

            # name / literal / closure
            if depth == 0:
                if t.value in stop:
                    return
                if t.value in EXPR_STOP:
                    if line is None or t.line > line:
                        return
                    return
                if line is not None and t.line > line:
                    if t.value == "if" and not self.value_position():
                        return              # a statement `if`
                    if t.kind == "name" and t.value in STARTERS:
                        return
                    if t.value not in BINARY_CONT:
                        return              # a new statement, not a continuation
                if t.value == "if" and not self.value_position():
                    return
                if (t.kind == "name" and t.value not in KEYWORDS
                        and self.peek(1) is not None and self.peek(1).value == "="):
                    self.next()             # a table key / named argument
                    line = t.line
                    continue
            if t.value == "function":
                self.next()
                self.parse_function_body(self.scope)
                line = t.line
                continue
            if t.value == "if":
                self.parse_inline_if()
                line = t.line
                continue
            self.next()
            line = t.line

    def parse_inline_if(self):
        """Luau conditional expression: `if c then a elseif c2 then b else d`."""
        self.next()                         # if
        self.read_expr({"then"})
        if self.at("then"):
            self.next()
        self.read_expr({"else", "elseif"})
        while self.at("elseif"):
            self.next()
            self.read_expr({"then"})
            if self.at("then"):
                self.next()
            self.read_expr({"else", "elseif"})
        if self.at("else"):
            self.next()
            self.read_expr(set())


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

def build(src, prefix, header=True):
    """Return (text, number_of_renamed_locals)."""
    body = strip_comments(src)
    raw = tokenize(body)
    toks = code_only(raw)
    p = Parser(toks)
    p.parse_chunk()
    used = [b for b in p.bindings if b.used]
    used.sort(key=lambda b: (b.rank, b.order))
    for n, b in enumerate(used):
        b.num = n

    out = []
    last = 0
    for t in raw:
        b = p.ref_map.get(id(t))
        if b is not None:
            out.append(body[last:t.start])
            out.append(prefix + str(b.num))
            last = t.end
        elif t.kind in ("string", "lstring"):
            data = (decode_short_string(t.value) if t.kind == "string"
                    else decode_long_string(t.value))
            out.append(body[last:t.start])
            out.append(encode_string(data))
            last = t.end
    out.append(body[last:])
    text = "".join(out)
    if header:
        nl = "\r\n" if "\r\n" in src else "\n"
        text = ("-- build: light obf | %d locals renamed%s" % (len(used), nl)) + text
    return text, len(used)


# --------------------------------------------------------------------------
# token-stream verification
# --------------------------------------------------------------------------

def shape(tok):
    """Compare tokens ignoring names, but keeping the string re-encoding."""
    if tok.kind == "ws":
        return ("ws",)
    if tok.kind in ("string", "lstring"):
        return ("hex",)
    return (tok.kind, tok.value)


def verify(out_text, src, prefix):
    """Check that `out_text` is a rename-only transformation of `src`."""
    obf = tokenize(out_text)
    if obf and obf[0].kind == "comment":
        body = out_text[obf[0].end:]
    else:
        body = out_text
    a = code_only(tokenize(strip_comments(src)))
    b = code_only(tokenize(body))
    if len(a) != len(b):
        return "token count differs: %d -> %d" % (len(a), len(b))
    for i, (x, y) in enumerate(zip(a, b)):
        if x.kind == "name" and y.kind == "name":
            if x.value in KEYWORDS or x.value in NOT_A_NAME:
                if x.value != y.value:
                    return "keyword %r became %r at token %d" % (x.value, y.value, i)
                continue
            if y.value.startswith(prefix):
                continue
            if x.value != y.value:
                return "name %r became %r (no prefix) at token %d" % (x.value, y.value, i)
            continue
        if x.kind in ("string", "lstring") and y.kind == "string":
            if debug_string(x.value) != y.value:
                return "string %r encoded as %r at token %d" % (x.value[:40], y.value[:40], i)
            continue
        if shape(x) != shape(y):
            return "token %d changed: %r -> %r" % (i, x, y)
    return None


def debug_string(text):
    return encode_string(decode_short_string(text))


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description="light obf builder")
    ap.add_argument("input")
    ap.add_argument("-o", "--output")
    ap.add_argument("--prefix", default="_JS")
    ap.add_argument("--check", metavar="REFERENCE")
    ap.add_argument("--no-header", action="store_true")
    ap.add_argument("--no-verify", action="store_true")
    args = ap.parse_args(argv)

    src = open(args.input, encoding="utf-8", newline="").read()
    text, count = build(src, args.prefix, header=not args.no_header)
    data = text.encode("utf-8")

    if not args.no_verify:
        problem = verify(text, src, args.prefix)
        if problem:
            print("verify: FAILED - %s" % problem)
            return 2
        print("verify: token stream identical (1:1), %d renamed locals" % count)

    if args.output:
        with open(args.output, "wb") as f:
            f.write(data)
        print("wrote %s (%d bytes)" % (args.output, len(data)))
    elif not args.check:
        sys.stdout.buffer.write(data)

    if args.check:
        ref = open(args.check, "rb").read()
        if ref == data:
            print("check: MATCH byte-for-byte (%d bytes, %d renamed locals)"
                  % (len(data), count))
            return 0
        print("check: MISMATCH (built %d bytes, reference %d bytes)"
              % (len(data), len(ref)))
        n = min(len(data), len(ref))
        first = next((i for i in range(n) if data[i] != ref[i]), n)
        print("first difference at byte %d (line %d)" %
              (first, data.count(b"\n", 0, first) + 1))

        def line_of(buf, at):
            a = buf.rfind(b"\n", 0, at) + 1
            b = buf.find(b"\n", at)
            return buf[a:(len(buf) if b < 0 else b)]

        print("  built: %r" % line_of(data, first)[:200])
        print("  ref  : %r" % line_of(ref, first)[:200])
        bl, rl = data.split(b"\n"), ref.split(b"\n")
        diff = sum(1 for x, y in zip(bl, rl) if x != y) + abs(len(bl) - len(rl))
        print("  differing lines: %d (built %d lines, ref %d lines)"
              % (diff, len(bl), len(rl)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
