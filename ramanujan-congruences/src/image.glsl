// Image — the rose window, two sliders, and a few lines of text.
// iChannel0 = Buffer A (state, p(n) mod 720720)   iChannel1 = font texture
//
// Text is fixed-width: each line costs one font sample per pixel, and strings
// are packed four characters to a uint (no arrays, no glyph-width passes).

const vec3 GOLD = vec3(1.0, 0.66, 0.24), IVORY = vec3(0.95, 0.88, 0.74);
const float PI = 3.14159265, TAU = 6.28318531, ADV = 0.5;
float PX;

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }
int pmodm(int n, int m) { return int(texelFetch(iChannel0, ivec2(n & 255, 1 + (n >> 8)), 0).x) % m; }

// ---- text ------------------------------------------------------------------------
uint packed(int s, int j) {                 // strings, four chars per uint
    if (s == 0) return j == 0 ? 1634558290u : j == 1 ? 1634366830u : j == 2 ? 544417646u
                     : j == 3 ? 1735290723u : j == 4 ? 1852142962u : 7562595u;   // Ramanujan's congruences
    if (s == 1) return j == 0 ? 1684828007u : j == 1 ? 544022586u : j == 2 ? 1769367908u
                     : j == 3 ? 544433508u : 695085168u;                           // gold: m divides p(n)
    if (s == 2) return j == 0 ? 1735289202u : 115u;                                // rings
    return j == 0 ? 1734439524u : j == 1 ? 1701344288u : j == 2 ? 1768715040u : 1936876900u; // drag the sliders
}
uint strChar(int s, int i) { return (packed(s, i >> 2) >> (8 * (i & 3))) & 255u; }
int ndig(int v) { return v >= 10 ? 2 : 1; }
uint digitOf(int v, int nd, int i) { return 48u + uint(nd == 2 && i == 0 ? v / 10 : v % 10); }

// signed distance (em) to glyph c drawn in the fixed-width slot at q (em, baseline y = 0)
float glyph(uint c, vec2 q) {
    if (c == 1u) {                           // the congruence sign, drawn: three bars
        vec2 r = vec2(abs(q.x - 0.5 * ADV) - 0.2, 0.0);
        float d = 1e5;
        for (int k = 0; k < 3; k++) d = min(d, length(vec2(max(r.x, 0.0), q.y - 0.17 - 0.14 * float(k))));
        return d - 0.04;
    }
    vec2 uv = vec2(0.5 + q.x - 0.5 * ADV, 0.8 - q.y);
    if (c == 32u || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1e5;
    return textureLod(iChannel1, (vec2(float(c % 16u), float(c / 16u)) + uv) / 16.0, 0.0).a - 0.5;
}

// the formula "p(mk+d) = 0 (mod m)" for the current modulus, char by char
uint formulaChar(int i, int m, int d) {
    int lm = ndig(m), ld = ndig(d);
    if (i < 2) return i == 0 ? 112u : 40u;                 i -= 2;   // p(
    if (i < lm) return digitOf(m, lm, i);                  i -= lm;
    if (i < 2) return i == 0 ? 107u : 43u;                 i -= 2;   // k+
    if (i < ld) return digitOf(d, ld, i);                  i -= ld;
    if (i < 2) return i == 0 ? 41u : 32u;                  i -= 2;   // ")"
    if (i < 1) return 1u;                                  i -= 1;   // congruence sign
    if (i < 8) return i == 0 ? 32u : i == 1 ? 48u : i == 2 ? 32u : i == 3 ? 40u
                    : i == 4 ? 109u : i == 5 ? 111u : i == 6 ? 100u : 32u;  i -= 8;   // " 0 (mod "
    if (i < lm) return digitOf(m, lm, i);                  i -= lm;
    return i == 0 ? 41u : 32u;
}

// Draws one line: `kind` 0-4 packed strings, 10 formula, 11 "m = ", 12 "rings = ", 13 a number
vec4 textLine(vec2 uv, vec2 org, float em, int kind, int n, int a, int b, vec3 col, vec4 acc) {
    vec2 q = (uv - org) / em;
    if (q.y < -0.35 || q.y > 1.0 || q.x < 0.0 || q.x > float(n) * ADV) return acc;
    int i = int(q.x / ADV);
    uint c;
    if (kind < 10) c = strChar(kind, i);
    else if (kind == 10) c = formulaChar(i, a, b);
    else if (kind == 13) c = digitOf(a, ndig(a), i);
    else {
        int pre = kind == 11 ? 4 : 8;           // "m = " or "rings = "
        c = i >= pre ? digitOf(a, ndig(a), i - pre)
          : kind == 11 ? (i == 0 ? 109u : i == 2 ? 61u : 32u)
          : (i < 5 ? strChar(2, i) : i == 6 ? 61u : 32u);
    }
    float d = glyph(c, vec2(q.x - float(i) * ADV, q.y)) * em;
    float cov = smoothstep(0.7 * PX, -0.7 * PX, d);
    float glow = exp(-max(d, 0.0) / (0.06 * em)) * 0.25;
    return vec4(mix(acc.rgb * (1.0 - 0.5 * smoothstep(0.12 * em, 0.0, d)), col, cov) + col * glow * (1.0 - cov), 1.0);
}

// ---- the rose window ----------------------------------------------------------------
int special(int m) { for (int d = 0; d < 16; d++) if ((24 * d) % m == 1) return d; return -1; }
float wedgeOffset(int m) { int s = special(m); return PI * 0.5 - TAU * (float(max(s, 0)) + 0.5) / float(m); }

vec3 jewel(float h) {
    vec3 a = mix(vec3(0.10, 0.12, 0.62), vec3(0.02, 0.48, 0.55), smoothstep(0.0, 0.5, h));
    return mix(a, vec3(0.55, 0.10, 0.62), smoothstep(0.5, 1.0, h));
}
vec3 tileColor(int n, int m) {
    int r = pmodm(n, m);
    if (r == 0) return GOLD * 1.6;
    return jewel(float(r - 1) / float(max(m - 2, 1))) * (0.45 + 0.4 * fract(sin(float(n * 7 + m)) * 43758.5));
}

vec3 window(vec2 uv, float m, float rings, float ready) {
    int m0 = int(floor(m)), m1 = m0 + 1;
    float x = m - float(m0);
    int mr = int(floor(m + 0.5));
    float off = mix(wedgeOffset(m0), wedgeOffset(m1), x);
    float lock = pow(max(1.0 - abs(m - float(mr)) * 4.0, 0.0), 2.0)
               * ((mr == 5 || mr == 7 || mr == 11) ? 1.0 : 0.0);

    vec2 c = uv - vec2(0.30, 0.0);
    float rho = length(c);
    const float RIN = 0.075, ROUT = 0.46;
    float w = (ROUT - RIN) / rings;
    float sf = (rho - RIN) / w;
    float s0 = mod(atan(c.y, c.x) - off, TAU) / TAU;
    float sp = s0 + floor(sf - s0 + 0.5);                // spiral parameter of this band
    float dr = sf - sp;
    float xs = sp * m;
    int n = int(floor(xs));

    float wedgeAng = abs(mod(atan(c.y, c.x) - PI * 0.5 + PI, TAU) - PI);
    float halfW = PI / m;
    float beam = smoothstep(halfW * 1.05, halfW * 0.4, wedgeAng) * smoothstep(RIN * 0.5, ROUT, rho);
    vec3 col = vec3(0.008, 0.009, 0.022) + GOLD * 0.10 * lock * beam * smoothstep(ROUT + 0.25, ROUT, rho);

    if (sp < 0.0 || sp >= rings || n < 0 || n >= PN) {
        float hub = smoothstep(RIN - 0.004, RIN - 0.006 - PX, rho);
        col = mix(col, vec3(0.012, 0.012, 0.03), hub);
        col += GOLD * 0.9 * smoothstep(1.5 * PX, 0.0, abs(rho - RIN + 0.008));
        col += GOLD * 0.5 * smoothstep(1.5 * PX, 0.0, abs(rho - ROUT - 0.008));
        return col;
    }
    float L = TAU * rho / m;                            // tile length along the spiral
    vec2 q = vec2((fract(xs) - 0.5) * L, dr * w);
    vec2 hs = vec2(0.5 * L, 0.5 * w) - 1.1 * PX;
    float rr = min(0.35 * w, 3.0 * PX);
    vec2 d = abs(q) - hs + rr;
    float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rr;
    float cov = smoothstep(0.75 * PX, -0.75 * PX, sd);
    float bev = smoothstep(0.0, 0.35 * w, -sd);

    vec3 tc = tileColor(n, max(m0, 2));
    if (x > 0.001) tc = mix(tc, tileColor(n, m1), x);
    tc *= 1.0 + lock * (wedgeAng < halfW ? 0.8 : -0.25);
    tc *= float(n) < ready ? 1.0 : 0.15;                // table still filling (first 2 s)
    col = mix(col, tc * (0.55 + 0.45 * bev) + tc * 0.25 * (1.0 - bev) * sign(dr), cov);
    return col + GOLD * 0.25 * lock * beam * cov;
}

// ---- sliders ----------------------------------------------------------------------------
vec3 slider(vec2 uv, float y, float f, bool hot, vec3 col) {
    float dx = uv.x - clamp(uv.x, SX0, SX1);
    float dTrack = length(vec2(dx, uv.y - y));
    float kx = mix(SX0, SX1, f);
    col = mix(col, vec3(0.30, 0.28, 0.36), smoothstep(2.0 * PX, 0.5 * PX, dTrack - 0.002));
    col = mix(col, GOLD * 0.8, smoothstep(2.0 * PX, 0.5 * PX, dTrack - 0.002) * step(uv.x, kx));
    float dk = length(uv - vec2(kx, y)) - (hot ? 0.016 : 0.013);
    col = mix(col, IVORY, smoothstep(PX, -PX, dk));
    return col + GOLD * 0.35 * exp(-max(dk, 0.0) * 60.0);
}

vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

void mainImage(out vec4 O, in vec2 fc) {
    PX = 1.0 / iResolution.y;
    vec2 uv = (fc - 0.5 * iResolution.xy) * PX;
    float m = st(1), rings = st(3), act = st(4), ready = st(5) * 8.0;
    int mr = int(floor(m + 0.5)), rr = int(floor(rings + 0.5));

    vec3 col = aces(window(uv, m, rings, ready) * 1.1);
    col = slider(uv, SY_M, (m - M_MIN) / (M_MAX - M_MIN), act == 1.0, col);
    col = slider(uv, SY_R, (rings - R_MIN) / (R_MAX - R_MIN), act == 2.0, col);

    // text: only when the pixel is on the left panel or the hub
    vec4 t = vec4(col, 0.0);
    if (uv.x < -0.1) {
        t = textLine(uv, vec2(-0.82, 0.40), 0.046, 0, 23, 0, 0, GOLD, t);
        t = textLine(uv, vec2(-0.82, 0.33), 0.028, 1, 20, 0, 0, IVORY * 0.6, t);
        int d = special(mr);
        float lock = max(1.0 - abs(m - float(mr)) * 4.0, 0.0);
        if ((mr == 5 || mr == 7 || mr == 11) && lock > 0.0) {
            vec4 f = textLine(uv, vec2(-0.82, 0.05), 0.046, 10, 16 + 2 * ndig(mr) + ndig(d), mr, d, GOLD, t);
            t.rgb = mix(t.rgb, f.rgb, lock);
        }
        t = textLine(uv, vec2(-0.82, SY_M + 0.03), 0.03, 11, 4 + ndig(mr), mr, 0, IVORY, t);
        t = textLine(uv, vec2(-0.82, SY_R + 0.03), 0.03, 12, 8 + ndig(rr), rr, 0, IVORY, t);
        t = textLine(uv, vec2(-0.82, SY_R - 0.085), 0.024, 4, 16, 0, 0, IVORY * 0.45, t);
    } else if (length(uv - vec2(0.30, 0.0)) < 0.07) {
        int nd = ndig(mr);
        t = textLine(uv, vec2(0.30 - 0.5 * float(nd) * ADV * 0.06, -0.018), 0.06, 13, nd, mr, 0, GOLD, t);
    }
    col = t.rgb;
    vec2 v = fc / iResolution.xy - 0.5;
    col *= 1.0 - 0.5 * dot(v * vec2(1.1, 1.3), v * vec2(1.1, 1.3));
    O = vec4(pow(col, vec3(1.0 / 2.2)), 1.0);
}
