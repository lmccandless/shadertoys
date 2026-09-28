// RAMANUJAN'S MOCK THETA FUNCTION (interactive)
// f(q) = 1 + q/(1+q)^2 + q^4/((1+q)^2(1+q^2)^2) + ...   (last letter, 1920)
// It erupts at every root of unity of even order 2k. Near each one,
// f(q) - (-1)^k b(q) stays bounded, b a theta function. So f - b tames the
// orders 4, 8, 12, ... and f + b tames 2, 6, 10, ...: every eruption is
// copied by a modular form, but no single one copies them all.

// sliders, in screen-height units from the centre
const float SX0 = -0.80, SX1 = -0.30, SY_S = -0.14, SY_R = -0.28, S_HIT = 0.045;
const float R_MIN = 0.95, R_MAX = 0.996;
