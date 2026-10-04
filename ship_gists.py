"""Publish scripts into their gists: plain file and light-obf copy.

Each script lives in its own secret gist, and every gist holds two files —
`vanta_<name>.lua` (plain) and `vanta_<name>_obf.lua` (light obf build). The
injector links people paste point at those raw URLs, so after any redesign both
files have to be refreshed or the obf link keeps serving the old build.

Usage:
    python ship_gists.py                # собрать obf там, где его нет, и залить всё
    python ship_gists.py --check        # ничего не заливать, только сравнить размеры
    python ship_gists.py mm2 wh         # только выбранные
"""
import json
import os
import subprocess
import sys
import urllib.request

PY = sys.executable

# local file -> (gist id, remote plain name, remote obf name, title)
TARGETS = {
    "mm2":        ("JakoScripts.lua",            "d9426b0772256a4709608e96f710508d", "vanta_mm2.lua",          "vanta_mm2_obf.lua",          "MM2 v4.0"),
    "lostfront":  ("JakoScripts_lostfront.lua",  "de7c068ca91e534ed54f3e64d191483f", "vanta_lostfront.lua",    "vanta_lostfront_obf.lua",    "Lost Front v2.4"),
    "stealegg":   ("JakoScripts_stealegg.lua",   "5f6e4bcab0f3df2680a1944a29362b1a", "vanta_stealegg.lua",     "vanta_stealegg_obf.lua",     "Steal an Egg v2.1"),
    "bladeball":  ("JakoScripts_bladeball.lua",  "0ce0c7ccfe1655547e19253ab16138b2", "vanta_bladeball.lua",    "vanta_bladeball_obf.lua",    "Blade Ball v2.1"),
    "deagle":     ("JakoScripts_deagle.lua",     "f037386d8aac2c924d78bee6157c3f66", "vanta_deagle_duels.lua", "vanta_deagle_duels_obf.lua", "Deagle Duels v2"),
    "fpv":        ("JakoScripts_fpv_esp.lua",    "61316c34897c57a840d0e1bdd24724ef", "vanta_fpv_esp.lua",      "vanta_fpv_esp_obf.lua",      "FPV ESP v2"),
    "hitbox":     ("JakoScripts_hitbox.lua",     "61e8e91041a490a3e8f258cfbbcc51c7", "vanta_hitbox.lua",       "vanta_hitbox_obf.lua",       "Hitbox v2.1"),
    "wh":         ("JakoScripts_wh.lua",         "455138e3d75b17f9610507f66b7594aa", "vanta_wh.lua",           "vanta_wh_obf.lua",           "WH v2"),
}


def token():
    return subprocess.check_output(["gh", "auth", "token"], text=True).strip()


def api(url, payload=None):
    req = urllib.request.Request(
        url,
        method="PATCH" if payload else "GET",
        data=json.dumps(payload).encode() if payload else None,
        headers={
            "Authorization": "Bearer " + token(),
            "Accept": "application/vnd.github+json",
            "User-Agent": "JakoScripts",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def obf_path(plain_path, prefix):
    base = plain_path[:-4] if plain_path.endswith(".lua") else plain_path
    return f"{base}_obf.lua"


def run(cmd, timeout=180):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        class R:
            returncode, stdout, stderr = 124, "", f"timeout after {timeout}s"
        return R()


def checker_profile(path):
    """Собирает проблемы, которые видит структурная проверка (имена и сервисы)."""
    r = run([PY, "JakoScripts_check.py", path])
    out = r.stdout
    names, services = set(), set()
    section = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("calls to possibly undefined names:"):
            section = "names"
            continue
        if s.startswith("logic uses undeclared service:"):
            section = None
            for part in re.findall(r"([A-Za-z_]\w*)\(", s):
                services.add(part)
            continue
        if s and not s.startswith(("brackets", "blocks", "scope", "shell", "state", "service", "emoji", "lines", "  ")):
            section = None
        if section == "names" and s:
            names.add(s.split()[0])
    broken = ("MISMATCH" in out) or ("UNCLOSED" in out) or ("UNDERFLOW" in out)
    return names, services, broken


def verify_obf(plain, obf):
    """Обф-сборка не должна добавлять ни одной новой проблемы к обычной."""
    pn, ps, pbad = checker_profile(plain)
    on, os_, obad = checker_profile(obf)
    r = run([PY, "obf_diff.py", plain, obf, "--assert"])
    problems = []
    if obad or pbad:
        problems.append("структура файла сломана")
    new_names = sorted(on - pn)
    new_services = sorted(os_ - ps)
    if new_names:
        problems.append(f"новые неопределённые имена: {new_names[:6]}")
    if new_services:
        problems.append(f"потеряны объявления сервисов: {new_services[:6]}")
    if r.returncode != 0:
        problems.append("проверка эквивалентности не прошла: " + r.stdout.strip().splitlines()[-1][:120])
    return problems


def build_obf(plain_path, key, force=False):
    """Light-obf the plain file (locals renamed + strings hexed + comments dropped)."""
    out = obf_path(plain_path, key)
    if os.path.exists(out) and not force:
        return out
    if not os.path.exists("light_obf.py"):
        return None
    prefix = "_" + key[:2].upper()
    r = run([PY, "light_obf.py", plain_path, "-o", out, "--prefix", prefix])
    if r.returncode != 0:
        print(f"  obf build failed for {plain_path}: {r.stderr.strip()[:200]}")
        return None
    problems = verify_obf(plain_path, out)
    if problems:
        print(f"  obf ОТКЛОНЁН для {plain_path}:")
        for p in problems:
            print(f"    - {p}")
        os.remove(out)
        return None
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    check_only = "--check" in sys.argv
    force_obf = "--rebuild-obf" in sys.argv
    no_obf = "--no-obf" in sys.argv
    keys = args or list(TARGETS)

    for key in keys:
        if key not in TARGETS:
            print(f"unknown target: {key}")
            continue
        plain, gist_id, plain_name, obf_name, title = TARGETS[key]
        if not os.path.exists(plain):
            print(f"{key:<10} SKIP — нет файла {plain}")
            continue

        if check_only:
            existing_obf = obf_path(plain, key)
            files = {plain_name: plain}
            if os.path.exists(existing_obf):
                files[obf_name] = existing_obf
            info = api(f"https://api.github.com/gists/{gist_id}")
            for remote, local in files.items():
                cur = info["files"].get(remote, {}).get("size", -1)
                want = os.path.getsize(local)
                flag = "ok" if cur == want else f"РАСХОД (в гисте {cur})"
                print(f"{key:<10} {remote:<28} local={want:<7} {flag}")
            continue

        obf = None if no_obf else build_obf(plain, key, force=force_obf)
        files = {plain_name: plain}
        if obf and os.path.exists(obf):
            files[obf_name] = obf

        desc = f"JakoScripts {title} - VANTA Style A"
        payload = {"description": desc, "files": {}}
        for remote, local in files.items():
            payload["files"][remote] = {"content": open(local, encoding="utf-8").read()}
        res = api(f"https://api.github.com/gists/{gist_id}", payload)
        got = {n: f["size"] for n, f in res["files"].items() if n in files}
        sizes = ", ".join(f"{n}={s}" for n, s in got.items())
        print(f"{key:<10} {title:<18} -> {sizes}")


if __name__ == "__main__":
    main()
