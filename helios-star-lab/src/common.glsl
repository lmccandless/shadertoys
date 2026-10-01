/*! Original shader code (c) 2026 Logan McCandless. CC BY-NC-ND 4.0.
https://creativecommons.org/licenses/by-nc-nd/4.0/ */
// HELIOS: STAR LAB
// Common: state layout, the stellar model, active regions, the magnetic field, camera, UI layout.
//
// Every visible property is derived from five inputs: temperature, radius, mass, rotation
// (as a fraction of breakup) and magnetic-cycle phase. Nothing is a per-star special case.

const float PI = 3.14159265, TAU = 6.28318531;
// Loop bounds plus ZERO cannot be folded, so ANGLE's HLSL backend does not unroll them.
// Unrolled nested loops are what make shader compiles explode.
#define ZERO min(iFrame, 0)
const float VERSION = 601.0;

// ---- Buffer A, row 0 -------------------------------------------------------------
const int S_CTRL  = 0;   // star, view (0 visible, 1 EUV), field overlay, paused
const int S_SLIDE = 1;   // slider targets 0..1: temperature, radius, rotation, cycle
const int S_EASED = 2;   // eased slider values (what is rendered)
const int S_CAM   = 3;   // eased camera: yaw, pitch, log2 zoom, ui hidden
const int S_CAMT  = 4;   // camera target: yaw, pitch, log2 zoom, modified
const int S_MOUSE = 5;   // last mouse: x, y, down, hit id
const int S_CLOCK = 6;   // star days, spin angle, granule phase, flare clock (s)
const int S_META  = 7;   // version, mass target, mass eased, time-lapse (days/s) eased
const int S_MODEL = 8;   // 8..15: packed Star
// Row 1: Planck table. Row 2: field sources (2 per region). Rows 3-5: active regions. Rows 8+: text table.
// Rows 6-7: interface text lines (see Buffer A), indexed by these:
const int TL_STAR = 0, TL_SLAB = 8, TL_SVAL = 12, TL_ZOOM = 16, TL_VIS = 17, TL_EUV = 18, TL_FIELD = 19, TL_PAUSE = 20;
const int TL_HIDE = 21, TL_SHOW = 22, NTL = 23;
const int NREG = 16;
const int NSTARS = 8;

// ---- Field-line geometry (Buffer B) ---------------------------------------------
const int NLINES = 256;            // 16 regions x 12 + 64 global
const int NODES = 64;
const int STRIDE = 73;             // 64 nodes, 8 chunk bounds, meta
const float RSS = 2.5;             // source surface: field is radial beyond it
const float RMAX = 3.4;
const int TILE = 32;               // Buffer C screen tiles

float sat(float x) { return clamp(x, 0.0, 1.0); }
float sq(float x) { return x * x; }
vec4 fetch(sampler2D s, int x, int y) { return texelFetch(s, ivec2(x, y), 0); }

uint pcg(uint v) { uint s = v * 747796405u + 2891336453u; uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u; return (w >> 22u) ^ w; }
float hashu(uint v) { return float(pcg(v) >> 8) * (1.0 / 16777216.0); }
vec4 hash4(uint a, uint b) {
    uint h = pcg(a * 1664525u + pcg(b));
    return vec4(hashu(h), hashu(h ^ 0x9e3779b9u), hashu(h ^ 0x85ebca6bu), hashu(h ^ 0xc2b2ae35u));
}
float hash13(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
vec3 hash33(vec3 p) { p = fract(p * vec3(0.1031, 0.1030, 0.0973)); p += dot(p, p.yxz + 33.33); return fract((p.xxy + p.yxx) * p.zyx); }
float vnoise(vec3 p) {
    vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
// fBm that fades each octave to its mean once it is smaller than the pixel footprint fp.
float fbm(vec3 p, float fp, int octaves) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < octaves + ZERO; i++) {
        s += a * mix(vnoise(p), 0.5, smoothstep(0.35, 1.0, fp));
        p = p * 2.03 + vec3(17.1, 9.7, 3.3); fp *= 2.03; a *= 0.5;
    }
    return s / (1.0 - a * 2.0 + 1e-4) ;
}
vec3 rotY(vec3 p, float a) { float c = cos(a), s = sin(a); return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z); }

// ---- Sliders and presets -------------------------------------------------------------
float sliderT(float x) { return 2400.0 * pow(45000.0 / 2400.0, x); }
float sliderR(float x) { return 0.008 * pow(1000.0 / 0.008, x); }
float sliderW(float x) { return 1e-4 * pow(0.95 / 1e-4, x); }       // omega = Omega / Omega_crit
float unT(float v) { return log(v / 2400.0) / log(45000.0 / 2400.0); }
float unR(float v) { return log(v / 0.008) / log(1000.0 / 0.008); }
float unW(float v) { return log(v / 1e-4) / log(0.95 / 1e-4); }

// Breakup period of a Roche star with polar radius R (Rsun) and mass M (Msun), days:
// Omega_crit^2 = 8 GM / (27 Rp^3).
float critPeriod(float R, float M) { return 0.2129 * sqrt(R * R * R / M); }

// T (K), polar R (Rsun), M (Msun), rotation period (days); cycle phase separately.
// Sun: IAU nominal. AB Dor A: Guirado+ 2011. Proxima: Boyajian+ 2012, P 83 d (Benedict+ 1998).
// Arcturus: Ramirez & Allende Prieto 2011. Betelgeuse: Joyce+ 2020, P 36 yr (Kervella+ 2018).
// Altair: Monnier+ 2007 (polar R, omega 0.923). Rigel: Przybilla+ 2006. Sirius B: Bond+ 2017.
vec4 presetStar(int k) {
    if (k == 1) return vec4(5080.0, 0.96, 0.86, 0.514);
    if (k == 2) return vec4(3042.0, 0.154, 0.122, 83.0);
    if (k == 3) return vec4(4286.0, 25.4, 1.08, 730.0);
    if (k == 4) return vec4(3600.0, 764.0, 16.5, 13150.0);
    if (k == 5) return vec4(7550.0, 1.63, 1.79, -0.923);         // negative: omega given directly
    if (k == 6) return vec4(12100.0, 78.9, 21.0, 150.0);
    if (k == 7) return vec4(25000.0, 0.0081, 1.02, 0.25);
    return vec4(5772.0, 1.0, 1.0, 25.4);
}
float presetCycle(int k) { return k == 0 ? 0.42 : (k == 2 ? 0.55 : 0.5); }
vec4 presetSliders(int k) {
    vec4 s = presetStar(k);
    float w = s.w < 0.0 ? -s.w : critPeriod(s.y, s.z) / s.w;
    return vec4(unT(s.x), unR(s.y), unW(w), presetCycle(k));
}

// ---- The stellar model -------------------------------------------------------------------
struct Star {
    float T, R, M, omega, cycle;
    float logg, logL, P, veq;
    float conv, alpha, Ro, giant;
    float gran, cgran, spotDT, beta;
    float eq, gdNorm, logY0, highLat;
    vec3 dipole; float flareRate;
    float wind, molsphere, wd, lapse;
    float chromo, coronaH, fullConv, cycleAmp;
};

// Effective gravity on the (ellipsoidal) Roche surface, units of GM/Rp^2. p on the surface.
float effGravity(vec3 p, float omega) {
    float r = length(p);
    vec3 g = -p / (r * r * r) + (8.0 / 27.0) * omega * omega * vec3(p.x, 0.0, p.z);
    return length(g);
}
// Equatorial / polar radius of a Roche surface rotating at omega.
float rocheEq(float w) {
    if (w < 0.05) return 1.0 + 4.0 * w * w / 27.0;
    return 3.0 / w * cos((PI + acos(w)) / 3.0);
}
// Photopic luminance (log) of a blackbody at temperature T, from the table in A, row 1.
vec4 planck(sampler2D A, float T) {
    float f = clamp(log(T / 1000.0) / log(100.0), 0.0, 1.0) * 255.0;
    int i = int(floor(f));
    return mix(fetch(A, i, 1), fetch(A, min(i + 1, 255), 1), fract(f));
}

Star makeStar(vec4 x, float M, float lapse) {
    Star s;
    s.T = sliderT(x.x); s.R = sliderR(x.y); s.M = M; s.omega = sliderW(x.z); s.cycle = x.w;
    s.logg = 4.438 + log(M / (s.R * s.R)) / log(10.0);
    s.eq = rocheEq(s.omega);
    s.logL = log(s.R * s.R * s.eq * pow(s.T / 5772.0, 4.0)) / log(10.0);
    s.P = critPeriod(s.R, M) / s.omega;
    s.veq = 2.0 * PI * s.R * s.eq * 695700.0 / (s.P * 86400.0);
    s.wd = smoothstep(5.5, 7.0, s.logg);
    // Convective envelope: granulation disappears in the late A stars.
    s.conv = (1.0 - smoothstep(6600.0, 7600.0, s.T)) * (1.0 - s.wd);
    // Rossby number with the convective turnover time of Wright+ 2011 (main sequence),
    // lengthened for inflated envelopes; X-ray activity saturates at Ro < 0.13.
    float Mc = clamp(M, 0.1, 1.36);
    float tauc = pow(10.0, 2.33 - 1.50 * Mc + 0.31 * Mc * Mc) * sqrt(max(s.R / pow(M, 0.8), 1.0));
    s.Ro = s.P / tauc;
    float logRx = -3.13 - 2.7 * max(log(s.Ro / 0.13) / log(10.0), 0.0);
    s.alpha = sat((logRx + 7.5) / 4.37) * s.conv;
    s.fullConv = smoothstep(0.42, 0.32, M) * s.conv;
    s.highLat = smoothstep(0.25, 0.04, s.Ro) * s.conv;
    s.cycleAmp = 1.0 - 0.75 * smoothstep(0.55, 1.0, s.alpha);
    // Granule size tracks the pressure scale height, d ~ T/g, scaled to 1 Mm on the Sun.
    s.gran = 0.00144 * (s.T / 5772.0) * (s.R / M);
    s.giant = smoothstep(1.2, -0.2, s.logg) * s.conv;          // a few huge cells (3D RHD supergiants)
    s.cgran = min(0.03 * pow(s.T / 5772.0, 1.5), 0.05) * s.conv;
    // Spot temperature deficit, approximate fit to Berdyugina 2005 (fig. 7).
    s.spotDT = clamp(0.62 * (s.T - 2800.0), 120.0, 2200.0);
    s.beta = mix(0.20, 0.08, s.conv);                          // gravity-darkening exponent
    // Normalise von Zeipel darkening so the area-averaged T^4 equals Teff^4.
    float tot = 0.0, area = 0.0;
    for (int j = 0; j < 24 + ZERO; j++) {
        float z = (float(j) + 0.5) / 24.0;
        vec3 n = vec3(sqrt(1.0 - z * z), z, 0.0), p = n * vec3(s.eq, 1.0, s.eq);
        float da = length(n / vec3(s.eq, 1.0, s.eq)) * s.eq * s.eq;
        tot += da * pow(effGravity(p, s.omega), 4.0 * s.beta); area += da;
    }
    s.gdNorm = pow(tot / area, -0.25);
    s.logY0 = 0.0;
    // Global dipole: polar field reverses through cycle maximum while its axis swings
    // through the equator. Fully convective dwarfs carry strong axisymmetric dipoles.
    float act = smoothstep(0.02, 0.5, s.alpha);
    float dip = 0.10 * act * (1.0 + 2.5 * s.fullConv + 1.5 * s.highLat);
    float ph = PI * s.cycle * s.cycleAmp;
    s.dipole = dip * vec3(0.45 * sin(ph), cos(ph), 0.0);
    s.flareRate = sat(0.9 * smoothstep(0.12, 0.75, s.alpha) + 0.5 * s.fullConv);
    float lumHot = smoothstep(3.8, 5.3, s.logL) * (1.0 - s.conv) * (1.0 - s.wd);
    s.wind = lumHot;
    s.molsphere = s.giant * smoothstep(3.0, 4.5, s.logL);
    s.lapse = lapse;
    s.chromo = s.giant;
    // Coronal pressure scale height ~ T_corona R / M (0.11 R at 1.5 MK on the Sun).
    s.coronaH = clamp(0.11 * (1.0 + 1.2 * s.alpha) * s.R / M, 0.05, 0.6);
    return s;
}

void packStar(Star s, int i, out vec4 o) {
    if (i == 0) o = vec4(s.T, s.R, s.M, s.omega);
    else if (i == 1) o = vec4(s.cycle, s.logg, s.logL, s.P);
    else if (i == 2) o = vec4(s.conv, s.alpha, s.Ro, s.giant);
    else if (i == 3) o = vec4(s.gran, s.cgran, s.spotDT, s.beta);
    else if (i == 4) o = vec4(s.eq, s.gdNorm, s.veq, s.highLat);
    else if (i == 5) o = vec4(s.dipole, s.flareRate);
    else if (i == 6) o = vec4(s.wind, s.molsphere, s.wd, s.lapse);
    else o = vec4(s.chromo, s.coronaH, s.fullConv, s.cycleAmp);
}
Star loadStar(sampler2D A) {
    vec4 a = fetch(A, 8, 0), b = fetch(A, 9, 0), c = fetch(A, 10, 0), d = fetch(A, 11, 0);
    vec4 e = fetch(A, 12, 0), f = fetch(A, 13, 0), g = fetch(A, 14, 0), h = fetch(A, 15, 0);
    Star s;
    s.T = a.x; s.R = a.y; s.M = a.z; s.omega = a.w;
    s.cycle = b.x; s.logg = b.y; s.logL = b.z; s.P = b.w;
    s.conv = c.x; s.alpha = c.y; s.Ro = c.z; s.giant = c.w;
    s.gran = d.x; s.cgran = d.y; s.spotDT = d.z; s.beta = d.w;
    s.eq = e.x; s.gdNorm = e.y; s.veq = e.z; s.highLat = e.w;
    s.dipole = f.xyz; s.flareRate = f.w;
    s.wind = g.x; s.molsphere = g.y; s.wd = g.z; s.lapse = g.w;
    s.chromo = h.x; s.coronaH = h.y; s.fullConv = h.z; s.cycleAmp = h.w;
    s.logY0 = 0.0;
    return s;
}
vec3 starAxes(Star s) { return vec3(s.eq, 1.0, s.eq); }

// ---- Active regions -------------------------------------------------------------------------
// A region is a tilted bipole: centre n, unit axis u pointing to the leading spot, half
// separation a, spot size w; strength e, flare level, leading polarity sign, age.
struct Region { vec3 n; float a; vec3 u; float w; float e; float flare; float lead; float age; };
Region loadRegion(sampler2D A, int k) {
    vec4 p = fetch(A, k, 3), q = fetch(A, k, 4), r = fetch(A, k, 5);
    Region g; g.n = p.xyz; g.a = p.w; g.u = q.xyz; g.w = q.w; g.e = r.x; g.flare = r.y; g.lead = r.z; g.age = r.w;
    return g;
}

// ---- Potential field with a source surface ------------------------------------------------
// Buried point sources, each with a grounded-sphere image so the field is radial at RSS.
// They are a boundary basis (every bipole carries zero net flux), not magnetic monopoles.
vec3 dipoleField(vec3 p, vec3 m) {
    float r2 = max(dot(p, p), 0.25), ir = inversesqrt(r2), ir3 = ir * ir * ir;
    return 3.0 * p * dot(m, p) * ir3 / r2 - m * ir3 + m / (RSS * RSS * RSS);
}
vec3 sourceField(vec3 p, vec4 src) {
    vec3 q = src.xyz; float ar = length(q);
    vec3 d = p - q, di = p - q * (RSS * RSS / dot(q, q));
    float d2 = max(dot(d, d), 1e-6), i2 = max(dot(di, di), 1e-6);
    return src.w * (d / (d2 * sqrt(d2)) - (RSS / ar) * di / (i2 * sqrt(i2)));
}

// ---- Camera ---------------------------------------------------------------------------------
const float CAMDIST = 12.0;
float uiScale(vec2 res) { return min(res.x / 960.0, res.y / 540.0); }
struct Cam { vec3 ro, fw, rt, up; float focal; vec2 center; };
Cam makeCam(vec4 c, vec2 res) {
    float zoom = exp2(c.z);
    vec3 d = vec3(sin(c.x) * cos(c.y), sin(c.y), cos(c.x) * cos(c.y));
    Cam k; k.ro = d * CAMDIST; k.fw = -d;
    k.rt = normalize(cross(k.fw, vec3(0, 1, 0))); k.up = cross(k.rt, k.fw);
    k.focal = 0.5 * res.y * CAMDIST / (1.75 / zoom);         // frame half-height 1.75 R at zoom 1
    k.center = vec2(0.5 * res.x, 0.5 * res.y + 34.0 * uiScale(res) * smoothstep(1.5, 0.0, c.z) * (1.0 - c.w));
    return k;
}
// Camera expressed in the rotating star frame.
Cam starCam(Cam k, float spin) { k.ro = rotY(k.ro, -spin); k.fw = rotY(k.fw, -spin); k.rt = rotY(k.rt, -spin); k.up = rotY(k.up, -spin); return k; }
vec3 camRay(Cam k, vec2 px) { return normalize(k.fw * k.focal + k.rt * (px.x - k.center.x) + k.up * (px.y - k.center.y)); }

// ---- UI layout (virtual 960 x 540 canvas, bottom-anchored, centred) -----------------------
vec2 uiPoint(vec2 px, vec2 res) { float s = uiScale(res); return vec2(px.x - 0.5 * (res.x - 960.0 * s), px.y) / s; }
// Star picker: x start of each name in the first row (14 px font, 7 px advance).
float starX(int k) { return k == 0 ? 20.0 : k == 1 ? 57.0 : k == 2 ? 115.0 : k == 3 ? 180.0 : k == 4 ? 252.0 : k == 5 ? 338.0 : k == 6 ? 396.0 : 447.0; }
float starW(int k) { return 7.0 * (k == 0 ? 3.0 : k == 1 ? 6.0 : k == 2 ? 7.0 : k == 3 ? 8.0 : k == 4 ? 10.0 : k == 5 ? 6.0 : k == 6 ? 5.0 : 8.0); }
vec2 sliderSpan(int k) { float x = 20.0 + float(k) * 235.0; return vec2(x, x + 210.0); }
const float ROW1 = 56.0, TRACK = 12.0;
// Hit ids: 0-3 sliders, 10-17 stars, 20 visible, 21 euv, 22 field, 23 pause, 24 zoom-, 25 zoom+, 26 hide, 27 show, -1 scene.
int uiHit(vec2 px, vec2 res, bool hidden) {
    vec2 p = uiPoint(px, res);
    if (hidden) return (p.x > 890.0 && p.x < 950.0 && p.y < 34.0) ? 27 : -1;
    if (p.y < 0.0 || p.y > 74.0 || p.x < 0.0 || p.x > 960.0) return -1;
    if (p.y < 40.0) {
        for (int k = 0; k < 4 + ZERO; k++) { vec2 s = sliderSpan(k); if (p.x > s.x - 8.0 && p.x < s.y + 8.0) return k; }
        return 99;
    }
    for (int k = 0; k < NSTARS + ZERO; k++) if (p.x > starX(k) - 6.0 && p.x < starX(k) + starW(k) + 6.0) return 10 + k;
    if (p.x > 552.0 && p.x < 616.0) return 20;
    if (p.x > 617.0 && p.x < 654.0) return 21;
    if (p.x > 672.0 && p.x < 722.0) return 22;
    if (p.x > 737.0 && p.x < 788.0) return 23;
    if (p.x > 805.0 && p.x < 826.0) return 24;
    if (p.x > 864.0 && p.x < 886.0) return 25;
    if (p.x > 898.0 && p.x < 945.0) return 26;
    return 99;
}
