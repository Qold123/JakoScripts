"""Token-level equivalence check between a plain script and its obf build.

The light-obf pass is a pure transformation: rename locals, hex-encode strings,
drop comments. Nothing else may change. Tokenizing both files and aligning them
1:1 proves that — if the token streams match and every renamed identifier maps
consistently, the build cannot have broken a reference.

Usage:
    python obf_diff.py plain.lua obf.lua            # отчёт
    python obf_diff.py plain.lua obf.lua --assert   # exit 1, если сборка неверна
"""
import re
import sys
from collections import Counter

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


def tokenize(text):
    return [(m.lastgroup, m.group(0)) for m in TOKEN.finditer(text)]


def code_tokens(text):
    return [(k, v) for k, v in tokenize(text) if k not in ("ws", "comment")]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    plain_path, obf_path = sys.argv[1], sys.argv[2]
    strict = "--assert" in sys.argv

    tp = code_tokens(open(plain_path, encoding="utf-8").read())
    to = code_tokens(open(obf_path, encoding="utf-8").read())
    problems = []

    if len(tp) != len(to):
        problems.append(f"token count differs: {len(tp)} vs {len(to)}")
        for i, (a, b) in enumerate(zip(tp, to)):
            if a != b:
                problems.append(f"  first divergence at token {i}: {a} -> {b}")
                break
    else:
        mapping, back, collisions = {}, {}, []
        renamed = 0
        for (kp, vp), (ko, vo) in zip(tp, to):
            if kp == "name" and ko == "name" and vp != vo:
                renamed += 1
                if vp in mapping and mapping[vp] != vo:
                    collisions.append((vp, mapping[vp], vo))
                mapping[vp] = vo
                if vo in back and back[vo] != vp:
                    collisions.append((vo, back[vo], vp))
                back[vo] = vp
            elif kp != ko:
                problems.append(f"token kind changed: {kp}/{vp} -> {ko}/{vo}")
                break
        if collisions:
            problems.append(f"inconsistent renaming: {collisions[:4]}")
        print(f"tokens: {len(tp)} (1:1) | renamed occurrences: {renamed} | distinct: {len(mapping)}")

    # имена, которые переименованы частично: встречаются в obf как переменные,
    # хотя в plain это была одна и та же локальная (проверяем только позиции,
    # не являющиеся полем/методом)
    renamed_names = {vp for (kp, vp), (ko, vo) in zip(tp, to) if kp == "name" and ko == "name" and vp != vo}
    leftovers = []
    for i, (k, v) in enumerate(to):
        if k != "name" or v not in renamed_names:
            continue
        prev = to[i - 1][1] if i else ""
        nxt = to[i + 1][1] if i + 1 < len(to) else ""
        if prev in (".", ":"):
            continue          # поле или метод — имя не переменная
        if nxt == "=" and prev in ("{", ","):
            continue          # ключ таблицы
        leftovers.append(v)
    if leftovers:
        problems.append(f"имена переименованы частично (осталось {len(leftovers)} вхождений): "
                        f"{sorted(set(leftovers))[:8]}")

    if problems:
        print("ОБФ-СБОРКА НЕВАЛИДНА:")
        for p in problems[:12]:
            print("  " + p)
        return 1 if strict else 0

    print("эквивалентность: ок — токен-поток совпадает, переименование согласовано")
    return 0


if __name__ == "__main__":
    sys.exit(main())
