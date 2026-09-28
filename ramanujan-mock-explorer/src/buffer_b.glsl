// Buffer B — the field lines, in HDR (bloomed by Image).
// iChannel0 = Buffer A (UI state)
//
// One series evaluation per pixel: line widths come from fwidth() rather than
// extra samples, and the sums are renormalised as they grow so the eruptions
// never overflow a float, however deep the zoom.

const vec3 GOLD = vec3(1.0, 0.66, 0.24);
const float TAU = 6.28318531;

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }
vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }

// f - s b = (1-s) A - 2(1+s) B via Watson (f = A - 2B, b = A + 2B): no
// cancellation. Returns the value scaled by e^-lsc.
vec2 mockF(vec2 q, float s, out float lsc) {
    vec2 one = vec2(1.0, 0.0), q2 = cmul(q, q), qp = q;
    vec2 a = cdiv(-q, one + q2), b = -cdiv(q, one + q);
    vec2 A = one + a, B = b;
    lsc = 0.0;
    for (int n = 2; n < 700; n++) {
        qp = cmul(qp, q2);                              // q^(2n-1)
        a = cmul(a, cdiv(-qp, one + cmul(qp, q)));
        b = cmul(b, cdiv(-qp, one + qp));
        A += a; B += b;
        if (max(dot(A, A), dot(B, B)) > 1e24) { a *= 1e-12; b *= 1e-12; A *= 1e-12; B *= 1e-12; lsc += 27.631021; }
        if (n > 4 && dot(qp, qp) < 1e-14 * (1.0 + dot(a, a) + dot(b, b))) break;
    }
    return (1.0 - s) * A - 2.0 * (1.0 + s) * B;
}

vec3 palette(float h) {                                 // gold, saffron, crimson, violet, peacock
    h = fract(h) * 5.0;
    vec3 c = mix(vec3(1.1, 0.73, 0.26), vec3(1.0, 0.42, 0.1), smoothstep(0.0, 1.0, h));
    c = mix(c, vec3(0.88, 0.08, 0.13), smoothstep(1.0, 2.0, h));
    c = mix(c, vec3(0.42, 0.1, 0.62), smoothstep(2.0, 3.0, h));
    c = mix(c, vec3(0.06, 0.78, 0.86), smoothstep(3.0, 4.0, h));
    return mix(c, vec3(1.1, 0.73, 0.26), smoothstep(4.0, 5.0, h));
}

void mainImage(out vec4 O, in vec2 fc) {
    float px = 1.0 / iResolution.y;
    vec2 uv = (fc - 0.5 * iResolution.xy) * px;
    float scale = DISK_R * exp2(st(2));                  // screen units per disk unit
    vec2 q = vec2(st(0), st(1)) + uv / scale;
    float fp = px / scale, r = length(q);
    vec3 col = vec3(0.006, 0.007, 0.016);

    if (r < 1.0) {
        float lsc;
        vec2 F = mockF(q, st(5), lsc);
        float lnF = 0.5 * log(max(dot(F, F), 1e-37)) + lsc;
        float lm = lnF * 1.442695;                       // log2|f|
        float ph = atan(F.y, F.x) / TAU;
        vec3 hue = palette(ph + 0.12);

        float wm = max(fwidth(lm), 1e-6);
        float wp = max(min(fwidth(ph), fwidth(fract(ph + 0.5))) * 12.0, 1e-6);
        float dense = smoothstep(0.45, 1.5, max(wm, wp)); // lines finer than a pixel
        vec3 c = vec3(0.008, 0.009, 0.022) + hue * (0.015 + 0.03 * fract(lm));
        c += GOLD * 0.5 * smoothstep(1.4, 0.3, abs(lm - floor(lm + 0.5)) / wm) * (1.0 - dense);
        c += hue * 0.8 * smoothstep(1.4, 0.3, abs(ph * 12.0 - floor(ph * 12.0 + 0.5)) / wp) * (1.0 - dense);
        c = mix(c, hue * 0.16 + GOLD * 0.06, dense * 0.85); // their average, as a glow
        // eruptions: growth (1-|q|) ln|f| ~ c/k^2 near a root of order 2k; a
        // soft ember right at the rim, where the lines pile up into flowers
        c += mix(GOLD, vec3(1.0), 0.3) * 0.5 * pow(clamp((1.0 - r) * lnF / 0.4, 0.0, 1.0), 3.0) * smoothstep(0.85, 1.0, r);
        col = c;
    }
    col += GOLD * (0.9 * smoothstep(1.6 * fp, 0.3 * fp, abs(r - 1.0)) + 0.12 * exp(-abs(r - 1.0) / fp * 0.05));
    O = vec4(col, 1.0);
}
