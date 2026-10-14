#!/usr/bin/env python3
"""Renders the Slice 2 roster contact sheet as an SVG.

Reads ds3d/units/roster_models.json -- the exact same box-primitive data
ds3d/units/roster_visuals.gd uses to build the live Godot rig -- and draws an
isometric box projection per role, in both team colors.

Why SVG from raw data instead of an in-engine screenshot: this sandbox's
Godot binary only has the "dummy" rendering driver under --headless (no GPU/
EGL/X11 display -- confirmed here the same way Slice 0's build notes
document: get_viewport().get_texture().get_image() returns null). Slice 0
worked around this by loading the *published* GitHub Pages build in a
browser, which this warm-up's hard rules explicitly forbid (no publish).
This script is the alternative: a geometry-accurate render driven by the
same data file the real rig loads, not hand-drawn art and not a screenshot.

Usage: python3 render_contact_sheet.py
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DATA_PATH = os.path.join(REPO_ROOT, "ds3d", "units", "roster_models.json")
OUT_PATH = os.path.join(HERE, "roster_contact_sheet.svg")

COS30 = math.cos(math.radians(30))
SIN30 = math.sin(math.radians(30))
SCALE = 130.0  # px per world unit


def project(x, y, z):
    sx = (x - z) * COS30
    sy = (x + z) * SIN30 - y
    return sx * SCALE, sy * SCALE


def darken(rgb, amount):
    return tuple(max(0.0, c * (1.0 - amount)) for c in rgb)


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(min(255, max(0, round(c * 255))) for c in rgb)


def resolve_color(key, team_rgb, metal_rgb):
    if key == "team":
        return team_rgb
    if key == "team_dark1":
        return darken(team_rgb, 0.15)
    if key == "team_dark2":
        return darken(team_rgb, 0.35)
    if key == "emissive":
        return tuple(min(1.0, c * 1.25 + 0.1) for c in team_rgb)
    if key == "metal":
        return metal_rgb
    return team_rgb


def box_faces(size, pos, origin_x, origin_y):
    sw, sh, sd = size
    px, py, pz = pos
    hw, hh, hd = sw / 2.0, sh / 2.0, sd / 2.0

    def corner(dx, dy, dz):
        wx, wy, wz = px + dx * hw, py + dy * hh, pz + dz * hd
        sx, sy = project(wx, wy, wz)
        return (origin_x + sx, origin_y + sy)

    top = [corner(-1, 1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(-1, 1, 1)]
    front = [corner(1, -1, -1), corner(1, -1, 1), corner(1, 1, 1), corner(1, 1, -1)]
    side = [corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)]
    return top, front, side


def points_attr(points):
    return " ".join("%.1f,%.1f" % p for p in points)


def render_unit(svg_parts, role_data, team_rgb, metal_rgb, origin_x, origin_y):
    polys = []
    for part in role_data["parts"]:
        base_rgb = resolve_color(part["color"], team_rgb, metal_rgb)
        top, front, side = box_faces(part["size"], part["pos"], origin_x, origin_y)
        top_color = to_hex(base_rgb)
        front_color = to_hex(darken(base_rgb, 0.25))
        side_color = to_hex(darken(base_rgb, 0.45))
        avg_y = part["pos"][1]
        polys.append((avg_y, side, side_color))
        polys.append((avg_y, front, front_color))
        polys.append((avg_y + 0.5, top, top_color))
    # Painter's algorithm: draw lower parts first so taller parts overlap correctly.
    polys.sort(key=lambda p: p[0])
    for _, pts, color in polys:
        svg_parts.append(
            '<polygon points="%s" fill="%s" stroke="#00000055" stroke-width="0.6"/>'
            % (points_attr(pts), color)
        )


def main():
    with open(DATA_PATH) as f:
        data = json.load(f)

    team_a = tuple(data["colors"]["team_a"])
    team_b = tuple(data["colors"]["team_b"])
    metal = tuple(data["colors"]["metal"])
    roles = data["role_order"]

    cell_w, cell_h = 260, 300
    cols = 3
    rows = math.ceil(len(roles) / cols)
    width = cell_w * cols
    height = cell_h * rows + 40

    svg = []
    svg.append(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
        % (width, height, width, height)
    )
    svg.append('<rect width="100%%" height="100%%" fill="#12131a"/>')
    svg.append(
        '<text x="16" y="26" fill="#e8e8ee" font-family="monospace" font-size="18">'
        "Direct Strike 3D — Slice 2 Roster Contact Sheet (geometry-accurate, not an engine screenshot)</text>"
    )

    for i, role in enumerate(roles):
        role_data = data["roles"][role]
        col = i % cols
        row = i // cols
        panel_x = col * cell_w
        panel_y = 40 + row * cell_h

        svg.append(
            '<rect x="%d" y="%d" width="%d" height="%d" fill="#1b1d27" stroke="#33364a"/>'
            % (panel_x + 4, panel_y + 4, cell_w - 8, cell_h - 8)
        )
        svg.append(
            '<text x="%d" y="%d" fill="#ffffff" font-family="monospace" font-size="15" font-weight="bold">%s</text>'
            % (panel_x + 14, panel_y + 24, role_data["label"])
        )

        ground_y = panel_y + cell_h - 60
        origin_a_x = panel_x + cell_w * 0.32
        origin_b_x = panel_x + cell_w * 0.70
        render_unit(svg, role_data, team_a, metal, origin_a_x, ground_y)
        render_unit(svg, role_data, team_b, metal, origin_b_x, ground_y)

        svg.append(
            '<text x="%d" y="%d" fill="#9fb4ff" font-family="monospace" font-size="10">A</text>'
            % (origin_a_x - 4, ground_y + 14)
        )
        svg.append(
            '<text x="%d" y="%d" fill="#ff9f94" font-family="monospace" font-size="10">B</text>'
            % (origin_b_x - 4, ground_y + 14)
        )

        note_lines = _wrap(role_data["note"], 34)
        for li, line in enumerate(note_lines):
            svg.append(
                '<text x="%d" y="%d" fill="#9a9db0" font-family="monospace" font-size="10">%s</text>'
                % (panel_x + 14, panel_y + cell_h - 34 + li * 13, _escape(line))
            )

    svg.append("</svg>")

    with open(OUT_PATH, "w") as f:
        f.write("\n".join(svg))
    print("wrote", OUT_PATH)


def _wrap(text, width):
    words = text.split()
    lines = []
    cur = ""
    for w in words:
        if len(cur) + len(w) + 1 > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        lines.append(cur)
    return lines


def _escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


if __name__ == "__main__":
    main()
