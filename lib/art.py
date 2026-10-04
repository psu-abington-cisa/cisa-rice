"""CISA Rice artwork: palettes, the CISA marks, and wallpapers, all as SVG.

Everything is vector and rendered to PNG with rsvg-convert at the size needed, so
logos and lettering stay sharp at any resolution. The "ci" mark, the "cisa"
wordmark and the seal come from the CISA logo concepts canvas.
"""
import math
import pathlib
import random
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
VW, VH = 1920, 1080          # wallpaper design space (rendered at any 16:9 size)


# --------------------------------------------------------------------------- palette

def load_theme(theme_id):
    """Parse a themes/<id>.theme file (KEY="value"; KEY=value) into a dict."""
    text = (ROOT / "themes" / f"{theme_id}.theme").read_text()
    t = {"ID": theme_id}
    for key, val in re.findall(r'([A-Z][A-Z0-9_]*)=("[^"]*"|[^\s;#]+)', text):
        t[key] = val.strip('"')
    for k in ("DARK", "BLUR", "RADIUS", "BORDER", "GAPS_IN", "GAPS_OUT"):
        t[k] = int(t[k])
    t.setdefault("ACCENT_ON_PANEL", mix(t["ACCENT"], "#000000", 22) if t["DARK"] else t["ACCENT"])
    return t


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, pct):
    """Blend colour a toward b by pct percent."""
    ra, rb = hex_rgb(a), hex_rgb(b)
    return "#" + "".join(f"{round(x * (100 - pct) / 100 + y * pct / 100):02x}" for x, y in zip(ra, rb))


def rgba(h, alpha):
    r, g, b = hex_rgb(h)
    return f"rgba({r}, {g}, {b}, {alpha})"


def luminance(h):
    r, g, b = hex_rgb(h)
    return (r * 299 + g * 587 + b * 114) / 1000


def on(h):
    """Readable text colour on top of h."""
    return "#101010" if luminance(h) > 150 else "#ffffff"


# --------------------------------------------------------------------------- marks

def ci_mark(x, y, size, fg, accent, stroke=17):
    """The "ci" mark (the i inside the c): x, y top-left, size = box width."""
    s = size / 100
    return (f'<g transform="translate({x:.2f} {y:.2f}) scale({s:.4f})">'
            f'<path d="M70.25 25.87 A31.5 31.5 0 1 0 70.25 74.13" fill="none" stroke="{fg}" stroke-width="{stroke}"/>'
            f'<rect x="58" y="39" width="17" height="22" fill="{accent}"/></g>')


def wordmark(x, y, height, fg, accent, cursor=False):
    """The "cisa" wordmark; with cursor=True it ends in a blinking-style underscore."""
    s = height / 126
    extra = f'<rect x="282" y="111" width="34" height="12" fill="{accent}"/>' if cursor else ""
    return (f'<g transform="translate({x:.2f} {y:.2f}) scale({s:.4f})" fill="none" stroke="{fg}" stroke-width="17">'
            '<path d="M60.25 55.87 A31.5 31.5 0 1 0 60.25 104.13"/>'
            '<line x1="95" y1="40" x2="95" y2="120"/>'
            f'<rect x="86.5" y="6" width="17" height="22" fill="{accent}" stroke="none"/>'
            '<path d="M165.84 55.22 A23 15.75 0 0 0 147.00 48.50 A23 15.75 0 0 0 124.00 64.25 A23 15.75 0 0 0 147.00 80.00 '
            'A23 15.75 0 0 1 170.00 95.75 A23 15.75 0 0 1 147.00 111.50 A23 15.75 0 0 1 128.16 104.78"/>'
            '<circle cx="229" cy="80" r="31.5"/><line x1="260.5" y1="40" x2="260.5" y2="120"/>'
            f'{extra}</g>')


def wordmark_width(height, cursor=False):
    return (316 if cursor else 269) * height / 126


def seal(cx, cy, r, t):
    """The ci seal: tick ring, ring lettering, inner disc with the ci mark."""
    fg, bg = t["FG"], t["BG"]
    k = r / 200
    ticks = []
    for i in range(72):
        deg = i * 5
        a = math.radians(deg)
        if deg % 90 == 0:
            r1, w = 168, 2.4
        elif deg % 30 == 0:
            r1, w = 176, 1.3
        else:
            r1, w = 180, 1.3
        ticks.append(f'<line x1="{200 + 186 * math.cos(a):.2f}" y1="{200 + 186 * math.sin(a):.2f}" '
                     f'x2="{200 + r1 * math.cos(a):.2f}" y2="{200 + r1 * math.sin(a):.2f}" stroke-width="{w}"/>')
    ring = (ASSETS / "seal-ring.svgfrag").read_text().replace("{{FG}}", fg)
    ring = re.sub(r"<!--.*?-->", "", ring)
    return (f'<g transform="translate({cx - 200 * k:.2f} {cy - 200 * k:.2f}) scale({k:.4f})">'
            f'<circle cx="200" cy="200" r="196" fill="none" stroke="{fg}" stroke-width="3"/>'
            f'<g stroke="{fg}">{"".join(ticks)}</g>{ring}'
            f'<rect x="66" y="268" width="7" height="7" fill="{t["ACCENT"]}"/>'
            f'<rect x="327" y="268" width="7" height="7" fill="{t["ACCENT"]}"/>'
            f'<circle cx="200" cy="200" r="118" fill="none" stroke="{fg}" stroke-width="1.2"/>'
            f'<circle cx="200" cy="200" r="104" fill="{fg}"/>'
            f'{ci_mark(130, 130, 140, bg, t["ACCENT_ON_PANEL"])}</g>')


def badge(x, y, size):
    """The original CISA badge (vector), embedded as a nested SVG."""
    inner = (ASSETS / "cisa-logo.svg").read_text()
    inner = re.sub(r"^.*?<svg[^>]*>|</svg>\s*$", "", inner, flags=re.S)
    return f'<svg x="{x:.2f}" y="{y:.2f}" width="{size:.2f}" height="{size:.2f}" viewBox="0 0 1000 1000">{inner}</svg>'


def svg_doc(body, w=VW, h=VH, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            f'<defs>{defs}</defs>{body}</svg>')


MONO = "JetBrains Mono, DejaVu Sans Mono, monospace"


def text(x, y, s, size, fill, anchor="start", weight=500, spacing=0, opacity=1):
    s = s.replace("&", "&amp;").replace("<", "&lt;")
    return (f'<text x="{x}" y="{y}" font-family="{MONO}" font-size="{size}" font-weight="{weight}" '
            f'letter-spacing="{spacing}" fill="{fill}" fill-opacity="{opacity}" text-anchor="{anchor}">{s}</text>')


# --------------------------------------------------------------------------- wallpapers

def wp_badge(t):
    """CISA Navy: hex grid, a glow, the badge, the tagline."""
    defs = (f'<radialGradient id="bg" cx="50%" cy="42%" r="75%"><stop offset="0" stop-color="{t["SURFACE"]}"/>'
            f'<stop offset="1" stop-color="{t["BG"]}"/></radialGradient>'
            f'<pattern id="hex" width="56" height="97" patternUnits="userSpaceOnUse">'
            f'<path d="M28 0 L56 16 L56 48 L28 64 L0 48 L0 16 Z M28 64 L28 97" fill="none" stroke="{t["ACCENT2"]}" '
            f'stroke-width="1" opacity="0.09"/></pattern>'
            '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="60"/></filter>')
    body = (f'<rect width="{VW}" height="{VH}" fill="url(#bg)"/><rect width="{VW}" height="{VH}" fill="url(#hex)"/>'
            f'<circle cx="960" cy="470" r="230" fill="{t["ACCENT"]}" opacity="0.45" filter="url(#glow)"/>'
            + badge(960 - 200, 270, 400)
            + text(960, 775, "LEARN TO HACK. THE LEGAL WAY.", 26, t["FG"], "middle", 600, 8, 0.92)
            + text(960, 812, "cybersecurity & it student association · penn state abington", 15, t["MUTED"], "middle", 400, 1)
            + corner_marks(t["MUTED"], 0.5))
    return svg_doc(body, defs=defs)


def corner_marks(color, opacity):
    """Thin registration marks in the corners (inside the 16:10 / 4:3 safe area)."""
    out = []
    for x, y, dx, dy in ((150, 90, 1, 1), (VW - 150, 90, -1, 1), (150, VH - 120, 1, -1), (VW - 150, VH - 120, -1, -1)):
        out.append(f'<path d="M{x} {y + 26 * dy} V{y} H{x + 26 * dx}" fill="none" stroke="{color}" '
                   f'stroke-width="1.5" opacity="{opacity}"/>')
    return "".join(out)


def wp_seal(t):
    """P1/P2/P3/P5: the ci seal with the wordmark lockup, on a dot grid."""
    fg, line = t["FG"], t["LINE"]
    defs = (f'<pattern id="dots" width="32" height="32" patternUnits="userSpaceOnUse">'
            f'<circle cx="16" cy="16" r="1.3" fill="{line}"/></pattern>')
    rings = "".join(f'<circle cx="1330" cy="540" r="{r}" fill="none" stroke="{line}" stroke-width="1" '
                    f'opacity="{0.55 - i * 0.08:.2f}"/>' for i, r in enumerate((360, 450, 560, 690, 840)))
    wm_h = 112
    body = (f'<rect width="{VW}" height="{VH}" fill="{t["BG"]}"/>'
            f'<rect width="{VW}" height="{VH}" fill="url(#dots)" opacity="0.55"/>{rings}'
            + seal(1330, 540, 290, t)
            + wordmark(240, 430, wm_h, fg, t["ACCENT"])
            + f'<line x1="{240 + wordmark_width(wm_h) + 40:.0f}" y1="452" x2="{240 + wordmark_width(wm_h) + 40:.0f}" '
              f'y2="540" stroke="{line}" stroke-width="1.5"/>'
            + "".join(text(240 + wordmark_width(wm_h) + 72, 470 + i * 30, s, 19, fg, weight=500)
                      for i, s in enumerate(("Cybersecurity & IT", "Student Association", "Penn State Abington")))
            + text(240, 640, "learn to hack. the legal way.", 18, t["MUTED"], weight=500, spacing=1)
            # JetBrains Mono advances 0.6 em per glyph, plus 1px letter-spacing
            + f'<rect x="{240 + 29 * (0.6 * 18 + 1) + 6:.0f}" y="626" width="12" height="16" fill="{t["ACCENT"]}"/>'
            + corner_marks(t["MUTED"], 0.45))
    return svg_doc(body, defs=defs)


def wp_oled(t, variant="field"):
    """OLED (from the logo concepts): pure black; a field of dim marks with one lit, or the prompt."""
    body = [f'<rect width="{VW}" height="{VH}" fill="#000000"/>']
    if variant == "field":
        cols, rows, step = 16, 9, 120
        lit = (8, 5)
        for cy in range(rows):
            for cx in range(cols):
                x, y = 60 + cx * step - 14, 60 + cy * step - 14
                if (cx, cy) == lit:
                    body.append(ci_mark(x - 4, y - 4, 36, t["FG"], t["ACCENT"], 15))
                else:
                    body.append(ci_mark(x, y, 28, "#10161f", "#10161f", 15))
    else:  # prompt
        h = 64
        w = wordmark_width(h, cursor=True)
        body.append(wordmark((VW - w) / 2, (VH - h) / 2, h, t["FG"], t["ACCENT"], cursor=True))
    return svg_doc("".join(body))


def wp_aurora(t):
    """Glass: a vivid aurora with film grain, so frosted windows have something to refract."""
    defs = ('<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="130"/></filter>'
            '<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7"/>'
            '<feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.55 0"/></filter>'
            f'<linearGradient id="base" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0b1030"/>'
            f'<stop offset="1" stop-color="{t["BG"]}"/></linearGradient>'
            '<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">'
            '<stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/></linearGradient>')
    blobs = (("#22c4ff", 380, 230, 470), ("#7b4dff", 1420, 260, 520), ("#ff4fa8", 1180, 880, 420),
             ("#2f5bff", 260, 900, 420), ("#2effc0", 820, 560, 260))
    body = (f'<rect width="{VW}" height="{VH}" fill="url(#base)"/>'
            '<g filter="url(#soft)">'
            + "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}" opacity="0.62"/>' for c, x, y, r in blobs)
            + '</g>'
            '<g fill="none" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1.2">'
            + "".join(f'<path d="M{-200 + i * 140} {VH} L{400 + i * 140} 0"/>' for i in range(18)) + '</g>'
            f'<rect width="{VW}" height="{VH}" filter="url(#grain)" opacity="0.07"/>'
            # a glass disc behind the badge, with a specular sheen
            '<circle cx="960" cy="520" r="250" fill="#ffffff" fill-opacity="0.08" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2"/>'
            '<circle cx="960" cy="520" r="250" fill="url(#sheen)"/>'
            + badge(960 - 190, 520 - 190, 380)
            + text(960, 830, "LEARN TO HACK. THE LEGAL WAY.", 24, "#ffffff", "middle", 600, 8, 0.9))
    return svg_doc(body, defs=defs)


def wp_blueprint(t):
    """Blueprint: the CISA shield as an engineering drawing (like the reference rice)."""
    fg, m = t["FG"], t["MUTED"]
    ox, oy, k = 960 - 360, 70, 0.72          # badge geometry (1000 box) placed and scaled
    P = lambda x, y: (ox + x * k, oy + y * k)
    def L(x1, y1, x2, y2, w=1.2, op=0.75, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        return (f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{fg}" stroke-width="{w}" '
                f'stroke-opacity="{op}"{d}/>')
    def arrow(x, y, ang):
        a = math.radians(ang)
        p1 = (x - 12 * math.cos(a - 0.35), y - 12 * math.sin(a - 0.35))
        p2 = (x - 12 * math.cos(a + 0.35), y - 12 * math.sin(a + 0.35))
        return f'<path d="M{x:.1f} {y:.1f} L{p1[0]:.1f} {p1[1]:.1f} L{p2[0]:.1f} {p2[1]:.1f} Z" fill="{fg}" fill-opacity="0.8"/>'
    def balloon(x, y, n):
        return (f'<circle cx="{x}" cy="{y}" r="17" fill="none" stroke="{fg}" stroke-opacity="0.7" stroke-width="1.3"/>'
                + text(x, y + 6, str(n), 16, fg, "middle", 500, 0, 0.8))
    defs = (f'<pattern id="minor" width="24" height="24" patternUnits="userSpaceOnUse">'
            f'<path d="M24 0 H0 V24" fill="none" stroke="{fg}" stroke-opacity="0.035" stroke-width="1"/></pattern>'
            f'<pattern id="major" width="120" height="120" patternUnits="userSpaceOnUse">'
            f'<path d="M120 0 H0 V120" fill="none" stroke="{fg}" stroke-opacity="0.07" stroke-width="1"/></pattern>')
    shield = ("M 500 214 C 572 254 642 266 716 266 L 716 452 C 716 592 622 684 500 742 "
              "C 378 684 284 592 284 452 L 284 266 C 358 266 428 254 500 214 Z")
    tx, ty = P(0, 0)
    g = (f'<g transform="translate({tx} {ty}) scale({k})" fill="none" stroke="{fg}" stroke-linejoin="round">'
         f'<circle cx="500" cy="500" r="484" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="6 10"/>'
         f'<circle cx="500" cy="500" r="345" stroke-opacity="0.25" stroke-width="2"/>'
         f'<path d="{shield}" stroke-opacity="0.95" stroke-width="3"/>'
         f'<path d="{shield}" transform="translate(500 478) scale(0.9) translate(-500 -478)" stroke-opacity="0.45" stroke-width="2"/>'
         '<path d="M 452 440 V 392 A 48 48 0 0 1 548 392 V 440" stroke-opacity="0.9" stroke-width="3"/>'
         '<rect x="394" y="430" width="212" height="168" rx="20" stroke-opacity="0.9" stroke-width="3"/>'
         '<circle cx="500" cy="496" r="22" stroke-opacity="0.9" stroke-width="2.5"/>'
         '<path d="M 490 506 L 484 560 H 516 L 510 506" stroke-opacity="0.9" stroke-width="2.5"/>'
         '<g stroke-opacity="0.6" stroke-width="2.5" stroke-dasharray="10 6">'
         '<path d="M 150 466 H 226 L 250 448 H 300"/><path d="M 126 500 H 300"/>'
         '<path d="M 150 534 H 226 L 250 552 H 300"/><path d="M 196 584 H 236 L 258 602 H 312"/></g>'
         '<g stroke-opacity="0.7" stroke-width="2">'
         '<circle cx="150" cy="466" r="12"/><circle cx="126" cy="500" r="12"/>'
         '<circle cx="150" cy="534" r="12"/><circle cx="196" cy="584" r="12"/></g></g>')
    cxp, cyp = P(500, 0)[0], P(0, 478)[1]
    lx, rx = P(284, 0)[0], P(716, 0)[0]
    top, bot = P(0, 214)[1], P(0, 742)[1]
    dims = (L(cxp, top - 60, cxp, bot + 70, 1, 0.35, "18 6 3 6") + L(lx - 80, cyp, rx + 80, cyp, 1, 0.35, "18 6 3 6")
            # width
            + L(lx, bot + 40, lx, P(0, 600)[1], 1, 0.4) + L(rx, bot + 40, rx, P(0, 600)[1], 1, 0.4)
            + L(lx, bot + 30, rx, bot + 30, 1.2, 0.75) + arrow(lx, bot + 30, 180) + arrow(rx, bot + 30, 0)
            + text(cxp, bot + 22, "432.0 ±0.15", 15, fg, "middle", 500, 1, 0.85)
            # height
            + L(rx + 30, top, rx + 120, top, 1, 0.4) + L(rx + 30, bot, rx + 120, bot, 1, 0.4)
            + L(rx + 100, top, rx + 100, bot, 1.2, 0.75) + arrow(rx + 100, top, 270) + arrow(rx + 100, bot, 90)
            + f'<g transform="translate({rx + 90} {(top + bot) / 2}) rotate(-90)">'
            + text(0, 0, "528.0 ±0.15", 15, fg, "middle", 500, 1, 0.85) + '</g>'
            # callouts
            + L(*P(462, 352), P(462, 352)[0] - 170, P(462, 352)[1] - 90, 1, 0.55) + text(P(462, 352)[0] - 178, P(462, 352)[1] - 96, "R48 shackle", 15, fg, "end", 500, 0, 0.8)
            + L(*P(522, 496), P(522, 496)[0] + 230, P(522, 496)[1] + 40, 1, 0.55) + text(P(522, 496)[0] + 238, P(522, 496)[1] + 46, "Ø44 keyhole", 15, fg, weight=500, opacity=0.8)
            + L(*P(126, 500), P(126, 500)[0] - 130, P(126, 500)[1] - 120, 1, 0.55) + text(P(126, 500)[0] - 140, P(126, 500)[1] - 128, "4× trace, 9 wide", 15, fg, "end", 500, 0, 0.8)
            + balloon(P(716, 266)[0] + 60, P(716, 266)[1] - 60, 1) + L(P(716, 266)[0] + 12, P(716, 266)[1] - 12, P(716, 266)[0] + 47, P(716, 266)[1] - 47, 1, 0.55)
            + balloon(P(394, 598)[0] - 70, P(394, 598)[1] + 70, 2) + L(P(394, 598)[0] - 10, P(394, 598)[1] + 10, P(394, 598)[0] - 57, P(394, 598)[1] + 57, 1, 0.55)
            + balloon(P(150, 534)[0] - 40, P(150, 534)[1] + 130, 3) + L(P(150, 534)[0] - 5, P(150, 534)[1] + 14, P(150, 534)[0] - 34, P(150, 534)[1] + 114, 1, 0.55))
    # drawing frame with zone letters/numbers, and a title block
    fx0, fy0, fx1, fy1 = 150, 70, VW - 150, VH - 90
    frame = [f'<rect x="{fx0}" y="{fy0}" width="{fx1 - fx0}" height="{fy1 - fy0}" fill="none" stroke="{fg}" stroke-opacity="0.5" stroke-width="1.5"/>',
             f'<rect x="{fx0 + 14}" y="{fy0 + 14}" width="{fx1 - fx0 - 28}" height="{fy1 - fy0 - 28}" fill="none" stroke="{fg}" stroke-opacity="0.25" stroke-width="1"/>']
    for i in range(8):
        x = fx0 + 14 + (fx1 - fx0 - 28) * (i + 0.5) / 8
        frame.append(text(x, fy0 + 11, str(8 - i), 10, m, "middle", 500))
        frame.append(text(x, fy1 - 3, str(8 - i), 10, m, "middle", 500))
    for i, ch in enumerate("ABCDE"):
        y = fy0 + 14 + (fy1 - fy0 - 28) * (i + 0.5) / 5 + 4
        frame.append(text(fx0 + 7, y, ch, 10, m, "middle", 500))
        frame.append(text(fx1 - 7, y, ch, 10, m, "middle", 500))
    bx, by, bw, bh = fx1 - 14 - 470, fy1 - 14 - 150, 470, 150
    rows = (("CYBERSECURITY & IT STUDENT ASSOCIATION", 15, 600), ("PENN STATE ABINGTON", 13, 500))
    frame += [f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" fill="{t["BG"]}" stroke="{fg}" stroke-opacity="0.5" stroke-width="1.2"/>',
              f'<line x1="{bx}" y1="{by + 70}" x2="{bx + bw}" y2="{by + 70}" stroke="{fg}" stroke-opacity="0.35"/>',
              f'<line x1="{bx}" y1="{by + 110}" x2="{bx + bw}" y2="{by + 110}" stroke="{fg}" stroke-opacity="0.35"/>']
    frame += [f'<line x1="{bx + bw * f}" y1="{by + 70}" x2="{bx + bw * f}" y2="{by + bh}" stroke="{fg}" stroke-opacity="0.35"/>' for f in (0.34, 0.67)]
    frame += [text(bx + 16, by + 30 + i * 24, s, sz, fg, weight=w, opacity=0.9) for i, (s, sz, w) in enumerate(rows)]
    for i, (k1, v1) in enumerate((("DWG NO.", "CISA-01"), ("REV", "2026.10"), ("SCALE", "1 : 1"))):
        x = bx + 14 + bw * (0.34, 0.33, 0.33)[i] * 0 + bw * (0, 0.34, 0.67)[i]
        frame.append(text(x, by + 88, k1, 10, m, weight=500, spacing=1))
        frame.append(text(x, by + 104, v1, 14, fg, weight=600))
    frame.append(text(bx + 16, by + 136, "learn to hack. the legal way.", 13, m, weight=500))
    body = (f'<rect width="{VW}" height="{VH}" fill="{t["BG"]}"/><rect width="{VW}" height="{VH}" fill="url(#minor)"/>'
            f'<rect width="{VW}" height="{VH}" fill="url(#major)"/>' + "".join(frame) + g + dims)
    return svg_doc(body, defs=defs)


def wp_phosphor(t):
    """Phosphor: falling hex code, scanlines, vignette, and a terminal prompt."""
    rnd = random.Random(42)
    chars = "0123456789ABCDEF"
    cols = []
    for x in range(20, VW, 30):
        if rnd.random() < 0.3:
            continue
        head, length = rnd.randint(0, 34), rnd.randint(6, 24)
        for k in range(length):
            row = head - k
            if row < 0:
                break
            op = 1 if k == 0 else 0.7 - 0.66 * k / length
            col = t["ACCENT2"] if k == 0 else t["ACCENT"]
            cols.append(f'<text x="{x}" y="{row * 30 + 26}" fill="{col}" fill-opacity="{op:.2f}">{rnd.choice(chars)}</text>')
    defs = (f'<pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="1.4" fill="#000" opacity="0.45"/></pattern>'
            f'<radialGradient id="vig" cx="50%" cy="50%" r="72%"><stop offset="0.5" stop-color="#000" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000" stop-opacity="0.9"/></radialGradient>'
            '<filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6" result="b"/>'
            '<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    pw, ph = 720, 220
    px, py = (VW - pw) / 2, (VH - ph) / 2 + 40
    body = (f'<rect width="{VW}" height="{VH}" fill="{t["BG"]}"/>'
            f'<g font-family="{MONO}" font-size="22" font-weight="600">{"".join(cols)}</g>'
            f'<rect width="{VW}" height="{VH}" fill="url(#vig)"/>'
            f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" fill="{t["BG"]}" fill-opacity="0.92" stroke="{t["ACCENT"]}" stroke-width="2"/>'
            f'<g filter="url(#glow)">'
            + ci_mark(VW / 2 - 70, py - 190, 140, t["ACCENT2"], t["ACCENT"], 15)
            + text(px + 34, py + 70, "cisa@abington:~$ ./learn --legal", 26, t["ACCENT2"], weight=600)
            + text(px + 34, py + 118, "[+] access granted. welcome, hacker.", 22, t["ACCENT"], weight=500, opacity=0.85)
            + text(px + 34, py + 166, "cisa@abington:~$", 26, t["ACCENT2"], weight=600)
            + f'<rect x="{px + 34 + 0.6 * 26 * 17:.0f}" y="{py + 144}" width="16" height="28" fill="{t["ACCENT2"]}"/>'
            + '</g>'
            f'<rect width="{VW}" height="{VH}" fill="url(#scan)"/>')
    return svg_doc(body, defs=defs)


WALLPAPERS = {"badge": wp_badge, "seal": wp_seal, "oled": wp_oled, "aurora": wp_aurora,
              "blueprint": wp_blueprint, "phosphor": wp_phosphor}


def wallpaper_svg(t):
    return WALLPAPERS[t["MOTIF"]](t)


def lock_svg(t):
    """Background for the lock screen: OLED gets the "prompt" design, others reuse the wallpaper."""
    return wp_oled(t, "prompt") if t["MOTIF"] == "oled" else wallpaper_svg(t)


def icon_svg(t, size=512):
    """The CISA badge (vector) is the desktop's logo in every theme: bar, menu, fetch, start button."""
    return svg_doc(badge(0, 0, size), size, size)


def ci_tile_svg(t, size=512):
    """The ci mark on a rounded tile (from the logo concepts); kept for anyone who prefers it."""
    body = (f'<rect width="{size}" height="{size}" rx="{size * 0.22:.0f}" fill="{t["PANEL"]}"/>'
            + ci_mark(size * 0.19, size * 0.19, size * 0.62, t["BG"] if t["DARK"] else t["SURFACE"],
                      t["ACCENT_ON_PANEL"]))
    return svg_doc(body, size, size)
