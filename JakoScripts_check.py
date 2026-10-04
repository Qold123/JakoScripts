"""Structural sanity check for a Luau file.

Strips comments and string literals, then verifies that block keywords and
brackets balance. Also flags identifiers that are captured by a closure before
their local declaration exists (the classic "global lookup -> nil" trap).
"""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "vanta_mm2.lua"
src = open(PATH, encoding="utf-8").read()

# ---------- tokenizer: comments, strings, long strings ----------
out = []
i, n = 0, len(src)
line = 1
lines_kept = []
while i < n:
    ch = src[i]
    if ch == "\n":
        line += 1
        out.append(ch)
        i += 1
        continue
    # long bracket comment / string
    m = re.match(r"--\[(=*)\[", src[i:])
    if m:
        close = "]" + m.group(1) + "]"
        j = src.find(close, i)
        j = n if j < 0 else j + len(close)
        line += src.count("\n", i, j)
        out.append("\n" * src.count("\n", i, j))
        i = j
        continue
    if src.startswith("--", i):
        j = src.find("\n", i)
        i = n if j < 0 else j
        continue
    m = re.match(r"\[(=*)\[", src[i:])
    if m:
        close = "]" + m.group(1) + "]"
        j = src.find(close, i)
        j = n if j < 0 else j + len(close)
        out.append('""' + "\n" * src.count("\n", i, j))
        line += src.count("\n", i, j)
        i = j
        continue
    if ch in "\"'":
        j = i + 1
        while j < n:
            if src[j] == "\\":
                j += 2
                continue
            if src[j] == ch:
                break
            j += 1
        out.append('""')
        line += src.count("\n", i, j)
        i = j + 1
        continue
    out.append(ch)
    lines_kept.append(line)
    i += 1

clean = "".join(out)

# ---------- brackets ----------
pairs = {")": "(", "]": "[", "}": "{"}
stack = []
line_of = []
ln = 1
for ch in clean:
    if ch == "\n":
        ln += 1
    elif ch in "([{":
        stack.append((ch, ln))
    elif ch in ")]}":
        if not stack or stack[-1][0] != pairs[ch]:
            print(f"BRACKET MISMATCH: '{ch}' at line {ln}, stack top {stack[-1] if stack else None}")
            sys.exit(1)
        stack.pop()
if stack:
    print("UNCLOSED BRACKETS:", stack[:8])
    sys.exit(1)
print("brackets: balanced")

# ---------- block keywords ----------
OPEN = {"function", "if", "for", "while", "do", "repeat"}
# 'do' after for/while is part of the same block -> handled by counting 'do' only when standalone
tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", clean)
kw = []
for t in tokens:
    if t in OPEN or t in ("end", "until", "then", "else", "elseif"):
        kw.append(t)

depth = 0
maxdepth = 0
for idx, t in enumerate(kw):
    if t in ("function", "if", "for", "while"):
        depth += 1
        maxdepth = max(maxdepth, depth)
    elif t == "do":
        # 'do' opens a block only when not preceded by for/while on the same statement
        prev = kw[idx - 1] if idx else None
        if prev not in ("for", "while"):
            depth += 1
            maxdepth = max(maxdepth, depth)
    elif t == "repeat":
        depth += 1
        maxdepth = max(maxdepth, depth)
    elif t == "until":
        depth -= 1
    elif t == "end":
        depth -= 1
    if depth < 0:
        print("BLOCK UNDERFLOW near token index", idx)
        sys.exit(1)

print(f"blocks: final depth = {depth} (0 = balanced), max nesting = {maxdepth}")
if depth != 0:
    sys.exit(1)

# ---------- closure-before-local trap ----------
# a name is a hazard if it is referenced in a function body that appears before
# its 'local' declaration in the file
names = ["myChar", "myHRP", "myHum", "toast", "saveConfig", "loadConfig", "watermark"]
for name in names:
    decl = re.search(r"^\s*(?:local\s+(?:function\s+)?%s|function\s+%s)\b" % (name, name), clean, re.M)
    first_use = re.search(r"\b%s\b" % name, clean)
    if decl and first_use and first_use.start() < decl.start():
        head = clean[:decl.start()]
        print(f"note: '{name}' first referenced at char {first_use.start()}, declared at {decl.start()} "
              f"-> requires a forward declaration (check one exists)")
    else:
        print(f"scope: '{name}' ok")

# ---------- surface rules ----------
emoji = re.findall(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", src)
print("emoji in source:", len(emoji))
print("lines:", src.count("\n") + 1)
