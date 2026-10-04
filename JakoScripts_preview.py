"""JakoScripts — Style A mockup renderer.

Reads the UI wiring out of a refactored script (`UI:Tab(...)`, `v:Toggle(...)`,
`v:Slider(...)`) and renders the exact Style A shell at 2x, so a preview can
never drift from the code it documents.

Usage:
    python JakoScripts_preview.py JakoScripts_wh.lua [more.lua ...]
    python JakoScripts_preview.py --all
"""
import math
import os
import re
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2
WIN_W, WIN_H = 480 * S, 360 * S
SIDE = 150 * S
R = 12 * S
CANVAS = (1180, 1060)
WIN_XY = (110, 96)
FONTS = "C:/Windows/Fonts/"


def col(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


SURFACE, ACCENT, ACCENT_HI = col("06060B"), col("7C3AED"), col("C4B5FD")
ICON, TEXT, MUTED, DIM = col("A78BFA"), col("FFFFFF"), col("A1A1AA"), col("71717A")
W6, W8 = 0.06, 0.08
A_ROW, A_ROWLINE, A_BORDER = 0.031, 0.059, 0.110
A_HILITE, A_OFF, A_TRACK = 0.133, 0.118, 0.082

INTER = [f for f in os.listdir(FONTS) if f.lower().startswith("inter")] if os.path.isdir(FONTS) else []


def font(size, weight="reg"):
    if weight == "semi":
        cands = [FONTS + f for f in INTER if "semi" in f.lower() or "bold" in f.lower()]
        cands += [FONTS + "seguisb.ttf", FONTS + "arialbd.ttf"]
    elif weight == "med":
        cands = [FONTS + f for f in INTER if "medium" in f.lower()]
        cands += [FONTS + "segoeui.ttf", FONTS + "arial.ttf"]
    else:
        cands = [FONTS + f for f in INTER if "regular" in f.lower()]
        cands += [FONTS + "segoeui.ttf", FONTS + "arial.ttf"]
    for c in cands:
        try:
            return ImageFont.truetype(c, size)
        except Exception:
            continue
    return ImageFont.load_default()


F_LOGO, F_SUB = font(13 * S, "med"), font(9 * S, "med")
F_NAV, F_TITLE = font(12 * S, "med"), font(12 * S, "semi")
F_SECTION, F_ROW = font(10 * S, "semi"), font(12 * S, "reg")
F_VALUE, F_CHIP = font(11 * S, "semi"), font(10 * S, "semi")
F_HEX, F_NAME, F_CAP = font(11), font(10), font(12)
F_WM = font(10 * S, "med")
F_WM2 = font(10 * S, "semi")


# ---------------- hand specs (scripts whose UI is not the shell API) ----------------
HAND_SPECS = {
    "JakoScripts.lua": {
        "title": "MM2", "subtitle": "murder mystery 2", "version": "v3.0", "stat": "Innocent",
        "out": "JakoScripts_style_a_preview.png",
        "tabs": [
            {"name": "Combat", "icon": "target", "rows": [
                ("section", "aimbot"),
                ("toggle", "Aimbot", True), ("toggle", "Hold RMB only", True),
                ("toggle", "Visibility check", True),
                ("slider", "FOV", "150px", 0.24), ("slider", "Smooth", "25%", 0.25),
                ("cycle", "Aim part", "Head"),
                ("section", "auto"),
                ("toggle", "Auto shoot", False), ("toggle", "Auto equip tool", True),
                ("toggle", "Kill aura", False), ("slider", "Aura range", "10m", 0.29),
            ]},
            {"name": "Visuals", "icon": "eye", "rows": [
                ("section", "players"),
                ("toggle", "ESP murderer", True), ("toggle", "ESP sheriff", True),
                ("toggle", "ESP innocent", False), ("toggle", "Names + role", True),
                ("toggle", "Distance", True), ("toggle", "Health", True), ("toggle", "Tracers", False),
                ("section", "world"),
                ("toggle", "Item ESP", True), ("toggle", "Coins", True),
                ("toggle", "Dropped gun", True), ("toggle", "Fullbright", False),
            ]},
            {"name": "Movement", "icon": "zap", "rows": [
                ("section", "speed"),
                ("toggle", "Speed hack", False), ("slider", "Walk speed", "50", 0.25),
                ("toggle", "Higher jump", False), ("slider", "Jump power", "100", 0.25),
                ("toggle", "Noclip", False), ("toggle", "Infinite jump", False),
                ("section", "flight"),
                ("toggle", "Fly", False), ("slider", "Fly speed", "60", 0.22),
                ("section", "farm"),
                ("toggle", "Coin magnet", False), ("button", "Teleport to gun", True),
            ]},
            {"name": "Config", "icon": "settings", "rows": [
                ("section", "interface"),
                ("keybind", "Toggle key", "RightShift"),
                ("slider", "Panel opacity", "8%", 0.13),
                ("toggle", "Acrylic blur", True), ("toggle", "Watermark", True),
                ("toggle", "Notifications", True),
                ("section", "profile"),
                ("button", "Save config", False), ("button", "Load config", True),
                ("button", "Reset defaults", True),
                ("section", "session"), ("button", "Unload JakoScripts", True),
            ]},
        ],
    },
}


# ---------------- parsing ----------------
def parse_ui(path):
    src = open(path, encoding="utf-8").read()
    spec = {"title": "MM2", "subtitle": "", "version": "v3", "tabs": [], "stat": "—"}

    m = re.search(r"-- JakoScripts ([^|]+)\|", src)
    if m:
        spec["title"] = m.group(1).strip()
    m = re.search(r'title\s*=\s*"([^"]+)"', src)
    if m:
        spec["title"] = m.group(1)
    m = re.search(r'subtitle\s*=\s*"([^"]+)"', src)
    if m:
        spec["subtitle"] = m.group(1)
    m = re.search(r'version\s*=\s*"([^"]+)"', src)
    if m:
        spec["version"] = m.group(1)
    m = re.search(r'UI:Stat\(\s*"([^"]*)"', src)
    if m and m.group(1):
        spec["stat"] = m.group(1)

    # state defaults for sliders / cycles
    defaults = {}
    for m in re.finditer(r"(?m)^\s*([A-Za-z_]\w*)\s*=\s*(-?[\d.]+|true|false|\"[^\"]*\")\s*,?\s*$", src):
        defaults.setdefault(m.group(1), m.group(2))

    body = src
    cut = body.find("-- == /VANTA STYLE A SHELL ==")
    if cut >= 0:
        body = body[cut:]

    tabs = {}
    for m in re.finditer(r'local\s+(\w+)\s*=\s*UI:Tab\(\s*"([^"]+)"\s*,\s*"(\w+)"', body):
        tab = {"name": m.group(2), "icon": m.group(3), "rows": [], "at": m.start()}
        tabs[m.group(1)] = tab
        spec["tabs"].append(tab)

    # строки вкладок: вызовы могут быть многострочными (замыкания on_change)
    ROWS = [
        ("section", re.compile(r'(\w+):Section\(\s*"([^"]+)"')),
        ("info", re.compile(r'(\w+):Info\(\s*"([^"]+)"')),
        ("toggle", re.compile(r'(\w+):Toggle\(\s*"([^"]+)"\s*,\s*"(\w+)"\s*(?:,\s*(true|false))?')),
        ("slider", re.compile(r'(\w+):Slider\(\s*"([^"]+)"\s*,\s*"(\w+)"\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*(?:,\s*"([^"]*)")?')),
        ("cycle", re.compile(r'(\w+):Cycle\(\s*"([^"]+)"\s*,\s*"(\w+)"\s*,\s*\{([^}]*)\}')),
        ("keybind", re.compile(r'(\w+):Keybind\(\s*"([^"]+)"')),
        ("button", re.compile(r'(\w+):Button\(\s*(.+?)\s*,\s*"(\w+)"')),
    ]
    found = []
    for kind, rx in ROWS:
        for m in rx.finditer(body):
            h = m.group(1)
            if h not in tabs:
                continue
            found.append((m.start(), h, kind, m))
    found.sort(key=lambda t: t[0])

    for _pos, h, kind, m in found:
        rows = tabs[h]["rows"]
        if kind == "section":
            rows.append(("section", m.group(2)))
        elif kind == "info":
            rows.append(("info", m.group(2)))
        elif kind == "toggle":
            default = m.group(4)
            on = (default == "true") if default else (defaults.get(m.group(3), "false") == "true")
            rows.append(("toggle", m.group(2), on))
        elif kind == "slider":
            lo, hi = float(m.group(4)), float(m.group(5))
            try:
                val = float(defaults.get(m.group(3)))
            except (TypeError, ValueError):
                val = lo + (hi - lo) * 0.3
            ratio = 0 if hi == lo else max(0.0, min(1.0, (val - lo) / (hi - lo)))
            shown = f"{int(val)}" if (hi - lo) >= 10 else f"{val:g}"
            rows.append(("slider", m.group(2), shown + (m.group(6) or ""), ratio))
        elif kind == "cycle":
            opts = [o.strip().strip('"') for o in m.group(4).split(",") if o.strip()]
            rows.append(("cycle", m.group(2), opts[0] if opts else "—"))
        elif kind == "keybind":
            rows.append(("keybind", m.group(2), "RightShift"))
        elif kind == "button":
            label = re.sub(r'^"|"$', "", m.group(2))
            rows.append(("button", label, m.group(3) == "ghost"))

    spec["tabs"].sort(key=lambda t: t["at"])
    for t in spec["tabs"]:
        t.pop("at", None)
    return spec


# ---------------- drawing ----------------
def tracked_text(draw, xy, text, fnt, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + spacing
    return x - spacing


def rot_rect(cx, cy, w, h, deg):
    a = math.radians(deg)
    return [(cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a))
            for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]


def vgrad(size, c0, c1):
    w, h = size
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for i in range(w):
        t = i / max(1, w - 1)
        d.line([(i, 0), (i, h)], fill=tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(3)) + (255,))
    return g


def draw_icon(d, kind, cx, cy, color):
    if kind == "target":
        r = 5 * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=int(1.4 * S))
        dr, t = 1.5 * S, 0.7 * S
        d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=color)
        for box in ([cx - t, cy - 8 * S, cx + t, cy - 5.6 * S], [cx - t, cy + 5.6 * S, cx + t, cy + 8 * S],
                    [cx - 8 * S, cy - t, cx - 5.6 * S, cy + t], [cx + 5.6 * S, cy - t, cx + 8 * S, cy + t]):
            d.rectangle(box, fill=color)
    elif kind == "eye":
        w, h = 15 * S, 10 * S
        d.ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], outline=color, width=int(1.4 * S))
        r = 2 * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    elif kind == "zap":
        for ox, oy in ((1.6 * S, -2.4 * S), (-1.6 * S, 2.4 * S)):
            d.polygon(rot_rect(cx + ox, cy + oy, 1.7 * S, 9 * S, -22), fill=color)
        d.polygon(rot_rect(cx, cy, 6 * S, 1.7 * S, 0), fill=color)
    else:  # settings
        r = 5.5 * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=int(1.4 * S))
        dr = 1.6 * S
        d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=color)
        for i in range(8):
            a = math.radians(i * 45)
            d.polygon(rot_rect(cx + math.cos(a) * 6.4 * S, cy + math.sin(a) * 6.4 * S,
                               1.8 * S, 3.4 * S, i * 45), fill=color)


def render(spec, out_path):
    scene = Image.new("RGB", CANVAS, (9, 9, 16))
    sd = ImageDraw.Draw(scene, "RGBA")
    for i in range(CANVAS[1]):
        t = i / CANVAS[1]
        sd.line([(0, i), (CANVAS[0], i)],
                fill=(int(10 + 14 * (1 - t)), int(9 + 8 * (1 - t)), int(20 + 26 * (1 - t)), 255))
    sd.ellipse([620, 60, 1180, 520], fill=(124, 58, 237, 120))
    sd.ellipse([80, 480, 620, 1060], fill=(56, 92, 220, 90))
    sd.ellipse([700, 620, 1120, 1040], fill=(196, 181, 253, 55))
    scene = Image.blend(scene.filter(ImageFilter.GaussianBlur(28)), Image.new("RGB", CANVAS, (6, 6, 11)), 0.30)
    canvas = scene.convert("RGBA")

    x, y = WIN_XY
    glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [x - 22 * S, y - 22 * S, x + WIN_W + 22 * S, y + WIN_H + 22 * S],
        radius=28 * S, fill=ACCENT[:3] + (44,))
    canvas = Image.alpha_composite(canvas, glow.filter(ImageFilter.GaussianBlur(18 * S)))

    box = [x, y, x + WIN_W, y + WIN_H]
    shell = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shell).rounded_rectangle(box, radius=16 * S, fill=SURFACE[:3] + (int((1 - W8) * 255),))
    canvas = Image.alpha_composite(canvas, shell)

    win = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(win)
    d.rounded_rectangle(box, radius=16 * S, outline=(255, 255, 255, int(A_BORDER * 255)), width=max(1, S))
    d.rounded_rectangle([x + 16 * S, y, x + WIN_W - 16 * S, y + S], radius=S, fill=(255, 255, 255, int(A_HILITE * 255)))

    # sidebar
    d.rounded_rectangle([x, y, x + SIDE, y + WIN_H], radius=16 * S, fill=(255, 255, 255, int(W6 * 255)))
    d.rectangle([x + SIDE - 16 * S, y + 16 * S, x + SIDE, y + WIN_H - 16 * S], fill=(255, 255, 255, int(W6 * 255)))
    d.rectangle([x + SIDE, y + 12 * S, x + SIDE + S - 1, y + WIN_H - 12 * S], fill=(255, 255, 255, int(A_ROWLINE * 255)))
    tracked_text(d, (x + 16 * S, y + 14 * S), "— JAKO", F_LOGO, TEXT, 3 * S)
    tracked_text(d, (x + 16 * S, y + 38 * S), "SCRIPTS", F_SUB, ICON, 3 * S)
    d.text((x + 16 * S, y + 56 * S), (spec["subtitle"] or spec["title"]).upper()[:20], font=F_SUB, fill=DIM)

    ny = y + 84 * S
    for i, tab in enumerate(spec["tabs"]):
        active = (i == 0)
        wx, wy = x + 6 * S + 14 * S, ny + 19 * S
        if active:
            d.rounded_rectangle([wx - 14 * S, wy - 14 * S, wx + 14 * S, wy + 14 * S],
                                radius=9 * S, fill=(255, 255, 255, int(W8 * 255)))
            d.rounded_rectangle([x + 8 * S, ny + 10 * S, x + 10 * S, ny + 28 * S], radius=S, fill=ACCENT)
        draw_icon(d, tab["icon"], wx, wy, ICON if active else DIM)
        d.text((x + 48 * S, wy - 8 * S), tab["name"], font=F_NAV, fill=TEXT if active else DIM)
        ny += 44 * S

    fy = y + WIN_H - 46 * S
    d.rounded_rectangle([x + 12 * S, fy, x + 70 * S, fy + 22 * S], radius=7 * S,
                        fill=(255, 255, 255, int(A_TRACK * 255)),
                        outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
    kw = d.textlength("RSHIFT", font=F_CHIP)
    d.text((x + 12 * S + (58 * S - kw) / 2, fy + 4 * S), "RSHIFT", font=F_CHIP, fill=MUTED)
    vw = d.textlength(spec["version"] + " · STYLE A", font=F_SUB)
    d.text((x + SIDE - 12 * S - vw, fy + 5 * S), spec["version"] + " · STYLE A", font=F_SUB, fill=DIM)

    first = spec["tabs"][0]["name"].upper() if spec["tabs"] else "—"
    d.text((x + SIDE + 16 * S, y + 18 * S), first, font=F_TITLE, fill=TEXT)
    stat = [x + WIN_W - 34 * S - 132 * S, y + 16 * S, x + WIN_W - 34 * S, y + 38 * S]
    d.rounded_rectangle(stat, radius=8 * S, fill=(255, 255, 255, int(A_TRACK * 255)),
                        outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
    d.ellipse([stat[0] + 9 * S, stat[1] + 8 * S, stat[0] + 15 * S, stat[1] + 14 * S], fill=ACCENT)
    d.text((stat[0] + 20 * S, stat[1] + 5 * S), spec.get("stat", "—")[:18], font=F_CHIP, fill=MUTED)
    mw = d.textlength("—", font=F_TITLE)
    d.text((x + WIN_W - 34 * S + (22 * S - mw) / 2, y + 17 * S), "—", font=F_TITLE, fill=DIM)

    canvas = Image.alpha_composite(canvas, win)

    # watermark
    wm = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    wd = ImageDraw.Draw(wm)
    wmx, wmy, WM_W, WM_H = 16, 16, 200 * S, 26 * S
    wd.rounded_rectangle([wmx, wmy, wmx + WM_W, wmy + WM_H], radius=10 * S,
                         fill=(255, 255, 255, int(W8 * 255)),
                         outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
    end = tracked_text(wd, (wmx + 12 * S, wmy + 7 * S), "— JAKO", F_WM, TEXT, 2 * S)
    wd.text((end + 8 * S, wmy + 7 * S), "SCRIPTS", font=F_WM2, fill=ICON)
    tw = wd.textlength(spec["title"], font=F_SUB)
    wd.text((wmx + WM_W - 12 * S - tw, wmy + 8 * S), spec["title"], font=F_SUB, fill=MUTED)
    canvas = Image.alpha_composite(canvas, wm)

    # content
    content = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    cd = ImageDraw.Draw(content)
    CX = x + SIDE + 16 * S
    CW = WIN_W - SIDE - 32 * S
    C_TOP, C_BOT = y + 48 * S, y + WIN_H - 14 * S
    cy = C_TOP

    def row_box(h):
        nonlocal cy
        b = [CX, cy, CX + CW, cy + h]
        cd.rounded_rectangle(b, radius=R, fill=(255, 255, 255, int(A_ROW * 255)),
                             outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
        cy += h + 8 * S
        return b

    rows = spec["tabs"][0]["rows"] if spec["tabs"] else []
    for row in rows:
        if cy > C_BOT:
            break
        kind = row[0]
        if kind == "section":
            tracked_text(cd, (CX, cy + 4 * S), row[1].upper(), F_SECTION, DIM, 4 * S)
            cy += 30 * S
        elif kind == "info":
            b = row_box(34 * S)
            cd.text((b[0] + 14 * S, b[1] + 9 * S), row[1][:44], font=F_ROW, fill=DIM)
        elif kind == "toggle":
            b = row_box(40 * S)
            cd.text((b[0] + 14 * S, b[1] + 12 * S), row[1], font=F_ROW, fill=TEXT if row[2] else MUTED)
            pw, ph = 34 * S, 18 * S
            px, py = b[2] - 48 * S, b[1] + (40 * S - ph) / 2
            if row[2]:
                cd.rounded_rectangle([px, py, px + pw, py + ph], radius=ph / 2, fill=ACCENT)
                cd.ellipse([px + pw - 16 * S, py + 2 * S, px + pw - 2 * S, py + ph - 2 * S], fill=(255, 255, 255))
            else:
                cd.rounded_rectangle([px, py, px + pw, py + ph], radius=ph / 2, fill=(255, 255, 255, int(A_OFF * 255)))
                cd.ellipse([px + 2 * S, py + 2 * S, px + 16 * S, py + ph - 2 * S], fill=(255, 255, 255))
        elif kind == "slider":
            b = row_box(54 * S)
            cd.text((b[0] + 14 * S, b[1] + 7 * S), row[1], font=F_ROW, fill=MUTED)
            vwidth = cd.textlength(row[2], font=F_VALUE)
            cd.text((b[2] - 14 * S - vwidth, b[1] + 8 * S), row[2], font=F_VALUE, fill=ICON)
            tx0, tx1 = b[0] + 14 * S, b[2] - 14 * S
            ty = b[1] + 38 * S
            cd.rounded_rectangle([tx0, ty - 2 * S, tx1, ty + 2 * S], radius=2 * S, fill=(255, 255, 255, int(A_TRACK * 255)))
            fw = (tx1 - tx0) * row[3]
            if fw > 1:
                strip_ = vgrad((int(fw), int(4 * S)), ACCENT, ACCENT_HI)
                content.paste(strip_, (int(tx0), int(ty - 2 * S)), strip_)
            kx = tx0 + fw
            cd.ellipse([kx - 6 * S, ty - 6 * S, kx + 6 * S, ty + 6 * S], fill=(255, 255, 255))
        elif kind in ("cycle", "keybind"):
            b = row_box(40 * S)
            cd.text((b[0] + 14 * S, b[1] + 12 * S), row[1], font=F_ROW, fill=MUTED)
            bw, bh = 104 * S, 24 * S
            bx, by = b[2] - 116 * S, b[1] + (40 * S - bh) / 2
            cd.rounded_rectangle([bx, by, bx + bw, by + bh], radius=8 * S,
                                 fill=(255, 255, 255, int(A_TRACK * 255)),
                                 outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
            vwidth = cd.textlength(row[2], font=F_CHIP)
            cd.text((bx + (bw - vwidth) / 2, by + 5 * S), row[2], font=F_CHIP, fill=ICON if kind == "cycle" else MUTED)
        elif kind == "button":
            b = row_box(34 * S)
            ghost = row[2]
            cd.rounded_rectangle(b, radius=R, fill=(255, 255, 255, int((A_ROW if ghost else 1.0) * 255)),
                                 outline=(255, 255, 255, int(A_ROWLINE * 255)) if ghost else None, width=max(1, S))
            vwidth = cd.textlength(row[1], font=F_CHIP)
            cd.text((b[0] + (CW - vwidth) / 2, b[1] + 9 * S), row[1], font=F_CHIP,
                    fill=MUTED if ghost else col("09090B"))

    mask = Image.new("L", CANVAS, 0)
    ImageDraw.Draw(mask).rectangle([CX, C_TOP, CX + CW + 10 * S, C_BOT], fill=255)
    content.putalpha(Image.composite(content.getchannel("A"), Image.new("L", CANVAS, 0), mask))
    canvas = Image.alpha_composite(canvas, content)

    # palette strip
    strip = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(strip)
    sx, sy = x, y + WIN_H + 44
    swatches = [("#06060B", "surface"), ("#FFFFFF08", "row bg"), ("#FFFFFF0F", "row border"),
                ("#FFFFFF1C", "border"), ("#FFFFFF22", "highlight"), ("#7C3AED", "accent"),
                ("#C4B5FD", "accent hi"), ("#A78BFA", "icon"), ("#FFFFFF", "text"),
                ("#A1A1AA", "muted"), ("#71717A", "dim"), ("#09090B", "action fg")]
    for i, (h, nm) in enumerate(swatches):
        bx = sx + i * 92
        sd2.rounded_rectangle([bx, sy, bx + 56, sy + 56], radius=14, fill=col(h),
                              outline=(255, 255, 255, 34), width=1)
        sd2.text((bx, sy + 62), h, font=F_HEX, fill=MUTED)
        sd2.text((bx, sy + 78), nm, font=F_NAME, fill=DIM)
    tabs_line = " · ".join(t["name"] for t in spec["tabs"])
    sd2.text((sx, sy + 108),
             f"JakoScripts {spec['title']}  ·  VANTA STYLE A — DARK VIOLET GLASS  ·  480x360  ·  "
             f"sidebar 150  ·  blur 28px  ·  tabs: {tabs_line}",
             font=F_CAP, fill=DIM)
    canvas = Image.alpha_composite(canvas, strip)

    canvas.convert("RGB").save(out_path, quality=95)
    return out_path


def main():
    args = sys.argv[1:]
    if not args or args == ["--all"]:
        args = sorted(f for f in os.listdir(".")
                       if f.startswith("JakoScripts_") and f.endswith(".lua") and not f.endswith("_obf.lua"))
    for path in args:
        spec = parse_ui(path)
        if not spec["tabs"]:
            spec = HAND_SPECS.get(os.path.basename(path)) or spec
        out = spec.get("out") or HAND_SPECS.get(os.path.basename(path), {}).get("out") \
            or (re.sub(r"\.lua$", "", path) + "_preview.png")
        if not spec["tabs"]:
            print(f"{path:<32} skipped: вкладки не распознаны")
            continue
        render(spec, out)
        print(f"{path:<32} -> {out}   tabs={[t['name'] for t in spec['tabs']]}")


if __name__ == "__main__":
    main()
