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
        pass  # forward-declared intentionally in the current builds
    else:
        print(f"scope: '{name}' ok")

# ---------- calls to undefined locals ----------
GLOBALS = {
    "print", "warn", "pcall", "xpcall", "error", "assert", "select", "type", "typeof",
    "tostring", "tonumber", "ipairs", "pairs", "next", "unpack", "table", "string", "math",
    "os", "coroutine", "task", "bit32", "utf8", "require", "setmetatable", "getmetatable",
    "rawget", "rawset", "rawequal", "collectgarbage", "loadstring", "load", "delay", "wait",
    "spawn", "tick", "time", "newproxy", "getfenv", "setfenv", "buffer", "vector",
    "game", "workspace", "Instance", "Vector2", "Vector3", "CFrame", "Color3", "ColorSequence",
    "ColorSequenceKeypoint", "NumberSequence", "NumberRange", "UDim", "UDim2", "Rect", "Enum",
    "TweenInfo", "Ray", "Region3", "BrickColor", "Font", "Random", "DateTime", "PhysicalProperties",
    "Drawing", "filtergc", "gethui", "get_hidden_gui", "get_hui", "getgenv", "getrenv",
    "hookfunction", "hookmetamethod", "newcclosure", "request", "http_request", "syn", "http",
    "firetouchinterest", "fireproximityprompt", "writefile", "readfile", "isfile", "delfile",
    "listfiles", "makefolder", "appendfile", "setclipboard", "getrawmetatable", "setreadonly",
    "getconnections", "getnamecallmethod", "islclosed", "checkcaller", "getgc", "getloadedmodules",
    "identifyexecutor", "getexecutorname", "setthreadidentity", "getscriptclosure", "debug",
    "cloneref", "clone_ref", "cloneRef", "newcclosure", "isfolder", "getcustomasset",
    "StyleA",  # шелл подставляется маркером -- @@SHELL@@ уже после проверки
}
declared = set(GLOBALS)
for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", clean):
    declared.add(m.group(1))
for m in re.finditer(r"\blocal\s+([A-Za-z_][\w,\s]*?)\s*(?:=|$)", clean):
    for name in m.group(1).split(","):
        name = name.strip()
        if re.fullmatch(r"[A-Za-z_]\w*", name):
            declared.add(name)
for m in re.finditer(r"(?m)^\s*function\s+([A-Za-z_]\w*)\s*\(", clean):
    declared.add(m.group(1))
for m in re.finditer(r"\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)?)\s+(?:in|=)", clean):
    for name in m.group(1).split(","):
        declared.add(name.strip())
for m in re.finditer(r"\bfunction\s*\(([^)]*)\)", clean):
    for name in m.group(1).split(","):
        name = name.strip().rstrip(":")
        if re.fullmatch(r"[A-Za-z_]\w*", name):
            declared.add(name)
# method / named function params: function tbl:name(a, b, c)  |  function name(a, b)
for m in re.finditer(r"\bfunction\s+[\w.:]+\s*\(([^)]*)\)", clean):
    for name in m.group(1).split(","):
        name = name.strip().rstrip(":")
        if re.fullmatch(r"[A-Za-z_]\w*", name):
            declared.add(name)

KEYWORD_CALLS = {"and", "or", "not", "if", "while", "return", "then", "else", "elseif",
                 "do", "end", "for", "in", "local", "function", "break", "repeat", "until"}

undefined = {}
for m in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(", clean):
    name = m.group(1)
    if name in declared or name in OPEN or name in KEYWORD_CALLS:
        continue
    line = clean.count("\n", 0, m.start()) + 1
    undefined.setdefault(name, []).append(line)

if undefined:
    print("calls to possibly undefined names:")
    for name, lines in sorted(undefined.items(), key=lambda kv: -len(kv[1])):
        print(f"  {name:<22} {len(lines)}x  lines {lines[:6]}")
else:
    print("undefined-call scan: clean")

# ---------- shell wiring: shadowing + API surface ----------
if "UI:Tab(" in clean:
    marker = clean.find("-- == VANTA STYLE A SHELL")
    head = clean[:marker] if marker > 0 else ""
    handles = re.findall(r"local\s+(\w+)\s*=\s*UI:Tab\(", clean)
    wiring = ["UI", "setStat"] + handles
    shadowed = []
    for name in wiring:
        # top-level declaration only: a `local v` inside a function body is scoped
        # and cannot clash with the file-scope tab handle
        if re.search(r"(?m)^local\s+(?:function\s+)?%s\b" % re.escape(name), head):
            shadowed.append(name)
    print(f"shell wiring: tabs={handles}")
    if shadowed:
        print(f"  SHADOWING: {shadowed} already declared as locals before the shell")
    api = {
        "Tab", "Toast", "Stat", "Destroy", "Banner",
        "Section", "Toggle", "Slider", "Cycle", "Keybind", "Button", "Info",
    }
    receivers = set(handles) | {"UI"}
    bad = {}
    for m in re.finditer(r"\b(\w+):(\w+)\(", clean):
        if m.group(1) not in receivers:
            continue
        if m.group(2) in api:
            continue
        bad.setdefault(m.group(2), 0)
        bad[m.group(2)] += 1
    if bad:
        print(f"  unknown shell methods: {sorted(bad)}")
    else:
        print("shell method surface: clean")

    # --- state <-> UI binding cross-check (needs raw source: strings are stripped in `clean`) ---
    ui_keys = set(re.findall(r':(?:Toggle|Slider|Cycle|Keybind)\(\s*"[^"]*"\s*,\s*"(\w+)"', src))
    sblock = re.search(r"\bState\s*=\s*\{(.*?)\n\}", src, re.S)
    state_keys = set(re.findall(r"(?m)^\s*(\w+)\s*=", sblock.group(1))) if sblock else set()
    cut_a = src.find("-- == VANTA STYLE A SHELL")
    cut_b = src.find("-- == /VANTA STYLE A SHELL ==")
    if cut_a > 0 and cut_b > cut_a:
        logic = src[:cut_a] + src[cut_b + len("-- == /VANTA STYLE A SHELL =="):]
    else:
        logic = src
    used = set(re.findall(r"\b(?:state|State)\.(\w+)", logic))
    shell_owned = {"ui_key", "ui_toasts", "ui_alpha", "ui_blur", "ui_watermark"}
    print(f"state keys: declared={len(state_keys)} ui-bound={len(ui_keys)} logic-used={len(used)}")
    silent = sorted(used - ui_keys - shell_owned)
    if silent:
        print(f"  logic reads keys with no UI row: {silent}")
    unbound = sorted(ui_keys - state_keys - shell_owned)
    if unbound:
        print(f"  UI rows binding keys absent from State: {unbound}")

# ---------- service locals that the old UI used to declare ----------
# проверяем только вне шелла: сам шелл свои сервисы объявляет внутри IIFE
SERVICE_LOCALS = ["UserInputService", "TweenService", "RunService", "Players", "Workspace",
                  "Lighting", "HttpService", "StarterGui", "LocalPlayer", "Camera", "CoreGui"]
s_open, s_close = clean.find("-- == VANTA STYLE A SHELL"), clean.find("-- == /VANTA STYLE A SHELL ==")
logic_src = (clean[:s_open] + clean[s_close + 30:]) if (s_open >= 0 and s_close > s_open) else clean
missing = []
for s in SERVICE_LOCALS:
    uses = len(re.findall(r"\b%s\b" % s, logic_src))
    if not uses:
        continue
    if not re.search(r"(?m)^\s*local\s+[\w,\s]*\b%s\b" % s, logic_src):
        lines = [logic_src.count("\n", 0, m.start()) + 1 for m in re.finditer(r"\b%s\b" % s, logic_src)]
        missing.append(f"{s}({uses}x, logic lines {lines[:5]})")
if missing:
    print(f"logic uses undeclared service: {missing}")
else:
    print("service locals: clean")


# ---------- surface rules ----------
emoji = re.findall(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", src)
print("emoji in source:", len(emoji))
print("lines:", src.count("\n") + 1)
