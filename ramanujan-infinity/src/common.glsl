// ============================================================================
//  RAMANUJAN: NOTES FROM THE EDGE OF INFINITY
// ----------------------------------------------------------------------------
//  Six movements, one loop:
//    I    p(n)        exact partition numbers, computed on the GPU (Buffer A)
//    II   congruences p(5k+4)=0 mod 5, p(7k+5)=0 mod 7, p(11k+6)=0 mod 11
//    III  the crown   the circle method: every root of unity is a singularity
//    IV   the edge    an endless modular zoom into the golden boundary point
//    V    -1/12       taming the divergent 1+2+3+...
//    VI   mock theta  the functions of his last letter (1920)
//
//  Buffer A  state: clock + exact p(n) table (bignum) + random partition
//  Buffer B  scene (HDR)
//  Buffer C  captions (Hershey stroke font)
//  Buffer D  bloom (from Buffer B's mip chain)
//  Image     composite, tone map, grain, timeline scrubber
//
//  Drag horizontally anywhere to scrub the timeline.
// ============================================================================

const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
const float PHI = 1.61803398874989;

// ---- timeline --------------------------------------------------------------
const int   N_ACTS  = 6;
const float T_TOTAL = 132.0;
const float T_FADE  = 2.4;          // cross-fade between movements

float actStart(int i) {
    // I: 0  II: 22  III: 42  IV: 66  V: 88  VI: 108  (loop at 132)
    return i == 0 ? 0.0 : i == 1 ? 22.0 : i == 2 ? 42.0 : i == 3 ? 66.0
         : i == 4 ? 88.0 : i == 5 ? 108.0 : T_TOTAL;
}
int actAt(float t) {
    int a = 0;
    for (int i = 1; i < N_ACTS; i++) if (t >= actStart(i)) a = i;
    return a;
}
// Weight of act i at film time t. Each movement fades in over the tail of the
// previous one; the first rises from black and the last sinks back into it.
float actWeight(int i, float t) {
    float s = actStart(i), e = actStart(i + 1);
    float fin  = i == 0 ? smoothstep(0.0, 1.5, t) : smoothstep(s, s + T_FADE, t);
    float fout = i == N_ACTS - 1 ? 1.0 - smoothstep(T_TOTAL - 2.5, T_TOTAL - 0.2, t)
                                 : 1.0 - smoothstep(e, e + T_FADE, t);
    return fin * fout;
}

// ---- small helpers -----------------------------------------------------------
vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }
vec2 cexp(vec2 z)         { return exp(z.x) * vec2(cos(z.y), sin(z.y)); }
vec2 clog(vec2 z)         { return vec2(0.5 * log(dot(z, z)), atan(z.y, z.x)); }
vec2 cconj(vec2 z)        { return vec2(z.x, -z.y); }

float sat(float x) { return clamp(x, 0.0, 1.0); }
float easeio(float x) { x = sat(x); return x * x * (3.0 - 2.0 * x); }
float win(float t, float a, float b, float f) { return smoothstep(a, a + f, t) * (1.0 - smoothstep(b - f, b, t)); }

// ---- Buffer A layout ---------------------------------------------------------
//  (0,0)  x film time, y frames since reset, z size of the random partition, w -
//  p(n) table: n in [0, 2048), 12 base-10^4 limbs = 3 texels per n,
//              64 values per row, rows PT_Y0 .. PT_Y0+31
//  profile:    column heights of the random partition, j in [1, 1024]
//  captions:   token stream (rows TX_Y0..) and font glyph extents (row FX_Y)
const int PT_Y0   = 2;
const int PT_N    = 2048;
const int PT_LEVELS = 8;            // recurrence levels resolved per frame
const int PR_Y0   = 40;
const int PR_N    = 1024;
const int TX_Y0   = 48;             // caption tokens, 256 per row (Buffer C)
const int FX_Y    = 60;             // glyph extents (left, width) per char code
const int CW_Y    = 61;             // static width of each caption (em)

ivec2 ptTexel(int n, int g) { return ivec2((n & 63) * 3 + g, PT_Y0 + (n >> 6)); }
ivec2 prTexel(int j)        { return ivec2((j - 1) & 255, PR_Y0 + ((j - 1) >> 8)); }

// ---- random partition (Boltzmann model, coupled across n) -------------------
//  Part k occurs m_k ~ Geometric(x^k) times, x = exp(-c/sqrt(n)), c = pi/sqrt(6).
//  With a fixed exponential variate E_k per k, m_k = floor(E_k sqrt(n) / (c k))
//  grows monotonically with n, so the diagram only ever gains cells.
const float CPART = 1.28254983016186;   // pi / sqrt(6)

uint hashu(uint x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
}
float hash1(uint x) { return (float(hashu(x) >> 8) + 0.5) * (1.0 / 16777216.0); }
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)) + 32768);
    return hash1(q.x * 1973u + hashu(q.y * 9277u + 26699u));
}
float partE(int k) { return -log(hash1(uint(k) * 747796405u + 679232157u)); }

// Nominal size parameter of the growing partition during movement I:
// exponential growth 1 -> 1100 over u in [6, 17], then a rush to 60000.
float partitionN(float u) {
    float b = easeio((u - 17.5) / 3.5);
    return exp(0.6368 * clamp(u - 6.0, -1.0, 11.0) + log(55.0) * b);
}

// Movements III -> IV: the dive onto the golden point and the endless zoom
const float DIVE_RATE = 0.45;       // exponential descent (1/s), matched by movement IV
float diveHeight(float u) { return 0.62 * exp(-DIVE_RATE * (u - 18.5)); }
const float KAPPA_LOG = 1.9248473;     // 4 log(phi): log-zoom of one step of M
const float EDGE_RATE = 1.35;

float edgeZoom(float u) {               // accumulated log-zoom since IV began
    float a = sat((u - 3.0) / 6.0);
    return DIVE_RATE * u + (EDGE_RATE - DIVE_RATE) * (6.0 * (a * a * a - 0.5 * a * a * a * a) + max(u - 9.0, 0.0));
}
float edgeStartScale() { return diveHeight(24.0) / (TAU * 1.6); }

// Movement V view (shared with the captions that label its points)
// view: s = centre + uv * scale; the real axis stays on the golden line of IV
void zetaView(float u, out vec2 ctr, out float sc) {
    float z = easeio((u - 12.5) / 8.0);
    ctr = mix(vec2(-0.6, 0.0), vec2(-1.0, 0.0), z);
    sc = mix(5.4, 3.6, z);
}

// ---- caption layout (Buffer A measures, Buffer C draws) ------------------------
const uint ITAL_ON = 256u, ITAL_OFF = 257u, SUP_ON = 258u, SUP_OFF = 259u, SUB_ON = 260u,
           SUB_OFF = 261u, OVER_ON = 262u, OVER_OFF = 263u, THIN = 264u, EQUIV = 265u,
           ARROW = 266u, CDOTS = 267u, FIELD0 = 280u;
struct Pen { float x, s, dy; bool ital; };
void penControl(inout Pen P, uint c) {
    if (c == ITAL_ON) P.ital = true;
    else if (c == ITAL_OFF) P.ital = false;
    else if (c == SUP_ON) { P.dy += 0.42 * P.s; P.s *= 0.62; }
    else if (c == SUP_OFF) { P.s /= 0.62; P.dy -= 0.42 * P.s; }
    else if (c == SUB_ON) { P.dy -= 0.16 * P.s; P.s *= 0.62; }
    else if (c == SUB_OFF) { P.s /= 0.62; P.dy += 0.16 * P.s; }
}
// advance in em of a glyph whose measured ink extents are `e` (left, width)
float glyphAdvance(uint c, vec2 e) {
    if (c == 32u) return 0.32;
    if (c == THIN) return 0.08;
    if (c == EQUIV) return 0.46;
    if (c == ARROW) return 0.62;
    if (c == CDOTS) return 0.52;
    return c >= 256u ? 0.0 : e.y + 0.1;
}

// Palette shared by scene and captions (linear RGB).
const vec3 INK     = vec3(0.004, 0.005, 0.012);
const vec3 GOLD    = vec3(1.00, 0.66, 0.24);
const vec3 SAFFRON = vec3(1.00, 0.42, 0.10);
const vec3 CRIMSON = vec3(0.80, 0.07, 0.12);
const vec3 PEACOCK = vec3(0.04, 0.50, 0.55);
const vec3 INDIGO  = vec3(0.10, 0.10, 0.45);
const vec3 IVORY   = vec3(0.95, 0.88, 0.74);
