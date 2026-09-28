include <params.scad>

module flange() {
    difference() {
        rounded_base(w + 2*margin, d + 2*margin, flange_h, r);
        translate([screw_offset, screw_offset, -1]) cylinder(r=screw_r, h=flange_h+2);
        translate([w+2*margin-screw_offset, screw_offset, -1]) cylinder(r=screw_r, h=flange_h+2);
        translate([screw_offset, d+2*margin-screw_offset, -1]) cylinder(r=screw_r, h=flange_h+2);
        translate([w+2*margin-screw_offset, d+2*margin-screw_offset, -1]) cylinder(r=screw_r, h=flange_h+2);
    }
}

module bottom_assembly(){
    union() {
        flange();
        translate([margin, margin, 0])
        difference() {
            rounded_base(w, d, h, r);
            translate([wall, wall, wall])
                rounded_base(w - 2*wall, d - 2*wall, h, r - wall);
            translate([w-wall-1, d/2 - cut_w/2, cut_z])
                cube([wall + 2, cut_w, cut_h]);
        }
    }
}

bottom_assembly();