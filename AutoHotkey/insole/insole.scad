// =====================================================================
// Parametric shoe insole  (OpenSCAD 2021.01 or newer)
//
// Axes: +Y = toward toes (heel at y=0), X = across the foot, Z = up.
// Everything is driven by the parameters below. Open in OpenSCAD,
// press F5 to preview, F6 to render, then File > Export > STL.
// Use the Customizer panel (Window > Customizer) to tweak live.
// =====================================================================

/* [Size] */
// Insole length, heel to longest toe (mm). Rough guide: EU size x 6.67 - 5
insole_length = 270;
// Width across the ball of the foot (mm)
forefoot_width = 100;

/* [Side] */
// Which foot
foot = "right"; // [right, left]

/* [Thickness] */
// Base thickness at the heel (mm)
base_heel = 4;
// Base thickness at the toes (mm)
base_toe = 2;

/* [Heel cup] */
heel_cup_height = 12;   // wall height at the back/sides of heel (mm)
heel_cup_length = 0.30; // fraction of length the cup extends along
heel_cup_depth_ratio = 0.55; // 0 = shallow dish, 1 = steep walls

/* [Arch support] */
arch_height = 9;       // peak height of medial arch above base (mm)
arch_pos = 0.34;       // fraction of length from heel
arch_length = 0.30;    // fraction of length (size of the bump)
arch_width = 0.55;     // fraction of forefoot width

/* [Metatarsal pad] */
met_pad_height = 3;    // 0 to disable
met_pad_pos = 0.50;    // fraction of length from heel

/* [Ventilation holes] */
vent_holes = false;
vent_diameter = 4;
vent_spacing = 12;

/* [Quality] */
grid_step = 2;         // heightfield resolution (mm); smaller = smoother
curve_steps = 12;      // outline smoothness per control point

// ---------------------------------------------------------------------
// Outline: closed Catmull-Rom spline through normalized control points.
// x is a fraction of forefoot_width (0 = centerline, - = medial/big-toe
// side for a right foot); y is a fraction of insole_length.
// ---------------------------------------------------------------------
ctrl = [
    [ 0.00, 0.000], [ 0.20, 0.012], [ 0.33, 0.060], [ 0.36, 0.140],
    [ 0.37, 0.250], [ 0.42, 0.380], [ 0.49, 0.580], [ 0.47, 0.760],
    [ 0.38, 0.900], [ 0.20, 0.985], [-0.05, 1.000], [-0.30, 0.960],
    [-0.46, 0.850], [-0.50, 0.700], [-0.42, 0.520], [-0.30, 0.380],
    [-0.28, 0.250], [-0.30, 0.130], [-0.25, 0.050], [-0.14, 0.008]
];

function scaled(p) = [p[0] * forefoot_width, p[1] * insole_length];

function cr(p0, p1, p2, p3, t) =
    0.5 * ((2 * p1) + (-p0 + p2) * t
         + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
         + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);

function outline() =
    let (n = len(ctrl))
    [ for (i = [0 : n - 1]) for (s = [0 : curve_steps - 1])
        cr(scaled(ctrl[(i + n - 1) % n]), scaled(ctrl[i]),
           scaled(ctrl[(i + 1) % n]), scaled(ctrl[(i + 2) % n]),
           s / curve_steps) ];

module outline_2d() { polygon(outline()); }

// ---------------------------------------------------------------------
// Height field  z(x, y)  (mm above the flat bottom)
// ---------------------------------------------------------------------
function smooth(a, b, x) =
    let (t = max(0, min(1, (x - a) / (b - a)))) t * t * (3 - 2 * t);

function bump(x, y, cx, cy, sx, sy) =
    exp(-0.5 * (pow((x - cx) / sx, 2) + pow((y - cy) / sy, 2)));

function height(x, y) =
    let (
        L = insole_length, W = forefoot_width,
        // base slab tapering heel -> toe
        base = base_heel + (base_toe - base_heel) * smooth(0, L, y),
        // heel cup: elliptical bowl, walls rise toward the rim
        hcx = 0, hcy = L * heel_cup_length * 0.55,
        r = sqrt(pow((x - hcx) / (0.36 * W), 2)
               + pow((y - hcy) / (L * heel_cup_length * 0.62), 2)),
        cup = heel_cup_height * smooth(1 - heel_cup_depth_ratio, 1.05, r),
        // medial arch
        arch = arch_height * bump(x, y, -0.13 * W, arch_pos * L,
                                  arch_width * W * 0.45,
                                  arch_length * L * 0.5),
        // metatarsal pad (just behind the ball)
        met = met_pad_height * bump(x, y, -0.02 * W, met_pad_pos * L,
                                    0.22 * W, 0.045 * L)
    )
    max(0.8, base + cup + arch + met);

// ---------------------------------------------------------------------
// Heightfield as a polyhedron over a bounding grid
// ---------------------------------------------------------------------
x0 = -0.60 * forefoot_width;
x1 =  0.60 * forefoot_width;
y0 = -2;
y1 = insole_length + 2;
nx = ceil((x1 - x0) / grid_step) + 1;
ny = ceil((y1 - y0) / grid_step) + 1;

function gx(i) = x0 + (x1 - x0) * i / (nx - 1);
function gy(j) = y0 + (y1 - y0) * j / (ny - 1);
function T(i, j) = j * nx + i;           // top vertex index
function B(i, j) = nx * ny + j * nx + i; // bottom vertex index

module heightfield() {
    pts = concat(
        [ for (j = [0 : ny - 1]) for (i = [0 : nx - 1])
            [gx(i), gy(j), height(gx(i), gy(j))] ],
        [ for (j = [0 : ny - 1]) for (i = [0 : nx - 1])
            [gx(i), gy(j), 0] ]);
    faces = concat(
        // top
        [ for (j = [0 : ny - 2]) for (i = [0 : nx - 2])
            [T(i, j), T(i, j + 1), T(i + 1, j + 1), T(i + 1, j)] ],
        // bottom
        [ for (j = [0 : ny - 2]) for (i = [0 : nx - 2])
            [B(i, j), B(i + 1, j), B(i + 1, j + 1), B(i, j + 1)] ],
        // y = min side
        [ for (i = [0 : nx - 2])
            [T(i, 0), T(i + 1, 0), B(i + 1, 0), B(i, 0)] ],
        // y = max side
        [ for (i = [0 : nx - 2])
            [T(i + 1, ny - 1), T(i, ny - 1), B(i, ny - 1), B(i + 1, ny - 1)] ],
        // x = min side
        [ for (j = [0 : ny - 2])
            [T(0, j + 1), T(0, j), B(0, j), B(0, j + 1)] ],
        // x = max side
        [ for (j = [0 : ny - 2])
            [T(nx - 1, j), T(nx - 1, j + 1), B(nx - 1, j + 1), B(nx - 1, j)] ]
    );
    polyhedron(points = pts, faces = faces, convexity = 10);
}

// ---------------------------------------------------------------------
// Assembly
// ---------------------------------------------------------------------
module vent_pattern() {
    // staggered holes in the forefoot / midfoot only (clear of heel cup)
    for (y = [0.38 * insole_length : vent_spacing : 0.92 * insole_length])
        for (x = [-0.45 * forefoot_width : vent_spacing : 0.45 * forefoot_width])
            translate([x + (round(y / vent_spacing) % 2) * vent_spacing / 2, y, -1])
                cylinder(d = vent_diameter, h = 60, $fn = 16);
}

module insole() {
    difference() {
        intersection() {
            heightfield();
            translate([0, 0, -1]) linear_extrude(height = 60) outline_2d();
        }
        if (vent_holes)
            intersection() {
                vent_pattern();
                // keep holes at least 6 mm inside the edge
                translate([0, 0, -1])
                    linear_extrude(height = 60) offset(delta = -6) outline_2d();
            }
    }
}

if (foot == "left") mirror([1, 0, 0]) insole(); else insole();
