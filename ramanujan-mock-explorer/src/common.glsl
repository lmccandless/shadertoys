// MOCK THETA FIELD LINES
// Ramanujan's third-order mock theta function f(q) = 1 + q/(1+q)^2 + ...
// on the unit disk, drawn as field lines: coloured lines where its phase is a
// multiple of 1/12 turn, gold lines where |f| doubles. It erupts at every root
// of unity of even order; zoom into the rim to see the flowers it makes there.
// Drag: pan.  Bottom-right: zoom.  Bottom-left: morph f + b | f | f - b, where
// b is a theta function that calms half of the eruptions each way.

const float UI_Y = -0.43, UI_HIT = 0.045;
const float MX0 = -0.82, MX1 = -0.50;     // morph slider
const float ZX0 = 0.50, ZX1 = 0.82;       // zoom slider
const float ZOOM_MAX = 8.0;               // log2 of the deepest zoom (x256)
const float DISK_R = 0.44;                // disk radius on screen at zoom 1
