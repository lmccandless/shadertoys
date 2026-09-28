// Image — composite: scene + bloom, filmic tone map, captions, vignette,
// grain, and the timeline scrubber while the mouse is held.
//
// iChannel0 = Buffer B (scene)   iChannel1 = Buffer C (captions)
// iChannel2 = Buffer D (bloom)   iChannel3 = Buffer A (clock)

vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

void mainImage(out vec4 O, in vec2 fc) {
    vec2 uv = fc / iResolution.xy;
    vec3 scene = texture(iChannel0, uv).rgb;
    vec3 bloom = texture(iChannel2, uv).rgb;
    vec3 c = scene + 0.28 * bloom;
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = aces(mix(vec3(l), c, 1.15));          // a touch more saturation before the curve

    // vignette
    vec2 q = uv - 0.5;
    c *= 1.0 - 0.55 * dot(q * vec2(1.1, 1.3), q * vec2(1.1, 1.3));

    // captions: darken behind them, then lay the text on top
    vec4 t = texture(iChannel1, uv);
    c = c * (1.0 - 0.6 * t.a) + min(t.rgb, 1.2);

    // timeline, shown while scrubbing
    float T = texelFetch(iChannel3, ivec2(0), 0).x;
    if (iMouse.z > 0.0) {
        float y = fc.y / iResolution.y;
        float x = uv.x;
        float bar = smoothstep(0.022, 0.018, y) * smoothstep(0.008, 0.012, y);
        c = mix(c, vec3(0.06, 0.06, 0.1), bar * 0.8);
        c = mix(c, GOLD, bar * step(x, T / T_TOTAL) * 0.9);
        for (int i = 1; i < N_ACTS; i++)
            c = mix(c, IVORY, bar * (1.0 - smoothstep(0.0, 1.5 / iResolution.x, abs(x - actStart(i) / T_TOTAL))));
    }

    c = pow(c, vec3(1.0 / 2.2));
    c += (hash12(fc + float(iFrame) * 17.0) - 0.5) / 255.0;   // dither
    O = vec4(c, 1.0);
}
