# Ramanujan: The Crown and the Edge (lite)

A trimmed, compile-friendly cut of movements III and IV of `../ramanujan-infinity`,
with no text: the circle-method crown over the unit disk (24 s), then an endless,
exactly self-similar modular zoom at the golden point that never stops.

- **Drag in the bar at the bottom** to scrub (it spans the crown and the first 22 s of zoom).
- **Drag anywhere else** to pan: orbit the crown, or slide along the edge. The camera eases after your hand.

![crown](shots/crown.jpg) ![edge](shots/edge.jpg)

- **Buffer A** (iChannel0 = itself, nearest): the scene. State (clock, pan target, eased pan,
  pan at drag start) lives in the alpha of texels (0..6, 0).
- **Image** (iChannel0 = Buffer A, mipmap): bloom from A's mip chain, ACES, vignette, dither, timeline bar.

Kept small for compile time: no Common, no arrays or text. The modular reduction is inlined
at only three call sites: the ray-march and its bisection share one loop, and the normal
and the zoom's three samples are loops too.

`node tools/build.mjs` writes `ramanujan-edge.json` and `viewer.html`.
