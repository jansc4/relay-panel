import Part
import math
from FreeCAD import Vector

# ============================================================
# PARAMETRY - zmierzone na wydrukowanym bottomie
# ============================================================

flange_w = 187      # os X - "dluga" krawedz flanszy
flange_d = 107.3    # os Y - "krotka" krawedz flanszy
r = 5

top_h = 3            # grubosc plyty top
skirt_h = 3
skirt_wall = 2
fit_clearance = 0.25

# gap X (od koncow - gora telefonu / port), prostopadly do KROTSZYCH krawedzi
x_start = 24
x_end = flange_w - 20
opening_lx = x_end - x_start

# gap Y (lewa/prawa), prostopadly do DLUZSZYCH krawedzi
y_start = 13
y_end = flange_d - 13
opening_ly = y_end - y_start

cut_height = top_h + 2   # przebija na wylot z zapasem


# ============================================================
# FUNKCJE POMOCNICZE
# ============================================================

def rounded_rect_wire(w, d, r, z=0):
    p1 = Vector(r, 0, z); p2 = Vector(w - r, 0, z)
    p3 = Vector(w, r, z); p4 = Vector(w, d - r, z)
    p5 = Vector(w - r, d, z); p6 = Vector(r, d, z)
    p7 = Vector(0, d - r, z); p8 = Vector(0, r, z)
    c_br = Vector(w - r, r, z); c_tr = Vector(w - r, d - r, z)
    c_tl = Vector(r, d - r, z); c_bl = Vector(r, r, z)

    def arc_point(center, radius, angle_deg):
        a = math.radians(angle_deg)
        return Vector(center.x + radius * math.cos(a),
                       center.y + radius * math.sin(a), z)

    edges = [
        Part.makeLine(p1, p2),
        Part.Arc(p2, arc_point(c_br, r, 315), p3).toShape(),
        Part.makeLine(p3, p4),
        Part.Arc(p4, arc_point(c_tr, r, 45), p5).toShape(),
        Part.makeLine(p5, p6),
        Part.Arc(p6, arc_point(c_tl, r, 135), p7).toShape(),
        Part.makeLine(p7, p8),
        Part.Arc(p8, arc_point(c_bl, r, 225), p1).toShape(),
    ]
    return Part.Wire(edges)


def centered_offset(w_outer, d_outer, w_inner, d_inner):
    return (w_outer - w_inner) / 2, (d_outer - d_inner) / 2


def rounded_ring_face(w_outer, d_outer, r_outer, w_inner, d_inner, r_inner, z=0):
    outer_wire = rounded_rect_wire(w_outer, d_outer, r_outer, z=z)
    inner_wire = rounded_rect_wire(w_inner, d_inner, r_inner, z=z)
    dx, dy = centered_offset(w_outer, d_outer, w_inner, d_inner)
    inner_wire.translate(Vector(dx, dy, 0))
    return Part.Face(outer_wire).cut(Part.Face(inner_wire))


# ============================================================
# PLYTA TOP + WYCIECIE OKNA (prostokat, bez skosu)
# ============================================================

def build_top_plate():
    outer_wire = rounded_rect_wire(flange_w, flange_d, r, z=0)
    plate = Part.Face(outer_wire).extrude(Vector(0, 0, top_h))

    window = Part.makeBox(
        opening_lx, opening_ly, cut_height,
        Vector(x_start, y_start, -1)   # -1 zeby przebic dno na wylot
    )
    return plate.cut(window)


# ============================================================
# SKIRT - doklejony OD SPODU plyty
# ============================================================

def build_skirt():
    ring = rounded_ring_face(
        flange_w + 2 * skirt_wall, flange_d + 2 * skirt_wall, r + skirt_wall,
        flange_w - 2 * fit_clearance, flange_d - 2 * fit_clearance, r - fit_clearance,
        z=0,
    )
    skirt = ring.extrude(Vector(0, 0, skirt_h))
    skirt.translate(Vector(-skirt_wall, -skirt_wall, -skirt_h))
    return skirt


# ============================================================
# SKLADANIE
# ============================================================

top_plate = build_top_plate()
skirt = build_skirt()

top_assembly = top_plate.fuse(skirt)
Part.show(top_assembly, "top_assembly")
