// Buffer C: which field lines can touch each 32 x 32 screen tile.
// iChannel0 = Buffer A (state)   iChannel1 = Buffer B (field lines)
//
// Four texels per tile, each a 64-line mask stored as four exact 16-bit integers. A line is
// listed when any of its eight chunk bounding spheres projects onto the tile.

vec4 lineTexel(int line, int slot) {
    int j = line * STRIDE + slot, w = int(iResolution.x);
    return texelFetch(iChannel1, ivec2(j % w, j / w), 0);
}

void mainImage(out vec4 O, in vec2 P) {
    O = vec4(0);
    vec2 res = iResolution.xy;
    int tx = (int(res.x) + TILE - 1) / TILE, ty = (int(res.y) + TILE - 1) / TILE;
    int idx = int(P.y) * int(res.x) + int(P.x), tile = idx / 4, group = idx % 4;
    if (tile >= tx * ty) return;
    vec4 ctrl = fetch(iChannel0, S_CTRL, 0);
    if (ctrl.y < 0.5 && ctrl.z < 0.5) return;            // no lines drawn in this view
    Star s = loadStar(iChannel0);
    vec3 ax = starAxes(s);
    float axm = max(ax.x, ax.y);
    Cam k = starCam(makeCam(fetch(iChannel0, S_CAM, 0), res), fetch(iChannel0, S_CLOCK, 0).y);
    vec2 lo = vec2(tile % tx, tile / tx) * float(TILE) - 4.0, hi = lo + float(TILE) + 8.0;
    uvec4 bits = uvec4(0);
    for (int l = 0; l < 64; l++) {
        int line = group * 64 + l;
        if (lineTexel(line, STRIDE - 1).x <= 0.0) continue;
        for (int c = 0; c < 8; c++) {
            vec4 b = lineTexel(line, NODES + c);
            if (b.w < 0.0) break;
            vec3 v = b.xyz * ax - k.ro;
            float z = dot(v, k.fw), r = b.w * axm;
            if (z + r <= 0.0) continue;
            bool hit = z <= r + 0.01;
            if (!hit) {
                vec2 c2 = k.center + k.focal * vec2(dot(v, k.rt), dot(v, k.up)) / z;
                float rp = k.focal * r / sqrt(max(z * z - r * r, 1e-6)) + 1.5;
                vec2 d = max(max(lo - c2, c2 - hi), vec2(0));
                hit = dot(d, d) < rp * rp;
            }
            if (hit) {
                uint bit = 1u << uint(l % 16);
                if (l < 16) bits.x |= bit; else if (l < 32) bits.y |= bit; else if (l < 48) bits.z |= bit; else bits.w |= bit;
                break;
            }
        }
    }
    O = vec4(bits);
}
