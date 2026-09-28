// Buffer A — UI state (texels 0..11 of row 0).  iChannel0 = Buffer A (self)
//  0-1 pan target (disk units), 2-3 pan eased, 4-5 zoom target/eased (log2),
//  6-7 morph target/eased, 8 active (0, 1 pan, 2 morph, 3 zoom), 10-11 pan at press

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }

void mainImage(out vec4 O, in vec2 fc) {
    ivec2 p = ivec2(fc);
    O = vec4(0.0);
    if (p.y != 0 || p.x > 11) return;
    bool init = iFrame == 0;
    vec2 tp = init ? vec2(0.0) : vec2(st(0), st(1)), cp = init ? vec2(0.0) : vec2(st(2), st(3));
    float tz = init ? 0.0 : st(4), cz = init ? 0.0 : st(5);
    float tm = init ? 0.0 : st(6), cm = init ? 0.0 : st(7);
    float act = init ? 0.0 : st(8);
    vec2 p0 = init ? vec2(0.0) : vec2(st(10), st(11));
    float px = 1.0 / iResolution.y;
    vec2 ms = (iMouse.xy - 0.5 * iResolution.xy) * px;
    vec2 ck = (abs(iMouse.zw) - 0.5 * iResolution.xy) * px;
    if (iMouse.z > 0.0) {
        if (iMouse.w > 0.0) {
            bool onUI = abs(ck.y - UI_Y) < UI_HIT;
            act = onUI && ck.x > MX0 - 0.03 && ck.x < MX1 + 0.03 ? 2.0
                : onUI && ck.x > ZX0 - 0.03 && ck.x < ZX1 + 0.03 ? 3.0 : 1.0;
            p0 = tp;
        }
        if (act == 1.0) tp = p0 - (ms - ck) / (DISK_R * exp2(cz));
        if (act == 2.0) tm = mix(-1.0, 1.0, clamp((ms.x - MX0) / (MX1 - MX0), 0.0, 1.0));
        if (act == 3.0) tz = ZOOM_MAX * clamp((ms.x - ZX0) / (ZX1 - ZX0), 0.0, 1.0);
    } else {
        act = 0.0;
        tm = floor(tm + 0.5);                       // morph settles on f+b, f, f-b
    }
    tp = clamp(tp, vec2(-1.1), vec2(1.1));
    float k = 1.0 - exp(-6.0 * clamp(iTimeDelta, 0.0, 0.1));
    cp += (tp - cp) * k; cz += (tz - cz) * k; cm += (tm - cm) * k;
    O.x = p.x == 0 ? tp.x : p.x == 1 ? tp.y : p.x == 2 ? cp.x : p.x == 3 ? cp.y : p.x == 4 ? tz : p.x == 5 ? cz
        : p.x == 6 ? tm : p.x == 7 ? cm : p.x == 8 ? act : p.x == 10 ? p0.x : p.x == 11 ? p0.y : 0.0;
}
