// Buffer A: interface state, the derived stellar model, active regions, Planck table.
// iChannel0 = Buffer A (itself, nearest)
//
// Row 0: state (see Common). Row 1: blackbody colour table. Row 2: field sources.
// Rows 3-5: active regions. Regions are a deterministic function of the star's clock, so
// every pass sees the same spots, the same field and the same flares.

// CIE 1931 2-degree colour matching functions, 380-780 nm in 10 nm steps.
const vec3 CIE[41] = vec3[41](
    vec3(0.001368,3.9e-05,0.006450001),
    vec3(0.004243,0.00012,0.02005001),
    vec3(0.01431,0.000396,0.06785001),
    vec3(0.04351,0.00121,0.2074),
    vec3(0.13438,0.004,0.6456),
    vec3(0.2839,0.0116,1.3856),
    vec3(0.34828,0.023,1.74706),
    vec3(0.3362,0.038,1.77211),
    vec3(0.2908,0.06,1.6692),
    vec3(0.19536,0.09098,1.28764),
    vec3(0.09564,0.13902,0.8129501),
    vec3(0.03201,0.20802,0.46518),
    vec3(0.0049,0.323,0.272),
    vec3(0.0093,0.503,0.1582),
    vec3(0.06327,0.71,0.07824999),
    vec3(0.1655,0.862,0.04216),
    vec3(0.2904,0.954,0.0203),
    vec3(0.4334499,0.9949501,0.008749999),
    vec3(0.5945,0.995,0.0039),
    vec3(0.7621,0.952,0.0021),
    vec3(0.9163,0.87,0.001650001),
    vec3(1.0263,0.757,0.0011),
    vec3(1.0622,0.631,0.0008),
    vec3(1.0026,0.503,0.00034),
    vec3(0.8544499,0.381,0.00019),
    vec3(0.6424,0.265,4.999999e-05),
    vec3(0.4479,0.175,2e-05),
    vec3(0.2835,0.107,0.0),
    vec3(0.1649,0.061,0.0),
    vec3(0.0874,0.032,0.0),
    vec3(0.04677,0.017,0.0),
    vec3(0.0227,0.00821,0.0),
    vec3(0.01135916,0.004102,0.0),
    vec3(0.005790346,0.002091,0.0),
    vec3(0.002899327,0.001047,0.0),
    vec3(0.001439971,0.00052,0.0),
    vec3(0.0006900786,0.0002492,0.0),
    vec3(0.0003323011,0.00012,0.0),
    vec3(0.0001661505,6e-05,0.0),
    vec3(8.307527e-05,3e-05,0.0),
    vec3(4.150994e-05,1.499e-05,0.0)
);
// Linear sRGB per unit photopic luminance, and log luminance, of a blackbody.
vec4 planckEntry(int i) {
    float T = 1000.0 * pow(100.0, float(i) / 255.0);
    vec3 xyz = vec3(0);
    for (int j = 0; j < 41 + ZERO; j++) {
        float w = (380.0 + 10.0 * float(j)) * 1e-3, w5 = w * w * w * w * w;
        xyz += CIE[j] / (w5 * (exp(14387.77 / (w * T)) - 1.0));
    }
    vec3 rgb = mat3(3.24097, -0.96924, 0.05563, -1.53738, 1.87597, -0.20398, -0.49861, 0.04156, 1.05697) * xyz;
    return vec4(rgb / xyz.y, log(xyz.y));
}

float presetPeriod(int k) {
    vec4 s = presetStar(k);
    return s.w < 0.0 ? critPeriod(s.y, s.z) / -s.w : s.w;
}

// ---- Active regions ---------------------------------------------------------------------
// Each of the 16 slots lives through successive regions. Count follows the cycle, latitude
// follows the butterfly diagram (and moves poleward on fast rotators), tilt follows Joy's
// law, polarity order follows Hale's law, and differential rotation shears them.
Region makeRegion(Star s, int k, float days, float flareClock) {
    Region g;
    float h0 = hashu(uint(k) * 7919u + 17u), h1 = hashu(uint(k) * 104729u + 3u);
    float life = mix(14.0, 48.0, h1);
    float cyc = s.cycle, warp = pow(cyc, 0.75);
    float cycleShape = mix(1.0, 0.05 + 0.95 * sq(sin(PI * warp)), s.cycleAmp);
    float nfrac = smoothstep(0.03, 0.45, s.alpha) * cycleShape;
    float phase = days / life + h0, gen = floor(phase), age = fract(phase);
    vec4 r = hash4(uint(k), uint(int(gen) & 0xffffff)), q = hash4(uint(k) + 500u, uint(int(gen) & 0xffffff));
    float on = sat((nfrac - 0.92 * r.x) / 0.08);
    float hemi = r.z < 0.5 ? 1.0 : -1.0;
    float latDeg = mix(30.0, 8.0, cyc);
    latDeg = mix(latDeg, 62.0, s.highLat) + (r.y - 0.5) * mix(16.0, 12.0, s.highLat);
    float lat = hemi * radians(latDeg);
    float shear = 0.2 * smoothstep(0.02, 0.5, s.Ro) + 0.01;
    float lon = r.w * TAU - shear * TAU / s.P * sq(sin(lat)) * age * life;
    vec3 n = rotY(vec3(0.0, sin(lat), cos(lat)), lon);
    vec3 east = normalize(vec3(n.z, 0.0, -n.x)), north = normalize(vec3(0, 1, 0) - n * n.y);
    float gam = 0.5 * abs(lat);                                        // Joy's law
    g.n = n;
    g.u = cos(gam) * east - sin(gam) * hemi * north;                  // leading spot: ahead, equatorward
    float f = 0.35 + 1.3 * q.x * q.x * q.x;
    float big = 1.0 + 1.8 * smoothstep(0.45, 1.0, s.alpha);
    g.w = 0.024 * sqrt(f) * big;
    g.a = (0.03 + 0.035 * f) * sqrt(big) * (0.35 + 0.65 * smoothstep(0.0, 0.12, age)) * (1.0 + 0.8 * age);
    g.e = on * smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.3, 1.0, age)) * f * s.conv;
    g.lead = hemi;                                                     // Hale's law for this cycle
    g.age = age;
    // Flares: real-time clock, so a flare is always watchable whatever the time-lapse.
    float I = 5.0, fp = flareClock / I + h1, slot = floor(fp);
    vec4 fr = hash4(uint(k) + 900u, uint(int(slot) & 0xffffff));
    float local = fract(fp) * I - fr.y * 2.5;
    float prof = local < 0.0 ? 0.0 : (1.0 - exp(-local / 0.10)) * exp(-local / 1.0);
    g.flare = fr.x < s.flareRate * sat(g.e) * 0.8 ? prof * (0.5 + fr.z) : 0.0;
    if (g.e < 0.002) { g.e = 0.0; g.flare = 0.0; }
    return g;
}


// ---- Interface text --------------------------------------------------------------------------
// Every string the interface shows is composed here once per frame: row 6 holds 5 texels of
// 12 chars per line (3 chars per channel), row 7 the lengths. Image only looks characters up.
/*TEXT_DATA*/

// One string at a time is composed into a global scratch buffer (no array copies).
uint SW[16]; int SN;
void str() { for (int i = 0; i < 16 + ZERO; i++) SW[i] = 0u; SN = 0; }
// The table is decoded once, on the reset frame, into rows 8+ (one char per channel).
uint textChar(ivec2 t, int i) { int j = t.x + i, x = j >> 2; vec4 v = fetch(iChannel0, x % 256, 8 + x / 256); int c = j & 3; return uint(c == 0 ? v.x : c == 1 ? v.y : c == 2 ? v.z : v.w); }
void put(uint c) { if (SN < 60) { SW[SN >> 2] |= c << uint(8 * (SN & 3)); SN++; } }
void putT(ivec2 t) { for (int i = 0; i < t.y + ZERO; i++) put(textChar(t, i)); }
void putInt(int v) {
    int d = 1;
    for (int k = 0; k < 8 + ZERO; k++) if (d * 10 <= v) d *= 10;
    for (int k = 0; k < 9 + ZERO; k++) { put(uint(48 + (v / d) % 10)); if (d == 1) break; d /= 10; }
}
void putFix(float v, int dec) {
    int m = dec == 0 ? 1 : dec == 1 ? 10 : dec == 2 ? 100 : dec == 3 ? 1000 : 10000;
    int n = int(floor(max(v, 0.0) * float(m) + 0.5)), ip = n / m;
    putInt(ip);
    if (dec > 0) {
        put(46u);
        int fr = n - ip * m, d = m / 10;
        for (int k = 0; k < 4 + ZERO; k++) { if (k >= dec) break; put(uint(48 + (fr / d) % 10)); d = max(d / 10, 1); }
    }
}
void putSig(float v) { putFix(v, v >= 100.0 ? 0 : v >= 10.0 ? 1 : v >= 1.0 ? 2 : v >= 0.1 ? 3 : 4); }


ivec2 starName(int k) {
    return k == 0 ? TXT("Sun") : k == 1 ? TXT("AB Dor") : k == 2 ? TXT("Proxima") : k == 3 ? TXT("Arcturus")
         : k == 4 ? TXT("Betelgeuse") : k == 5 ? TXT("Altair") : k == 6 ? TXT("Rigel") : TXT("Sirius B");
}


// Period or time in days, with sensible units.
void putTime(float d) {
    if (d < 1.0 / 24.0) { putSig(d * 1440.0); putT(TXT(" min")); }
    else if (d < 1.0) { putSig(d * 24.0); putT(TXT(" h")); }
    else if (d < 700.0) { putSig(d); putT(TXT(" d")); }
    else { putSig(d / 365.25); putT(TXT(" yr")); }
}
void composeLine(int L, Star st) {
    vec4 ctrl = fetch(iChannel0, S_CTRL, 0), camT = fetch(iChannel0, S_CAMT, 0);
    str();
    if (L >= TL_STAR && L < TL_STAR + NSTARS) putT(starName(L - TL_STAR));
    else if (L >= TL_SLAB && L < TL_SLAB + 4) { int k = L - TL_SLAB; putT(k == 0 ? TXT("Temperature") : k == 1 ? TXT("Radius") : k == 2 ? TXT("Rotation") : TXT("Cycle")); }
    else if (L >= TL_SVAL && L < TL_SVAL + 4) {
        int k = L - TL_SVAL;
        if (k == 0) { putInt(int(st.T + 0.5)); putT(TXT(" K")); }
        else if (k == 1) { putSig(st.R); putT(TXT(" Rsun")); }
        else if (k == 2) putTime(st.P);
        else {
            float c = st.cycle;
            if (st.alpha < 0.02) putT(TXT("none"));
            else putT(c < 0.15 || c > 0.88 ? TXT("minimum") : c < 0.32 ? TXT("rising") : c < 0.58 ? TXT("maximum") : TXT("declining"));
        }
    }
    else if (L == TL_ZOOM) { put(120u); putInt(int(exp2(camT.z) + 0.5)); }
    else if (L == TL_VIS) putT(TXT("Visible"));
    else if (L == TL_EUV) putT(TXT("EUV"));
    else if (L == TL_FIELD) putT(TXT("Field"));
    else if (L == TL_PAUSE) putT(ctrl.w > 0.5 ? TXT("Play") : TXT("Pause"));
    else if (L == TL_HIDE) putT(TXT("Hide"));
    else if (L == TL_SHOW) putT(TXT("Show"));
}

void mainImage(out vec4 O, in vec2 P) {
    ivec2 p = ivec2(P); vec2 res = iResolution.xy;
    vec4 meta = fetch(iChannel0, S_META, 0);
    bool reset = iFrame == 0 || meta.x != VERSION;
    O = vec4(0);
    if (p.y == 1) { if (p.x < 256) O = reset ? planckEntry(p.x) : fetch(iChannel0, p.x, 1); return; }
    if (p.y >= 2 && p.y <= 5) {
        if (reset) return;
        Star s = loadStar(iChannel0); vec4 clock = fetch(iChannel0, S_CLOCK, 0);
        int k = p.y == 2 ? p.x / 2 : p.x;
        if (k >= NREG) return;
        Region g = makeRegion(s, k, clock.x, clock.w);
        if (p.y == 2) {
            // Buried sources under the two spots; positive one first.
            vec3 lead = normalize(g.n + g.a * g.u), foll = normalize(g.n - g.a * g.u);
            vec3 pos = (g.lead > 0.0) == (p.x % 2 == 0) ? lead : foll;
            float depth = clamp(0.5 * g.w + 0.3 * g.a, 0.025, 0.1);
            float q = 0.02 * g.e * (1.0 + 1.5 * g.flare);
            O = q > 0.0 ? vec4(pos * (1.0 - depth), p.x % 2 == 0 ? q : -q) : vec4(0);
        }
        else if (p.y == 3) O = vec4(g.n, g.a);
        else if (p.y == 4) O = vec4(g.u, g.w);
        else O = vec4(g.e, g.flare, g.lead, g.age);
        return;
    }
    if (p.y >= 8 && p.y < 8 + (TEXT_LEN + 1023) / 1024) {
        int x = (p.y - 8) * 256 + p.x;
        if (p.x < 256 && 4 * x < TEXT_LEN) {
            if (!reset) { O = fetch(iChannel0, p.x, p.y); return; }
            uint w = textWord(x);
            O = vec4(w & 255u, (w >> 8) & 255u, (w >> 16) & 255u, w >> 24);
        }
        return;
    }
    if (p.y == 6 || p.y == 7) {
        if (reset || (p.y == 6 && p.x >= 5 * NTL) || (p.y == 7 && p.x >= NTL)) return;
        int L = p.y == 6 ? p.x / 5 : p.x;
        composeLine(L, loadStar(iChannel0));
        if (p.y == 7) { O = vec4(float(SN), 0, 0, 0); return; }
        int base = 12 * (p.x % 5);
        for (int c = 0; c < 4 + ZERO; c++) {
            uint v = 0u;
            for (int b = 0; b < 3 + ZERO; b++) { int i = base + 3 * c + b; v |= ((SW[i >> 2] >> uint(8 * (i & 3))) & 255u) << uint(8 * b); }
            O[c] = float(v);
        }
        return;
    }
    if (p.y != 0 || p.x > 15) return;

    // ---- state update (every row-0 texel runs it and keeps its own part) ----
    vec4 ctrl, slide, eased, cam, camT, mouse, clock;
    if (reset) {
        ctrl = vec4(0, 1, 0, 0); slide = presetSliders(0); eased = slide;
        cam = vec4(0.35, 0.16, 0, 0); camT = cam; mouse = vec4(0, 0, 0, -1); clock = vec4(0);
        meta = vec4(VERSION, 1.0, 1.0, presetPeriod(0) / 45.0);
    } else {
        ctrl = fetch(iChannel0, S_CTRL, 0); slide = fetch(iChannel0, S_SLIDE, 0); eased = fetch(iChannel0, S_EASED, 0);
        cam = fetch(iChannel0, S_CAM, 0); camT = fetch(iChannel0, S_CAMT, 0); mouse = fetch(iChannel0, S_MOUSE, 0);
        clock = fetch(iChannel0, S_CLOCK, 0);
    }
    float dt = clamp(iTimeDelta, 0.0, 0.1);
    bool down = iMouse.z > 0.0, fresh = down && mouse.z < 0.5;
    int hit = fresh ? uiHit(iMouse.xy, res, cam.w > 0.5) : (down ? int(mouse.w) : -2);
    if (fresh) {
        if (hit >= 10 && hit < 10 + NSTARS) {
            int k = hit - 10;
            slide = presetSliders(k); meta.y = presetStar(k).z; camT.w = 0.0; ctrl.x = float(k);
            camT.y = k == 5 ? 0.62 : 0.16;                    // Altair: show the hot pole
        }
        if (hit == 20) ctrl.y = 0.0;
        if (hit == 21) ctrl.y = 1.0;
        if (hit == 22) ctrl.z = 1.0 - ctrl.z;
        if (hit == 23) ctrl.w = 1.0 - ctrl.w;
        if (hit == 24) camT.z = max(camT.z - 1.0, 0.0);
        if (hit == 25) camT.z = min(camT.z + 1.0, 6.0);
        if (hit == 26) cam.w = 1.0;
        if (hit == 27) cam.w = 0.0;
    }
    if (down && hit >= 0 && hit < 4) {
        vec2 span = sliderSpan(hit);
        float v = sat((uiPoint(iMouse.xy, res).x - span.x) / (span.y - span.x));
        if (hit == 0) slide.x = v; else if (hit == 1) slide.y = v; else if (hit == 2) slide.z = v; else slide.w = v;
        camT.w = 1.0;
    }
    if (down && hit == -1 && mouse.z > 0.5) {
        vec2 d = (iMouse.xy - mouse.xy) * 3.2 / res.y / exp2(cam.z);
        camT.x -= d.x; camT.y = clamp(camT.y - d.y, -1.45, 1.45);
    }
    mouse = vec4(iMouse.xy, down ? 1.0 : 0.0, float(hit));

    float ke = 1.0 - exp(-dt * 9.0);
    eased = mix(eased, slide, ke);
    cam.xyz = mix(cam.xyz, camT.xyz, 1.0 - exp(-dt * 7.0));
    meta.z = exp(mix(log(meta.z), log(meta.y), ke));
    meta.w = exp(mix(log(meta.w), log(presetPeriod(int(ctrl.x)) / 45.0), ke));
    Star s = makeStar(eased, meta.z, meta.w);
    if (ctrl.w < 0.5 && !reset) {
        float lapse = meta.w;
        clock.x += dt * lapse;
        clock.y = mod(clock.y + dt * min(TAU * lapse / s.P, TAU / 3.0), TAU);
        float tauGran = 0.0058 * s.gran * s.R * 695.7;
        clock.z = mod(clock.z + dt * min(lapse / tauGran, 0.4), 1000.0);
        clock.w += dt;
    }
    if (p.x == S_CTRL) O = ctrl;
    else if (p.x == S_SLIDE) O = slide;
    else if (p.x == S_EASED) O = eased;
    else if (p.x == S_CAM) O = cam;
    else if (p.x == S_CAMT) O = camT;
    else if (p.x == S_MOUSE) O = mouse;
    else if (p.x == S_CLOCK) O = clock;
    else if (p.x == S_META) O = meta;
    else packStar(s, p.x - S_MODEL, O);
}
