"""JakoScripts light-obf build (conservative, verifiable).

Produces the same shape as the original build:
    -- build: light obf | N locals renamed
    local _JS0 = ...
    ... "\x50\x6c\x61\x79\x65\x72\x73" ...

Renaming is done at NAME level, not scope level, which is what makes it safe
without a full parser:

  * every occurrence of a renamed name must sit in variable position — if the
    name is ever used as a field (`a.x`), method (`a:x()`), table key (`{x=1}`)
    or label (`::x::`), the whole name is left alone;
  * the name must be declared as a local (incl. `local function`, params and
    for-loop variables) and must never be defined as a global function;
  * a name of one variable maps to exactly one new identifier, everywhere.

Lua scoping makes that sound: renaming every occurrence of a name keeps each
scope's own `local` shadowing relation intact, because both the declaration and
its uses move together.

Verification lives outside (obf_diff.py + JakoScripts_check.py), and
ship_gists.py refuses to publish a build that fails either.

Usage:
    python light_obf_safe.py input.lua [-o out.lua] [--prefix _JS]
"""
import argparse
import re
import sys

TOKEN = re.compile(r"""
    (?P<long>\[(?P<eq>=*)\[.*?\](?P=eq)\])
  | (?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<num>\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>[+\-*/%^#=~<>{}()\[\];:,.?&|!]+)
  | (?P<ws>\s+)
  | (?P<other>.)
""", re.X | re.S)

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
    "until", "while", "continue", "export", "type", "typeof",
}
NEVER = KEYWORDS | {"self", "_ENV", "_G", "getgenv", "getrenv", "game", "script", "workspace"}


def tokenize(src):
    return [(m.lastgroup, m.group(0), m.start(), m.end()) for m in TOKEN.finditer(src)]


def decode_lua_string(tok):
    """Lua string literal -> bytes (what the string actually contains)."""
    if tok.startswith("["):
        eq = re.match(r"\[(=*)\[", tok).group(1)
        body = tok[len(eq) + 2:-(len(eq) + 2)]
        return body.encode("utf-8")
    body = tok[1:-1]
    out = bytearray()
    i = 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out += c.encode("utf-8")
            i += 1
            continue
        i += 1
        if i >= len(body):
            break
        e = body[i]
        simple = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11,
                  "\\": 92, '"': 34, "'": 39, "\n": 10}
        if e in simple:
            if e == "\n":
                i += 1
            else:
                out.append(simple[e])
                i += 1
            continue
        if e == "z":
            i += 1
            while i < len(body) and body[i] in " \t\r\n":
                i += 1
            continue
        if e == "x":
            out.append(int(body[i + 1:i + 3], 16))
            i += 3
            continue
        if e == "u" and body[i + 1:i + 2] == "{":
            j = body.index("}", i)
            out += chr(int(body[i + 2:j], 16)).encode("utf-8")
            i = j + 1
            continue
        if e.isdigit():
            j = i
            digits = ""
            while j < len(body) and body[j].isdigit() and len(digits) < 3:
                digits += body[j]
                j += 1
            out.append(int(digits) % 256)
            i = j
            continue
        out += body[i - 1:i + 1].encode("utf-8")
        i += 1
    return bytes(out)


def encode_hex(raw):
    if not raw:
        return '""'
    return '"' + "".join("\\x%02x" % b for b in raw) + '"'


def build(src, prefix):
    toks = tokenize(src)
    sig = [i for i, t in enumerate(toks) if t[0] not in ("ws", "comment")]
    pos_in_sig = {ti: k for k, ti in enumerate(sig)}

    def prev_sig(k):
        return toks[sig[k - 1]] if k > 0 else None

    def next_sig(k):
        return toks[sig[k + 1]] if k + 1 < len(sig) else None

    declared, global_defs, blocked = set(), set(), set()
    for k, ti in enumerate(sig):
        kind, text, _s, _e = toks[ti]
        if kind != "name":
            continue
        if text == "local":
            nxt = next_sig(k)
            if nxt and nxt[0] == "name" and nxt[1] == "function":
                after = next_sig(k + 2)
                if after:
                    declared.add(after[1])
                continue
            j = k + 1
            while j < len(sig):
                t = toks[sig[j]]
                if t[0] == "name":
                    declared.add(t[1])
                elif t[1] in (",",):
                    pass
                else:
                    break
                j += 1
                if j < len(sig) and toks[sig[j]][1] == ",":
                    j += 1
                else:
                    break
            continue
        if text == "function":
            nxt = next_sig(k)
            if nxt and nxt[0] == "name":
                p = prev_sig(k)
                if not (p and p[1] == "local"):
                    global_defs.add(nxt[1])
            # параметры
            j = k + 1
            while j < len(sig) and toks[sig[j]][1] != "(":
                j += 1
            depth = 0
            while j < len(sig):
                kind2, text2, _a, _b = toks[sig[j]]
                if text2 == "(":
                    depth += 1
                elif text2 == ")":
                    depth -= 1
                    if depth == 0:
                        break
                elif kind2 == "name" and depth == 1:
                    declared.add(text2)
                j += 1
            continue
        if text == "for":
            j = k + 1
            while j < len(sig) and toks[sig[j]][1] not in ("=", "in"):
                if toks[sig[j]][0] == "name":
                    declared.add(toks[sig[j]][1])
                j += 1

    # какие имена вообще встречаются и в каких позициях
    occ = {}
    for k, ti in enumerate(sig):
        kind, text, _s, _e = toks[ti]
        if kind != "name" or text in NEVER or text not in declared:
            continue
        p, n = prev_sig(k), next_sig(k)
        bad = False
        if p and p[1] in (".", ":"):
            bad = True                      # поле или метод
        if p and p[1] == "::" or (n and n[1] == "::"):
            bad = True                      # метка
        if p and p[1] in ("{", ",") and n and n[1] == "=":
            bad = True                      # ключ таблицы
        if text in global_defs:
            bad = True
        occ.setdefault(text, {"bad": False, "tokens": []})
        occ[text]["tokens"].append(ti)
        if bad:
            occ[text]["bad"] = True

    rename = {}
    n = 0
    for name in sorted(occ, key=lambda x: occ[x]["tokens"][0]):
        if occ[name]["bad"]:
            continue
        if name in KEYWORDS:
            continue
        rename[name] = f"{prefix}{n}"
        n += 1

    out = []
    for kind, text, _s, _e in toks:
        if kind == "comment":
            continue
        if kind == "name" and text in rename:
            out.append(rename[text])
        elif kind == "str":
            out.append(encode_hex(decode_lua_string(text)))
        elif kind == "long":
            out.append(encode_hex(decode_lua_string(text)))
        else:
            out.append(text)

    body = "".join(out).strip("\n")
    header = f"-- build: light obf | {n} locals renamed\n"
    return header + body + "\n", n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--out")
    ap.add_argument("--prefix", default="_JS")
    args = ap.parse_args()

    src = open(args.input, encoding="utf-8").read()
    text, n = build(src, args.prefix)
    if args.out:
        open(args.out, "w", encoding="utf-8", newline="\n").write(text)
        print(f"wrote {args.out} ({len(text)} bytes, {n} renamed locals)")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
