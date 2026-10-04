"""JakoScripts — VANTA Style A "Dark Violet Glass", 2x mockup of JakoScripts.lua.

Exact spec render: surface #06060B, glass white 6-10% over blur 28px,
border #FFFFFF1C + highlight #FFFFFF22, accent #7C3AED, icons #A78BFA,
row #FFFFFF08 / #FFFFFF0F radius 12, switch ON #7C3AED OFF #FFFFFF1E,
slider track #FFFFFF15 fill #7C3AED -> #C4B5FD, action #FFFFFF on #09090B.
"""
import math
import os
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


SURFACE = col("06060B")
ACCENT = col("7C3AED")
ACCENT_HI = col("C4B5FD")
ICON = col("A78BFA")
TEXT = col("FFFFFF")
MUTED = col("A1A1AA")
DIM = col("71717A")

W6, W8, W10 = 0.06, 0.08, 0.10
A_ROW, A_ROWLINE, A_BORDER = 0.031, 0.059, 0.110
A_HILITE, A_OFF, A_TRACK = 0.133, 0.118, 0.082

inter = [f for f in os.listdir(FONTS) if f.lower().startswith("inter")] if os.path.isdir(FONTS) else []
print("inter files found:", inter[:6])


def font(size, weight="reg"):
    if weight == "semi":
        cands = [FONTS + f for f in inter if "semi" in f.lower() or "bold" in f.lower()]
        cands += [FONTS + "seguisb.ttf", FONTS + "arialbd.ttf"]
    elif weight == "med":
        cands = [FONTS + f for f in inter if "medium" in f.lower()]
        cands += [FONTS + "segoeui.ttf", FONTS + "arial.ttf"]
    else:
        cands = [FONTS + f for f in inter if "regular" in f.lower()]
        cands += [FONTS + "segoeui.ttf", FONTS + "arial.ttf"]
    for c in cands:
        try:
            return ImageFont.truetype(c, size)
        except Exception:
            continue
    return ImageFont.load_default()


F_LOGO = font(13 * S, "med")
F_SUB = font(9 * S, "med")
F_NAV = font(12 * S, "med")
F_TITLE = font(12 * S, "semi")
F_SECTION = font(10 * S, "semi")
F_ROW = font(12 * S, "reg")
F_VALUE = font(11 * S, "semi")
F_CHIP = font(10 * S, "semi")
F_HEX = font(11)
F_NAME = font(10)
F_CAP = font(12)


def tracked_text(draw, xy, text, fnt, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + spacing
    return x - spacing


def tracked_width(draw, text, fnt, spacing):
    return sum(draw.textlength(ch, font=fnt) + spacing for ch in text) - spacing


def rot_rect(cx, cy, w, h, deg):
    a = math.radians(deg)
    pts = []
    for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + dx * math.cos(a) - dy * math.sin(a),
                    cy + dx * math.sin(a) + dy * math.cos(a)))
    return pts


def vgrad(size, c0, c1):
    w, h = size
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for i in range(w):
        t = i / max(1, w - 1)
        c = tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(3)) + (255,)
        d.line([(i, 0), (i, h)], fill=c)
    return g


# ---------------- lucide icons ----------------
def draw_target(d, cx, cy, color):
    r = 5 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=int(1.4 * S))
    dr = 1.5 * S
    d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=color)
    t = 0.7 * S
    d.rectangle([cx - t, cy - 8 * S, cx + t, cy - 5.6 * S], fill=color)
    d.rectangle([cx - t, cy + 5.6 * S, cx + t, cy + 8 * S], fill=color)
    d.rectangle([cx - 8 * S, cy - t, cx - 5.6 * S, cy + t], fill=color)
    d.rectangle([cx + 5.6 * S, cy - t, cx + 8 * S, cy + t], fill=color)


def draw_eye(d, cx, cy, color):
    w, h = 15 * S, 10 * S
    d.ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], outline=color, width=int(1.4 * S))
    r = 2 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def draw_zap(d, cx, cy, color):
    for ox, oy in ((1.6 * S, -2.4 * S), (-1.6 * S, 2.4 * S)):
        d.polygon(rot_rect(cx + ox, cy + oy, 1.7 * S, 9 * S, -22), fill=color)
    d.polygon(rot_rect(cx, cy, 6 * S, 1.7 * S, 0), fill=color)


def draw_settings(d, cx, cy, color):
    r = 5.5 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=int(1.4 * S))
    dr = 1.6 * S
    d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=color)
    for i in range(8):
        a = math.radians(i * 45)
        d.polygon(rot_rect(cx + math.cos(a) * 6.4 * S, cy + math.sin(a) * 6.4 * S,
                           1.8 * S, 3.4 * S, i * 45), fill=color)


ICONS = {"target": draw_target, "eye": draw_eye, "zap": draw_zap, "settings": draw_settings}

# ---------------- blurred scene behind the glass ----------------
scene = Image.new("RGB", CANVAS, (9, 9, 16))
sd = ImageDraw.Draw(scene, "RGBA")
for i in range(CANVAS[1]):
    t = i / CANVAS[1]
    sd.line([(0, i), (CANVAS[0], i)],
            fill=(int(10 + 14 * (1 - t)), int(9 + 8 * (1 - t)), int(20 + 26 * (1 - t)), 255))
sd.ellipse([620, 60, 1180, 520], fill=(124, 58, 237, 120))
sd.ellipse([80, 480, 620, 1060], fill=(56, 92, 220, 90))
sd.ellipse([700, 620, 1120, 1040], fill=(196, 181, 253, 55))
scene = scene.filter(ImageFilter.GaussianBlur(28))
scene = Image.blend(scene, Image.new("RGB", CANVAS, (6, 6, 11)), 0.30)
canvas = scene.convert("RGBA")

glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
x, y = WIN_XY
gd.rounded_rectangle([x - 22 * S, y - 22 * S, x + WIN_W + 22 * S, y + WIN_H + 22 * S],
                     radius=28 * S, fill=ACCENT[:3] + (44,))
canvas = Image.alpha_composite(canvas, glow.filter(ImageFilter.GaussianBlur(18 * S)))

box = [x, y, x + WIN_W, y + WIN_H]

# ---------------- shell (transparent 8% -> glass over the blur) ----------------
shell = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
ImageDraw.Draw(shell).rounded_rectangle(box, radius=16 * S, fill=SURFACE[:3] + (int((1 - W8) * 255),))
canvas = Image.alpha_composite(canvas, shell)

win = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
d = ImageDraw.Draw(win)
d.rounded_rectangle(box, radius=16 * S, outline=(255, 255, 255, int(A_BORDER * 255)), width=max(1, S))
d.rounded_rectangle([x + 16 * S, y, x + WIN_W - 16 * S, y + S], radius=S,
                    fill=(255, 255, 255, int(A_HILITE * 255)))

# sidebar
d.rounded_rectangle([x, y, x + SIDE, y + WIN_H], radius=16 * S, fill=(255, 255, 255, int(W6 * 255)))
d.rectangle([x + SIDE - 16 * S, y + 16 * S, x + SIDE, y + WIN_H - 16 * S], fill=(255, 255, 255, int(W6 * 255)))
d.rectangle([x + SIDE, y + 12 * S, x + SIDE + S - 1, y + WIN_H - 12 * S], fill=(255, 255, 255, int(A_ROWLINE * 255)))

tracked_text(d, (x + 16 * S, y + 14 * S), "— JAKO", F_LOGO, TEXT, 3 * S)
tracked_text(d, (x + 16 * S, y + 38 * S), "SCRIPTS", F_SUB, ICON, 3 * S)
d.text((x + 16 * S, y + 56 * S), "MURDER MYSTERY 2", font=F_SUB, fill=DIM)

NAV = [("Combat", "target", True), ("Visuals", "eye", False),
       ("Movement", "zap", False), ("Config", "settings", False)]
ny = y + 84 * S
for name, ico, active in NAV:
    wx, wy = x + 6 * S + 14 * S, ny + 19 * S
    if active:
        d.rounded_rectangle([wx - 14 * S, wy - 14 * S, wx + 14 * S, wy + 14 * S],
                            radius=9 * S, fill=(255, 255, 255, int(W8 * 255)))
        d.rounded_rectangle([x + 8 * S, ny + 10 * S, x + 10 * S, ny + 28 * S], radius=S, fill=ACCENT)
    ICONS[ico](d, wx, wy, ICON if active else DIM)
    d.text((x + 48 * S, wy - 8 * S), name, font=F_NAV, fill=TEXT if active else DIM)
    ny += 44 * S

fy = y + WIN_H - 46 * S
d.rounded_rectangle([x + 12 * S, fy, x + 70 * S, fy + 22 * S], radius=7 * S,
                    fill=(255, 255, 255, int(A_TRACK * 255)),
                    outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
kw = d.textlength("RSHIFT", font=F_CHIP)
d.text((x + 12 * S + (58 * S - kw) / 2, fy + 4 * S), "RSHIFT", font=F_CHIP, fill=MUTED)
vw = d.textlength("v3 · STYLE A", font=F_SUB)
d.text((x + SIDE - 12 * S - vw, fy + 5 * S), "v3 · STYLE A", font=F_SUB, fill=DIM)

d.text((x + SIDE + 16 * S, y + 18 * S), "COMBAT", font=F_TITLE, fill=TEXT)
chip = [x + WIN_W - 34 * S - 84 * S, y + 16 * S, x + WIN_W - 34 * S, y + 38 * S]
d.rounded_rectangle(chip, radius=8 * S, fill=(255, 255, 255, int(A_TRACK * 255)),
                    outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
d.ellipse([chip[0] + 9 * S, chip[1] + 8 * S, chip[0] + 15 * S, chip[1] + 14 * S], fill=(52, 211, 153))
d.text((chip[0] + 20 * S, chip[1] + 5 * S), "Innocent", font=F_CHIP, fill=(52, 211, 153))
mw = d.textlength("—", font=F_TITLE)
d.text((x + WIN_W - 34 * S + (22 * S - mw) / 2, y + 17 * S), "—", font=F_TITLE, fill=DIM)

canvas = Image.alpha_composite(canvas, win)

# ---------------- brand watermark (top-left of the screen) ----------------
wm = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
wd2 = ImageDraw.Draw(wm)
wmx, wmy = 16, 16
WM_W, WM_H = 200 * S, 26 * S
wd2.rounded_rectangle([wmx, wmy, wmx + WM_W, wmy + WM_H], radius=10 * S,
                      fill=(255, 255, 255, int(W8 * 255)),
                      outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
mark_end = tracked_text(wd2, (wmx + 12 * S, wmy + 7 * S), "— JAKO", F_CHIP, TEXT, 2 * S)
wd2.text((mark_end + 8 * S, wmy + 7 * S), "SCRIPTS", font=F_CHIP, fill=ICON)
rw = wd2.textlength("INNOCENT", font=F_SUB)
wd2.text((wmx + WM_W - 12 * S - rw, wmy + 8 * S), "INNOCENT", font=F_SUB, fill=(52, 211, 153))
canvas = Image.alpha_composite(canvas, wm)

# ---------------- content (clipped to the shell) ----------------
content = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
cd = ImageDraw.Draw(content)
CX = x + SIDE + 16 * S
CW = WIN_W - SIDE - 32 * S
C_TOP = y + 48 * S
C_BOT = y + WIN_H - 14 * S
cy = C_TOP


def section(title):
    global cy
    tracked_text(cd, (CX, cy + 4 * S), title.upper(), F_SECTION, DIM, 4 * S)
    cy += 30 * S


def row_box(h):
    global cy
    b = [CX, cy, CX + CW, cy + h]
    cd.rounded_rectangle(b, radius=R, fill=(255, 255, 255, int(A_ROW * 255)),
                         outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
    cy += h + 8 * S
    return b


def toggle(text, on):
    b = row_box(40 * S)
    cd.text((b[0] + 14 * S, b[1] + 12 * S), text, font=F_ROW, fill=TEXT if on else MUTED)
    pw, ph = 34 * S, 18 * S
    px, py = b[2] - 48 * S, b[1] + (40 * S - ph) / 2
    if on:
        cd.rounded_rectangle([px, py, px + pw, py + ph], radius=ph / 2, fill=ACCENT)
        cd.ellipse([px + pw - 16 * S, py + 2 * S, px + pw - 2 * S, py + ph - 2 * S], fill=(255, 255, 255))
    else:
        cd.rounded_rectangle([px, py, px + pw, py + ph], radius=ph / 2, fill=(255, 255, 255, int(A_OFF * 255)))
        cd.ellipse([px + 2 * S, py + 2 * S, px + 16 * S, py + ph - 2 * S], fill=(255, 255, 255))


def slider(text, value_text, ratio):
    b = row_box(54 * S)
    cd.text((b[0] + 14 * S, b[1] + 7 * S), text, font=F_ROW, fill=MUTED)
    vwidth = cd.textlength(value_text, font=F_VALUE)
    cd.text((b[2] - 14 * S - vwidth, b[1] + 8 * S), value_text, font=F_VALUE, fill=ICON)
    tx0, tx1 = b[0] + 14 * S, b[2] - 14 * S
    ty = b[1] + 38 * S
    cd.rounded_rectangle([tx0, ty - 2 * S, tx1, ty + 2 * S], radius=2 * S, fill=(255, 255, 255, int(A_TRACK * 255)))
    fw = (tx1 - tx0) * ratio
    if fw > 1:
        strip = vgrad((int(fw), int(4 * S)), ACCENT, ACCENT_HI)
        content.paste(strip, (int(tx0), int(ty - 2 * S)), strip)
    kx = tx0 + fw
    cd.ellipse([kx - 6 * S, ty - 6 * S, kx + 6 * S, ty + 6 * S], fill=(255, 255, 255))


def cycle(text, value):
    b = row_box(40 * S)
    cd.text((b[0] + 14 * S, b[1] + 12 * S), text, font=F_ROW, fill=MUTED)
    bw, bh = 104 * S, 24 * S
    bx, by = b[2] - 116 * S, b[1] + (40 * S - bh) / 2
    cd.rounded_rectangle([bx, by, bx + bw, by + bh], radius=8 * S,
                         fill=(255, 255, 255, int(A_TRACK * 255)),
                         outline=(255, 255, 255, int(A_ROWLINE * 255)), width=max(1, S))
    vwidth = cd.textlength(value, font=F_CHIP)
    cd.text((bx + (bw - vwidth) / 2, by + 5 * S), value, font=F_CHIP, fill=ICON)


section("aimbot")
toggle("Aimbot", True)
toggle("Hold RMB only", True)
toggle("Visibility check", True)
slider("FOV", "150px", 0.24)
slider("Smooth", "25%", 0.25)
cycle("Aim part", "Head")
section("auto")
toggle("Auto shoot", False)
toggle("Auto equip tool", True)
toggle("Kill aura", False)
slider("Aura range", "10m", 0.29)

mask = Image.new("L", CANVAS, 0)
ImageDraw.Draw(mask).rectangle([CX, C_TOP, CX + CW + 10 * S, C_BOT], fill=255)
content.putalpha(Image.composite(content.getchannel("A"), Image.new("L", CANVAS, 0), mask))
canvas = Image.alpha_composite(canvas, content)

# ---------------- palette strip ----------------
strip = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
sd2 = ImageDraw.Draw(strip)
sx, sy = x, y + WIN_H + 44
swatches = [("#06060B", "surface"), ("#FFFFFF08", "row bg"), ("#FFFFFF0F", "row border"),
            ("#FFFFFF1C", "border"), ("#FFFFFF22", "highlight"), ("#7C3AED", "accent"),
            ("#C4B5FD", "accent hi"), ("#A78BFA", "icon"), ("#FFFFFF", "text"),
            ("#A1A1AA", "muted"), ("#71717A", "dim"), ("#09090B", "action fg")]
pitch = 92
for i, (h, nm) in enumerate(swatches):
    bx = sx + i * pitch
    sd2.rounded_rectangle([bx, sy, bx + 56, sy + 56], radius=14, fill=col(h),
                          outline=(255, 255, 255, 34), width=1)
    sd2.text((bx, sy + 62), h, font=F_HEX, fill=MUTED)
    sd2.text((bx, sy + 78), nm, font=F_NAME, fill=DIM)
sd2.text((sx, sy + 108),
         "JakoScripts  ·  VANTA STYLE A — DARK VIOLET GLASS  ·  window 480x360  ·  sidebar 150  ·  blur 28px  ·  Inter  ·  lucide icons",
         font=F_CAP, fill=DIM)
canvas = Image.alpha_composite(canvas, strip)

canvas.convert("RGB").save("JakoScripts_style_a_preview.png", quality=95)
print("wrote JakoScripts_style_a_preview.png", canvas.size)
