// Image: bloom straight from Buffer A's mip chain, ACES tone map, vignette, dither.
// iChannel0 = Buffer A (mipmap)

vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

void mainImage(out vec4 O, in vec2 fc) {
    vec2 uv = fc / iResolution.xy;
    vec3 c = textureLod(iChannel0, uv, 0.0).rgb;
    vec3 bloom = vec3(0.0);
    for (int l = 1; l <= 6; l++) {
        float lod = float(l);
        vec2 o = exp2(lod) / iResolution.xy;
        vec3 s = textureLod(iChannel0, uv + vec2(o.x, o.y) * 0.5, lod).rgb + textureLod(iChannel0, uv - vec2(o.x, o.y) * 0.5, lod).rgb
               + textureLod(iChannel0, uv + vec2(o.x, -o.y) * 0.5, lod).rgb + textureLod(iChannel0, uv - vec2(o.x, -o.y) * 0.5, lod).rgb;
        bloom += s * 0.25 / (1.0 + 0.35 * lod);
    }
    c += 0.28 * max(bloom / 3.3 - 0.02, 0.0);
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = aces(mix(vec3(l), c, 1.15));
    vec2 q = uv - 0.5;
    c *= 1.0 - 0.55 * dot(q * vec2(1.1, 1.3), q * vec2(1.1, 1.3));
    // timeline bar: drag inside it to scrub (it spans the intro and the first
    // turns of the zoom; the zoom itself runs on forever)
    float T = texelFetch(iChannel0, ivec2(0), 0).a;
    float barH = 0.045 * iResolution.y;
    bool scrub = iMouse.z > 0.0 && abs(iMouse.w) < barH;
    float y = fc.y, x = uv.x;
    float line = smoothstep(2.5, 0.5, abs(y - barH * 0.45));
    float prog = clamp(T / 46.0, 0.0, 1.0);
    float vis = scrub ? 1.0 : 0.45;
    c = mix(c, vec3(0.35, 0.33, 0.4), line * 0.35 * vis);
    c = mix(c, vec3(1.0, 0.66, 0.24), line * step(x, prog) * vis);
    c = mix(c, vec3(0.95, 0.88, 0.74), smoothstep(2.0, 0.0, abs(x - 24.0 / 46.0) * iResolution.x) * smoothstep(6.0, 2.0, abs(y - barH * 0.45)) * vis);
    float head = length(vec2((x - prog) * iResolution.x, y - barH * 0.45));
    c += vec3(1.0, 0.75, 0.4) * smoothstep(4.5, 2.5, head) * vis * (T > 46.0 ? 0.6 + 0.4 * sin(iTime * 3.0) : 1.0);

    c = pow(c, vec3(1.0 / 2.2));
    c += (fract(sin(dot(fc + float(iFrame), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    O = vec4(c, 1.0);
}
