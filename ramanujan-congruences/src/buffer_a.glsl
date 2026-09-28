// Buffer A — state and data.  iChannel0 = Buffer A (self)
//  row 0: x of texel 0 m target, 1 m eased, 2 rings target, 3 rings eased,
//         4 active slider (0 none, 1 m, 2 rings), 5 frames since start
//  rows 1..4: p(n) mod 720720 for n < 1024 (256 per row), from Euler's
//  pentagonal recurrence jumped 8 levels per frame (complete after 128 frames):
//    p(n) = sum_k (-1)^(k+1) sum_{g = k(3k-+1)/2} sum_{i<8, g+i>=8} p(i) p(n-g-i)

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }
int smallp(int i) { return i < 2 ? 1 : i == 2 ? 2 : i == 3 ? 3 : i == 4 ? 5 : i == 5 ? 7 : i == 6 ? 11 : 15; }
int pmod(int n) { return int(texelFetch(iChannel0, ivec2(n & 255, 1 + (n >> 8)), 0).x); }

void mainImage(out vec4 O, in vec2 fc) {
    ivec2 p = ivec2(fc);
    O = vec4(0.0);
    if (p.y == 0 && p.x < 6) {
        bool init = iFrame == 0;
        float tm = init ? 5.0 : st(0), cm = init ? 5.0 : st(1);
        float tr = init ? 30.0 : st(2), cr = init ? 30.0 : st(3);
        float act = init ? 0.0 : st(4), fr = init ? 0.0 : st(5) + 1.0;
        float px = 1.0 / iResolution.y;
        vec2 ms = (iMouse.xy - 0.5 * iResolution.xy) * px;
        vec2 ck = (abs(iMouse.zw) - 0.5 * iResolution.xy) * px;
        if (iMouse.z > 0.0) {
            if (iMouse.w > 0.0) {                   // press: which slider?
                bool inX = ck.x > SX0 - 0.03 && ck.x < SX1 + 0.03;
                act = inX && abs(ck.y - SY_M) < S_HIT ? 1.0 : inX && abs(ck.y - SY_R) < S_HIT ? 2.0 : 0.0;
            }
            float f = clamp((ms.x - SX0) / (SX1 - SX0), 0.0, 1.0);
            if (act == 1.0) tm = mix(M_MIN, M_MAX, f);
            if (act == 2.0) tr = mix(R_MIN, R_MAX, f);
        } else {
            act = 0.0;
            tm = floor(tm + 0.5);                   // m settles on a whole number
        }
        float k = 1.0 - exp(-7.0 * clamp(iTimeDelta, 0.0, 0.1));
        cm += (tm - cm) * k; cr += (tr - cr) * k;
        O.x = p.x == 0 ? tm : p.x == 1 ? cm : p.x == 2 ? tr : p.x == 3 ? cr : p.x == 4 ? act : fr;
        return;
    }
    if (p.y < 1 || p.y > 4) return;
    int n = (p.y - 1) * 256 + p.x;
    if (n < 8) { O.x = float(smallp(n)); return; }
    int pos = 0, neg = 0;
    for (int k = 1; k < 40; k++) {
        int g1 = k * (3 * k - 1) / 2;
        if (g1 > n) break;
        for (int s = 0; s < 2; s++) {
            int g = g1 + s * k;
            for (int i = max(0, 8 - g); i < 8; i++) {
                int m = n - g - i;
                if (m < 0) break;
                int v = (smallp(i) * pmod(m)) % LMOD;
                if ((k & 1) == 1) pos = (pos + v) % LMOD; else neg = (neg + v) % LMOD;
            }
        }
    }
    O.x = float((pos - neg + LMOD) % LMOD);
}
