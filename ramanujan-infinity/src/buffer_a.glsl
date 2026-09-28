// Buffer A — state and data.
//
//  * the film clock (drag the mouse horizontally to scrub)
//  * the exact partition numbers p(0..2047), as base-10^4 bignums, from Euler's
//    pentagonal number theorem  prod(1-q^n) = sum (-1)^k q^{k(3k-1)/2}.
//    The recurrence is "jumped" 8 levels, so every frame resolves 8 more values
//    (all 2048 are exact after 256 frames):
//        p(n) = sum_k (-1)^(k+1) sum_{g = k(3k-+1)/2} sum_{i<8, g+i>=8} p(i) p(n-g-i)
//  * the column heights of a random partition of ~n (Boltzmann model)
//
//  * caption token streams and per-glyph widths measured from the font's
//    distance field, so Buffer C only does cheap texel fetches
//
// iChannel0 = Buffer A (self)
// iChannel1 = font texture

#define SELF iChannel0
#define FONT iChannel1

#include "text_tokens.glsl"
#include "text_captions.glsl"

float fontEdge(int c, vec2 uv) {
    vec4 s = textureLod(FONT, (vec2(float(c % 16), float(c / 16)) + uv) / 16.0, 0.0);
    return uv.x - (s.a - 127.0 / 255.0) * (s.g * 2.0 - 1.0);
}

float clockUpdate(vec4 st) {
    float t = st.x + clamp(iTimeDelta, 0.0, 0.1);
    if (iFrame == 0) t = 0.0;
    if (iMouse.z > 0.0) t = clamp(iMouse.x / iResolution.x, 0.0, 0.9999) * T_TOTAL;
    return mod(t, T_TOTAL);
}

const int SMALLP[8] = int[8](1, 1, 2, 3, 5, 7, 11, 15);

void addLimbs(int m, int c, inout int acc[12]) {
    vec4 a = texelFetch(SELF, ptTexel(m, 0), 0);
    vec4 b = texelFetch(SELF, ptTexel(m, 1), 0);
    vec4 d = texelFetch(SELF, ptTexel(m, 2), 0);
    acc[0] += c * int(a.x); acc[1] += c * int(a.y); acc[2]  += c * int(a.z); acc[3]  += c * int(a.w);
    acc[4] += c * int(b.x); acc[5] += c * int(b.y); acc[6]  += c * int(b.z); acc[7]  += c * int(b.w);
    acc[8] += c * int(d.x); acc[9] += c * int(d.y); acc[10] += c * int(d.z); acc[11] += c * int(d.w);
}

vec4 partitionNumber(int n, int g) {
    if (n < PT_LEVELS) {
        return g == 0 ? vec4(float(SMALLP[n]), 0.0, 0.0, 0.0) : vec4(0.0);
    }
    int pos[12], neg[12];
    for (int i = 0; i < 12; i++) { pos[i] = 0; neg[i] = 0; }
    for (int k = 1; k < 40; k++) {
        int g1 = k * (3 * k - 1) / 2;
        if (g1 > n) break;
        bool plus = (k & 1) == 1;
        for (int s = 0; s < 2; s++) {
            int gg = s == 0 ? g1 : g1 + k;           // k(3k-1)/2, k(3k+1)/2
            for (int i = max(0, PT_LEVELS - gg); i < PT_LEVELS; i++) {
                int m = n - gg - i;
                if (m < 0) break;
                if (plus) addLimbs(m, SMALLP[i], pos);
                else      addLimbs(m, SMALLP[i], neg);
            }
        }
    }
    // pos - neg is p(n) >= 0: normalise with borrows in base 10^4.
    int carry = 0, r[12];
    for (int i = 0; i < 12; i++) {
        int v = pos[i] - neg[i] + carry;
        int q = v >= 0 ? v / 10000 : -((-v + 9999) / 10000);
        r[i] = v - q * 10000;
        carry = q;
    }
    int o = g * 4;
    return vec4(float(r[o]), float(r[o + 1]), float(r[o + 2]), float(r[o + 3]));
}

void mainImage(out vec4 O, in vec2 fc) {
    ivec2 p = ivec2(fc);
    vec4 st = texelFetch(SELF, ivec2(0), 0);
    float t = clockUpdate(st);
    float frames = iFrame == 0 ? 0.0 : st.y;          // frames completed before this one
    O = vec4(0.0);

    if (p == ivec2(0, 0)) {
        O = vec4(t, frames + 1.0, 0.0, 0.0);
        return;
    }

    bool actI = t < actStart(1) + T_FADE;
    float nParam = partitionN(t);
    float sq = sqrt(nParam) / CPART;

    if (p == ivec2(1, 0)) {
        // size, number of parts and largest part of the random partition
        float size = 0.0, parts = 0.0, largest = 0.0;
        if (actI) for (int k = 1; k <= PR_N; k++) {
            float m = floor(partE(k) * sq / float(k));
            size += m * float(k);
            parts += m;
            if (m > 0.0) largest = float(k);
        }
        O = vec4(size, parts, largest, nParam);
        return;
    }

    // exact partition numbers
    if (p.y >= PT_Y0 && p.y < PT_Y0 + PT_N / 64 && p.x < 192) {
        int n = (p.y - PT_Y0) * 64 + p.x / 3;
        if (iFrame > 0 && frames * float(PT_LEVELS) > float(PT_N + 16)) {
            O = texelFetch(SELF, p, 0);             // table complete: hold it
        } else {
            O = partitionNumber(n, p.x % 3);
        }
        return;
    }

    // caption tokens
    if (p.y >= TX_Y0 && p.y < FX_Y && p.x < 256) {
        int i = (p.y - TX_Y0) * 256 + p.x;
        O = vec4(i < N_TOK ? float((TOKP[i / 3] >> (10 * (i % 3))) & 1023u) : 0.0, 0.0, 0.0, 0.0);
        return;
    }
    // glyph extents: left edge and ink width at mid height (auto spacing)
    if (p.y == FX_Y && p.x < 256) {
        float l = fontEdge(p.x, vec2(0.02, 0.5));
        O = vec4(l, fontEdge(p.x, vec2(0.98, 0.5)) - l, 0.0, 0.0);
        return;
    }

    // static width of each caption (live fields excluded), from last frame's tables
    if (p.y == CW_Y && p.x < N_CAP) {
        ivec3 r = CRANGE[p.x];
        Pen P = Pen(0.0, 1.0, 0.0, false);
        for (int i = 0; i < r.y; i++) {
            ivec2 q = ivec2((r.x + i) & 255, TX_Y0 + ((r.x + i) >> 8));
            uint c = uint(texelFetch(SELF, q, 0).x);
            if (c >= FIELD0) continue;
            if (c >= 256u && c < THIN) { penControl(P, c); continue; }
            vec2 e = c < 256u ? texelFetch(SELF, ivec2(int(c), FX_Y), 0).xy : vec2(0.0);
            P.x += glyphAdvance(c, e) * P.s;
        }
        O = vec4(P.x, 0.0, 0.0, 0.0);
        return;
    }

    // column heights S_j = #{parts >= j} of the random partition (suffix sums)
    if (p.y >= PR_Y0 && p.y < PR_Y0 + PR_N / 256 && p.x < 256) {
        int j = (p.y - PR_Y0) * 256 + p.x + 1;
        float S = 0.0;
        if (actI) for (int k = j; k <= PR_N; k++) S += floor(partE(k) * sq / float(k));
        O = vec4(S, floor(partE(j) * sq / float(j)), 0.0, 0.0);
        return;
    }
}
