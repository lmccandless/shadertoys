// Buffer B — the scene, in linear HDR.
//
// iChannel0 = Buffer A (clock, p(n) table, random partition)

#define DATA iChannel0

float PX;           // one pixel in screen-height units
float T;            // film time

vec2 screenUV(vec2 fc) { return (fc - 0.5 * iResolution.xy) / iResolution.y; }

vec3 background(vec2 uv) {
    float r = length(uv * vec2(0.8, 1.0));
    vec3 c = mix(vec3(0.010, 0.011, 0.028), INK, smoothstep(0.1, 0.9, r));
    return c;
}

// ============================================================================
//  I. p(n) — partitions
// ============================================================================
//  Diagrams are drawn in the "Russian" convention (rotated 45 degrees). Scaled
//  by 1/sqrt(n) a uniformly random partition converges to the curve
//  e^{-cx} + e^{-cy} = 1 (c = pi/sqrt 6), which in these coordinates is
//  v = 2 log(2 cosh(u/2)).

float pS(int j) {                       // column height S_j of the random partition
    if (j < 1 || j > PR_N) return 0.0;
    return texelFetch(DATA, prTexel(j), 0).x;
}

// the seven partitions of 5, as parts (largest first)
const int GAL[35] = int[35](5,0,0,0,0, 4,1,0,0,0, 3,2,0,0,0, 3,1,1,0,0,
                            2,2,1,0,0, 2,1,1,1,0, 1,1,1,1,1);
float galS(int d, int j) {              // column height of gallery diagram d
    float s = 0.0;
    for (int i = 0; i < 5; i++) s += GAL[d * 5 + i] >= j ? 1.0 : 0.0;
    return j < 1 ? 0.0 : s;
}

// Shaded diamond tile. `ab` are continuous cell coordinates, `cpx` the cell
// size in pixels. Returns rgb and coverage in .a
vec4 tile(vec2 ab, float cpx, vec3 base, float seed) {
    vec2 f = fract(ab) - 0.5;
    float gap = mix(0.0, 0.07, smoothstep(3.0, 9.0, cpx));
    vec2 d = abs(f) - (0.5 - gap);
    float rr = 0.12;
    float sd = length(max(d + rr, 0.0)) + min(max(d.x + rr, d.y + rr), 0.0) - rr;
    float cov = smoothstep(0.7 / cpx, -0.7 / cpx, sd);
    // bevel: light from above (in diagram coordinates, "above" is +a+b)
    float h = smoothstep(0.0, 0.22, -sd);
    vec2 n2 = sd > -0.22 ? normalize(f + 1e-4) : vec2(0.0);
    float lit = 0.75 + 0.45 * dot(n2, normalize(vec2(1.0, 1.0))) * (1.0 - h);
    float grain = 0.88 + 0.24 * hash12(vec2(seed, floor(ab.x) * 131.0 + floor(ab.y)));
    float detail = smoothstep(2.5, 7.0, cpx);
    vec3 c = base * mix(1.0, lit * grain, detail);
    c += base * 0.35 * pow(h * (1.0 - h) * 4.0, 3.0) * detail;
    return vec4(c, mix(1.0, cov, detail));
}

vec3 cellColor(float u, float v) {
    float k = smoothstep(0.0, 3.6, abs(u));
    vec3 c = mix(GOLD * 1.25, SAFFRON, smoothstep(0.0, 0.5, k));
    c = mix(c, CRIMSON * 0.9, smoothstep(0.35, 1.0, k));
    return c * (1.05 - 0.25 * smoothstep(0.5, 4.0, v));
}

// distance (cell units) from (a,b) to the boundary of a staircase region
float stairDist(vec2 ab, int j0, bool gallery, int d) {
    float best = 1e9;
    for (int dj = -2; dj <= 2; dj++) {
        int j = j0 + dj;
        if (j < 1) continue;
        float Sj  = gallery ? galS(d, j) : pS(j);
        float Sj1 = gallery ? galS(d, j + 1) : pS(j + 1);
        if (Sj <= 0.0 && Sj1 <= 0.0) continue;
        // top edge of column j:  b = Sj, a in [j-1, j]
        if (Sj > 0.0) best = min(best, length(vec2(ab.x - clamp(ab.x, float(j - 1), float(j)), ab.y - Sj)));
        // right edge of column j: a = j, b in [S_{j+1}, S_j]
        best = min(best, length(vec2(ab.x - float(j), ab.y - clamp(ab.y, min(Sj1, Sj), max(Sj1, Sj)))));
    }
    return best;
}

// distance to the two axes of a diagram with `len` parts and largest part `lam`
float axisDist(vec2 ab, float len, float lam) {
    return min(length(vec2(ab.x, ab.y - clamp(ab.y, 0.0, len))),
               length(vec2(ab.x - clamp(ab.x, 0.0, lam), ab.y)));
}

vec3 actPartitions(vec2 uv, float u) {
    vec3 col = background(uv);
    const float K = 0.30;                       // screen-height per scaled unit
    vec2 org = vec2(0.0, -0.47);

    // --- the gallery: all seven partitions of 5 ---------------------------
    float galA = win(u, 0.6, 6.4, 0.8);
    if (galA > 0.0) {
        float s = 0.042;                        // cell edge in screen units
        for (int d = 0; d < 7; d++) {
            float appear = smoothstep(0.9 + 0.32 * float(d), 1.5 + 0.32 * float(d), u);
            if (appear <= 0.0) continue;
            float lam = float(GAL[d * 5]), len = galS(d, 1);
            vec2 o = vec2((float(d) - 3.0) * 0.232 - (lam - len) * s / (2.0 * sqrt(2.0)),
                          -0.16 - 0.02 * (1.0 - appear));
            vec2 q = uv - o;
            vec2 ab = vec2(q.y + q.x, q.y - q.x) / sqrt(2.0) / s;
            int j = int(floor(ab.x)) + 1;
            float cpx = s / PX;
            bool inside = ab.x >= 0.0 && ab.y >= 0.0 && ab.y < galS(d, j);
            if (inside) {
                vec4 tl = tile(ab, cpx, cellColor((ab.x - ab.y) * 0.9, 0.0), float(d));
                col = mix(col, tl.rgb, tl.a * appear * galA);
            }
            float e = stairDist(ab, j, true, d);
            e = min(e, axisDist(ab, galS(d, 1), lam)) * cpx;
            col += GOLD * (0.55 * exp(-e * 0.35) + 1.2 * smoothstep(1.4, 0.4, e)) * appear * galA * 0.5;
        }
    }

    // --- the growing random partition -------------------------------------
    float grow = smoothstep(5.2, 6.6, u);
    if (grow <= 0.0) return col;
    vec4 info = texelFetch(DATA, ivec2(1, 0), 0);
    float n = info.w;
    float G = sqrt(n) / CPART;                  // cells per scaled unit
    vec2 p = (uv - org) / K;                    // scaled, rotated coordinates
    float U = p.x, V = p.y;
    vec2 XY = vec2(V + U, V - U) / sqrt(2.0);   // scaled (x, y)
    vec2 ab = XY * G;                           // cell coordinates
    float cpx = K / G / PX;                     // cell edge in pixels
    int j = int(floor(ab.x)) + 1;

    float cov = 0.0;
    vec3 tcol = vec3(0.0);
    if (cpx > 3.0) {
        if (ab.x >= 0.0 && ab.y >= 0.0 && ab.y < pS(j)) {
            vec4 tl = tile(ab, cpx, cellColor(U * sqrt(2.0), V * sqrt(2.0)), 7.0);
            tcol = tl.rgb; cov = tl.a;
        }
    } else {
        // cells are tiny: supersample the region coverage
        for (int s = 0; s < 4; s++) {
            vec2 o = (vec2(s & 1, s >> 1) - 0.5) * 0.5 * PX / K * G;
            vec2 q = ab + vec2(o.x + o.y, o.y - o.x) / sqrt(2.0);
            int jj = int(floor(q.x)) + 1;
            cov += (q.x >= 0.0 && q.y >= 0.0 && q.y < pS(jj)) ? 0.25 : 0.0;
        }
        tcol = cellColor(U * sqrt(2.0), V * sqrt(2.0)) * (0.9 + 0.1 * smoothstep(0.0, 3.0, cpx));
    }
    // limit shape  v = 2 log(2 cosh(u/2))  in scaled (u, v)
    float cu = U * sqrt(2.0), cv = V * sqrt(2.0);
    float vc = 2.0 * log(2.0 * cosh(0.5 * cu));
    // once the cells are tiny, glow brightest near the edge, like an ember
    float depth = max(vc - cv, 0.0);
    tcol *= mix(1.0, 0.28 + 0.72 * exp(-depth / 0.42), smoothstep(5.0, 1.5, cpx));
    col = mix(col, tcol, cov * grow);
    float es = stairDist(ab, j, false, 0);

    // golden outline of the staircase
    float e = min(es, axisDist(ab, pS(1), info.z)) * cpx;
    float lineW = mix(0.6, 1.2, smoothstep(2.0, 12.0, cpx));
    col += GOLD * (0.35 * exp(-e * 0.25) + 1.4 * smoothstep(lineW + 0.8, lineW - 0.4, e)) * grow
         * mix(0.35, 1.0, smoothstep(1.0, 6.0, cpx));

    // the limit curve itself
    float slope = tanh(0.5 * cu);
    float dc = abs(cv - vc) / sqrt(1.0 + slope * slope) * K / sqrt(2.0) / PX;
    float curveA = smoothstep(12.0, 18.0, u);
    col += mix(GOLD, IVORY, 0.4) * curveA * (1.6 * smoothstep(1.6, 0.3, dc) + 0.25 * exp(-dc * 0.08));
    return col;
}

// ============================================================================
//  placeholders for the remaining movements
// ============================================================================

// ============================================================================
//  II. Congruences:  p(5k+4) = 0 mod 5,  p(7k+5) = 0 mod 7,  p(11k+6) = 0 mod 11
// ============================================================================
//  p(n) is laid along a spiral with m tiles per turn, so tile n sits at angle
//  2 pi n / m. When m is an integer every residue class n mod m becomes a
//  wedge. Tiles are gold when m divides p(n): for m = 5, 7, 11 the class
//  24n = 1 (mod m) is an unbroken golden wedge. For 13 there is none.

int pMod(int n, int m) {
    vec4 L0 = texelFetch(DATA, ptTexel(n, 0), 0);
    vec4 L1 = texelFetch(DATA, ptTexel(n, 1), 0);
    vec4 L2 = texelFetch(DATA, ptTexel(n, 2), 0);
    int b = 10000 % m, pw = 1, r = 0;
    for (int i = 0; i < 12; i++) {
        vec4 L = i < 4 ? L0 : i < 8 ? L1 : L2;
        int k = i & 3;
        int limb = int(k == 0 ? L.x : k == 1 ? L.y : k == 2 ? L.z : L.w);
        r = (r + (limb % m) * pw) % m;
        pw = (pw * b) % m;
    }
    return r;
}

int special(int m) {            // the residue class 24n = 1 (mod m)
    for (int d = 0; d < 13; d++) if ((24 * d) % m == 1) return d;
    return 0;
}

// modulus schedule: hold 5, 7, 11, 13 with swirling transitions
void congruenceSchedule(float u, out float m, out int ma, out int mb, out float x) {
    const float H[8] = float[8](6.4, 8.2, 11.6, 13.4, 16.8, 18.6, 99.0, 99.0);
    const int   M[5] = int[5](5, 7, 11, 13, 13);
    int i = 0;
    for (int k = 0; k < 3; k++) if (u > H[2 * k]) i = k + 1;
    ma = M[max(i - 1, 0)]; mb = M[i];
    x = i == 0 ? 1.0 : easeio((u - H[2 * i - 2]) / (H[2 * i - 1] - H[2 * i - 2]));
    if (i == 0) ma = mb;
    m = mix(float(ma), float(mb), x);
}

float congruenceOffset(int m) { return PI * 0.5 - TAU * (float(special(m)) + 0.5) / float(m); }

vec3 jewel(float h) {
    vec3 a = mix(vec3(0.10, 0.12, 0.62), vec3(0.02, 0.48, 0.55), smoothstep(0.0, 0.5, h));
    return mix(a, vec3(0.55, 0.10, 0.62), smoothstep(0.5, 1.0, h));
}

vec3 tileColor(int n, int m, float sparkle) {
    int r = pMod(n, m);
    if (r == 0) return GOLD * (1.5 + 1.2 * sparkle);
    return jewel(float(r - 1) / float(max(m - 2, 1))) * (0.45 + 0.4 * hash1(uint(n * 7 + m)));
}

vec3 actCongruences(vec2 uv, float u) {
    vec3 col = background(uv);
    float m; int ma, mb; float x;
    congruenceSchedule(u, m, ma, mb, x);
    float off = mix(congruenceOffset(ma), congruenceOffset(mb), x);
    // the wedge is "locked" while m rests on a modulus with a congruence
    float lockA = (ma == 13 ? 0.0 : 1.0) * (1.0 - x), lockB = (mb == 13 ? 0.0 : 1.0) * x;
    float lock = pow(max(1.0 - abs(m - floor(m + 0.5)) * 4.0, 0.0), 2.0) * max(lockA, lockB);
    lock *= smoothstep(2.5, 4.0, u);

    vec2 c = uv - vec2(0.30, 0.0);             // the window sits right of the text
    float rho = length(c);
    float th = mod(atan(c.y, c.x) - off, TAU);
    const float RIN = 0.075, ROUT = 0.475;
    const float RINGS = 30.0;
    float w = (ROUT - RIN) / RINGS;
    float sf = (rho - RIN) / w;                 // continuous turn coordinate
    float s0 = th / TAU;
    float k = floor(sf - s0 + 0.5);
    float sp = s0 + k;                          // spiral parameter of this band
    float dr = sf - sp;                         // radial offset in [-0.5, 0.5]
    float xs = sp * m;
    int n = int(floor(xs));
    float fx = fract(xs);

    // wedge light: a shaft of gold along the locked residue class
    float wedgeAng = abs(mod(atan(c.y, c.x) - PI * 0.5 + PI, TAU) - PI);
    float halfW = PI / m;
    float beam = smoothstep(halfW * 1.05, halfW * 0.4, wedgeAng) * smoothstep(RIN * 0.5, ROUT, rho);
    col += GOLD * 0.10 * lock * beam * smoothstep(ROUT + 0.25, ROUT, rho);

    if (sp < 0.0 || sp >= RINGS || n < 0) {
        // hub
        float hub = smoothstep(RIN - 0.004, RIN - 0.006 - PX, rho);
        col = mix(col, vec3(0.012, 0.012, 0.03), hub);
        col += GOLD * 0.9 * smoothstep(1.5 * PX, 0.0, abs(rho - RIN + 0.008));
        col += GOLD * 0.5 * smoothstep(1.5 * PX, 0.0, abs(rho - ROUT - 0.008)) * smoothstep(2.0, 3.5, u);
        return col;
    }

    // tile geometry (screen units)
    float L = TAU * rho / m;
    vec2 q = vec2((fx - 0.5) * L, dr * w);
    vec2 hs = vec2(0.5 * L, 0.5 * w) - 1.1 * PX;
    float rr = min(0.35 * w, 3.0 * PX);
    vec2 d = abs(q) - hs + rr;
    float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rr;
    float cov = smoothstep(0.75 * PX, -0.75 * PX, sd);
    float bev = smoothstep(0.0, 0.35 * w, -sd);

    // tiles appear in order of n
    float nVis = 620.0 * easeio((u - 0.3) / 3.2);
    float appear = sat((nVis - float(n)) / 25.0);

    float sparkle = pow(0.5 + 0.5 * sin(u * 3.0 + float(n) * 2.3), 8.0);
    vec3 tc = tileColor(n, ma, sparkle);
    if (mb != ma) tc = mix(tc, tileColor(n, mb, sparkle), x);
    // the locked wedge burns brighter
    bool inWedge = wedgeAng < halfW;
    tc *= 1.0 + lock * (inWedge ? 0.8 : -0.25);
    vec3 shade = tc * (0.55 + 0.45 * bev) + tc * 0.25 * (1.0 - bev) * sign(dr);
    col = mix(col, shade, cov * appear);
    col += GOLD * 0.25 * lock * beam * cov * appear;
    return col;
}

// ============================================================================
//  Modular machinery shared by III, IV and VI
// ============================================================================
//  tau = x + iy in the upper half plane is moved into the fundamental domain
//  |x| <= 1/2, |tau| >= 1 by tau -> tau - n and tau -> -1/tau, tracking the
//  matrix g = (a b; c d) with g.tau = tau0. The cusp that "owns" tau is
//  g^-1(i inf) = -d/c: tau lies in the Ford circle of -d/c iff Im(tau0) >= 1.
//  y^(1/4)|eta(tau)| is invariant, so log|eta(tau)| = log|eta(tau0)| + log(y0/y)/4.
struct Mod { vec2 t0; vec4 g; };

Mod reduceTau(vec2 tau) {
    float x = tau.x, y = tau.y;
    vec4 g = vec4(1.0, 0.0, 0.0, 1.0);
    for (int i = 0; i < 48; i++) {
        float n = floor(x + 0.5);
        x -= n;
        g.xy -= n * g.zw;
        float r2 = x * x + y * y;
        if (r2 >= 1.0) break;
        x = -x / r2; y = y / r2;
        g = vec4(-g.z, -g.w, g.x, g.y);
    }
    return Mod(vec2(x, y), g);
}

// log|eta(tau0)| for tau0 in the fundamental domain (|q0| < 0.0044)
float logEta0(vec2 t0) {
    vec2 q = exp(-TAU * t0.y) * vec2(cos(TAU * t0.x), sin(TAU * t0.x));
    vec2 qn = q, pr = vec2(1.0, 0.0);
    for (int n = 1; n <= 3; n++) { pr = cmul(pr, vec2(1.0, 0.0) - qn); qn = cmul(qn, q); }
    return -PI * t0.y / 12.0 + 0.5 * log(dot(pr, pr));
}

// ============================================================================
//  III. The crown — the circle method
// ============================================================================
//  P(q) = sum p(n) q^n = prod 1/(1-q^n) = q^(1/24)/eta(tau). Near the root of
//  unity e^(2 pi i h/k), (1-|q|) log|P(q)| -> pi^2/(6k^2). We plot
//      L = (6/pi^2)(1-|q|) log|P(q)|,    height ~ sqrt(L) -> 1/k at the rim
//  (Thomae's popcorn function, wrapped around the circle). The raised lobes are
//  the Ford circles of the circle method; the tallest, at q = 1, is where
//  Hardy and Ramanujan's main term  e^(pi sqrt(2n/3)) / (4n sqrt 3)  lives.
const float CROWN_H = 0.34;

float gCrownH;       // current relief scale (flattens during the final dive)

// world xz -> q = x - iz, so that looking down with the disk centre "up" shows
// the rim with Re(tau) increasing to the right, as in movement IV
float crownL(vec2 w, float yMin, out Mod m, out float y) {
    vec2 q = vec2(w.x, -w.y);
    float r = max(length(q), 1e-6);
    y = max(-log(r) / TAU, yMin);
    m = reduceTau(vec2(atan(q.y, q.x) / TAU, y));
    float logEta = logEta0(m.t0) + 0.25 * log(m.t0.y / y);
    float logP = -PI * y / 12.0 - logEta;
    return 0.6079271 * (1.0 - exp(-TAU * y)) * logP;
}

float crownHeight(vec2 q, float yMin) {
    Mod m; float y;
    float L = crownL(q, yMin, m, y);
    float h = L / sqrt(abs(L) + 0.004);
    h *= smoothstep(0.0, 0.004, 1.0 - length(q));   // let the lobes meet the rim
    return gCrownH * (h > 0.0 ? h : 0.35 * h);
}

// Cusp colours cycle once per factor phi^2 in the denominator k, so the
// endless zoom of movement IV (which multiplies denominators by ~phi^2 per
// step) loops seamlessly in colour too.
vec3 cyclePalette(float s) {
    s = fract(s) * 5.0;
    vec3 P0 = GOLD * 1.1, P1 = SAFFRON, P2 = CRIMSON * 1.1, P3 = vec3(0.42, 0.10, 0.62), P4 = PEACOCK * 1.3;
    vec3 c = mix(P0, P1, smoothstep(0.0, 1.0, s));
    c = mix(c, P2, smoothstep(1.0, 2.0, s));
    c = mix(c, P3, smoothstep(2.0, 3.0, s));
    c = mix(c, P4, smoothstep(3.0, 4.0, s));
    return mix(c, P0, smoothstep(4.0, 5.0, s));
}
vec3 cuspColor(float k) { return cyclePalette(log(max(k, 1.0)) / 0.962424); }

// camera path: top-down mandala -> tilt -> glide along the rim -> dive to the
// golden point e^(2 pi i/phi) (the next movement continues from there)

void crownCamera(float u, out vec3 ro, out vec3 ta, out vec3 upHint) {
    float gAng = TAU / PHI;                         // the golden point e^(2 pi i/phi)
    vec3 gp = vec3(cos(gAng), 0.0, -sin(gAng));
    // 1: overhead mandala, slowly turning; 2: tilt and orbit
    float a = easeio((u - 2.5) / 6.5);
    float ang = 0.9 + 0.07 * u + 0.8 * a;
    float el = mix(1.50, 0.40, a);
    float dist = mix(2.45, 2.05, a);
    ro = dist * vec3(cos(el) * cos(ang), sin(el), cos(el) * sin(ang));
    ta = vec3(0.0, -0.08 * a, 0.0);
    upHint = vec3(0.0, 1.0, 0.0);
    // 3: rise over the centre and look out towards the golden point
    float b = easeio((u - 10.0) / 5.5);
    vec3 side = vec3(gp.z, 0.0, -gp.x);
    float fwd = mix(-0.05, 0.42, easeio((u - 13.0) / 5.0));
    vec3 roB = gp * fwd + side * 0.10 + vec3(0.0, mix(0.62, 0.32, easeio((u - 13.0) / 5.0)), 0.0);
    vec3 taB = gp * 1.1 + vec3(0.0, 0.02, 0.0);
    ro = mix(ro, roB, b);
    ta = mix(ta, taB, easeio((u - 9.0) / 4.5));   // look first, then move
    // 4: pitch straight down onto the golden point and fall towards it
    float c = easeio((u - 17.0) / 4.0);
    vec3 roD = gp + vec3(0.0, diveHeight(max(u, 18.5)), 0.0);
    ro = mix(ro, roD, c);
    ta = mix(ta, gp, c);
    // screen-up points to the disk centre, so the rim lies flat along the bottom
    upHint = normalize(mix(upHint, -gp, smoothstep(0.3, 0.8, c)));
}

vec3 crownSky(vec3 rd) {
    float h = rd.y;
    vec3 c = mix(vec3(0.012, 0.012, 0.03), vec3(0.03, 0.025, 0.07), smoothstep(-0.2, 0.6, h));
    c += GOLD * 0.25 * pow(max(dot(rd, normalize(vec3(-0.4, 0.35, 0.8))), 0.0), 12.0);
    return c;
}

vec3 actCrown(vec2 uv, float u) {
    vec3 ro, ta, up;
    crownCamera(u, ro, ta, up);
    gCrownH = CROWN_H * (1.0 - smoothstep(18.0, 22.5, u));
    vec3 fw = normalize(ta - ro);
    if (abs(dot(fw, up)) > 0.999) up = vec3(0.0, 0.0, 1.0);
    vec3 rt = normalize(cross(fw, up));
    vec3 upv = cross(rt, fw);
    const float FOV = 1.6;
    vec3 rd = normalize(uv.x * rt + uv.y * upv + FOV * fw);
    float pixAng = PX / FOV;

    vec3 col = crownSky(rd);

    // bounding cylinder r <= 1, slab y in [-0.1, 1.05] * H
    float tmin = 1e9, tmax = -1e9;
    {
        vec2 o = ro.xz, d = rd.xz;
        float A = dot(d, d), B = dot(o, d), C = dot(o, o) - 1.0;
        float disc = B * B - A * C;
        if (disc > 0.0 && A > 1e-8) {
            float sq = sqrt(disc);
            tmin = (-B - sq) / A; tmax = (-B + sq) / A;
        } else if (A <= 1e-8 && C < 0.0) { tmin = -1e9; tmax = 1e9; }
        float y0 = -0.12 * gCrownH - 1e-3, y1 = 1.05 * gCrownH + 1e-3;
        float ta0 = (y0 - ro.y) / rd.y, ta1 = (y1 - ro.y) / rd.y;
        tmin = max(tmin, min(ta0, ta1));
        tmax = min(tmax, max(ta0, ta1));
        tmin = max(tmin, 0.0);
    }

    // floor outside the disk
    float tf = (-0.02 - ro.y) / rd.y;
    if (tf > 0.0) {
        vec3 pf = ro + rd * tf;
        float rr = length(pf.xz);
        if (rr > 1.0) {
            vec3 fl = vec3(0.004, 0.004, 0.010) + GOLD * 0.05 * exp(-(rr - 1.0) * 25.0);
            col = mix(fl, col, smoothstep(2.0, 6.0, tf));
        }
    }

    bool hit = false, wall = false;
    float t = tmin;
    vec3 p;
    if (tmin < tmax) {
        float tPrev = t, dPrev = 1.0;
        for (int i = 0; i < 180; i++) {
            p = ro + rd * t;
            float fp = t * pixAng;
            float yMin = 1.2 * fp / TAU;
            float h = crownHeight(p.xz, yMin);
            float d = p.y - h;
            if (d < 0.0 && i == 0 && length(p.xz) > 0.999) {
                wall = true; hit = true;          // entered through the rim cliff
                break;
            }
            if (d < 0.0) {
                // refine between the last two samples
                float lo = tPrev, hi = t;
                for (int j = 0; j < 6; j++) {
                    float mid = 0.5 * (lo + hi);
                    vec3 pm = ro + rd * mid;
                    if (pm.y - crownHeight(pm.xz, yMin) < 0.0) hi = mid; else lo = mid;
                }
                t = hi; p = ro + rd * t; hit = true;
                break;
            }
            tPrev = t;
            float r = length(p.xz);
            float nearRim = mix(0.25, 1.0, smoothstep(0.02, 0.25, 1.0 - r));
            t += max(d * 0.45 * nearRim, 0.6 * fp);
            if (t > tmax) break;
        }
    }

    if (wall) {
        vec3 nw = vec3(p.x, 0.0, p.z);
        float top = crownHeight(p.xz * 0.9999, t * pixAng * 1.2 / TAU);
        float f = sat(p.y / max(top, 1e-3));
        vec3 c = vec3(0.02, 0.015, 0.03) + GOLD * (0.08 + 0.5 * pow(f, 6.0));
        c += crownSky(reflect(rd, nw)) * 0.4;
        col = c;
    } else if (hit) {
        float fp = t * pixAng;
        float yMin = 1.2 * fp / TAU;
        Mod m; float y;
        float L = crownL(p.xz, yMin, m, y);
        float e = max(1.5 * fp, 1e-4);
        vec3 nor = normalize(vec3(crownHeight(p.xz - vec2(e, 0.0), yMin) - crownHeight(p.xz + vec2(e, 0.0), yMin),
                                  2.0 * e,
                                  crownHeight(p.xz - vec2(0.0, e), yMin) - crownHeight(p.xz + vec2(0.0, e), yMin)));
        float k = abs(m.g.z);
        vec3 kc = cuspColor(k);
        float lobe = smoothstep(-0.002, 0.02, L);
        vec3 alb = mix(vec3(0.016, 0.018, 0.05) + kc * 0.07, kc * 0.55, lobe);

        vec3 ld = normalize(vec3(-0.4, 0.75, 0.55));
        float dif = max(dot(nor, ld), 0.0);
        vec3 hv = normalize(ld - rd);
        float spe = pow(max(dot(nor, hv), 0.0), mix(24.0, 80.0, lobe));
        float fre = pow(1.0 - max(dot(nor, -rd), 0.0), 4.0);
        vec3 c = alb * (0.08 + 0.95 * dif);
        c += mix(vec3(0.25, 0.3, 0.5), kc, lobe) * spe * mix(0.25, 1.0, lobe);
        c += crownSky(reflect(rd, nor)) * fre * 1.5;

        // candle-glow at the lobe tips: L k^2 -> 1 at the rim point
        c += kc * 1.8 * pow(sat(L * k * k), 5.0) * lobe;

        // Ford-domain boundaries (|tau0| = 1), drawn at constant pixel width
        float r = length(p.xz);
        float cell = TAU * r * y;                    // world size of one hyperbolic unit
        float dh = abs(length(m.t0) - 1.0) / m.t0.y;
        float dw = dh * cell;
        float lod = smoothstep(3.0 * fp, 12.0 * fp, cell * 0.3);
        c += mix(GOLD, kc, 0.3) * 0.6 * smoothstep(1.6 * fp, 0.4 * fp, dw) * lod;
        // horocycles Im(tau0) = 2^j: the nested Ford circles, like contour lines
        float lj = log2(max(m.t0.y, 1e-6));
        float dho = abs(lj - floor(lj + 0.5)) * 0.693147 * cell;
        float lodH = smoothstep(4.0 * fp, 16.0 * fp, cell * 0.69);
        c += kc * 0.35 * smoothstep(1.4 * fp, 0.3 * fp, dho) * lodH * step(1.0, m.t0.y) * lobe;
        // soft stained-glass glow in the Ford domains
        c += kc * 0.05 * (1.0 - lobe);

        col = mix(c, col, smoothstep(3.0, 7.0, t));  // distance haze
    }

    // the unit circle: the natural boundary
    {
        // closest approach of the ray to the rim circle at height ~0
        float tc = (0.0 - ro.y) / rd.y;
        vec3 pc = ro + rd * max(tc, 0.0);
        float dr = abs(length(pc.xz) - 1.0);
        float fp = max(tc, 0.0) * pixAng;
        if (tc > 0.0 && (!hit || tc < t + 0.02))
            col += GOLD * 0.9 * smoothstep(2.0 * fp, 0.3 * fp, dr);
    }
    return col;
}

// ============================================================================
//  IV. The edge — an endless zoom into the golden point
// ============================================================================
//  Continuing the dive of III, we fall into the rim at q = e^(2 pi i/phi),
//  i.e. tau = phi. M = (2 1; 1 1) is in SL2(Z) and fixes phi; in the
//  coordinate sigma = (tau - phi)/(tau + 1/phi) it is exactly the dilation
//  sigma -> phi^-4 sigma. Everything drawn here is built from SL2(Z)-invariant
//  quantities (the reduced point tau0, horocycles, hyperbolic sizes), so the
//  picture after one step of M is identical: the zoom never ends, and never
//  runs out of floating-point precision. Denominators grow by ~phi^2 per step:
//  21/13 -> 55/34 -> 144/89 -> ... -> phi.

struct EdgeSample { Mod m; float y, cellPx; bool mirror; };

EdgeSample edgeSample(vec2 uv, float Sf) {
    vec2 sig = uv * Sf / sqrt(5.0);
    vec2 d = cdiv(sig * sqrt(5.0), vec2(1.0, 0.0) - sig);   // tau - phi
    EdgeSample e;
    e.mirror = d.y < 0.0;
    d.y = abs(d.y);
    vec2 tau = vec2(PHI - 2.0 + d.x, max(d.y, 1e-9));
    e.m = reduceTau(tau);
    e.m.g.xy += 2.0 * e.m.g.zw;         // account for the shift by 2 above
    e.y = tau.y;
    vec2 om = vec2(1.0, 0.0) - sig;
    float pxT = PX * Sf / dot(om, om);  // one pixel, in tau units
    e.cellPx = tau.y / pxT;             // one hyperbolic unit, in pixels
    return e;
}

vec3 actEdge(vec2 uv, float u) {
    float z = edgeZoom(u);
    float tl = z / KAPPA_LOG;
    float Sf = edgeStartScale() * exp(-fract(tl) * KAPPA_LOG);

    EdgeSample e = edgeSample(uv, Sf);
    float y0 = e.m.t0.y, k = abs(e.m.g.z);
    vec3 kc = cuspColor(k);
    float cell = e.cellPx;

    // the raised lobes first match III, then swell into the full Ford circles
    float lobeY = mix(8.7, 1.0, easeio((u - 2.0) / 4.5));
    float lg = log(y0 / lobeY);
    float lobe = smoothstep(-0.8, 0.8, lg * cell);

    // relief: over each Ford circle a dome of height y*sqrt(s-1) (in pixels)
    float relief = easeio((u - 3.0) / 4.0);
    vec3 nor = vec3(0.0, 0.0, 1.0);
    if (relief > 0.0 && lobe > 0.0) {
        EdgeSample ex = edgeSample(uv + vec2(PX, 0.0), Sf);
        EdgeSample ey = edgeSample(uv + vec2(0.0, PX), Sf);
        float Z0 = cell * sqrt(max(y0 / lobeY - 1.0, 0.0));
        float Zx = ex.cellPx * sqrt(max(ex.m.t0.y / lobeY - 1.0, 0.0));
        float Zy = ey.cellPx * sqrt(max(ey.m.t0.y / lobeY - 1.0, 0.0));
        if (abs(ex.m.g.z) != k) Zx = Z0;
        if (abs(ey.m.g.z) != k) Zy = Z0;
        vec2 gr = vec2(Zx - Z0, Zy - Z0) * (e.mirror ? vec2(1.0, -1.0) : vec2(1.0));
        nor = normalize(vec3(-gr * relief * 0.9, 1.0));
    }

    vec3 alb = mix(vec3(0.016, 0.018, 0.05) + kc * 0.07, kc * 0.55, lobe);
    vec3 ld = normalize(vec3(-0.45, 0.55, 0.70));
    float dif = max(dot(nor, ld), 0.0);
    vec3 hv = normalize(ld + vec3(0.0, 0.0, 1.0));
    float spe = pow(max(dot(nor, hv), 0.0), mix(24.0, 80.0, lobe));
    vec3 c = alb * (0.08 + 0.95 * dif) * mix(1.0, 1.25, relief * lobe);
    c += mix(vec3(0.25, 0.3, 0.5), kc, lobe) * spe * mix(0.25, 1.0, lobe) * mix(0.35, 1.0, relief);
    // rim light on the domes
    c += kc * 0.5 * pow(1.0 - nor.z, 2.0) * lobe * relief;
    // glow near each point of tangency (the cusp itself)
    c += kc * 1.8 * pow(sat(1.0 - lobeY / y0), 5.0) * lobe;

    // boundaries of the Ford domains |tau0| = 1, and horocycles Im tau0 = 2^j
    float dh = abs(length(e.m.t0) - 1.0) / y0 * cell;
    float lod = smoothstep(3.0, 12.0, cell * 0.3);
    c += mix(GOLD, kc, 0.3) * 0.6 * smoothstep(1.6, 0.4, dh) * lod;
    float lj = log2(y0);
    float dho = abs(lj - floor(lj + 0.5)) * 0.693147 * cell;
    c += kc * 0.35 * smoothstep(1.4, 0.3, dho) * smoothstep(4.0, 16.0, cell * 0.69) * step(1.0, y0) * lobe;
    c += kc * 0.05 * (1.0 - lobe);

    // below a few pixels per hyperbolic unit, dissolve into a golden haze
    vec3 haze = mix(GOLD, SAFFRON, 0.4) * 0.35;
    c = mix(haze, c, smoothstep(0.6, 3.0, cell));

    // the real line (the rim of the disk) and the world below it
    float dl = abs(uv.y) / PX;
    if (e.mirror) c *= 0.16 * smoothstep(1.0, 4.0, u) * exp(-abs(uv.y) * 3.0);
    c += GOLD * (1.1 * smoothstep(1.6, 0.3, dl) + 0.25 * exp(-dl * 0.08));
    return c;
}

// ============================================================================
//  V. 1 + 2 + 3 + 4 + ... = -1/12
// ============================================================================
//  "I told him that the sum of an infinite number of terms of the series
//   1 + 2 + 3 + 4 + ... = -1/12 under my theory."  (letter to Hardy, 1913)
//  Ramanujan's "constant" of a series is the value of its analytic
//  continuation. Phase portrait of zeta(s): both constants behind the
//  partition function are values of this one function:
//      zeta(2)  =  pi^2/6  ->  log P(e^-t) ~ pi^2/(6t),  p(n) ~ e^(pi sqrt(2n/3))
//      zeta(-1) = -1/12    ->  q^(1/24) = q^(-zeta(-1)/2), the factor that
//                              makes eta(tau) modular (movement IV)
const float BW[18] = float[18](-1.0, 1.0, -0.999999998, 0.999999899, -0.999997675, 0.999967238,
    -0.999691461, 0.997945883, -0.989945315, 0.962753843, -0.893200919, 0.758310399,
    -0.55988449, 0.340089638, -0.1598346, 0.0537534737, -0.0114065727, 0.00114065727);

vec2 zetaBorwein(vec2 s) {              // Re s >= 1/2
    vec2 sum = vec2(0.0);
    for (int k = 0; k < 18; k++) sum += BW[k] * cexp(-s * log(float(k + 1)));
    vec2 den = vec2(1.0, 0.0) - cexp((vec2(1.0, 0.0) - s) * 0.693147181);
    return -cdiv(sum, den);
}

vec2 clogGamma(vec2 z) {                // Re z >= 1/2, Stirling after a shift of 7
    vec2 acc = vec2(0.0);
    for (int j = 0; j < 7; j++) acc += clog(z + vec2(float(j), 0.0));
    vec2 w = z + vec2(7.0, 0.0);
    vec2 iw = cdiv(vec2(1.0, 0.0), w), iw2 = cmul(iw, iw);
    vec2 ser = iw * (1.0 / 12.0) - cmul(iw, iw2) * (1.0 / 360.0) + cmul(cmul(iw, iw2), iw2) * (1.0 / 1260.0);
    return cmul(w - vec2(0.5, 0.0), clog(w)) - w + vec2(0.918938533, 0.0) + ser - acc;
}

vec2 zeta(vec2 s) {
    if (s.x >= 0.5) return zetaBorwein(s);
    // functional equation: zeta(s) = 2^s pi^(s-1) sin(pi s/2) Gamma(1-s) zeta(1-s)
    vec2 one = vec2(1.0, 0.0);
    vec2 lg = s * 0.693147181 + (s - one) * 1.144729886 + clogGamma(one - s);
    vec2 a = 0.5 * PI * s;
    vec2 sn = vec2(sin(a.x) * cosh(a.y), cos(a.x) * sinh(a.y));
    return cmul(cmul(cexp(lg), sn), zetaBorwein(one - s));
}

vec2 zetaPath(float v) {                // around the pole, from s = 2 to s = -1
    float a = PI * v;
    return vec2(0.5 + 1.5 * cos(a), 1.5 * sin(a));
}

vec3 actMinus12(vec2 uv, float u) {
    vec2 ctr; float sc;
    zetaView(u, ctr, sc);
    vec2 sp = ctr + uv * sc;
    float pxS = PX * sc;                 // one pixel in s units

    vec2 F  = zeta(sp);
    vec2 Fx = zeta(sp + vec2(pxS, 0.0));
    vec2 Fy = zeta(sp + vec2(0.0, pxS));
    float lm = 0.5 * log2(dot(F, F));
    float ph = atan(F.y, F.x) / TAU;
    vec2 glm = vec2(0.5 * log2(dot(Fx, Fx)) - lm, 0.5 * log2(dot(Fy, Fy)) - lm);
    vec2 gph = vec2(atan(Fx.y, Fx.x) / TAU - ph, atan(Fy.y, Fy.x) / TAU - ph);
    gph = gph - floor(gph + 0.5);

    float appear = smoothstep(0.5, 3.5, u);
    vec3 hue = cyclePalette(ph + 0.12);
    vec3 col = background(uv) + hue * 0.07 * appear;

    // relief: |zeta| as terrain, lit from the upper left
    vec3 nor = normalize(vec3(-glm * 0.9, 1.0));
    col *= 0.6 + 0.8 * max(dot(nor, normalize(vec3(-0.5, 0.6, 0.6))), 0.0);

    // iso-modulus lines |zeta| = 2^j (gold) and iso-phase lines (palette)
    float gm = max(length(glm), 1e-5);
    float dM = abs(lm - floor(lm + 0.5)) / gm;
    float denseM = smoothstep(0.35, 0.12, gm);          // fade where lines crowd
    col += GOLD * 0.55 * smoothstep(1.4, 0.3, dM) * denseM * appear;
    float P12 = ph * 12.0;
    float gp = max(length(gph) * 12.0, 1e-5);
    float dP = abs(P12 - floor(P12 + 0.5)) / gp;
    float denseP = smoothstep(0.35, 0.12, gp);
    col += hue * 0.9 * smoothstep(1.4, 0.3, dP) * denseP * appear;

    // the pole at s = 1: the harmonic series 1 + 1/2 + 1/3 + ... = infinity
    float dPole = length(sp - vec2(1.0, 0.0)) / pxS;
    col += mix(IVORY, GOLD, 0.5) * (0.9 * exp(-dPole * 0.045) + 2.0 * exp(-dPole * 0.35)) * appear;

    // analytic continuation: a comet runs around the pole from 2 to -1
    float v = easeio((u - 4.0) / 7.5);
    float trail = 1e9, head = 1e9;
    for (int i = 0; i <= 48; i++) {
        float w = float(i) / 48.0;
        if (w > v) break;
        vec2 a = zetaPath(w), b = zetaPath(min(w + 1.0 / 48.0, v));
        vec2 pa = sp - a, ba = b - a;
        float h = sat(dot(pa, ba) / max(dot(ba, ba), 1e-8));
        trail = min(trail, length(pa - ba * h));
    }
    head = length(sp - zetaPath(v));
    float onPath = step(4.0, u);
    col += IVORY * onPath * (1.2 * smoothstep(1.8, 0.4, trail / pxS) + 0.12 * exp(-trail / pxS * 0.12));
    col += IVORY * onPath * (3.0 * exp(-head / pxS * 0.25) + 0.6 * exp(-head / pxS * 0.04)) * (1.0 - smoothstep(11.5, 13.0, u));

    // markers at s = 2 and s = -1
    float r2 = abs(length(sp - vec2(2.0, 0.0)) / pxS - 9.0);
    col += GOLD * 1.2 * smoothstep(1.5, 0.3, r2) * smoothstep(2.5, 4.0, u);
    float arrive = smoothstep(11.0, 11.6, u);
    float r1 = length(sp - vec2(-1.0, 0.0)) / pxS;
    float pulse = 9.0 + 70.0 * sat(u - 11.3) * exp(-2.0 * max(u - 11.3, 0.0));
    col += GOLD * 1.6 * smoothstep(1.6, 0.3, abs(r1 - 9.0)) * arrive;
    col += GOLD * 0.8 * smoothstep(3.0, 0.5, abs(r1 - pulse)) * arrive * exp(-1.5 * max(u - 11.3, 0.0));
    col += GOLD * 1.5 * exp(-r1 * 0.3) * arrive;

    // the real line, and the mirror world below it (zeta(conj s) = conj zeta(s))
    if (uv.y < 0.0) col *= 0.42;
    float dl = abs(uv.y) / PX;
    col += GOLD * (1.1 * smoothstep(1.6, 0.3, dl) + 0.25 * exp(-dl * 0.08));
    return col;
}

// ============================================================================
//  VI. Mock theta functions — the last letter (12 January 1920)
// ============================================================================
//  f(q) = 1 + q/(1+q)^2 + q^4/((1+q)^2(1+q^2)^2) + ...  blows up at every root
//  of unity of even order 2k, and stays bounded at the odd ones. Ramanujan:
//  near such a root,  f(q) - (-1)^k b(q) = O(1),  b(q) = (1-q)(1-q^3)(1-q^5)...
//  x (1 - 2q + 2q^4 - ...), a theta function. So every singularity is copied
//  by a modular form, but no single one copies them all: f is "mock".
//  Watson's identities give both sides without cancellation:
//      f = A - 2B,  b = A + 2B,   A = phi(-q), B = psi(-q)
//      f - s b = (1-s) A - 2(1+s) B
//  A blows up only at orders = 0 (mod 4), B only at orders = 2 (mod 4).
void mockAB(vec2 q, out vec2 A, out vec2 B) {
    vec2 q2 = cmul(q, q);
    vec2 qp = q;                                   // q^(2n-1)
    vec2 a = vec2(1.0, 0.0), b = -cdiv(q, vec2(1.0, 0.0) + q);
    A = a + cdiv(-q, vec2(1.0, 0.0) + q2);          // n = 1 term of A
    a = A - a;
    B = b;
    for (int n = 2; n < 110; n++) {
        qp = cmul(qp, q2);                          // q^(2n-1)
        vec2 q2n = cmul(qp, q);                     // q^(2n)
        a = cmul(a, cdiv(-qp, vec2(1.0, 0.0) + q2n));
        b = cmul(b, cdiv(-qp, vec2(1.0, 0.0) + qp));
        A += a; B += b;
        if (dot(qp, qp) < 1e-14 * (1.0 + dot(a, a) + dot(b, b))) break;
    }
}

vec2 mockF(vec2 q, float s) {
    vec2 A, B;
    mockAB(q, A, B);
    return (1.0 - s) * A - 2.0 * (1.0 + s) * B;
}

// morph: f -> f - b -> f + b -> f
float mockS(float u) {
    return easeio((u - 7.5) / 1.8) - 2.0 * easeio((u - 12.0) / 2.2) + easeio((u - 17.3) / 1.6);
}

// Growth rate (1-r) log|F| at radius r: ~ c/k^2 near a singular root of order k.
float mockGrowth(vec2 q, float s) {
    vec2 F = mockF(q, s);
    return (1.0 - length(q)) * 0.5 * log(max(dot(F, F), 1e-30));
}

const float MOCK_R = 0.33;              // disk radius on screen
const vec2 MOCK_C = vec2(0.36, 0.0);     // disk centre (text to the left)

vec3 actMock(vec2 uv, float u) {
    float rot = -0.03 * u;                   // a slow turn
    float zoom = mix(1.0, 1.06, easeio(u / 20.0));
    vec2 p = (uv - MOCK_C) / (MOCK_R * zoom);
    p = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * p;
    vec2 q = vec2(p.x, p.y);
    float r = length(q);
    float fp = PX / (MOCK_R * zoom);        // one pixel in q units
    float sM = mockS(u);
    float appear = smoothstep(0.3, 2.5, u);
    vec3 col = background(uv);

    // --- corona: one ray per singular root of unity ------------------------
    //     length ~ growth rate of |f - s b| as q -> the rim at that angle
    const float R0 = 0.992;
    float ang = atan(q.y, q.x);
    vec2 qr = R0 * vec2(cos(ang), sin(ang));
    float G = mockGrowth(qr, sM);
    Mod m = reduceTau(vec2(ang / TAU, -log(R0) / TAU));
    float k = abs(m.g.z);
    float kmod4 = mod(k, 4.0);
    vec3 rayC = kmod4 == 2.0 ? GOLD * 1.1 : kmod4 == 0.0 ? PEACOCK * 1.6 + vec3(0.0, 0.1, 0.15) : IVORY * 0.4;
    float len = 0.85 * sqrt(max(G - 0.012, 0.0) / 0.44);
    if (r > 1.0 && len > 0.002) {
        float x = (r - 1.0) / len;
        float shimmer = 0.85 + 0.15 * sin(u * 5.0 + ang * 40.0);
        col += rayC * (0.9 * exp(-2.2 * x) + 1.6 * exp(-x * 12.0)) * shimmer * appear;
    }

    // --- the disk: phase portrait of f(q) - s b(q) ---------------------------
    if (r < 1.0) {
        vec2 qi = q * min(1.0, R0 / max(r, 1e-6));
        vec2 F  = mockF(qi, sM);
        vec2 Fx = mockF(qi + vec2(fp, 0.0), sM);
        vec2 Fy = mockF(qi + vec2(0.0, fp), sM);
        float lm = 0.5 * log2(dot(F, F));
        float ph = atan(F.y, F.x) / TAU;
        vec2 glm = vec2(0.5 * log2(dot(Fx, Fx)) - lm, 0.5 * log2(dot(Fy, Fy)) - lm);
        vec2 gph = vec2(atan(Fx.y, Fx.x) / TAU - ph, atan(Fy.y, Fy.x) / TAU - ph);
        gph -= floor(gph + 0.5);
        vec3 hue = cyclePalette(ph + 0.12);
        vec3 c = vec3(0.012, 0.013, 0.032) + hue * (0.03 + 0.05 * fract(lm));
        float gm = max(length(glm), 1e-5);
        float dM = abs(lm - floor(lm + 0.5)) / gm;
        c += GOLD * 0.5 * smoothstep(1.4, 0.3, dM) * smoothstep(0.45, 0.15, gm);
        float P12 = ph * 12.0, gp = max(length(gph) * 12.0, 1e-5);
        float dP = abs(P12 - floor(P12 + 0.5)) / gp;
        c += hue * 0.75 * smoothstep(1.4, 0.3, dP) * smoothstep(0.45, 0.15, gp);
        // where lines crowd beyond the pixel grid, a soft glow in their colour
        c = mix(c, hue * 0.22 + GOLD * 0.08, smoothstep(0.45, 1.5, max(gm, gp)) * 0.85);
        // heat near the rim where the function erupts
        float gRim = (1.0 - length(qi)) * lm * 0.693147;
        c += rayC * 1.5 * pow(sat(gRim / 0.4), 2.0) * smoothstep(0.8, 0.99, r);
        col = mix(col, c, appear);
    }
    // the unit circle
    col += GOLD * (0.9 * smoothstep(1.6 * fp, 0.3 * fp, abs(r - 1.0)) + 0.15 * exp(-abs(r - 1.0) / fp * 0.05)) * appear;
    return col;
}

vec3 renderAct(int a, vec2 uv, float u) {
    if (a == 0) return actPartitions(uv, u);
    if (a == 1) return actCongruences(uv, u);
    if (a == 2) return actCrown(uv, u);
    if (a == 3) return actEdge(uv, u);
    if (a == 4) return actMinus12(uv, u);
    return actMock(uv, u);
}

void mainImage(out vec4 O, in vec2 fc) {
    PX = 1.0 / iResolution.y;
    T = texelFetch(DATA, ivec2(0), 0).x;
    vec2 uv = screenUV(fc);
    int a = actAt(T);
    vec3 col = actWeight(a, T) * renderAct(a, uv, T - actStart(a));
    if (a > 0 && T < actStart(a) + T_FADE)
        col += actWeight(a - 1, T) * renderAct(a - 1, uv, T - actStart(a - 1));
    O = vec4(max(col, 0.0), 1.0);
}
