// Image — the disk, its corona of rays, two sliders and a little text.
// iChannel0 = Buffer A (UI state)   iChannel1 = font texture
//
// Compile-light: the q-series is inlined once (the ray sample and the three
// disk samples share one loop), the modular reduction once, and text is
// fixed-width with strings packed four characters to a uint.

const vec3 GOLD = vec3(1.0, 0.66, 0.24), IVORY = vec3(0.95, 0.88, 0.74), PEA = vec3(0.07, 0.75, 0.82);
const float PI = 3.14159265, TAU = 6.28318531, ADV = 0.5;
float PX;

float st(int i) { return texelFetch(iChannel0, ivec2(i, 0), 0).x; }
vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }

// ---- the functions ---------------------------------------------------------------
// Watson: f = A - 2B and b = A + 2B, with A = phi(-q), B = psi(-q) (third-order
// mock thetas). So f - s b = (1-s) A - 2(1+s) B, computed without cancellation.
// A erupts only at orders 0 (mod 4), B only at orders 2 (mod 4).
vec2 mockF(vec2 q, float s) {
    vec2 one = vec2(1.0, 0.0), q2 = cmul(q, q), qp = q;
    vec2 a = cdiv(-q, one + q2), b = -cdiv(q, one + q);
    vec2 A = one + a, B = b;
    for (int n = 2; n < 110; n++) {
        qp = cmul(qp, q2);                          // q^(2n-1)
        a = cmul(a, cdiv(-qp, one + cmul(qp, q)));
        b = cmul(b, cdiv(-qp, one + qp));
        A += a; B += b;
        if (dot(qp, qp) < 1e-14 * (1.0 + dot(a, a) + dot(b, b))) break;
    }
    return (1.0 - s) * A - 2.0 * (1.0 + s) * B;
}

// denominator of the fraction nearest the rim point at angle t (Ford reduction)
float rimOrder(float t, float y) {
    vec2 tau = vec2(t / TAU, y);
    vec4 g = vec4(1, 0, 0, 1);
    for (int i = 0; i < 32; i++) {
        float n = floor(tau.x + 0.5);
        tau.x -= n; g.xy -= n * g.zw;
        float r2 = dot(tau, tau);
        if (r2 >= 1.0) break;
        tau = vec2(-tau.x, tau.y) / r2;
        g = vec4(-g.zw, g.xy);
    }
    return abs(g.z);
}

vec3 cyc(float h) {                                 // phase colours
    h = fract(h) * 5.0;
    vec3 c = mix(GOLD * 1.1, vec3(1.0, 0.42, 0.1), smoothstep(0.0, 1.0, h));
    c = mix(c, vec3(0.88, 0.08, 0.13), smoothstep(1.0, 2.0, h));
    c = mix(c, vec3(0.42, 0.1, 0.62), smoothstep(2.0, 3.0, h));
    c = mix(c, PEA * 1.2, smoothstep(3.0, 4.0, h));
    return mix(c, GOLD * 1.1, smoothstep(4.0, 5.0, h));
}

vec3 disk(vec2 uv, float s, float R0, float turn) {
    const vec2 C = vec2(0.36, 0.0);
    const float RAD = 0.33;
    vec2 p = (uv - C) / RAD;
    float cs = cos(turn), sn = sin(turn);
    p = mat2(cs, sn, -sn, cs) * p;
    float r = length(p), fp = PX / RAD;
    float ang = atan(p.y, p.x);
    vec3 col = vec3(0.008, 0.009, 0.022);
    bool outside = r > 1.0;

    // one loop: outside the disk a single rim sample for the ray, inside the
    // pixel and two neighbours for gradients of log|F| and arg F
    vec2 base = outside ? R0 * vec2(cos(ang), sin(ang)) : p * min(1.0, R0 / max(r, 1e-6));
    float lm = 0.0, ph = 0.0;
    vec2 glm = vec2(0.0), gph = vec2(0.0);
    for (int k = 0; k < 3; k++) {
        vec2 o = k == 1 ? vec2(fp, 0.0) : k == 2 ? vec2(0.0, fp) : vec2(0.0);
        vec2 F = mockF(base + o, s);
        float l = 0.5 * log2(max(dot(F, F), 1e-30)), a = atan(F.y, F.x) / TAU;
        if (k == 0) { lm = l; ph = a; }
        else {
            vec2 m = k == 1 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
            glm += m * (l - lm);
            gph += m * (a - ph - floor(a - ph + 0.5));
        }
        if (outside) break;
    }

    // ray colour by the order of the nearest root: 2 mod 4 gold, 0 mod 4 peacock
    float k = rimOrder(ang, -log(R0) / TAU);
    float k4 = mod(k, 4.0);
    vec3 rayC = k4 == 2.0 ? GOLD * 1.1 : k4 == 0.0 ? PEA * 1.6 : IVORY * 0.4;
    float grow = (1.0 - R0) * lm * 0.693147;          // (1-|q|) log|F|: ~ c/k^2 at a root
    float len = 0.85 * sqrt(max(grow - 0.02, 0.0) / 0.44);
    if (outside) {
        if (len > 0.002) {
            float x = (r - 1.0) / len;
            col += rayC * (0.9 * exp(-2.2 * x) + 1.6 * exp(-12.0 * x)) * (0.85 + 0.15 * sin(iTime * 5.0 + ang * 40.0));
        }
    } else {
        vec3 hue = cyc(ph + 0.12);
        vec3 c = vec3(0.012, 0.013, 0.032) + hue * (0.03 + 0.05 * fract(lm));
        float gm = max(length(glm), 1e-5), gp = max(length(gph) * 12.0, 1e-5);
        c += GOLD * 0.5 * smoothstep(1.4, 0.3, abs(lm - floor(lm + 0.5)) / gm) * smoothstep(0.45, 0.15, gm);
        c += hue * 0.75 * smoothstep(1.4, 0.3, abs(ph * 12.0 - floor(ph * 12.0 + 0.5)) / gp) * smoothstep(0.45, 0.15, gp);
        c = mix(c, hue * 0.22 + GOLD * 0.08, smoothstep(0.45, 1.5, max(gm, gp)) * 0.85);
        c += rayC * 1.5 * pow(clamp((1.0 - length(base)) * lm * 0.693147 / 0.4, 0.0, 1.0), 2.0) * smoothstep(0.8, 0.99, r);
        col = c;
    }
    col += GOLD * (0.9 * smoothstep(1.6 * fp, 0.3 * fp, abs(r - 1.0)) + 0.15 * exp(-abs(r - 1.0) / fp * 0.05));
    return col;
}

// ---- text -------------------------------------------------------------------------
uint packed(int s, int j) {             // strings, four chars per uint
    if (s == 0) return j == 0 ? 1634558290u : j == 1 ? 1634366830u : j == 2 ? 544417646u : j == 3 ? 1801678701u : j == 4 ? 1701344288u : j == 5 ? 1713398132u : j == 6 ? 1952673397u : 7237481u;   // Ramanujan's mock theta function
    if (s == 1) return j == 0 ? 695281766u : j == 1 ? 824196384u : j == 2 ? 1897933600u : j == 3 ? 724641839u : j == 4 ? 548546929u : j == 5 ? 1584472107u : j == 6 ? 824717108u : j == 7 ? 2989060395u : j == 8 ? 1898656040u : j == 9 ? 548546994u : j == 10 ? 774774827u : 46u;   // f(q) = 1 + q/(1+q)? + q^4/(1+q)?(1+q?)? + ...
    if (s == 2) return j == 0 ? 1836020326u : j == 1 ? 1936287776u : j == 2 ? 1935764512u : j == 3 ? 1701585012u : j == 4 ? 1919251572u : j == 5 ? 544175136u : j == 6 ? 1685217608u : j == 7 ? 824192121u : 3158585u;   // from his last letter to Hardy, 1920
    if (s == 3) return j == 0 ? 1684828007u : j == 1 ? 2036429344u : j == 2 ? 1864383091u : j == 3 ? 1919247474u : j == 4 ? 741482611u : j == 5 ? 539768352u : j == 6 ? 539766833u : 3026478u;   // gold rays: orders 2, 6, 10, ...
    if (s == 4) return j == 0 ? 1667327344u : j == 1 ? 543908719u : j == 2 ? 1937334642u : j == 3 ? 1919885370u : j == 4 ? 1936876900u : j == 5 ? 539767840u : j == 6 ? 824192056u : j == 7 ? 773860402u : 11822u;   // peacock rays: orders 4, 8, 12, ...
    if (s == 5) return j == 0 ? 539697254u : 98u;   // f + b
    if (s == 6) return 102u;   // f
    if (s == 7) return j == 0 ? 539828326u : 98u;   // f - b
    if (s == 8) return j == 0 ? 544041330u : j == 1 ? 1953523044u : 104u;   // rim depth
    if (s == 9) return j == 0 ? 695281762u : j == 1 ? 673201440u : j == 2 ? 2993765233u : j == 3 ? 2233506089u : j == 4 ? 975794472u : j == 5 ? 1948279072u : j == 6 ? 1635018088u : j == 7 ? 1853187616u : j == 8 ? 1869182051u : 110u;   // b(q) = (q;q?)? ?(q): a theta function
    if (s == 10) return j == 0 ? 1751343461u : j == 1 ? 1970431264u : j == 2 ? 1869182064u : j == 3 ? 1936269422u : j == 4 ? 1886348064u : j == 5 ? 543450473u : j == 6 ? 1646295394u : j == 7 ? 1769414700u : j == 8 ? 1629513844u : j == 9 ? 1734964000u : 15214u;   // each eruption is copied by b, with a sign;
    if (s == 11) return j == 0 ? 1931505518u : j == 1 ? 1818717801u : j == 2 ? 1752440933u : j == 3 ? 543257701u : j == 4 ? 1668183398u : j == 5 ? 1852795252u : j == 6 ? 1886348064u : j == 7 ? 544433513u : j == 8 ? 1835362420u : 1819042080u;   // no single theta function copies them all
    if (s == 12) return j == 0 ? 1734439524u : j == 1 ? 1701344288u : j == 2 ? 1936286752u : j == 3 ? 1869881451u : j == 4 ? 1920300064u : 1953046638u;   // drag the disk to turn it
    return 0u;
}
int strLen(int s) { return s == 0 ? 31 : s == 1 ? 45 : s == 2 ? 35 : s == 3 ? 31 : s == 4 ? 34 : s == 5 ? 5 : s == 6 ? 1 : s == 7 ? 5 : s == 8 ? 9 : s == 9 ? 37 : s == 10 ? 42 : s == 11 ? 40 : 24; }

uint strChar(int s, int i) { return (packed(s, i >> 2) >> (8 * (i & 3))) & 255u; }

float glyph(uint c, vec2 q) {
    vec2 uv = vec2(0.5 + q.x - 0.5 * ADV, 0.8 - q.y);
    if (c == 32u || c == 0u || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1e5;
    return textureLod(iChannel1, (vec2(float(c % 16u), float(c / 16u)) + uv) / 16.0, 0.0).a - 0.5;
}

// one line of packed string s; align 0 left, 0.5 centre
vec3 textLine(vec2 uv, vec2 org, float em, int s, float align, vec3 col, float alpha, vec3 acc) {
    int n = strLen(s);
    vec2 q = (uv - org) / em;
    q.x += align * float(n) * ADV;
    if (alpha <= 0.0 || q.y < -0.35 || q.y > 1.0 || q.x < 0.0 || q.x > float(n) * ADV) return acc;
    int i = int(q.x / ADV);
    float d = glyph(strChar(s, i), vec2(q.x - float(i) * ADV, q.y)) * em;
    float cov = smoothstep(0.7 * PX, -0.7 * PX, d) * alpha;
    acc *= 1.0 - 0.5 * smoothstep(0.12 * em, 0.0, d) * alpha;
    return mix(acc, col, cov) + col * exp(-max(d, 0.0) / (0.06 * em)) * 0.25 * alpha * (1.0 - cov);
}

vec3 slider(vec2 uv, float y, float f, bool hot, bool ticks, vec3 col) {
    float dTrack = length(vec2(uv.x - clamp(uv.x, SX0, SX1), uv.y - y));
    float kx = mix(SX0, SX1, f);
    float line = smoothstep(2.0 * PX, 0.5 * PX, dTrack - 0.002);
    col = mix(col, vec3(0.30, 0.28, 0.36), line);
    if (ticks) for (int i = 0; i < 3; i++) {
        float tx = mix(SX0, SX1, 0.5 * float(i));
        col = mix(col, IVORY * 0.7, smoothstep(1.5 * PX, 0.3 * PX, length(vec2(uv.x - tx, max(abs(uv.y - y) - 0.012, 0.0))) - 0.0015));
    } else col = mix(col, GOLD * 0.8, line * step(uv.x, kx));
    float dk = length(uv - vec2(kx, y)) - (hot ? 0.016 : 0.013);
    col = mix(col, IVORY, smoothstep(PX, -PX, dk));
    return col + GOLD * 0.35 * exp(-max(dk, 0.0) * 60.0);
}

vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

void mainImage(out vec4 O, in vec2 fc) {
    PX = 1.0 / iResolution.y;
    vec2 uv = (fc - 0.5 * iResolution.xy) * PX;
    float s = st(1), R0 = st(3), turn = st(5), act = st(6);

    vec3 col = aces(disk(uv, s, R0, turn) * 1.05);
    col = slider(uv, SY_S, 0.5 + 0.5 * s, act == 1.0, true, col);
    col = slider(uv, SY_R, (R0 - R_MIN) / (R_MAX - R_MIN), act == 2.0, false, col);

    if (uv.x < -0.08) {
        col = textLine(uv, vec2(-0.82, 0.40), 0.042, 0, 0.0, GOLD, 1.0, col);
        col = textLine(uv, vec2(-0.82, 0.32), 0.030, 1, 0.0, IVORY, 1.0, col);
        col = textLine(uv, vec2(-0.82, 0.265), 0.024, 2, 0.0, IVORY * 0.55, 1.0, col);
        // what the current mix shows
        float wf = 1.0 - min(abs(s), 1.0), wm = max(s, 0.0), wp = max(-s, 0.0);
        col = textLine(uv, vec2(-0.82, 0.17), 0.026, 3, 0.0, GOLD, wf + wm, col);
        col = textLine(uv, vec2(-0.82, 0.125), 0.026, 4, 0.0, PEA * 1.3, wf + wp, col);
        col = textLine(uv, vec2(-0.82, 0.06), 0.022, 10, 0.0, IVORY * 0.7, 1.0 - wf, col);
        col = textLine(uv, vec2(-0.82, 0.025), 0.022, 11, 0.0, IVORY * 0.7, 1.0 - wf, col);
        for (int i = 0; i < 3; i++) {
            float sel = 1.0 - min(abs(s - float(i - 1)), 1.0);
            col = textLine(uv, vec2(mix(SX0, SX1, 0.5 * float(i)), SY_S + 0.03), 0.028, 5 + i, 0.5,
                           mix(IVORY * 0.5, GOLD * 1.2, sel), 1.0, col);
        }
        col = textLine(uv, vec2(-0.82, SY_R + 0.03), 0.026, 8, 0.0, IVORY * 0.8, 1.0, col);
        col = textLine(uv, vec2(-0.82, -0.37), 0.022, 9, 0.0, IVORY * 0.5, 1.0, col);
        col = textLine(uv, vec2(-0.82, -0.42), 0.020, 12, 0.0, IVORY * 0.4, 1.0, col);
    }
    vec2 v = fc / iResolution.xy - 0.5;
    col *= 1.0 - 0.5 * dot(v * vec2(1.1, 1.3), v * vec2(1.1, 1.3));
    O = vec4(pow(col, vec3(1.0 / 2.2)), 1.0);
}
