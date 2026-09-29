// BROTHER TROUBLED -- a procedural oil-painted cattle portrait, rebuilt as true 3D geometry.
// Pure shared math only. No textures, photographs, fonts or external assets.
#define PI 3.14159265359
#define ORBIT_LIMIT 0.2617993878
#define PAINT_AMOUNT 0.52
#define EXPOSURE 1.0
#define COW_STEPS 96
#define SHADOW_STEPS 22
#define ZERO (min(iFrame,0))

// The camera is calibrated so that, at the reference framing (800x668), the ground plane, the
// horizon and the hooves land where they do in the painting. Scene pieces are authored in
// painting pixels through P()/PX() and converted to world units here.
#define CAM_D 16.0
#define CAM_YAW -0.025
#define CAM_PITCH -0.017
#define PXU 0.011062

float sat(float v) { return clamp(v,0.0,1.0); }
vec3 sat(vec3 v) { return clamp(v,0.0,1.0); }
float sq(float v) { return v*v; }
mat2 rot(float a) { float s=sin(a),c=cos(a); return mat2(c,-s,s,c); }
float hash12(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*0.1031);
    q+=dot(q,q.yzx+33.33); return fract((q.x+q.y)*q.z);
}
vec2 hash22(vec2 p) { return vec2(hash12(p),hash12(p+vec2(37.21,19.73))); }
float noise2(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash12(i),hash12(i+vec2(1,0)),f.x),
               mix(hash12(i+vec2(0,1)),hash12(i+vec2(1,1)),f.x),f.y);
}
float noise3(vec3 p) {
    vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    vec2 a=i.xy+vec2(37.0,17.0)*i.z;
    float l=mix(mix(hash12(a),hash12(a+vec2(1,0)),f.x),mix(hash12(a+vec2(0,1)),hash12(a+1.0),f.x),f.y);
    a+=vec2(37,17);
    float h=mix(mix(hash12(a),hash12(a+vec2(1,0)),f.x),mix(hash12(a+vec2(0,1)),hash12(a+1.0),f.x),f.y);
    return mix(l,h,f.z);
}
float smoothMin(float a,float b,float k) {
    float h=max(k-abs(a-b),0.0)/k; return min(a,b)-h*h*k*0.25;
}
float smoothMax(float a,float b,float k) { return -smoothMin(-a,-b,k); }
float boxSDF(vec3 p,vec3 b) {
    vec3 d=abs(p)-b; return length(max(d,0.0))+min(max(d.x,max(d.y,d.z)),0.0);
}
float ellipsoid(vec3 p,vec3 r) {
    float k0=length(p/r),k1=length(p/(r*r));
    return k0*(k0-1.0)/max(k1,0.00001);
}
// Linearly tapered capsule (a "round cone" with radii ra at a and rb at b).
float taper(vec3 p,vec3 a,vec3 b,float ra,float rb) {
    vec3 ba=b-a; float t=clamp(dot(p-a,ba)/dot(ba,ba),0.0,1.0);
    return length(p-a-ba*t)-mix(ra,rb,t);
}
// Exact-ish round cone (two spheres joined by a tangent cone): smoother than taper() at the ends.
float roundCone(vec3 p,vec3 a,vec3 b,float r1,float r2) {
    vec3 ba=b-a; float l2=dot(ba,ba),rr=r1-r2,a2=l2-rr*rr,il2=1.0/l2;
    vec3 pa=p-a; float y=dot(pa,ba),z=y-l2,x2=dot(pa*l2-ba*y,pa*l2-ba*y);
    float y2=y*y*l2,z2=z*z*l2,k=sign(rr)*rr*rr*x2;
    if(sign(z)*a2*z2>k) return sqrt(x2+z2)*il2-r2;
    if(sign(y)*a2*y2<k) return sqrt(x2+y2)*il2-r1;
    return (sqrt(x2*a2*il2)+y*rr)*il2-r1;
}
// Bent, tapering tube: an arc of radius R that starts at the origin heading +x and curves toward +y
// through `sweep` radians; the tube radius blends r0 -> r1 along the arc. The tip is a true sphere,
// so a horn made with it is smooth and round everywhere, with no straight-segment kinks.
float arcTaper(vec3 p,float R,float sweep,float r0,float r1) {
    float th=clamp(atan(p.x,R-p.y),0.0,sweep);
    vec3 c=vec3(R*sin(th),R*(1.0-cos(th)),0.0);
    return length(p-c)-mix(r0,r1,th/sweep);
}
// 2D rounded box with a separate radius per corner: r = (top-right, bottom-right, top-left, bottom-left).
float roundBox2(vec2 p,vec2 b,vec4 r) {
    r.xy=(p.x>0.0)?r.xy:r.zw;
    r.x=(p.y>0.0)?r.x:r.y;
    vec2 q=abs(p)-b+r.x;
    return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r.x;
}
// Inflates a 2D silhouette distance into a soft slab: half thickness h, edge rounding radius r <= h.
float inflate(float d2,float z,float h,float r) {
    vec2 w=vec2(d2+r,abs(z)-h+r);
    return min(max(w.x,w.y),0.0)+length(max(w,0.0))-r;
}
vec2 pick(vec2 a,vec2 b) { return a.x<b.x?a:b; }

// Painting pixel (800x668 reference, y down) -> world point on plane z, following the base camera.
vec3 P(float px,float py,float z) {
    float s=(CAM_D-z)/CAM_D;
    return vec3(-0.35+CAM_YAW*z+(px-400.0)*PXU*s,2.42+CAM_PITCH*z+(334.0-py)*PXU*s,z);
}
float PX(float px) { return px*PXU; }
// Length of n painting pixels at depth z (scenery further back covers more world per painted pixel).
float PXZ(float px,float z) { return px*PXU*(CAM_D-z)/CAM_D; }
#define WALL_Z -2.1
// Inverse of P(): where a world point lands in the 800x668 reference painting (y down).
vec2 pxOf(vec3 p) {
    float s=(CAM_D-p.z)/CAM_D;
    return vec2(400.0+(p.x+0.35-CAM_YAW*p.z)/(PXU*s),334.0-(p.y-2.42-CAM_PITCH*p.z)/(PXU*s));
}

vec2 encodeNormal(vec3 n) {
    n/=abs(n.x)+abs(n.y)+abs(n.z);
    vec2 p=n.xy;
    if(n.z<0.0) p=(1.0-abs(p.yx))*vec2(p.x>=0.0?1.0:-1.0,p.y>=0.0?1.0:-1.0);
    return p*0.5+0.5;
}
vec3 decodeNormal(vec2 e) {
    vec2 f=e*2.0-1.0; vec3 n=vec3(f,1.0-abs(f.x)-abs(f.y));
    float t=clamp(-n.z,0.0,1.0);
    n.xy+=vec2(n.x>=0.0?-t:t,n.y>=0.0?-t:t);
    return normalize(n);
}
bool isReady(sampler2D tex,float tag) { return abs(texelFetch(tex,ivec2(0),0).a-tag)<0.005; }
vec2 jitter(int frame) {
    // A fixed 16-sample stratification. Camera stillness resolves subpixel hair/grass.
    int f=frame%16;
    return vec2(float((f*5)%16)+0.5,float((f*9+3)%16)+0.5)/16.0-0.5;
}
void camera(vec2 angles,vec2 res,out vec3 ro,out mat3 basis,out float focal) {
    float height=max(5.85,8.85*res.y/res.x);
    vec3 target=vec3(-0.35,height*0.35-0.165,0.0);
    float yaw=angles.x+CAM_YAW, pitch=angles.y*0.38+CAM_PITCH;
    vec3 back=vec3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch));
    ro=target+CAM_D*back;
    vec3 fw=-back,rt=normalize(cross(fw,vec3(0,1,0))),up=cross(rt,fw);
    basis=mat3(rt,up,fw); focal=CAM_D/height;
}
vec3 cameraRay(vec2 fc,vec2 res,mat3 basis,float focal) {
    return normalize(basis*vec3((fc-0.5*res)/res.y,focal));
}
vec4 pigment(sampler2D tex,vec2 uv) {
    // The first row is reserved for feedback state, never for pigment sampling.
    uv=fract(uv); uv.y=0.012+0.976*uv.y;
    return textureLod(tex,uv,0.0);
}
float luminance(vec3 c) { return dot(c,vec3(0.2126,0.7152,0.0722)); }

// ---------------------------------------------------------------------------------------------
// The cow. Shared by the geometry pass (full detail) and the lighting pass (shadow / occlusion).
// Everything is authored in painting pixels of the 800x668 reference so it can be checked against
// the picture directly: P(px,py,z) is the world position, PX(n) a length of n painting pixels.
// ---------------------------------------------------------------------------------------------

// Body mass: barrel torso, brisket, neck, head, four legs and the tail. No fine detail.
// Head bounds (world): centre and radius of a sphere that encloses skull, muzzle, ears and horns.
#define HEAD_C vec3(-2.78,2.16,0.0)
#define HEAD_R 1.0
float cowHead(vec3 p) {
    // Skull and jaw in one tilted ellipsoid; the face is a tapering cone pulled out of it toward the
    // muzzle, exactly like the steep, short face in the painting (forehead 175,322 -> nose 138,373).
    vec3 hp=p-P(194.0,349.0,0.0); hp.xy=rot(0.32)*hp.xy;
    float d=ellipsoid(hp,vec3(PX(31.0),PX(35.0),0.275));
    d=smoothMin(d,roundCone(p,P(178.0,346.0,0.0),P(147.0,370.0,0.0),PX(23.0),PX(11.5)),0.10);
    // Cheek and jaw line: a long, soft plane running from the ear root down to the chin.
    d=smoothMin(d,roundCone(p,P(200.0,362.0,0.0),P(154.0,380.0,0.0),PX(19.0),PX(8.5)),0.08);
    // Muzzle pad (broad from the front, as a bovine muzzle is).
    d=smoothMin(d,ellipsoid(p-P(145.0,373.0,0.0),vec3(PX(11.0),PX(11.5),0.145)),0.06);
    return d;
}
float cowLegs(vec3 p) {
    // Near legs stand at z = +0.5, far legs at z = -0.4: the painted hoof spacing (11 px) needs that
    // little depth, and the flanks overhang them like a fat animal's should.
    // near fore: stout forearm, knee, slender cannon, fetlock, short pastern
    float d=roundCone(p,P(313.0,455.0,0.5),P(314.0,503.0,0.5),PX(19.0),PX(9.6));
    d=smoothMin(d,roundCone(p,P(314.0,503.0,0.5),P(315.0,532.0,0.5),PX(9.6),PX(6.2)),0.06);
    d=smoothMin(d,roundCone(p,P(315.0,532.0,0.5),P(316.0,543.0,0.5),PX(6.2),PX(7.2)),0.04);
    d=smoothMin(d,roundCone(p,P(316.0,543.0,0.5),P(314.0,551.0,0.5),PX(7.2),PX(6.0)),0.03);
    // far fore
    d=min(d,roundCone(p,P(284.0,455.0,-0.4),P(283.0,500.0,-0.4),PX(15.0),PX(8.0)));
    d=smoothMin(d,roundCone(p,P(283.0,500.0,-0.4),P(281.0,531.0,-0.4),PX(8.0),PX(5.6)),0.05);
    d=smoothMin(d,roundCone(p,P(281.0,531.0,-0.4),P(280.0,544.0,-0.4),PX(5.6),PX(6.2)),0.03);
    // near hind: heavy gaskin, a distinct hock with its point behind, slim cannon, fetlock
    d=min(d,roundCone(p,P(562.0,452.0,0.5),P(578.0,500.0,0.5),PX(31.0),PX(14.5)));
    d=smoothMin(d,ellipsoid(p-P(584.0,503.0,0.5),vec3(PX(11.5),PX(14.0),0.13)),0.05);
    d=smoothMin(d,roundCone(p,P(580.0,505.0,0.5),P(578.0,540.0,0.5),PX(10.5),PX(6.6)),0.05);
    d=smoothMin(d,roundCone(p,P(578.0,540.0,0.5),P(578.0,548.0,0.5),PX(6.6),PX(7.6)),0.03);
    d=smoothMin(d,roundCone(p,P(578.0,548.0,0.5),P(577.0,556.0,0.5),PX(7.6),PX(6.4)),0.03);
    // far hind: slants back under the body, so the hoof lands left of the thigh
    d=min(d,roundCone(p,P(536.0,452.0,-0.4),P(530.0,498.0,-0.4),PX(27.0),PX(13.0)));
    d=smoothMin(d,roundCone(p,P(530.0,498.0,-0.4),P(527.0,530.0,-0.4),PX(13.0),PX(6.4)),0.06);
    d=smoothMin(d,roundCone(p,P(527.0,530.0,-0.4),P(525.0,546.0,-0.4),PX(6.4),PX(6.6)),0.03);
    return d;
}
float cowTail(vec3 p) {
    // Root sunk into the rump, then a slender rope hanging straight down the rear edge.
    float d=roundCone(p,P(612.0,338.0,0.0),P(620.0,372.0,0.0),PX(7.5),PX(3.2));
    d=smoothMin(d,roundCone(p,P(620.0,372.0,0.0),P(620.5,462.0,0.0),PX(3.2),PX(2.7)),0.04);
    return d;
}
float cowMass(vec3 p) {
    // Barrel: the painting's silhouette (x 230..624, y 297..487 px) inflated into a soft slab, so the
    // outline is exactly the painted one while flanks, back and belly are properly round in depth.
    vec2 c=P(419.5,392.5,0.0).xy;
    float d2=roundBox2(p.xy-c,vec2(PX(189.5),PX(94.5)),vec4(PX(30.0),PX(94.0),PX(70.0),PX(46.0)));
    // The painted rump bulges out above the thigh, then the outline falls back in (623 px -> 614 px).
    d2=smoothMin(d2,ellipsoid(vec3(p.xy-P(596.0,340.0,0.0).xy,0.0),vec3(PX(28.0),PX(33.0),1.0)),PX(14.0));
    float d=inflate(d2,p.z,0.84,0.66);
    // Haunch and shoulder pads give the flank a sculpted, well-fed swell instead of a flat plate.
    d=smoothMin(d,ellipsoid(p-P(526.0,414.0,0.34),vec3(PX(72.0),PX(90.0),0.58)),0.30);
    d=smoothMin(d,ellipsoid(p-P(306.0,414.0,0.32),vec3(PX(66.0),PX(84.0),0.56)),0.26);
    // Brisket / dewlap: the painted chest bulges forward and hangs low in front of the near leg.
    d=smoothMin(d,ellipsoid(p-P(252.0,440.0,0.0),vec3(PX(34.0),PX(50.0),0.55)),0.16);
    // Short, thick neck carrying the head just in front of the shoulder.
    d=smoothMin(d,roundCone(p,P(248.0,360.0,0.0),P(210.0,354.0,0.0),PX(42.0),PX(30.0)),0.14);
    float hb=length(p-HEAD_C);
    if(hb<0.78) d=smoothMin(d,cowHead(p),0.08);
    else d=min(d,hb-0.72);
    if(p.y<1.45) d=smoothMin(d,cowLegs(p),0.12);
    if(p.x>1.85 && p.y>0.3) d=smoothMin(d,cowTail(p),0.05);
    return d;
}
