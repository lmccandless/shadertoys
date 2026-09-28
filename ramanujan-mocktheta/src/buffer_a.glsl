// Buffer A — UI state only (texels 0..7 of row 0).  iChannel0 = Buffer A (self)
//  0 morph target, 1 morph eased (-1 = f+b, 0 = f, 1 = f-b)
//  2 rim depth target, 3 eased, 4 turn target, 5 turn eased,
//  6 active control (0 none, 1 morph, 2 depth, 3 turning), 7 turn at drag start

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }

void mainImage(out vec4 O, in vec2 fc) {
    ivec2 p = ivec2(fc);
    O = vec4(0.0);
    if (p.y != 0 || p.x > 7) return;
    bool init = iFrame == 0;
    float ts = init ? 0.0 : st(0), cs = init ? 0.0 : st(1);
    float tr = init ? 0.992 : st(2), cr = init ? 0.992 : st(3);
    float ta = init ? 0.0 : st(4), ca = init ? 0.0 : st(5);
    float act = init ? 0.0 : st(6), a0 = init ? 0.0 : st(7);
    float px = 1.0 / iResolution.y;
    vec2 ms = (iMouse.xy - 0.5 * iResolution.xy) * px;
    vec2 ck = (abs(iMouse.zw) - 0.5 * iResolution.xy) * px;
    if (iMouse.z > 0.0) {
        if (iMouse.w > 0.0) {                       // press: pick a control
            bool inX = ck.x > SX0 - 0.03 && ck.x < SX1 + 0.03;
            act = inX && abs(ck.y - SY_S) < S_HIT ? 1.0 : inX && abs(ck.y - SY_R) < S_HIT ? 2.0 : 3.0;
            a0 = ta;
        }
        float f = clamp((ms.x - SX0) / (SX1 - SX0), 0.0, 1.0);
        if (act == 1.0) ts = mix(-1.0, 1.0, f);
        if (act == 2.0) tr = mix(R_MIN, R_MAX, f);
        if (act == 3.0) ta = a0 + (ms.x - ck.x) * 4.0;
    } else {
        act = 0.0;
        ts = floor(ts + 0.5);                       // settle on f + b, f or f - b
    }
    float dt = clamp(iTimeDelta, 0.0, 0.1), k = 1.0 - exp(-7.0 * dt);
    ta -= 0.03 * dt;                                // a slow drift
    cs += (ts - cs) * k; cr += (tr - cr) * k; ca += (ta - ca) * k;
    O.x = p.x == 0 ? ts : p.x == 1 ? cs : p.x == 2 ? tr : p.x == 3 ? cr
        : p.x == 4 ? ta : p.x == 5 ? ca : p.x == 6 ? act : a0;
}
