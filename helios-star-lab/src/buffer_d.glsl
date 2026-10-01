// Buffer D: the star, its atmosphere and its field lines, linear HDR.
// iChannel0 = Buffer A (state, model, regions)   iChannel1 = Buffer B (lines)   iChannel2 = Buffer C (tiles)
//
// Visible light: every surface point has a local temperature (gravity darkening, granulation,
// spots, faculae) and emits a blackbody at the temperature found at optical depth tau = mu
// (grey Eddington atmosphere, T^4 = 3/4 Teff^4 (tau + 2/3)). Limb darkening and limb
// reddening follow from that alone, so they differ correctly between a red supergiant and a
// white dwarf. Disc centre is normalised to 1 for every star; colour is not.
// EUV: optically thin emission (chromospheric network, plage, flares, corona, winds),
// displayed log-scaled in a He II 30.4 nm style false-colour palette.

// No arrays: indexable local arrays are what make D3D compiles slow. Regions and field sources
// are read straight from Buffer A where they are needed.
Star S; vec4 CTRL, CLOCK; vec3 AX;
float FIL;                                          // filament opacity along this pixel

// ---- Chromospheric material held by the field -------------------------------------------------
// The surface field gives two things the EUV disc needs. Its horizontal direction: chromospheric
// fibrils are dense material stretched along it (line-integral convolution of noise). And its
// polarity inversion lines: filaments are long dark ribbons of cool plasma suspended low above
// them, away from plage; past the limb the same material shows as prominences.
vec3 surfaceField(vec3 n) {
    vec3 p = n * 1.008, B = dipoleField(p, S.dipole);
    for (int i = 0; i < 2 * NREG + ZERO; i++) { vec4 q = fetch(iChannel0, i, 2); if (q.w != 0.0) B += sourceField(p, q); }
    return B;
}
float filament(vec3 n, out vec3 t, out float horiz) {
    vec3 B = surfaceField(n);
    horiz = 1.0 - abs(dot(normalize(B + 1e-9), n));
    float br = dot(B, n), bm = length(B) + 1e-6;
    vec3 bt = B - br * n; t = bt / max(length(bt), 1e-6);
    float act = 0.0;
    for (int k = 0; k < NREG + ZERO; k++) { float e = fetch(iChannel0, k, 5).x; if (e > 0.0) act += e * exp(-(1.0 - dot(n, fetch(iChannel0, k, 3).xyz)) / 0.012); }
    float wob = 0.6 + 0.8 * vnoise(n * 30.0);
    float q = sq(br / bm);
    float pil = exp(-q / (0.006 * wob)) + 0.25 * exp(-q / 0.05);    // ribbon plus its channel
    float seg = smoothstep(0.42, 0.62, vnoise(n * 4.5 + 11.3));        // only some stretches erupt into view
    return pil * seg * (1.0 - sat(3.0 * act));
}
float streaks(vec3 n, vec3 t, float scale, float fp) {
    float a = 0.0;
    for (int k = -4; k <= 4 + ZERO; k++) a += vnoise((n + t * (float(k) * 1.1 / scale)) * scale);
    return mix(a / 9.0, 0.5, smoothstep(0.3, 1.0, fp * scale));
}

vec3 voronoi(vec3 p, float t) {
    vec3 c = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0, id = 0.0;
    for (int k = 0; k < 27 + ZERO; k++) {
        vec3 o = vec3(float(k % 3) - 1.0, float((k / 3) % 3) - 1.0, float(k / 9) - 1.0);
        vec3 h = hash33(c + o);
        vec3 d = o + 0.5 + 0.36 * sin(TAU * (h + t * (0.6 + 0.8 * h.zxy))) - f;
        float q = dot(d, d);
        if (q < d1) { d2 = d1; d1 = q; id = h.x; } else d2 = min(d2, q);
    }
    return vec3(sqrt(d1), sqrt(d2), id);
}
// Zero-mean convective pattern: bright granule bodies, dark intergranular lanes.
float convection(vec3 p, float t, float px, float lw) {
    float vis = 1.0 - smoothstep(0.25, 0.7, px);
    if (vis <= 0.0) return 0.0;
    vec3 v = voronoi(p, t);
    float body = 1.0 - smoothstep(0.0, 0.85, v.x);
    float lane = 1.0 - smoothstep(0.0, lw + 0.5 * px, v.y - v.x);
    return vis * (1.1 * (body - 0.4) - 1.1 * lane * (0.12 / (lw + 0.05)) * lw * 4.0 + 0.6 * (v.z - 0.5));
}

vec3 palette304(float x) {
    x = max(x, 0.0);
    vec3 c = mix(vec3(0), vec3(0.42, 0.03, 0.0), smoothstep(0.0, 0.25, x));
    c = mix(c, vec3(0.95, 0.30, 0.02), smoothstep(0.18, 0.55, x));
    c = mix(c, vec3(1.0, 0.70, 0.22), smoothstep(0.5, 0.85, x));
    return mix(c, vec3(1.0, 0.97, 0.82), smoothstep(0.8, 1.15, x)) * (1.0 + 0.6 * smoothstep(1.0, 1.6, x));
}

// ---- The surface ---------------------------------------------------------------------------
// Returns visible RGB (relative to disc centre) or EUV emission in .x when euv.
vec3 surface(vec3 s, float mu, float fp, bool euv) {
    vec3 p = s * AX;
    float T = S.T * S.gdNorm * pow(effGravity(p, S.omega), S.beta);
    // Granulation, and the few giant cells of supergiants.
    float F = 1.0 / S.gran;
    float gr = S.conv > 0.0 ? convection(s * F, CLOCK.z, fp * F, 0.07) : 0.0;
    float gc = 0.0;
    if (S.giant > 0.0) {
        vec3 wp = s * 2.4 + 0.8 * vec3(vnoise(s * 2.0 + 7.1), vnoise(s * 2.0 + 1.3), vnoise(s * 2.0 + 4.7)) - 0.4;
        // Supergiant surfaces (3D RHD, e.g. Chiavassa+ 2011) are soft bright plumes over dark
        // downflows, not a cell network: warped, sharpened fBm.
        float b1 = fbm(s * 2.6 + 1.6 * wp + CLOCK.z * 0.004, fp * 2.6, 4), b2 = fbm(s * 8.0 + 2.0 * wp, fp * 8.0, 3);
        gc = 2.6 * (smoothstep(0.30, 0.72, b1) - 0.5) + 0.8 * (b2 - 0.5);
    }
    float fine = fbm(s * 90.0, fp * 90.0, 3);
    T *= 1.0 + S.cgran * gr * (1.0 - 0.7 * S.giant) + 0.07 * S.giant * gc;
    float umbra = 0.0, pen = 0.0, plage = 0.0, flare = 0.0;
    for (int k = 0; k < NREG + ZERO; k++) {
        Region g = loadRegion(iChannel0, k);
        if (g.e <= 0.0) continue;
        float reach = g.a + 4.0 * g.w + 0.04;
        if (dot(s, g.n) < 1.0 - 0.5 * reach * reach) continue;
        vec3 d = s - g.n;
        float x = dot(d, g.u), y = dot(d, cross(g.n, g.u));
        float sd = 1.0 - smoothstep(0.25, 0.75, g.age);
        float rl = g.w * sqrt(sd * sat(g.e * 1.5)) + 1e-4, rf = 0.75 * rl;
        float dl = length(vec2(x - g.a, y)) / rl + 0.25 * (fine - 0.5);
        float df = length(vec2(x + g.a, 1.25 * y)) / rf + 0.9 * (fine - 0.5) + 0.3 * (vnoise(s * 60.0) - 0.5);
        float um = max(1.0 - smoothstep(0.36, 0.46, dl), 1.0 - smoothstep(0.3, 0.42, df));
        float pn = max(1.0 - smoothstep(0.9, 1.05, dl), 1.0 - smoothstep(0.85, 1.0, df));
        // Radial penumbral filaments once they are resolved.
        float fil = 0.5 + 0.5 * sin(atan(y, x - g.a) * 70.0 + 6.0 * fine);
        fil = mix(0.5, fil, 1.0 - smoothstep(0.3, 1.0, fp * 70.0 / max(rl, 1e-3)));
        umbra = max(umbra, um); pen = max(pen, pn * (0.75 + 0.5 * fil));
        float ex = 1.2 * g.a + 2.6 * g.w, ey = 1.8 * g.w + 0.6 * g.a;
        plage += sqrt(g.e) * exp(-1.6 * (x * x / (ex * ex) + y * y / (ey * ey)));
        float rib = exp(-sq((abs(x) - 0.22 * g.a) / (0.07 * g.a + 0.003))) * exp(-sq(y / (1.3 * g.w + 0.004)));
        flare += g.flare * rib;
    }
    // Polar spots on fast rotators (Doppler imaging: AB Dor, LQ Hya...).
    float cap = S.highLat * smoothstep(0.80, 0.87, abs(s.y) + 0.06 * (fbm(s * 9.0, fp * 9.0, 3) - 0.5));
    umbra = max(umbra, cap * 0.8);
    float filigree = 0.55 + 0.9 * fine;
    if (!euv) {
        T -= S.spotDT * umbra + 0.35 * S.spotDT * max(pen - umbra, 0.0);
        T *= 1.0 + 0.05 * sat(plage) * filigree * (1.0 - mu) * (1.0 - umbra);   // faculae: bright at the limb
        float Te = T * pow(0.75 * (mu + 2.0 / 3.0), 0.25);
        vec4 pl = planck(iChannel0, Te), ref = planck(iChannel0, S.T * 1.0574), fl = planck(iChannel0, 9500.0);
        vec3 c = exp(pl.w - ref.w) * pl.rgb;
        return c + min(flare, 1.5) * 0.35 * exp(fl.w - ref.w) * fl.rgb;
    }
    // EUV disc: chromospheric network on the supergranulation scale, plage, flare ribbons,
    // coronal holes over the dipole poles, and the photosphere's own Wien tail.
    // Chromospheric mottling: domain-warped, so it swirls, with large dark filament channels.
    float drift = CLOCK.z * 0.004;
    vec3 wv = vec3(fbm(s * 6.0 + drift, fp * 6.0, 3), fbm(s * 6.0 + 5.2 - drift, fp * 6.0, 3), fbm(s * 6.0 + 9.1, fp * 6.0, 3)) - 0.5;
    float mott = fbm(s * 40.0 + 2.6 * wv, fp * 40.0, 4);
    float grain = fbm(s * 75.0 + 3.0 * wv, fp * 75.0, 3);
    float chan = smoothstep(0.50, 0.30, fbm(s * 4.0 + 3.0 * wv, fp * 4.0, 3));
    vec3 m = normalize(S.dipole + vec3(0, 1e-6, 0));
    float hole = smoothstep(0.62, 0.85, abs(dot(s, m))) * (0.35 + 0.65 * abs(cos(PI * S.cycle)));
    float E = S.conv * (0.06 + 0.75 * S.alpha) * (0.12 + 1.5 * sq(smoothstep(0.3, 0.8, mott)) + 0.9 * sq(sq(grain)) * 2.0)
            * (1.0 - 0.35 * chan * (1.0 - sat(plage))) * (1.0 - 0.7 * hole);
    if (S.alpha > 0.0) {
        vec3 t; float horiz; float fil = filament(s, t, horiz);
        float fib = streaks(s, t, 70.0, fp), thr = streaks(s, t, 260.0, fp);
        // Dark fibrils everywhere the field lies flat, densest around plage; filaments on top.
        E *= 1.0 - 0.6 * smoothstep(0.5, 0.36, fib) * horiz * (0.25 + sat(2.0 * plage));
        float lumps = smoothstep(0.25, 0.7, vnoise(s * 55.0 + 3.0 * t));
        FIL = 0.8 * smoothstep(0.05, 1.0, fil) * mix(0.35, 1.0, lumps) * (0.6 + 0.6 * thr);
    }
    E += S.chromo * 0.5 * (0.6 + 0.8 * fbm(s * 4.0 + CLOCK.z * 0.01, fp * 4.0, 3));
    // Plage glows in fans of fine threads that follow the field out of each polarity.
    float fan = 1.0;
    E += (2.4 * plage + 1.2 * sq(plage)) * filigree * fan * (1.0 - 0.6 * umbra) + 5.0 * flare;
    E *= 1.0 + 0.8 * sq(1.0 - mu);
    E += 2.0 * exp(-473289.0 * (1.0 / T - 1.0 / 25000.0)) + 0.035;
    return vec3(E, 0, 0);
}

// ---- Optically thin atmosphere --------------------------------------------------------------
// EUV: hydrostatic corona (scale height ~ T_c R / M) shaped by the helmet-streamer belt over the
// dipole's magnetic equator, coronal holes and radial rays; radiatively
// driven clumpy winds (beta-law, density ~ 1/(r^2 v)); extended supergiant chromospheres.
// Visible: the molecular layer of red supergiants (absorbs the disc edge, emits dim red).
vec2 atmosphere(vec3 ro, vec3 rd, float tEnd, bool euv) {
    float H = S.coronaH;
    float rout = 1.0 + max(max(euv ? max(6.0 * H * S.alpha, 0.03 * S.conv) : 0.0, (euv ? 2.6 : 0.0) * S.wind), max(euv ? 1.5 * S.chromo : 0.0, 0.7 * S.molsphere));
    if (rout <= 1.001) return vec2(0);
    float b = dot(ro, rd), c = dot(ro, ro) - rout * rout, h = b * b - c;
    if (h <= 0.0) return vec2(0);
    float t0 = max(-b - sqrt(h), 0.0), t1 = -b + sqrt(h);
    if (tEnd > 0.0) t1 = min(t1, tEnd);
    const int N = 40;
    float dt = (t1 - t0) / float(N), t = t0 + dt * hash13(vec3(gl_FragCoord.xy, CLOCK.w));
    vec3 m = normalize(S.dipole + vec3(0, 1e-6, 0));
    float E = 0.0, tau = 0.0;
    for (int i = 0; i < N + ZERO; i++) {
        vec3 x = ro + rd * t; float r = length(x), hh = max(r - 1.0, 0.0); vec3 n = x / r;
        if (euv) {
            if (S.alpha > 0.0) {
                float dens = exp(-(1.0 / H) * (1.0 - 1.0 / r));
                float md = dot(n, m), belt = exp(-md * md / (0.10 / (1.0 + 1.5 * hh)));
                float rays = vnoise(n * 38.0) * 0.7 + vnoise(n * 11.0) * 0.6;
                float hole = smoothstep(0.65, 0.9, abs(md)) * (0.35 + 0.65 * abs(cos(PI * S.cycle)));
                E += dens * dens * (0.3 + 1.6 * belt) * (0.4 + rays) * (1.0 - 0.7 * hole) * (0.35 + 0.5 * S.alpha) * 1.3;
            }
            if (S.wind > 0.0) {
                float v = 0.02 + pow(max(1.0 - 0.98 / r, 0.0), 1.0), rho = min(1.0 / (r * r * v), 25.0);
                float cl = vnoise(vec3(n * 16.0) + vec3(0.0, 0.0, 5.0 * (r - CLOCK.w * 0.12)));
                E += S.wind * 0.05 * pow(rho, 1.5) * (0.2 + 3.0 * cl * cl * cl);
            }
            if (S.conv > 0.0 && hh < 0.03) {
                float sp = vnoise(vec3(n * 260.0)) * vnoise(vec3(n * 90.0) + 3.1);
                E += S.conv * (0.4 + S.alpha) * 14.0 * exp(-hh / (0.004 + 0.012 * sp)) * (0.3 + sp);
            }
            if (S.chromo > 0.0) E += S.chromo * 0.55 * exp(-hh / 0.45) * (0.5 + vnoise(x * 3.0 + CLOCK.z * 0.01));
        } else {
            float rho = S.molsphere * exp(-hh / 0.16) * (0.5 + vnoise(x * 4.0 + CLOCK.z * 0.01));
            tau += 2.6 * rho * dt;
            E += 0.10 * rho * dt * exp(-tau);
        }
        t += dt;
    }
    return vec2(E * (euv ? dt : 1.0), tau);
}

// ---- Field lines ---------------------------------------------------------------------------------
vec2 erfa(vec2 x) { vec2 sg = sign(x); x = abs(x); vec2 t = 1.0 / (1.0 + 0.3275911 * x);
    return sg * (1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)); }
vec4 node(int line, int slot) {
    int j = line * STRIDE + slot, w = int(iResolution.x);
    return texelFetch(iChannel1, ivec2(j % w, j / w), 0);
}
vec3 fireColor(float heat) {
    heat = sat(heat);
    vec3 c = mix(vec3(1, 0.004, 0.0003), vec3(1, 0.100, 0.0015), smoothstep(0.08, 0.60, heat));
    c = mix(c, vec3(1, 0.72, 0.035), smoothstep(0.57, 0.95, heat));
    return mix(c, vec3(1, 0.98, 0.61), smoothstep(0.93, 1.0, heat));
}
// Field lines as thin glowing strands with bright packets running along them: white-gold over
// active regions, magenta for the large-scale field. Each segment's Gaussian tube is integrated
// along its projection, so joints add up exactly and sub-pixel strands keep their brightness.
vec3 fieldLines(vec3 ro, vec3 rd, float tEnd, float fp, vec2 px) {
    vec3 sum = vec3(0);
    vec2 res = iResolution.xy;
    int tx = (int(res.x) + TILE - 1) / TILE, tile = int(px.x) / TILE + (int(px.y) / TILE) * tx;
    float lim = tEnd > 0.0 ? tEnd : 1e5;
    for (int g = 0; g < 4 + ZERO; g++) {
        int j = tile * 4 + g, w = int(res.x);
        uvec4 mask = uvec4(texelFetch(iChannel2, ivec2(j % w, j / w), 0));
        for (int ch = 0; ch < 4 + ZERO; ch++) {
            uint bits = ch == 0 ? mask.x : ch == 1 ? mask.y : ch == 2 ? mask.z : mask.w;
            while (bits != 0u) {
                int bit = int(log2(float(bits & (~bits + 1u))) + 0.5); bits &= bits - 1u;
                int line = g * 64 + ch * 16 + bit;
                vec4 meta = node(line, STRIDE - 1);
                bool region = line < 12 * NREG;
                float seed = hash13(vec3(float(line), 9.37, 1.0));
                float gain = region ? 6.0 * min(meta.x, 1.5) + 1.5 : 2.2;
                for (int c = 0; c < 8 + ZERO; c++) {
                    vec4 bd = node(line, NODES + c);
                    if (bd.w < 0.0) break;
                    vec3 v = bd.xyz - ro; float tc = dot(v, rd);
                    float pad = bd.w + 0.01 + 3.0 * tc * fp;
                    if (dot(v, v) - tc * tc > pad * pad || tc + bd.w < 0.0 || tc - bd.w > lim) continue;
                    vec4 a = node(line, 8 * c);
                    int last = c == 7 ? 7 : 8;
                    for (int q = 1; q <= last + ZERO; q++) {
                        vec4 b = node(line, 8 * c + q);
                        vec3 ab = b.xyz - a.xyz;
                        float ta = dot(a.xyz - ro, rd), tb = dot(b.xyz - ro, rd);
                        vec3 pa = a.xyz - ro - rd * ta, vp = ab - rd * (tb - ta);
                        float vv = dot(vp, vp);
                        if (vv > 1e-12) {
                            float u = -dot(pa, vp) / vv, d2 = max(dot(pa, pa) - u * u * vv, 0.0);
                            float uc = clamp(u, 0.0, 1.0), t = mix(ta, tb, uc);
                            float r = length(a.xyz + ab * uc), hh = max(r - 1.0, 0.0), arc = mix(a.w, b.w, uc);
                            float wdt = (0.0012 + 0.0010 * seed) * (1.0 + 0.85 * hh) * (region ? 1.0 : 0.85);
                            float sg2 = wdt * wdt + sq(0.53 * t * fp);
                            if (t > 0.0 && t < lim && d2 < 18.0 * sg2) {
                                vec2 er = erfa(vec2(1.0 - u, -u) * sqrt(vv / (2.0 * sg2)));
                                float cov = exp(-0.5 * d2 / sg2) * 0.5 * (er.x - er.y) * wdt * inversesqrt(sg2);
                                float clk = CLOCK.w * (1.2 + 0.6 * seed), ph = arc * (18.0 + 15.0 * seed);
                                float pulse = pow(0.5 + 0.5 * sin(ph - clk + seed * 42.0), 8.0);
                                float back = pow(0.5 + 0.5 * sin(ph * 0.71 + clk * 0.81 + seed * 17.0), 12.0);
                                float env = exp(-hh * 2.0) * (1.0 - smoothstep(2.6, 3.4, r));
                                float heat = 0.60 + 0.17 * sin(arc * 12.0 - CLOCK.w * 1.7 + seed * 30.0) + 0.13 * exp(-hh * 15.0);
                                vec3 tint = region ? fireColor(heat) : mix(vec3(0.95, 0.30, 0.70), fireColor(heat), 0.25);
                                sum += tint * cov * env * gain * (0.35 + 1.4 * pulse + 0.5 * back);
                            }
                        }
                        a = b;
                    }
                }
            }
        }
    }
    return sum;
}

void mainImage(out vec4 O, in vec2 P) {
    vec2 res = iResolution.xy;
    S = loadStar(iChannel0); CTRL = fetch(iChannel0, S_CTRL, 0); CLOCK = fetch(iChannel0, S_CLOCK, 0); AX = starAxes(S);
    bool euv = CTRL.y > 0.5, overlay = CTRL.z > 0.5;
    Cam k = starCam(makeCam(fetch(iChannel0, S_CAM, 0), res), CLOCK.y);
    vec3 rdw = camRay(k, P);
    // Work in the space where the star is the unit sphere.
    vec3 ro = k.ro / AX, rdu = rdw / AX; float L = length(rdu); vec3 rd = rdu / L;
    float fp = 1.0 / k.focal;                       // world size of a pixel per unit distance
    float b = dot(ro, rd), c = dot(ro, ro) - 1.0, h = b * b - c;
    float tS = h > 0.0 ? -b - sqrt(h) : -1.0;
    float edge = sqrt(max(dot(ro, ro) - b * b, 0.0)) - 1.0, pxw = -b * fp;
    float cover = smoothstep(0.75 * pxw, -0.75 * pxw, edge);
    vec3 col = vec3(0); float E = 0.0; FIL = 0.0;
    if (cover > 0.0) {
        vec3 sp = h > 0.0 ? ro + rd * tS : normalize(ro - rd * b);
        vec3 nE = normalize(sp / AX);
        float mu = max(dot(nE, -rdw), 0.0);
        float fps = (h > 0.0 ? tS : -b) * fp / sqrt(max(mu, 0.04));
        vec3 sc = surface(normalize(sp), mu, fps, euv);
        if (euv) E += sc.x * cover; else col = sc * cover;
    }
    vec2 at = atmosphere(ro, rd, tS, euv);
    if (euv) {
        // Filaments sit in the low corona: they absorb the disc and the corona behind them.
        E = (E + at.x) * (1.0 - FIL * cover);
        col = palette304(log(1.0 + 2.2 * E) / log(1.0 + 2.2 * 2.5));
    } else {
        vec4 mol = planck(iChannel0, S.T * 0.6), ref = planck(iChannel0, S.T * 1.0574);
        col = col * exp(-at.y) + at.x * exp(mol.w - ref.w) * mol.rgb * 6.0;
    }
    if (overlay) col += fieldLines(ro, rd, tS, fp / L, P) * (euv ? 1.0 : 2.2);
    O = vec4(max(col, 0.0), 1.0);
}
