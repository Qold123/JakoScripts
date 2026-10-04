"""Compare a refactored script against its original: the logic must survive.

Only the UI layer is allowed to change. This prints what actually differs in the
regions that hold game logic (everything before the UI block, and the trailing
loop/print section), so an accidental logic edit cannot slip through review.

Usage:
    python verify_refactor.py <original.lua> <refactored.lua>
"""
import difflib
import re
import sys

UI_START_PATTERNS = [
    re.compile(r"(?m)^\s*--\s*=+\s*GUI"),
    re.compile(r'(?m)^.*Instance\.new\("ScreenGui"\)'),
    re.compile(r"(?m)^\s*local\s+function\s+(?:create)?toggle\("),
    re.compile(r"(?m)^\s*-- =+ VANTA STYLE A SHELL"),
    re.compile(r"(?m)^\s*local\s+StyleA\s*="),
]

UI_END_PATTERNS = [
    re.compile(r"(?m)^\s*--\s*=+\s*(?:LOOP|MAIN|CORE|ЛОГИКА)"),
    re.compile(r"(?m)^RunService\.\w+:Connect"),
    re.compile(r"(?m)^task\.spawn"),
    re.compile(r"(?m)^while true do"),
    re.compile(r"(?m)^\s*-- =+ LOOPS"),
]


def split_regions(text):
    start = None
    for p in UI_START_PATTERNS:
        m = p.search(text)
        if m and (start is None or m.start() < start):
            start = m.start()
    if start is None:
        return text, "", ""
    end = None
    for p in UI_END_PATTERNS:
        for m in p.finditer(text, start):
            if end is None or m.start() < end:
                end = m.start()
    if end is None:
        end = len(text)
    return text[:start], text[start:end], text[end:]


def main():
    orig_path, new_path = sys.argv[1], sys.argv[2]
    orig = open(orig_path, encoding="utf-8").read()
    new = open(new_path, encoding="utf-8").read()

    oh, _om, ot = split_regions(orig)
    nh, _nm, nt = split_regions(new)

    def norm(t):
        return [ln.rstrip() for ln in t.split("\n") if ln.strip()]

    print(f"=== {orig_path}  ->  {new_path}")
    for label, a, b in (("HEAD (логика до UI)", oh, nh), ("TAIL (циклы после UI)", ot, nt)):
        A, B = norm(a), norm(b)
        if label.startswith("TAIL"):
            A, B = A[-60:], B[-60:]
        diff = [d for d in difflib.unified_diff(A, B, lineterm="", n=0)
                if d[:1] in "+-" and d[:3] not in ("+++", "---")]
        print(f"-- {label}: {len(diff)} изменённых строк из {len(A)}")
        for d in diff[:40]:
            print("   " + d)
    print()


if __name__ == "__main__":
    main()
