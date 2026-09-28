// Buffer C — captions, drawn with Shadertoy's SDF font texture.
//
// Glyph widths are measured from the distance field itself (auto spacing, after
// "SDF Font Printing" ldfcDr and Klems' MsfyDN), so captions are plain token
// streams: char codes, plus a few controls (italic, super/subscript, overline
// for radicals, live number fields) and three glyphs the font lacks
// (the congruence sign, an arrow, and centred dots), drawn procedurally.
//
// iChannel0 = Buffer A (clock, p(n) table, random partition)
// iChannel1 = font texture
// Tokens and glyph widths are read from Buffer A.
// Output: rgb = premultiplied text colour incl. glow, a = coverage.

#define DATA iChannel0
#define FONT iChannel1

#include "text_captions.glsl"
#include "text_data.glsl"


float T;

// ---- font texture -------------------------------------------------------------
vec4 fontTex(uint c, vec2 uv) {
    return textureLod(FONT, (vec2(float(c % 16u), float(c / 16u)) + uv) / 16.0, 0.0);
}
// distance (in em) from uv (cell coordinates, y down) to glyph c
float fontDist(uint c, vec2 uv) {
    vec2 cu = clamp(uv, vec2(0.01), vec2(0.99));
    if (length(cu - uv) > 0.01) return 1e5;
    return fontTex(c, cu).a - 0.5 - 1.0 / 256.0;
}
uint tok(int i) { return uint(texelFetch(DATA, ivec2(i & 255, TX_Y0 + (i >> 8)), 0).x); }
// left edge and width of the ink (em), measured in Buffer A
vec2 extents(uint c) { return c < 256u ? texelFetch(DATA, ivec2(int(c), FX_Y), 0).xy : vec2(0.0); }
float advance(uint c) { return glyphAdvance(c, extents(c)); }

float segD(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
// procedural glyphs, p in em relative to the pen (baseline at y = 0)
float procDist(uint c, vec2 p) {
    const float w = 0.045;
    if (c == EQUIV) {
        float d = segD(p, vec2(0.02, 0.18), vec2(0.44, 0.18));
        d = min(d, segD(p, vec2(0.02, 0.32), vec2(0.44, 0.32)));
        return min(d, segD(p, vec2(0.02, 0.46), vec2(0.44, 0.46))) - w;
    }
    if (c == ARROW) {
        float d = segD(p, vec2(0.02, 0.3), vec2(0.58, 0.3));
        d = min(d, segD(p, vec2(0.58, 0.3), vec2(0.42, 0.44)));
        return min(d, segD(p, vec2(0.58, 0.3), vec2(0.42, 0.16))) - w;
    }
    if (c == CDOTS) {
        float d = length(p - vec2(0.06, 0.3));
        d = min(d, length(p - vec2(0.26, 0.3)));
        return min(d, length(p - vec2(0.46, 0.3))) - 0.055;
    }
    return 1e5;
}

// ---- live numbers ----------------------------------------------------------------
int gLimb[12];
int gNd;            // digits of p(N), 0 if not yet exact
int gInt[8];        // integer-valued fields by id
int gHRM;           // Hardy-Ramanujan mantissa x 1000

int ndigits(int v) { int n = 1; while (v >= 10 && n < 10) { v /= 10; n++; } return n; }
int pow10i(int e) { int r = 1; for (int i = 0; i < 9; i++) if (i < e) r *= 10; return r; }

void setupFields() {
    vec4 st = texelFetch(DATA, ivec2(0), 0);
    vec4 info = texelFetch(DATA, ivec2(1, 0), 0);
    int N = int(info.x);
    gInt[1] = N;
    gNd = 0;
    if (N < PT_N && float(N) < st.y * float(PT_LEVELS)) {
        for (int g = 0; g < 3; g++) {
            vec4 L = texelFetch(DATA, ptTexel(N, g), 0);
            gLimb[4 * g] = int(L.x); gLimb[4 * g + 1] = int(L.y);
            gLimb[4 * g + 2] = int(L.z); gLimb[4 * g + 3] = int(L.w);
        }
        int top = 0;
        for (int i = 0; i < 12; i++) if (gLimb[i] > 0) top = i;
        gNd = top * 4 + ndigits(gLimb[top]);
    }
    // p(n) ~ e^(pi sqrt(2n/3)) / (4 n sqrt 3)
    float n = max(float(N), 1.0);
    float l10 = (PI * sqrt(2.0 * n / 3.0) - log(4.0 * n * sqrt(3.0))) / log(10.0);
    float e = floor(l10);
    int m = int(floor(pow(10.0, l10 - e) * 1000.0 + 0.5));
    if (m >= 10000) { m = 1000; e += 1.0; }
    gHRM = m;
    gInt[4] = int(e);
    // movement IV: magnification relative to the whole disk, and the convergent
    float z = edgeZoom(max(T - actStart(3), 0.0));
    gInt[5] = int(floor((z + log(0.5 / edgeStartScale())) / log(10.0)));
    int k = 7 + int(floor(2.0 * z / KAPPA_LOG));
    int fa = 1, fb = 1;
    for (int i = 2; i < 44; i++) if (i <= k) { int c = fa + fb; fa = fb; fb = c; }
    gInt[6] = fb; gInt[7] = fa;         // F(k+1) / F(k) -> phi
}

int fieldLen(int id) {
    if (id == 2) return gNd == 0 ? 3 : gNd + (gNd - 1) / 3;
    if (id == 3) return 5;
    return ndigits(gInt[id]);
}
uint fieldChar(int id, int k) {
    if (id == 2) {
        if (gNd == 0) return 46u;                          // "..." until exact
        int g0 = gNd - 3 * ((gNd - 1) / 3);
        int d = k;
        if (k >= g0) {
            int kk = k - g0;
            if (kk % 4 == 0) return THIN;
            d = g0 + (kk / 4) * 3 + (kk % 4 - 1);
        }
        int r = gNd - 1 - d;
        int limb = gLimb[r / 4];
        return 48u + uint((limb / pow10i(r % 4)) % 10);
    }
    if (id == 3) {
        if (k == 1) return 46u;
        int d = k == 0 ? 0 : k - 1;
        return 48u + uint((gHRM / pow10i(3 - d)) % 10);
    }
    int v = gInt[id], nd = ndigits(v);
    return 48u + uint((v / pow10i(nd - 1 - k)) % 10);
}

// ---- caption layout and rendering -------------------------------------------------
float captionWidth(int cap) {
    float w = texelFetch(DATA, ivec2(cap, CW_Y), 0).x;
    ivec3 r = CRANGE[cap];
    if (r.z == 0) return w;
    Pen P = Pen(0.0, 1.0, 0.0, false);
    for (int i = 0; i < r.y; i++) {
        uint c = tok(r.x + i);
        if (c >= FIELD0) {
            int id = int(c - FIELD0);
            int n = fieldLen(id);
            for (int k = 0; k < n; k++) w += advance(fieldChar(id, k)) * P.s;
        } else if (c >= 256u && c < THIN) penControl(P, c);
    }
    return w;
}

float glyphAt(uint c, vec2 p, Pen P) {
    vec2 q = vec2(p.x - P.x, p.y - P.dy) / P.s;         // em of this glyph size
    float adv = advance(c);
    if (q.x < -0.3 || q.x > adv + 0.3 || q.y < -0.45 || q.y > 1.0) return 1e5;
    if (c >= 256u) return procDist(c, q) * P.s;
    vec2 e = extents(c);
    vec2 uv = vec2(q.x + e.x - 0.05, 0.8 - q.y);
    if (P.ital) uv.x -= (0.8 - uv.y) * 0.22;
    return fontDist(c, uv) * P.s;
}

float captionDist(int cap, vec2 p) {
    ivec3 r = CRANGE[cap];
    Pen P = Pen(0.0, 1.0, 0.0, false);
    float d = 1e5, overX = 0.0, overY = 0.0;
    bool over = false;
    for (int i = 0; i < r.y; i++) {
        if (P.x > p.x + 1.0 && !over) break;        // everything further is to the right
        uint c = tok(r.x + i);
        if (c >= FIELD0) {
            int id = int(c - FIELD0);
            int n = fieldLen(id);
            for (int k = 0; k < n; k++) {
                uint fc = fieldChar(id, k);
                d = min(d, glyphAt(fc, p, P));
                P.x += advance(fc) * P.s;
            }
        } else if (c == OVER_ON) {
            overX = P.x - 0.02 * P.s; overY = P.dy + 0.74 * P.s; over = true;
        } else if (c == OVER_OFF) {
            d = min(d, segD(p, vec2(overX, overY), vec2(P.x, overY)) - 0.04 * P.s);
            over = false;
        } else if (c >= 256u && c < THIN) {
            penControl(P, c);
        } else {
            d = min(d, glyphAt(c, p, P));
            P.x += advance(c) * P.s;
        }
    }
    return d;
}

vec3 textColor(int c) {
    return c == 0 ? IVORY : c == 1 ? GOLD * 1.25 : c == 2 ? IVORY * 0.62 : c == 3 ? vec3(0.25, 0.85, 0.85) : SAFFRON;
}

vec2 anchorPos(int a) {
    if (a == 0) return vec2(0.0);
    vec2 ctr; float sc;
    zetaView(T - actStart(4), ctr, sc);
    vec2 s = a == 1 ? vec2(2.0, 0.0) : a == 2 ? vec2(1.0, 0.0) : vec2(-1.0, 0.0);
    return (s - ctr) / sc;
}

void mainImage(out vec4 O, in vec2 fc) {
    T = texelFetch(DATA, ivec2(0), 0).x;
    vec2 uv = (fc - 0.5 * iResolution.xy) / iResolution.y;
    float px = 1.0 / iResolution.y;
    bool fieldsReady = false;
    vec3 col = vec3(0.0);
    float cov = 0.0;
    for (int i = 0; i < N_SCHED; i++) {
        vec4 A = SCH_T[i];
        if (T < A.x || T > A.y) continue;
        vec4 B = SCH_S[i];
        int capId = int(B.w) % 256, anchor = int(B.w) / 256;
        float em = B.x;
        vec2 org = A.zw + anchorPos(anchor);
        vec2 p = (uv - org) / em;
        if (p.y < -0.6 || p.y > 1.35 || abs(p.x) > 60.0) continue;
        if (!fieldsReady && CRANGE[capId].z != 0) { setupFields(); fieldsReady = true; }
        float w = captionWidth(capId);
        p.x += B.y * w;
        if (p.x < -0.5 || p.x > w + 0.5) continue;
        float d = captionDist(capId, p) * em;          // screen units
        float fade = smoothstep(A.x, A.x + 0.7, T) * (1.0 - smoothstep(A.y - 0.7, A.y, T));
        float a = smoothstep(0.75 * px, -0.75 * px, d) * fade;
        vec3 tc = textColor(int(B.z));
        float glow = exp(-max(d, 0.0) / (0.05 * em)) * 0.25 * fade;
        col = col * (1.0 - a) + tc * a + tc * glow * (1.0 - a);
        cov = max(cov, max(a, smoothstep(0.14 * em, 0.0, d) * 0.8 * fade));
    }
    O = vec4(col, cov);
}
