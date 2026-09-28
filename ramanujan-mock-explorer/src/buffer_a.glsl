// Buffer A — UI state (texels 0..6 of row 0).  iChannel0 = Buffer A (self)
//  0-1 pan (disk units at the screen centre), 2 zoom (log2), 3 zoom velocity,
//  4-5 morph target/eased, 6 active (0 none, 1 zooming, 2 morph slider)

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }

void mainImage(out vec4 O, in vec2 fc) {
    ivec2 p = ivec2(fc);
    O = vec4(0.0);
    if (p.y != 0 || p.x > 6) return;
    bool init = iFrame == 0;
    vec2 pan = init ? vec2(0.0) : vec2(st(0), st(1));
    float z = init ? 0.0 : st(2), zv = init ? 0.0 : st(3);
    float tm = init ? 0.0 : st(4), cm = init ? 0.0 : st(5), act = init ? 0.0 : st(6);
    float px = 1.0 / iResolution.y, dt = clamp(iTimeDelta, 0.0, 0.1);
    vec2 ms = (iMouse.xy - 0.5 * iResolution.xy) * px;
    vec2 ck = (abs(iMouse.zw) - 0.5 * iResolution.xy) * px;
    bool down = iMouse.z > 0.0;
    if (down && iMouse.w > 0.0)
        act = abs(ck.y - UI_Y) < UI_HIT && ck.x > MX0 - 0.03 && ck.x < MX1 + 0.03 ? 2.0 : 1.0;
    if (!down) act = 0.0;
    if (act == 2.0) tm = mix(-1.0, 1.0, clamp((ms.x - MX0) / (MX1 - MX0), 0.0, 1.0));
    if (!down) tm = floor(tm + 0.5);                        // morph settles on f+b, f, f-b

    // zoom speed eases toward +in while held, -out when released
    float target = act == 1.0 ? ZOOM_IN : z > 0.0 ? -ZOOM_OUT : 0.0;
    zv += (target - zv) * (1.0 - exp(-4.0 * dt));
    float z1 = clamp(z + zv * dt, 0.0, ZOOM_MAX);
    if (act == 1.0) {
        // keep the point under the cursor fixed while the scale changes
        vec2 qc = pan + ms / (DISK_R * exp2(z));
        pan = qc - ms / (DISK_R * exp2(z1));
    } else {
        pan *= 1.0 - (1.0 - exp(-1.5 * dt)) * (1.0 - smoothstep(0.0, 3.0, z1));   // recentre near home
    }
    z = z1;
    pan = clamp(pan, vec2(-1.2), vec2(1.2));
    cm += (tm - cm) * (1.0 - exp(-6.0 * dt));
    O.x = p.x == 0 ? pan.x : p.x == 1 ? pan.y : p.x == 2 ? z : p.x == 3 ? zv : p.x == 4 ? tm : p.x == 5 ? cm : act;
}
