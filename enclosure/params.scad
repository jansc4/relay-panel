$fn = 40;

wall = 2;
w = 162;    // w rzeczywistości jest o 5mm mniej
d = 83;     // w rzeczywistości jest o 5mm mniej
h = 10;
r = 6;

cut_w = 12;
cut_h = 10;
cut_z = 2;

margin = 12;        // +2mm aby wtyczka kabla weszła 
flange_h = wall;
screw_r = 2;
screw_offset = 8;
skirt_h = wall + 1;
skirt_wall = 2;
fit_clearance = 0.25;

flange_w = w + 2*margin;
flange_d = d + 2*margin;

x_start = margin + wall + 10;
x_end   = margin + w - wall - 8;
opening_lx = x_end - x_start;

y_start = margin + wall + 2;
y_end   = margin + d - wall - 2;
opening_ly = y_end - y_start;


opening_r = 4;

desired_wall = 2;   // faktyczna grubość ścianki, jaką chcesz mieć (prostopadle do skosu)

rise = h - skirt_h;
run_x = (flange_w + 2*skirt_wall - opening_lx) / 2;
run_y = (flange_d + 2*skirt_wall - opening_ly) / 2;

// bierzemy bardziej płaski kierunek (większy run = cieńsza ścianka), żeby zagwarantować
// minimum wszędzie
run_max = max(run_x, run_y);
slant = sqrt(rise*rise + run_max*run_max);

top_wall = desired_wall * slant / rise;   // to jest teraz Twój "shrink" w XY

module rounded_base(w, d, h, r) {
    hull() {
        translate([r, r, 0]) cylinder(r=r, h=h);
        translate([w-r, r, 0]) cylinder(r=r, h=h);
        translate([r, d-r, 0]) cylinder(r=r, h=h);
        translate([w-r, d-r, 0]) cylinder(r=r, h=h);
    }
}