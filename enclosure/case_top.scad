include <params.scad>

module skirt() {
    difference() {
        translate([-skirt_wall, -skirt_wall, 0])
            rounded_base(flange_w + 2*skirt_wall, flange_d + 2*skirt_wall, skirt_h, r + skirt_wall);
        translate([fit_clearance, fit_clearance, -1])
            rounded_base(flange_w - 2*fit_clearance, flange_d - 2*fit_clearance, skirt_h + 2, r - fit_clearance);
    }
}

module slope_solid(shrink) {
    hull() {
        translate([-skirt_wall+shrink, -skirt_wall+shrink, skirt_h])
            rounded_base(flange_w + 2*skirt_wall - 2*shrink, flange_d + 2*skirt_wall - 2*shrink, 0.01, r + skirt_wall - shrink);
        translate([x_start+shrink, y_start+shrink, h])
            rounded_base(opening_lx - 2*shrink, opening_ly - 2*shrink, 0.01, opening_r - shrink);
    }
}

module slope() {
    difference() {
        slope_solid(0);
        slope_solid(top_wall);
    }
}

module top_assembly(){
    union() {
        skirt();
        slope();
    }
}

top_assembly();