// Buffer B: field lines of the current potential field.
// iChannel0 = Buffer A (state, regions, sources)   iChannel1 = Buffer B (itself, nearest)
//
// 256 lines x 73 texels: 64 nodes (xyz in the star frame, w = arc length), 8 chunk bounding
// spheres, 1 meta texel. Node k is re-integrated every frame from the previous frame's node at
// the start of its 8-node chunk, so a line follows a changing field within 8 frames and costs
// at most 8 nodes of integration per texel. Bounds integrate their chunk from the same starts,
// so they always enclose this frame's nodes exactly.

vec4 SRC[2 * NREG];
int NSRC;
vec3 DIP;

vec3 field(vec3 p) {
    vec3 B = dipoleField(p, DIP);
    for (int i = 0; i < NSRC + ZERO; i++) B += sourceField(p, SRC[i]);
    return B;
}

// Line seeds: 12 per region (8 around the positive spot, traced along B; 4 around the
// negative spot, traced against B), then 64 on a Fibonacci sphere traced outward.
vec4 seed(int i, out float energy, out float kind) {
    kind = 1.0;
    if (i < 12 * NREG) {
        int k = i / 12, j = i % 12;
        Region g = loadRegion(iChannel0, k);
        energy = g.e * (1.0 + 2.0 * g.flare); kind = g.age > 0.55 ? 1.0 : 0.0;
        bool pos = j < 8;
        vec3 lead = normalize(g.n + g.a * g.u), foll = normalize(g.n - g.a * g.u);
        vec3 c = (g.lead > 0.0) == pos ? lead : foll;
        vec3 e1 = normalize(cross(c, g.u)), e2 = cross(c, e1);
        float ang = float(j) * 2.39996, rad = g.w * (0.35 + 0.9 * fract(float(j) * 0.618));
        return vec4(normalize(c + rad * (cos(ang) * e1 + sin(ang) * e2)) * 1.002, pos ? 1.0 : -1.0);
    }
    float k = float(i - 12 * NREG), y = 1.0 - 2.0 * (k + 0.5) / 64.0, az = k * 2.39996;
    vec3 p = vec3(cos(az) * sqrt(1.0 - y * y), y, sin(az) * sqrt(1.0 - y * y)) * 1.002;
    vec3 B = field(p);
    float br = dot(B, normalize(p));
    energy = NSRC > 0 || dot(DIP, DIP) > 0.0 ? 0.35 * smoothstep(0.0, 0.05, abs(br)) : 0.0; kind = 1.0;
    return vec4(p, br >= 0.0 ? 1.0 : -1.0);
}

// Advance n nodes (two midpoint steps each). Lines stop where they re-enter the surface
// or leave the domain; beyond the source surface the field is radial.
vec4 advance(vec4 s, float dir, int n, inout vec3 lo, inout vec3 hi) {
    vec3 p = s.xyz; float arc = s.w;
    for (int i = 0; i < n + ZERO; i++) {
        float r = length(p);
        if (r > RMAX || (r < 1.0001 && arc > 0.01)) break;
        for (int k = 0; k < 2 + ZERO; k++) {
            r = length(p);
            float ds = min(0.07, 0.006 + 0.045 * max(r - 1.0, 0.0));
            vec3 q;
            if (r >= RSS) q = p + normalize(p) * ds;
            else {
                // Midpoint rule; both stages share one field() call site.
                vec3 x = p;
                for (int st = 0; st < 2 + ZERO; st++) {
                    vec3 v = normalize(field(x) + 1e-12) * dir;
                    if (st == 0) x = p + v * 0.5 * ds; else q = p + v * ds;
                }
            }
            float rq = length(q);
            if (rq < 1.0 && arc > 0.004) {
                float f = clamp((r - 1.0) / max(r - rq, 1e-6), 0.0, 1.0);
                q = normalize(mix(p, q, f)); arc += f * ds; p = q; break;
            }
            arc += ds; p = q;
            if (rq > RMAX) break;
        }
        lo = min(lo, p); hi = max(hi, p);
    }
    return vec4(p, arc);
}

void mainImage(out vec4 O, in vec2 P) {
    int idx = int(P.y) * int(iResolution.x) + int(P.x);
    O = vec4(0);
    if (idx >= NLINES * STRIDE) return;
    int line = idx / STRIDE, slot = idx % STRIDE;
    NSRC = 0;
    for (int i = 0; i < 2 * NREG + ZERO; i++) { vec4 s = fetch(iChannel0, i, 2); if (s.w != 0.0) { SRC[NSRC] = s; NSRC++; } }
    DIP = fetch(iChannel0, S_MODEL + 5, 0).xyz;
    float energy, kind;
    vec4 s0 = seed(line, energy, kind);
    float dir = s0.w; s0.w = 0.0;
    if (slot == STRIDE - 1) {
        // energy, direction, closed (last node back on the surface), cool.
        // Cool lines are low closed loops rooted in quiet or decayed flux: they hold the
        // dense chromospheric material of filaments and prominences.
        int w = int(iResolution.x);
        float peak = 1.0;
        for (int k = 0; k < NODES + ZERO; k += 3) { int j = line * STRIDE + k; peak = max(peak, length(texelFetch(iChannel1, ivec2(j % w, j / w), 0).xyz)); }
        int j = line * STRIDE + NODES - 1;
        bool closed = length(texelFetch(iChannel1, ivec2(j % w, j / w), 0).xyz) < 1.02;
        O = vec4(energy < 0.02 ? 0.0 : energy, dir, closed ? 1.0 : 0.0, closed && kind > 0.5 && peak < 1.6 ? 1.0 : 0.0);
        return;
    }
    if (energy < 0.02) { O = slot < NODES ? s0 : vec4(0, 0, 0, -1); return; }
    // Every texel integrates at most two legs, through a single call site (compilers inline
    // each call). Node k: one leg from the start of its chunk. Bound c: first node 8c (from the
    // previous chunk start), then the chunk itself.
    int w = int(iResolution.x), c = slot - NODES;
    bool isNode = slot < NODES;
    if (isNode && slot == 0) { O = s0; return; }
    int k0 = isNode ? ((slot - 1) / 8) * 8 : 8 * c;
    int legs = isNode || c == 0 ? 1 : 2;
    vec3 lo = vec3(1e5), hi = vec3(-1e5);
    vec4 res = s0;
    for (int leg = 0; leg < legs + ZERO; leg++) {
        bool pre = legs == 2 && leg == 0;
        int from = pre ? k0 - 8 : k0, j = line * STRIDE + from;
        vec4 st = from == 0 ? s0 : texelFetch(iChannel1, ivec2(j % w, j / w), 0);
        int n = isNode ? slot - k0 : (pre ? 8 : (c == 7 ? 7 : 8));
        if (!isNode && legs == 1) { lo = st.xyz; hi = st.xyz; }      // chunk 0 starts at the seed
        res = advance(st, dir, n, lo, hi);
        if (pre) { lo = res.xyz; hi = res.xyz; }                      // chunk c starts at this frame's node 8c
    }
    if (isNode) { O = res; return; }
    O = vec4(0.5 * (lo + hi), 0.5 * length(hi - lo) + 0.004);
}
