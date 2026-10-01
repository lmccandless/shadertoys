// Image: glare, tone mapping and the interface.
// iChannel0 = Buffer D (mipmap)   iChannel1 = Buffer A (state, text)   iChannel2 = font texture
//
// Strings are composed in Buffer A; each text pixel here costs one texel fetch and one font
// sample. The font is fixed-width with a half-em advance.

float U;                                              // UI scale: virtual px -> screen px
const vec3 INK = vec3(0.94, 0.92, 0.87), MUTED = vec3(0.55, 0.54, 0.51), ACC = vec3(1.0, 0.70, 0.32);

float tlen(int L) { return fetch(iChannel1, L, 7).x; }
// Line L at baseline-left org (virtual px), size em: fill plus a soft dark halo.
void text(inout vec3 col, vec2 p, vec2 org, float em, int L, vec3 ink) {
    vec2 q = (p - org) / em;
    if (q.y < -0.3 || q.y > 0.74 || q.x < 0.0) return;
    int i = int(q.x / 0.5);
    if (float(i) >= tlen(L)) return;
    vec4 t = fetch(iChannel1, L * 5 + i / 12, 6);
    int j = i % 12;
    float v = j < 3 ? t.x : j < 6 ? t.y : j < 9 ? t.z : t.w;
    uint c = (uint(v) >> uint(8 * (j % 3))) & 255u;
    if (c == 32u) return;
    vec2 uv = vec2(0.25 + q.x - 0.5 * float(i), 0.8 - q.y);
    float d = (textureLod(iChannel2, (vec2(float(c % 16u), float(c / 16u)) + uv) / 16.0, 0.0).a - 0.5) * em * U;
    col = mix(col, vec3(0), 0.55 * smoothstep(3.0, 0.0, d));
    col = mix(col, ink, smoothstep(0.65, -0.65, d));
}
// Right-aligned variant.
void textR(inout vec3 col, vec2 p, vec2 right, float em, int L, vec3 ink) { text(col, p, right - vec2(0.5 * em * tlen(L), 0), em, L, ink); }
float seg(vec2 p, vec2 a, vec2 b, float w) {
    vec2 v = b - a; float h = clamp(dot(p - a, v) / max(dot(v, v), 1e-4), 0.0, 1.0);
    return smoothstep(w + 0.6 / U, w - 0.6 / U, length(p - a - v * h));
}
vec3 aces(vec3 x) { return clamp(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
vec3 srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

void mainImage(out vec4 O, in vec2 P) {
    vec2 res = iResolution.xy, uv = P / res;
    vec4 ctrl0 = fetch(iChannel1, S_CTRL, 0);
    vec3 sc = textureLod(iChannel0, uv, 0.0).rgb;
    vec3 glare = 0.30 * textureLod(iChannel0, uv, 2.5).rgb + 0.35 * textureLod(iChannel0, uv, 4.5).rgb + 0.35 * textureLod(iChannel0, uv, 6.5).rgb;
    // Hue-preserving: tone-map luminance, keep chromaticity, roll very bright colour toward white.
    vec3 hdr = (ctrl0.y > 0.5 ? 0.45 : 0.30) * (sc + 0.09 * glare);
    float Y = dot(hdr, vec3(0.2126, 0.7152, 0.0722)), Yt = aces(vec3(Y)).x;
    vec3 tm = hdr * (Yt / max(Y, 1e-5));
    tm = mix(tm, vec3(Yt), sat((max(tm.r, max(tm.g, tm.b)) - 1.0) * 1.5));
    vec3 col = srgb(clamp(tm, 0.0, 1.0));
    col += (hash13(vec3(P, iTime)) - 0.5) / 255.0;

    vec4 ctrl = fetch(iChannel1, S_CTRL, 0), slide = fetch(iChannel1, S_SLIDE, 0), cam = fetch(iChannel1, S_CAM, 0);
    vec4 camT = fetch(iChannel1, S_CAMT, 0);
    int star = int(ctrl.x + 0.5);
    U = uiScale(res);
    vec2 p = uiPoint(P, res);
    if (cam.w > 0.5) {
        text(col, p, vec2(906, 14), 13.0, TL_SHOW, MUTED);
        O = vec4(col, 1); return;
    }
    col *= mix(0.45, 1.0, smoothstep(0.0, 80.0, p.y));

    // Bottom panel.
    if (p.y < 76.0 && p.y > -2.0 && p.x > 0.0 && p.x < 960.0) {
        if (p.y > 40.0) {
            for (int k = 0; k < NSTARS + ZERO; k++) {
                if (abs(p.x - starX(k) - 0.5 * starW(k)) > 0.5 * starW(k) + 8.0) continue;
                text(col, p, vec2(starX(k), 51.0), 14.0, TL_STAR + k, k == star ? INK : MUTED);
                if (k == star) col = mix(col, ACC, seg(p, vec2(starX(k), 45.5), vec2(starX(k) + starW(k), 45.5), 0.6));
            }
            bool euv = ctrl.y > 0.5;
            text(col, p, vec2(556, 51), 13.0, TL_VIS, euv ? MUTED : INK);
            text(col, p, vec2(623, 51), 13.0, TL_EUV, euv ? INK : MUTED);
            col = mix(col, ACC, seg(p, euv ? vec2(623, 45.5) : vec2(556, 45.5), euv ? vec2(642, 45.5) : vec2(601, 45.5), 0.6));
            col = mix(col, vec3(0.3), seg(p, vec2(612, 49), vec2(612, 58), 0.5));
            text(col, p, vec2(676, 51), 13.0, TL_FIELD, ctrl.z > 0.5 ? INK : MUTED);
            if (ctrl.z > 0.5) col = mix(col, ACC, seg(p, vec2(676, 45.5), vec2(708, 45.5), 0.6));
            text(col, p, vec2(741, 51), 13.0, TL_PAUSE, ctrl.w > 0.5 ? ACC : MUTED);
            col = mix(col, MUTED, seg(p, vec2(810, 54), vec2(818, 54), 0.7));
            col = mix(col, MUTED, max(seg(p, vec2(871, 54), vec2(879, 54), 0.7), seg(p, vec2(875, 50), vec2(875, 58), 0.7)));
            text(col, p, vec2(845.0 - 3.25 * tlen(TL_ZOOM), 51.0), 13.0, TL_ZOOM, INK);
            text(col, p, vec2(902, 51), 13.0, TL_HIDE, MUTED);
        } else {
            // The four sliders. The tick marks the real star's value once you move away from it.
            vec4 pre = presetSliders(star);
            for (int k = 0; k < 4 + ZERO; k++) {
                vec2 sp = sliderSpan(k);
                if (p.x < sp.x - 10.0 || p.x > sp.y + 10.0) continue;
                float v = k == 0 ? slide.x : k == 1 ? slide.y : k == 2 ? slide.z : slide.w;
                float pv = k == 0 ? pre.x : k == 1 ? pre.y : k == 2 ? pre.z : pre.w;
                float kx = mix(sp.x, sp.y, v);
                col = mix(col, vec3(0.28), seg(p, vec2(sp.x, TRACK), vec2(sp.y, TRACK), 0.7));
                col = mix(col, vec3(0.78), seg(p, vec2(sp.x, TRACK), vec2(kx, TRACK), 0.9));
                if (camT.w > 0.5) col = mix(col, ACC * 0.8, seg(p, vec2(mix(sp.x, sp.y, pv), TRACK - 4.5), vec2(mix(sp.x, sp.y, pv), TRACK + 4.5), 0.5));
                col = mix(col, INK, smoothstep(4.6 + 0.6 / U, 4.6 - 0.6 / U, length(p - vec2(kx, TRACK))));
                text(col, p, vec2(sp.x, 25.0), 13.0, TL_SLAB + k, MUTED);
                textR(col, p, vec2(sp.y, 25.0), 13.0, TL_SVAL + k, INK);
            }
        }
    }
    O = vec4(clamp(col, 0.0, 1.0), 1);
}
