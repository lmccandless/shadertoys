// Image — bloom from Buffer B's mip chain, tone map, and two text-free sliders.
// iChannel0 = Buffer A (UI state)   iChannel1 = Buffer B (mipmap)

const vec3 GOLD = vec3(1.0, 0.66, 0.24), IVORY = vec3(0.95, 0.88, 0.74);
float PX;

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }

vec3 slider(vec2 uv, float x0, float x1, float f, bool hot, bool ticks, vec3 col) {
    float line = smoothstep(2.0 * PX, 0.5 * PX, length(vec2(uv.x - clamp(uv.x, x0, x1), uv.y - UI_Y)) - 0.002);
    col = mix(col, vec3(0.3, 0.28, 0.36), line * 0.9);
    float kx = mix(x0, x1, f);
    if (ticks) for (int i = 0; i < 3; i++) {
        float tx = mix(x0, x1, 0.5 * float(i));
        col = mix(col, IVORY * 0.7, smoothstep(1.5 * PX, 0.3 * PX, length(vec2(uv.x - tx, max(abs(uv.y - UI_Y) - 0.011, 0.0))) - 0.0015));
    } else col = mix(col, GOLD * 0.8, line * step(uv.x, kx));
    float dk = length(uv - vec2(kx, UI_Y)) - (hot ? 0.015 : 0.012);
    col = mix(col, IVORY, smoothstep(PX, -PX, dk));
    return col + GOLD * 0.3 * exp(-max(dk, 0.0) * 70.0);
}

vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

void mainImage(out vec4 O, in vec2 fc) {
    PX = 1.0 / iResolution.y;
    vec2 uv = fc / iResolution.xy;
    vec3 c = textureLod(iChannel1, uv, 0.0).rgb, bloom = vec3(0.0);
    for (int l = 1; l <= 6; l++) {
        float lod = float(l);
        vec2 o = exp2(lod) / iResolution.xy * 0.5;
        bloom += (textureLod(iChannel1, uv + o, lod).rgb + textureLod(iChannel1, uv - o, lod).rgb
                + textureLod(iChannel1, uv + vec2(o.x, -o.y), lod).rgb + textureLod(iChannel1, uv - vec2(o.x, -o.y), lod).rgb)
                * 0.25 / (1.0 + 0.4 * lod);
    }
    c = aces((c + 0.35 * max(bloom / 3.2 - 0.01, 0.0)) * 1.05);
    vec2 v = uv - 0.5;
    c *= 1.0 - 0.45 * dot(v * vec2(1.1, 1.3), v * vec2(1.1, 1.3));
    vec2 s = (fc - 0.5 * iResolution.xy) * PX;
    float act = st(8);
    c = slider(s, MX0, MX1, 0.5 + 0.5 * st(7), act == 2.0, true, c);
    c = slider(s, ZX0, ZX1, st(5) / ZOOM_MAX, act == 3.0, false, c);
    O = vec4(pow(c, vec3(1.0 / 2.2)), 1.0);
}
