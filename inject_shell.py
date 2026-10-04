"""Inline (or refresh) the Style A shell inside a refactored script.

Idempotent: an existing inlined block is stripped back to the `-- @@SHELL@@`
marker first, then the current StyleA_shell.lua is spliced in. That keeps every
script on one byte-identical shell, so a shell fix never has to be repeated
seven times by hand.

Usage:
    python inject_shell.py                 # all JakoScripts_*.lua in cwd
    python inject_shell.py file1 file2     # selected files
"""
import os
import re
import sys

SHELL = "StyleA_shell.lua"
MARK = "-- @@SHELL@@"
BANNER_OPEN = "-- == VANTA STYLE A SHELL — inline block, правки только в шапке =="
BANNER_CLOSE = "-- == /VANTA STYLE A SHELL =="
# маркер обязан быть отдельной строкой: литерал в комментарии не должен приниматься за точку вставки
MARK_LINE = re.compile(r"(?m)^[ \t]*--[ \t]*@@SHELL@@[ \t]*$")
# срезаем только собственный legacy-заголовок, а не любую строку со словом SHELL
STRAY = re.compile(r"(?m)^-- =+ VANTA STYLE A SHELL \(inline\) =+\s*\n?")


def shell_body():
    body = open(SHELL, encoding="utf-8").read().rstrip("\n")
    if body.startswith("--[["):
        end = body.find("]]")
        if end > 0:
            body = body[end + 2:].lstrip("\n")
    return body


def normalize_handles(src):
    """`local v = UI:Tab("Visuals", ...)` -> `local tabVisuals = ...`.

    Single-letter tab handles can shadow a logic local declared earlier in the
    file; prefixing them removes the whole class. Idempotent: already-prefixed
    handles are left alone.
    """
    pairs = re.findall(r'(?m)^local\s+(\w+)\s*=\s*UI:Tab\(\s*"(\w+)"', src)
    for handle, tab in pairs:
        if handle.startswith("tab"):
            continue
        new = "tab" + tab
        src = re.sub(r"(?m)^local\s+%s\s*=\s*UI:Tab\(" % re.escape(handle),
                     f"local {new} = UI:Tab(", src)
        src = re.sub(r"(?m)^%s:" % re.escape(handle), f"{new}:", src)
    return src


def process(path, body):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    had_block = BANNER_OPEN in src
    if had_block:
        start = src.find(BANNER_OPEN)
        end = src.find(BANNER_CLOSE) + len(BANNER_CLOSE)
        src = src[:start] + MARK + src[end:]
        src = STRAY.sub("", src)

    hits = MARK_LINE.findall(src)
    if not hits:
        return "no marker line, skipped"
    if len(hits) > 1:
        return f"ОТКАЗ: маркер встречается {len(hits)} раз отдельной строкой — вставка неоднозначна"

    block = f"{BANNER_OPEN}\n{body}\n{BANNER_CLOSE}"
    src = MARK_LINE.sub(lambda _m: block, src, count=1)
    src = normalize_handles(src)

    # после вставки в файле должно остаться ровно два баннера и ни одного маркера
    if MARK_LINE.search(src):
        return "ОТКАЗ: маркер остался после вставки"
    if src.count(BANNER_OPEN) != 1 or src.count(BANNER_CLOSE) != 1:
        return "ОТКАЗ: баннеры шелла продублированы"

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(src)
    return f"{'refreshed' if had_block else 'injected'} ({len(body)} chars shell)"


def main():
    body = shell_body()
    targets = sys.argv[1:]
    if not targets:
        targets = sorted(f for f in os.listdir(".")
                         if f.startswith("JakoScripts_") and f.endswith(".lua"))
    for t in targets:
        print(f"{t:<32} {process(t, body)}")


if __name__ == "__main__":
    main()
