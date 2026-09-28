// RAMANUJAN'S CONGRUENCES (interactive)
// p(n) is laid on a spiral with m tiles per turn, so tile n sits at angle
// 2 pi n / m and every residue class n mod m becomes a wedge. A tile is gold
// when m divides p(n). For m = 5, 7, 11 the class 24n = 1 (mod m) is gold all
// the way out:  p(5k+4) = 0 (mod 5),  p(7k+5) = 0 (mod 7),  p(11k+6) = 0 (mod 11).
// Drag the m slider through non-integer values to watch the spiral re-tune.

// slider geometry, in screen-height units from the centre
const float SX0 = -0.80, SX1 = -0.30, SY_M = -0.20, SY_R = -0.33, S_HIT = 0.045;
const float M_MIN = 2.0, M_MAX = 16.0, R_MIN = 6.0, R_MAX = 60.0;
const int   LMOD = 720720;              // lcm(1..16): p(n) mod m for every m <= 16
const int   PN = 1024;                  // table size
