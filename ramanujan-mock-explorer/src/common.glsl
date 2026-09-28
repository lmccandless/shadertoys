// MOCK THETA FIELD LINES
// Ramanujan's third-order mock theta function f(q) = 1 + q/(1+q)^2 + ...
// on the unit disk, drawn as field lines: coloured lines where its phase is a
// multiple of 1/12 turn, gold lines where |f| doubles. It erupts at every root
// of unity of even order; zoom into the rim to see the flowers it makes there.
// Click and hold: zoom continuously toward the cursor (steer by moving it);
// release: drift back out. Bottom-left: morph f + b | f | f - b, where b is a
// theta function that calms half of the eruptions each way.

const float UI_Y = -0.43, UI_HIT = 0.045;
const float MX0 = -0.82, MX1 = -0.50;     // morph slider
const float ZOOM_MAX = 15.0;              // log2 of the deepest zoom (x32768, ~float precision)
const float ZOOM_IN = 1.3, ZOOM_OUT = 1.8; // octaves per second while held / after release
const float DISK_R = 0.44;                // disk radius on screen at zoom 1
