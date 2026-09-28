// RAMANUJAN: THE CROWN AND THE EDGE (lite)
// ----------------------------------------------------------------------------
// 0-24 s   the circle method: (1-|q|) log|P(q)| over the unit disk, where
//          P(q) = sum p(n) q^n = prod 1/(1-q^n) = q^(1/24)/eta(tau).
//          Every root of unity e^(2 pi i h/k) is a singularity; its lobe (a Ford
//          circle) rises to 1/k. The camera dives onto the golden point.
// 24-46 s  the edge: an endless zoom into q = e^(2 pi i/phi). M = (2 1; 1 1)
//          fixes tau = phi and is an exact dilation in sigma = (tau-phi)/(tau+1/phi);
//          everything drawn is SL2(Z)-invariant, so the zoom loops seamlessly
//          and never runs out of precision.
// Drag horizontally to scrub.
//
// Buffer A: scene (HDR); alpha of texel (0,0) holds the clock. iChannel0 = Buffer A (self). Kept small for fast compiles: the modular reduction is
// inlined at three call sites only (raymarch+bisection share one loop, normals
// and the edge's three samples are loops too).

const float PI = 3.14159265, TAU = 6.28318531, PHI = 1.61803399;
const float LOOP = 46.0, EDGE_T = 24.0, FADE = 2.4;
const vec3 GOLD = vec3(1.0, 0.66, 0.24), SAFFRON = vec3(1.0, 0.42, 0.1);
float PX;

float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }

// ---- modular reduction: tau -> tau0 in the fundamental domain, g.tau = tau0.
// The cusp owning tau is -d/c (k = |c|); tau is in its Ford circle iff Im tau0 >= 1.
vec2 G_T0; vec4 G_G;
void reduceTau(vec2 tau) {
    vec4 g = vec4(1, 0, 0, 1);
    for (int i = 0; i < 48; i++) {
        float n = floor(tau.x + 0.5);
        tau.x -= n; g.xy -= n * g.zw;
        float r2 = dot(tau, tau);
        if (r2 >= 1.0) break;
        tau = vec2(-tau.x, tau.y) / r2;
        g = vec4(-g.zw, g.xy);
    }
    G_T0 = tau; G_G = g;
}

// cusp colours cycle once per factor phi^2 in k, matching one zoom step
vec3 cuspColor(float k) {
    float s = fract(log(max(k, 1.0)) / 0.962424) * 5.0;
    vec3 c = mix(GOLD * 1.1, SAFFRON, smoothstep(0.0, 1.0, s));
    c = mix(c, vec3(0.88, 0.08, 0.13), smoothstep(1.0, 2.0, s));
    c = mix(c, vec3(0.42, 0.1, 0.62), smoothstep(2.0, 3.0, s));
    c = mix(c, vec3(0.05, 0.65, 0.72), smoothstep(3.0, 4.0, s));
    return mix(c, GOLD * 1.1, smoothstep(4.0, 5.0, s));
}

// ---- shared timing: exponential dive, continued by the zoom
const float DIVE = 0.45, KLOG = 1.9248473;          // 4 log phi = log-zoom of one M step
float diveH(float u) { return 0.62 * exp(-DIVE * (u - 18.5)); }
float edgeZoom(float u) {
    float a = clamp((u - 3.0) / 6.0, 0.0, 1.0);
    return DIVE * u + 0.9 * (6.0 * (a * a * a - 0.5 * a * a * a * a) + max(u - 9.0, 0.0));
}

// ============================================================================
//  the crown
// ============================================================================
float gH;      // relief scale (flattens during the dive)
float gY;      // Im tau of the last evaluation

// L = (6/pi^2)(1-|q|) log|P(q)| at world xz (q = x - iz); fills G_T0, G_G
float crownL(vec2 w, float yMin) {
    float r = max(length(w), 1e-6);
    gY = max(-log(r) / TAU, yMin);
    reduceTau(vec2(atan(-w.y, w.x) / TAU, gY));
    vec2 q = exp(-TAU * G_T0.y) * vec2(cos(TAU * G_T0.x), sin(TAU * G_T0.x));
    vec2 pr = vec2(1, 0) - q, q2 = cmul(q, q);
    pr = cmul(pr, vec2(1, 0) - q2);                  // |q0| < 0.0044: two factors suffice
    float logEta = -PI * G_T0.y / 12.0 + 0.5 * log(dot(pr, pr)) + 0.25 * log(G_T0.y / gY);
    return 0.6079271 * (1.0 - exp(-TAU * gY)) * (-PI * gY / 12.0 - logEta);
}
float heightOf(float L, float r) {
    float h = L / sqrt(abs(L) + 0.004) * smoothstep(0.0, 0.004, 1.0 - r);
    return gH * (h > 0.0 ? h : 0.35 * h);
}

vec3 sky(vec3 rd) {
    vec3 c = mix(vec3(0.012, 0.012, 0.03), vec3(0.03, 0.025, 0.07), smoothstep(-0.2, 0.6, rd.y));
    return c + GOLD * 0.25 * pow(max(dot(rd, normalize(vec3(-0.4, 0.35, 0.8))), 0.0), 12.0);
}

vec3 crown(vec2 uv, float u) {
    // camera: overhead mandala -> orbit -> look out to the golden point -> dive
    float gA = TAU / PHI;
    vec3 gp = vec3(cos(gA), 0.0, -sin(gA));
    float a = ease((u - 2.5) / 6.5);
    float ang = 0.9 + 0.07 * u + 0.8 * a, el = mix(1.5, 0.4, a), dist = mix(2.45, 2.05, a);
    vec3 ro = dist * vec3(cos(el) * cos(ang), sin(el), cos(el) * sin(ang));
    vec3 ta = vec3(0.0, -0.08 * a, 0.0);
    float b = ease((u - 10.0) / 5.5), f = ease((u - 13.0) / 5.0);
    ro = mix(ro, gp * mix(-0.05, 0.42, f) + vec3(gp.z, 0.0, -gp.x) * 0.1 + vec3(0.0, mix(0.62, 0.32, f), 0.0), b);
    ta = mix(ta, gp * 1.1 + vec3(0.0, 0.02, 0.0), ease((u - 9.0) / 4.5));
    float c = ease((u - 17.0) / 4.0);
    ro = mix(ro, gp + vec3(0.0, diveH(max(u, 18.5)), 0.0), c);
    ta = mix(ta, gp, c);
    vec3 up = normalize(mix(vec3(0, 1, 0), -gp, smoothstep(0.3, 0.8, c)));
    gH = 0.34 * (1.0 - smoothstep(18.0, 22.5, u));

    vec3 fw = normalize(ta - ro);
    if (abs(dot(fw, up)) > 0.999) up = vec3(0, 0, 1);
    vec3 rt = normalize(cross(fw, up)), uw = cross(rt, fw);
    vec3 rd = normalize(uv.x * rt + uv.y * uw + 1.6 * fw);
    float pixAng = PX / 1.6;
    vec3 col = sky(rd);

    // dark floor beyond the rim
    float tf = (-0.02 - ro.y) / rd.y;
    if (tf > 0.0) {
        float rr = length((ro + rd * tf).xz);
        if (rr > 1.0) col = mix(vec3(0.004, 0.004, 0.01) + GOLD * 0.05 * exp(-(rr - 1.0) * 25.0), col, smoothstep(2.0, 6.0, tf));
    }

    // bounds: cylinder r <= 1 and slab of the relief
    float tmin = -1e9, tmax = 1e9;
    float A = dot(rd.xz, rd.xz), B = dot(ro.xz, rd.xz), C = dot(ro.xz, ro.xz) - 1.0;
    float disc = B * B - A * C;
    if (A > 1e-8) {
        if (disc < 0.0) tmax = -1.0;
        else { tmin = (-B - sqrt(disc)) / A; tmax = (-B + sqrt(disc)) / A; }
    }
    float s0 = (-0.12 * gH - 1e-3 - ro.y) / rd.y, s1 = (1.05 * gH + 1e-3 - ro.y) / rd.y;
    tmin = max(max(tmin, min(s0, s1)), 0.0);
    tmax = min(tmax, max(s0, s1));

    // one loop does both the march and the bisection (one crownL call site)
    bool hit = false, wall = false, refine = false;
    float t = tmin, tPrev = tmin, lo = 0.0, hi = 0.0, L = 0.0, yMin = 0.0;
    int nr = 0;
    vec3 p = ro;
    if (tmin < tmax) for (int i = 0; i < 200; i++) {
        float tt = refine ? 0.5 * (lo + hi) : t;
        p = ro + rd * tt;
        if (!refine) yMin = 1.2 * tt * pixAng / TAU;
        float r = length(p.xz);
        L = crownL(p.xz, yMin);
        float d = p.y - heightOf(L, r);
        if (refine) {
            if (d < 0.0) hi = tt; else lo = tt;
            if (++nr == 6) { t = hi; hit = true; break; }
        } else if (d < 0.0) {
            if (i == 0 && r > 0.999) { wall = true; break; }
            refine = true; lo = tPrev; hi = t;
        } else {
            tPrev = t;
            t += max(d * 0.45 * mix(0.25, 1.0, smoothstep(0.02, 0.25, 1.0 - r)), 0.6 * tt * pixAng);
            if (t > tmax) break;
        }
    }

    if (wall) {
        col = vec3(0.02, 0.015, 0.03) + GOLD * (0.08 + 0.5 * pow(clamp(p.y / max(gH, 1e-3), 0.0, 1.0), 6.0));
    } else if (hit) {
        float fp = t * pixAng, r = length(p.xz), y = gY;
        vec2 t0 = G_T0; float k = abs(G_G.z);
        float h0 = heightOf(L, r);
        // forward-difference normal (one more call site)
        float e = max(1.5 * fp, 1e-4);
        vec2 hd;
        for (int j = 0; j < 2; j++) {
            vec2 o = j == 0 ? vec2(e, 0.0) : vec2(0.0, e);
            hd[j] = heightOf(crownL(p.xz + o, yMin), length(p.xz + o)) - h0;
        }
        vec3 nor = normalize(vec3(-hd.x, e, -hd.y));
        vec3 kc = cuspColor(k);
        float lobe = smoothstep(-0.002, 0.02, L);
        vec3 alb = mix(vec3(0.016, 0.018, 0.05) + kc * 0.07, kc * 0.55, lobe);
        vec3 ld = normalize(vec3(-0.4, 0.75, 0.55));
        vec3 cc = alb * (0.08 + 0.95 * max(dot(nor, ld), 0.0));
        cc += mix(vec3(0.25, 0.3, 0.5), kc, lobe) * pow(max(dot(nor, normalize(ld - rd)), 0.0), mix(24.0, 80.0, lobe)) * mix(0.25, 1.0, lobe);
        cc += sky(reflect(rd, nor)) * pow(1.0 - max(dot(nor, -rd), 0.0), 4.0) * 1.5;
        cc += kc * 1.8 * pow(clamp(L * k * k, 0.0, 1.0), 5.0) * lobe;          // glowing tips
        float cell = TAU * r * y;                                               // one hyperbolic unit
        cc += mix(GOLD, kc, 0.3) * 0.6 * smoothstep(1.6 * fp, 0.4 * fp, abs(length(t0) - 1.0) / t0.y * cell)
            * smoothstep(3.0 * fp, 12.0 * fp, cell * 0.3);                     // Ford-domain edges
        float lj = log2(max(t0.y, 1e-6));
        cc += kc * 0.35 * smoothstep(1.4 * fp, 0.3 * fp, abs(lj - floor(lj + 0.5)) * 0.693 * cell)
            * smoothstep(4.0 * fp, 16.0 * fp, cell * 0.69) * step(1.0, t0.y) * lobe;   // horocycles
        cc += kc * 0.05 * (1.0 - lobe);
        col = mix(cc, col, smoothstep(3.0, 7.0, t));
    }
    // the unit circle
    float tc = -ro.y / rd.y;
    if (tc > 0.0 && (!hit || tc < t + 0.02))
        col += GOLD * 0.9 * smoothstep(2.0 * tc * pixAng, 0.3 * tc * pixAng, abs(length((ro + rd * tc).xz) - 1.0));
    return col;
}

// ============================================================================
//  the edge
// ============================================================================
vec3 edge(vec2 uv, float u) {
    float z = edgeZoom(u);
    float Sf = diveH(24.0) / (TAU * 1.6) * exp(-fract(z / KLOG) * KLOG);
    float lobeY = mix(8.7, 1.0, ease((u - 2.0) / 4.5));
    float relief = ease((u - 3.0) / 4.0);

    // three samples (pixel, +x, +y) in one loop; sample 0 is kept for shading
    vec2 t0 = vec2(0.0); float k = 1.0, cell = 1.0, Z0 = 0.0; vec2 gr = vec2(0.0);
    bool mirror = false;
    for (int s = 0; s < 3; s++) {
        vec2 o = s == 0 ? vec2(0.0) : s == 1 ? vec2(PX, 0.0) : vec2(0.0, PX);
        vec2 sig = (uv + o) * Sf / sqrt(5.0);
        vec2 om = vec2(1, 0) - sig;
        vec2 d = cdiv(sig * sqrt(5.0), om);            // tau - phi
        bool mi = d.y < 0.0;
        vec2 tau = vec2(PHI - 2.0 + d.x, max(abs(d.y), 1e-9));
        reduceTau(tau);
        float cp = tau.y * dot(om, om) / (PX * Sf);     // pixels per hyperbolic unit
        float Z = cp * sqrt(max(G_T0.y / lobeY - 1.0, 0.0));
        if (s == 0) { t0 = G_T0; k = abs(G_G.z); cell = cp; Z0 = Z; mirror = mi; }
        else if (abs(G_G.z) == k) gr[s - 1] = Z - Z0;
        if (s == 0 && (relief <= 0.0 || G_T0.y < lobeY)) break;
    }
    float y0 = t0.y;
    vec3 kc = cuspColor(k);
    float lobe = smoothstep(-0.8, 0.8, log(y0 / lobeY) * cell);
    vec3 nor = normalize(vec3(-gr * (mirror ? vec2(1, -1) : vec2(1)) * relief * 0.9, 1.0));

    vec3 alb = mix(vec3(0.016, 0.018, 0.05) + kc * 0.07, kc * 0.55, lobe);
    vec3 ld = normalize(vec3(-0.45, 0.55, 0.7));
    vec3 c = alb * (0.08 + 0.95 * max(dot(nor, ld), 0.0)) * mix(1.0, 1.25, relief * lobe);
    c += mix(vec3(0.25, 0.3, 0.5), kc, lobe) * pow(max(dot(nor, normalize(ld + vec3(0, 0, 1))), 0.0), mix(24.0, 80.0, lobe))
       * mix(0.25, 1.0, lobe) * mix(0.35, 1.0, relief);
    c += kc * 0.5 * pow(1.0 - nor.z, 2.0) * lobe * relief;                    // rim light on domes
    c += kc * 1.8 * pow(clamp(1.0 - lobeY / y0, 0.0, 1.0), 5.0) * lobe;       // glow at the cusps
    c += mix(GOLD, kc, 0.3) * 0.6 * smoothstep(1.6, 0.4, abs(length(t0) - 1.0) / y0 * cell) * smoothstep(3.0, 12.0, cell * 0.3);
    float lj = log2(y0);
    c += kc * 0.35 * smoothstep(1.4, 0.3, abs(lj - floor(lj + 0.5)) * 0.693 * cell) * smoothstep(4.0, 16.0, cell * 0.69) * step(1.0, y0) * lobe;
    c += kc * 0.05 * (1.0 - lobe);
    c = mix(mix(GOLD, SAFFRON, 0.4) * 0.35, c, smoothstep(0.6, 3.0, cell));  // sub-pixel haze
    if (mirror) c *= 0.16 * smoothstep(1.0, 4.0, u) * exp(-abs(uv.y) * 3.0);
    float dl = abs(uv.y) / PX;
    return c + GOLD * (1.1 * smoothstep(1.6, 0.3, dl) + 0.25 * exp(-dl * 0.08));
}

void mainImage(out vec4 O, in vec2 fc) {
    PX = 1.0 / iResolution.y;
    vec2 uv = (fc - 0.5 * iResolution.xy) * PX;
    // the clock lives in the alpha of texel (0,0), so scrubbing sticks
    float T = iFrame == 0 ? 0.0 : texelFetch(iChannel0, ivec2(0), 0).a + clamp(iTimeDelta, 0.0, 0.1);
    if (iMouse.z > 0.0) T = clamp(iMouse.x / iResolution.x, 0.0, 0.9999) * LOOP;
    T = mod(T, LOOP);
    float wc = smoothstep(0.0, 1.5, T) * (1.0 - smoothstep(EDGE_T, EDGE_T + FADE, T));
    float we = smoothstep(EDGE_T, EDGE_T + FADE, T) * (1.0 - smoothstep(LOOP - 2.0, LOOP - 0.1, T));
    vec3 col = vec3(0.0);
    if (wc > 0.0) col += wc * crown(uv, T);
    if (we > 0.0) col += we * edge(uv, T - EDGE_T);
    O = vec4(max(col, 0.0), T);
}
