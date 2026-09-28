import Part
import math
from FreeCAD import Vector

# ============ PARAMETRY (te same co w OpenSCAD) ============
wall = 2
w_bottom, d_bottom = 187, 107.8
w_top, d_top = 163, 83.8

skirt_h = wall + 1
skirt_wall = 2
fit_clearance = 0.25

# 107,3x187x2;r5; od dna do ekranu 11; 13mm po prawej i lewej, od krawędzi do krawędzi ekranu; 24 od góry, 20 od dołu

z_bottom = 0
z_top = 10
tol = 0.5
print("skrypt się zaczyna")
def centered_offset(w_outer, d_outer, w_inner, d_inner):
    return (w_outer - w_inner) / 2, (d_outer - d_inner) / 2

def rounded_rect_wire(w, d, r, z=0):
    p1 = Vector(r, 0, z); p2 = Vector(w - r, 0, z)
    p3 = Vector(w, r, z); p4 = Vector(w, d - r, z)
    p5 = Vector(w - r, d, z); p6 = Vector(r, d, z)
    p7 = Vector(0, d - r, z); p8 = Vector(0, r, z)
    c_br = Vector(w - r, r, z); c_tr = Vector(w - r, d - r, z)
    c_tl = Vector(r, d - r, z); c_bl = Vector(r, r, z)

    def arc_point(center, radius, angle_deg):
        a = math.radians(angle_deg)
        return Vector(center.x + radius*math.cos(a), center.y + radius*math.sin(a), z)

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


def find_face_by_z(shape, target_z, tol):
    for face in shape.Faces:
        if abs(face.CenterOfMass.z - target_z) < tol:
            return face
    return None

# --- geometria testowa ---


dx, dy = centered_offset(w_bottom, d_bottom, w_top, d_top)

wire_bottom = rounded_rect_wire(w_bottom, d_bottom, 8, z=z_bottom)
wire_top    = rounded_rect_wire(w_top, d_top, 4, z=z_top)
wire_top.translate(Vector(dx, dy, 0))

loft = Part.makeLoft([wire_bottom, wire_top], True)


bottom_face = find_face_by_z(loft, z_bottom, tol)
top_face    = find_face_by_z(loft, z_top, tol)

print("bottom_face found:", bottom_face is not None)
print("top_face found:", top_face is not None)

faces_to_remove = [f for f in [bottom_face] if f is not None]

shell = loft.makeThickness(faces_to_remove, -2.0, 0.01)

doc = App.ActiveDocument

body = doc.addObject('PartDesign::Body', 'top_body')
base = doc.addObject('PartDesign::FeatureBase', 'base_shape')
base.Shape = shell

body.Group = [base]
body.Tip = base

doc.recompute()