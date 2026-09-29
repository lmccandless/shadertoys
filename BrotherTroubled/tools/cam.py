#!/usr/bin/env python3
"""Camera model mirroring Common.glsl camera()/cameraRay(); used to place scenery from painting pixels.

  python3 tools/cam.py            # print the calibration table
  from cam import Cam; Cam().px_to_world(px, py, z)
"""
import math

class Cam:
    def __init__(self, W=800, H=668, D=16.0, tx=-0.35, ty=2.6, yaw=-0.025, pitch=0.0, height=None):
        self.W, self.H, self.D = W, H, D
        self.height = height if height else max(5.85, 8.85 * H / W)
        self.set(tx, ty, yaw, pitch)

    def set(self, tx, ty, yaw, pitch):
        self.tx, self.ty, self.yaw, self.pitch = tx, ty, yaw, pitch
        back = (math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
        self.ro = tuple(t + self.D * b for t, b in zip((tx, ty, 0.0), back))
        fw = tuple(-b for b in back)
        rt = self._norm(self._cross(fw, (0, 1, 0)))
        up = self._cross(rt, fw)
        self.fw, self.rt, self.up = fw, rt, up
        self.focal = self.D / self.height

    @staticmethod
    def _cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    @staticmethod
    def _norm(a):
        l = math.sqrt(sum(x*x for x in a)); return tuple(x/l for x in a)

    def ray(self, px, py):
        u = (px - 0.5 * self.W) / self.H
        v = ((self.H - py) - 0.5 * self.H) / self.H
        return self._norm(tuple(self.rt[i]*u + self.up[i]*v + self.fw[i]*self.focal for i in range(3)))

    def px_to_world(self, px, py, z=0.0):
        d = self.ray(px, py); t = (z - self.ro[2]) / d[2]
        return tuple(self.ro[i] + d[i] * t for i in range(3))

    def world_to_px(self, x, y, z):
        d = tuple(w - r for w, r in zip((x, y, z), self.ro))
        cz = sum(d[i]*self.fw[i] for i in range(3)); cx = sum(d[i]*self.rt[i] for i in range(3)); cy = sum(d[i]*self.up[i] for i in range(3))
        u = cx / cz * self.focal; v = cy / cz * self.focal
        return (u * self.H + 0.5 * self.W, self.H - (v * self.H + 0.5 * self.H))

    def ground_py(self, x, z):  # py of the ground plane point (x, 0, z)
        return self.world_to_px(x, 0.0, z)[1]

    def horizon_py(self):
        # ray with rd.y == 0 -> project a far point
        return self.world_to_px(self.ro[0], self.ro[1], self.ro[2] - 1e6)[1]

if __name__ == '__main__':
    best = None
    D = float(__import__('sys').argv[1]) if len(__import__('sys').argv) > 1 else 16.0
    for pitch_i in range(0, 60):
        pitch = -pitch_i * 0.001   # negative pitch: camera above target, looking slightly up? (see back.y)
        for ty_i in range(0, 200):
            ty = 1.6 + ty_i * 0.01
            c = Cam(D=D, ty=ty, pitch=pitch)
            err = (c.horizon_py() - 358) ** 2 + (c.ground_py(-1.3, 0.5) - 560) ** 2 + (c.ground_py(-1.3, -0.4) - 549) ** 2
            if best is None or err < best[0]: best = (err, ty, pitch)
    err, ty, pitch = best
    c = Cam(D=D, ty=ty, pitch=pitch)
    print(f'D={D} best ty={ty:.3f} pitch={pitch:.4f} err={err:.1f}  horizon={c.horizon_py():.1f}  nearHoof={c.ground_py(-1.3,0.5):.1f} farHoof={c.ground_py(-1.3,-0.4):.1f}')
    print('ro', [round(v, 3) for v in c.ro])
    for name, (px, py, z) in {'back top': (430, 297, 0), 'belly': (430, 485, 0), 'rump edge': (624, 340, 0), 'chest': (230, 440, 0), 'eye': (180, 341, 0.2),
                              'muzzle': (139, 378, 0.1), 'tail': (620, 400, 0.0)}.items():
        print(f'{name:10s}', [round(v, 3) for v in c.px_to_world(px, py, z)])
    print('wall base z=-1.5 py', round(c.ground_py(0, -1.5), 1), ' z=-2 py', round(c.ground_py(0, -2.0), 1))
