// Buffer D — bloom. Buffer B is sampled through its mip chain (mipmap filter):
// each level is blurred with a small tent and the levels are summed, giving a
// wide, soft halo for the cost of a few dozen taps.
//
// iChannel0 = Buffer B (mipmap)

vec3 tap(vec2 uv, float lod) { return textureLod(iChannel0, uv, lod).rgb; }

void mainImage(out vec4 O, in vec2 fc) {
    vec2 uv = fc / iResolution.xy;
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int l = 1; l <= 6; l++) {
        float lod = float(l);
        vec2 o = exp2(lod) / iResolution.xy;
        vec3 c = 4.0 * tap(uv, lod)
               + 2.0 * (tap(uv + vec2(o.x, 0.0), lod) + tap(uv - vec2(o.x, 0.0), lod)
                      + tap(uv + vec2(0.0, o.y), lod) + tap(uv - vec2(0.0, o.y), lod))
               + tap(uv + o, lod) + tap(uv - o, lod) + tap(uv + vec2(o.x, -o.y), lod) + tap(uv - vec2(o.x, -o.y), lod);
        float w = 1.0 / (1.0 + 0.35 * lod);
        acc += w * c / 16.0;
        wsum += w;
    }
    vec3 b = acc / wsum;
    O = vec4(max(b - 0.02, 0.0), 1.0);        // only light, not the dark ground, blooms
}
