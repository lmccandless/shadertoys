// Geometry only: the barn, the tree, the distant church and tree line, and the cow.
// RGB stores octahedral normal.xy + ray distance; A is the material ID.
// iChannel0: A (current camera/pigment atlas).
//  ID  0 sky   1 hide   2 ground   3 barn wall   4 oak    5 shutter   6 eye   7 horn   8 hoof
//      9 muzzle 10 inner ear 11 foliage 13 post  14 church stone 16 tail switch 17 thatch 18 bench
struct Hit { float t; vec3 n; float m; };

// ---- cow: fine detail on top of Common's cowMass ------------------------------------------------
mat3 frameOf(vec3 t,vec3 curl) {
    t=normalize(t); vec3 n=normalize(curl-dot(curl,t)*t);
    return mat3(t,n,cross(t,n));
}
vec2 cowHeadFine(vec3 p,vec2 res) {
    // Eye: a socket pressed into the skull, a proud eyeball in it, and a soft lid rim around it.
    vec3 e=p-P(180.5,341.0,0.235);
    res.x=smoothMax(res.x,-ellipsoid(e,vec3(PX(8.4),PX(7.2),0.060)),0.018);
    res=pick(res,vec2(ellipsoid(e-vec3(0.0,0.0,-0.012),vec3(PX(5.4),PX(4.8),0.050)),6.0));
    // Ears: a leaf of hide leaning up and back from the poll, with a cupped, pinker inside. The lower
    // end is sunk into the skull and blended with a small radius, so the ear is grown from the head.
    vec3 ep=p-P(214.0,325.0,0.205); ep.xy=rot(1.02)*ep.xy;
    ep.xz=rot(-0.30)*ep.xz;
    float ear=ellipsoid(ep,vec3(0.185,0.082,0.044));
    float cup=ellipsoid(ep-vec3(0.01,0.0,0.052),vec3(0.135,0.052,0.040));
    vec3 far=p; far.z=-far.z;
    vec3 fp=far-P(214.0,325.0,0.205); fp.xy=rot(1.02)*fp.xy; fp.xz=rot(-0.30)*fp.xz;
    float ear2=ellipsoid(fp,vec3(0.185,0.082,0.044));
    ear=min(ear,ear2);
    float earD=max(ear,-cup);
    bool earWins=earD<res.x;
    res.x=smoothMin(res.x,earD,0.035);
    if(earWins && -cup>ear) res.y=10.0;
    // Poll boss between the horns, and the horns themselves: smooth bent tubes, tapering to a
    // rounded tip, growing out of the boss (smooth union), never a chain of straight segments.
    float boss=ellipsoid(p-P(187.0,315.0,0.0),vec3(PX(19.0),PX(8.0),0.175));
    vec3 hq=p; hq.z=abs(hq.z);
    vec3 hb=P(197.0,314.5,0.11);
    mat3 hf=frameOf(vec3(-0.936,-0.10,0.14),vec3(0.0,1.0,-0.05));
    float horn=arcTaper(transpose(hf)*(hq-hb),0.85,0.68,0.046,0.007);
    float hornAll=smoothMin(boss,horn,0.05);
    res=pick(res,vec2(hornAll,7.0));
    res.x=smoothMin(res.x,hornAll,0.02);
    return res;
}
float hoof(vec3 f,vec3 half3) {
    // Cloven wedge: flat sole, toe (-x) leaning forward, a shallow cleft down the front of the toe.
    float d=boxSDF(f,half3)-0.020;
    d=max(d,dot(f.xy,vec2(-0.61,0.79))-half3.y*0.55);
    float cleft=max(abs(f.z)-0.007,f.x+half3.x*0.15);
    return max(d,-cleft);
}
vec2 cowHooves(vec3 p,vec2 res) {
    // Cloven hoof wedges: toe forward (-x), always dark against the pale pastern above.
    res=pick(res,vec2(hoof(p-P(313.0,555.0,0.5),vec3(PX(9.0),PX(5.6),0.085)),8.0));
    res=pick(res,vec2(hoof(p-P(279.0,546.0,-0.4),vec3(PX(8.0),PX(4.8),0.070)),8.0));
    res=pick(res,vec2(hoof(p-P(578.0,563.0,0.5),vec3(PX(9.5),PX(5.6),0.090)),8.0));
    res=pick(res,vec2(hoof(p-P(525.0,553.0,-0.4),vec3(PX(8.5),PX(5.0),0.078)),8.0));
    return res;
}
vec2 cowTuft(vec3 p,vec2 res) {
    // The switch: a soft, tapering brush of hair below the rope, ending in a wisp (not a blade).
    float t=roundCone(p,P(620.5,458.0,0.0),P(619.5,482.0,0.0),PX(2.7),PX(4.4));
    t=smoothMin(t,roundCone(p,P(619.5,482.0,0.0),P(617.5,509.0,0.0),PX(4.4),PX(1.2)),0.03);
    return pick(res,vec2(t,16.0));
}
vec2 cow(vec3 p) {
    vec2 res=vec2(cowMass(p),1.0);
    float hb=length(p-HEAD_C);
    if(hb<HEAD_R) res=cowHeadFine(p,res);
    else res.x=min(res.x,hb-HEAD_R+0.05);
    if(p.y<0.3) res=cowHooves(p,res);
    if(p.x>1.9 && p.y<1.2) res=cowTuft(p,res);
    return res;
}
vec3 cowNormal(vec3 p,float e) {
    vec3 n=vec3(0);
    for(int i=ZERO;i<4;i++) {
        vec3 k=0.5773*vec3(float((((i+3)>>1)&1)*2-1),float(((i>>1)&1)*2-1),float((i&1)*2-1));
        n+=k*cow(p+k*e).x;
    }
    return normalize(n);
}
// ---- architecture --------------------------------------------------------------------------------
vec2 boxInterval(vec3 ro,vec3 rd,vec3 center,vec3 size) {
    vec3 inv=sign(rd)/max(abs(rd),vec3(0.000001));
    vec3 a=(center-size-ro)*inv,b=(center+size-ro)*inv;
    vec3 lo=min(a,b),hi=max(a,b);
    return vec2(max(lo.x,max(lo.y,lo.z)),min(hi.x,min(hi.y,hi.z)));
}
void addBox(inout Hit h,vec3 ro,vec3 rd,vec3 center,vec3 size,float mat) {
    vec2 t=boxInterval(ro,rd,center,size);
    if(t.x>0.0 && t.x<t.y && t.x<h.t) {
        vec3 q=(ro+rd*t.x-center)/size,a=abs(q);
        vec3 n=vec3(0);
        if(a.x>a.y && a.x>a.z)n.x=sign(q.x);
        else if(a.y>a.z)n.y=sign(q.y); else n.z=sign(q.z);
        h=Hit(t.x,n,mat);
    }
}
void addEllipsoid(inout Hit h,vec3 ro,vec3 rd,vec3 c,vec3 r,float mat) {
    vec3 o=(ro-c)/r,d=rd/r;
    float a=dot(d,d),b=dot(o,d),k=dot(o,o)-1.0,disc=b*b-a*k;
    if(disc>0.0) {
        float t=(-b-sqrt(disc))/a;
        if(t>0.0 && t<h.t)h=Hit(t,normalize((ro+rd*t-c)/(r*r)),mat);
    }
}
// One row of round tree crowns: overlapping half-discs of random height and spacing.
float crownRow(float x,float seed) {
    float c=x/1.55+seed,i=floor(c),top=0.0;
    for(int k=-1;k<=1;k++) {
        float id=i+float(k);
        float h=0.50+0.50*hash12(vec2(id,seed));
        float cx=id+0.5+(hash12(vec2(id,seed+5.0))-0.5)*0.45;
        float w=0.62+0.35*hash12(vec2(id,seed+9.0));
        top=max(top,h*sqrt(max(0.0,1.0-sq((c-cx)/w))));
    }
    return top;
}
// Flat cut-out at depth z whose top edge is a row of crowns; used for the far woods.
void addTreeLine(inout Hit h,vec3 ro,vec3 rd,float z,float base,float amp,float freq,float seed,float mat) {
    if(rd.z>-0.0001) return;
    float t=(z-ro.z)/rd.z;
    if(t<=0.0 || t>=h.t) return;
    vec3 q=ro+rd*t;
    float x=q.x*freq;
    float top=base+amp*(0.75*crownRow(x,seed)+0.25*noise2(vec2(x*9.0,seed)));
    if(q.y<top && q.y>-0.05) h=Hit(t,normalize(vec3(0.3*(noise2(vec2(x*7.0,1.0))-0.5),0.6*smoothstep(top-0.35,top,q.y),1.0)),mat);
}
// A single lumpy crown cut-out standing on the ground at depth z: centre x, half width w, height hgt.
void addCrown(inout Hit h,vec3 ro,vec3 rd,float z,float cx,float w,float hgt,float seed,float mat) {
    if(rd.z>-0.0001) return;
    float t=(z-ro.z)/rd.z;
    if(t<=0.0 || t>=h.t) return;
    vec3 q=ro+rd*t;
    vec2 e=vec2((q.x-cx)/w,(q.y-hgt*0.52)/(hgt*0.52));
    float lump=0.17*(noise2(vec2(q.x*3.1+seed,q.y*3.1))-0.5)+0.09*(noise2(vec2(q.x*9.0+seed,q.y*9.0))-0.5);
    if(dot(e,e)+lump<1.0 && q.y>-0.05) h=Hit(t,normalize(vec3(e.x*0.5,0.4+0.4*e.y,1.0)),mat);
}
float thatchSDF(vec3 q) {
    vec3 c=q-vec3(-1.62,7.30,-0.30);
    c.xy=rot(0.30)*c.xy;
    float d=boxSDF(c,vec3(0.58,1.35,2.30))-0.16;
    return d+0.05*(noise3(q*vec3(6.0,1.6,6.0))-0.5)+0.02*(noise3(q*vec3(21.0,3.0,21.0))-0.5);
}
float tree(vec3 p) {
    // Tall, oval elm crown behind the barn corner (painting px 205..295 x 155..300), leaning slightly.
    p-=P(252.0,232.0,-6.0);
    float u=PX(1.0)*1.375;
    float a=ellipsoid(p-vec3(0.0,-3.0*u,0.0),vec3(46.0*u,80.0*u,0.85));
    float b=ellipsoid(p-vec3(9.0*u,41.0*u,0.05),vec3(30.0*u,42.0*u,0.62));
    float e=ellipsoid(p-vec3(-4.0*u,-50.0*u,0.0),vec3(52.0*u,50.0*u,0.85));
    float d=smoothMin(smoothMin(a,b,0.35),e,0.30);
    d+=0.15*(noise3(p*4.4)-0.5)+0.06*(noise3(p*12.0)-0.5);
    return d*0.72;
}
vec3 treeNormal(vec3 p) {
    vec2 k=vec2(1,-1)*0.015;
    return normalize(k.xyy*tree(p+k.xyy)+k.yyx*tree(p+k.yyx)+k.yxy*tree(p+k.yxy)+k.xxx*tree(p+k.xxx));
}
void mainImage(out vec4 O,in vec2 F) {
    if(!isReady(iChannel0,61.25)) { O=vec4(0);return; }
    if(all(equal(ivec2(F),ivec2(0)))) { O=vec4(0,0,0,62.25);return; }
    vec3 ro;mat3 basis;float focal;
    camera(texelFetch(iChannel0,ivec2(1,0),0).xy,iResolution.xy,ro,basis,focal);
    vec3 rd=cameraRay(F+jitter(iFrame),iResolution.xy,basis,focal);
    Hit h=Hit(600.0,vec3(0,1,0),0.0);
    if(rd.y<-0.0002) {
        float t=-ro.y/rd.y;
        if(t>0.0 && t<92.0) h=Hit(t,vec3(0,1,0),2.0);
    }
    // We stand inside the barn, looking out through its open bay: a thatched roof and rafters overhead,
    // a recessed back wall with its hatch, a heavy bay post with a knee brace, daylight only at the left.
    float wl=P(330.0,0.0,WALL_Z).x;
    addBox(h,ro,rd,vec3(wl+5.55,5.6,WALL_Z-0.90),vec3(5.55,5.6,0.90),3.0);
    addBox(h,ro,rd,vec3(4.60,7.35,-0.60),vec3(6.40,1.10,2.60),17.0);                 // roof, underside at y=6.25
    for(int k=0;k<6;k++)                                                              // rafters
        addBox(h,ro,rd,vec3(-0.20+1.90*float(k),6.07,-0.60),vec3(0.13,0.16,2.50),17.0);
    addBox(h,ro,rd,vec3(4.50,5.95,WALL_Z+0.16),vec3(5.30,0.30,0.16),19.0);           // tie beam on the wall
    // Bay post (painting px 293..332): a square oak timber from the floor into the roof, and a broad knee brace
    // that grows out of its upper right, flush with the post's face, and runs up into the roof plate
    // (centre line 322,176 px -> 372,-20 px). Both share a face plane, so the joint reads as one frame.
    vec3 pc=P(312.5,150.0,-1.5);
    addBox(h,ro,rd,vec3(pc.x,3.1,pc.z),vec3(PXZ(19.5,-1.5),3.2,0.22),13.0);
    vec3 bo=ro-vec3(-0.953,5.533,-1.45),br=rd;bo.xy=rot(-0.2496)*bo.xy;br.xy=rot(-0.2496)*br.xy;
    Hit brace=Hit(h.t,vec3(0),0.0);
    addBox(brace,bo,br,vec3(0),vec3(0.18,1.22,0.15),19.0);
    if(brace.m>0.0) { brace.n.xy=rot(0.2496)*brace.n.xy;h=brace; }
    // Thatch eave: a rounded, shaggy bundle at the corner of the roof (painting px 250..340 x 0..70).
    vec2 tb=boxInterval(ro,rd,vec3(-1.62,7.20,-0.30),vec3(0.95,1.80,2.50));
    if(tb.x<tb.y && tb.x<h.t && tb.y>0.0) {
        float t=max(tb.x,0.0),endT=min(tb.y,h.t);
        for(int i=0;i<40;i++) {
            vec3 q=ro+rd*t;
            float d=thatchSDF(q);
            if(d<0.004) {
                vec3 nn=vec3(0);
                for(int k=ZERO;k<4;k++) {
                    vec3 e=0.5773*vec3(float((((k+3)>>1)&1)*2-1),float(((k>>1)&1)*2-1),float((k&1)*2-1));
                    nn+=e*thatchSDF(q+e*0.02);
                }
                h=Hit(t,normalize(normalize(nn)+0.25*(vec3(noise3(q*9.0),noise3(q*9.0+3.0),noise3(q*9.0+7.0))-0.5)),17.0);
                break;
            }
            t+=max(d*0.7,0.01);
            if(t>endT)break;
        }
    }
    // Hatch in the back wall (painting px 590..690 x 135..265): a recessed frame with a planked leaf.
    vec3 sc=P(640.0,200.0,WALL_Z+0.05);
    addBox(h,ro,rd,sc,vec3(PXZ(54.0,WALL_Z),PXZ(69.0,WALL_Z),0.05),4.0);
    addBox(h,ro,rd,sc+vec3(0.0,0.0,0.05),vec3(PXZ(46.0,WALL_Z),PXZ(61.0,WALL_Z),0.035),5.0);
    // A bench against the back wall at the right edge (painting px 700..790 x 400..470).
    vec3 bt=P(758.0,405.0,-1.55);
    addBox(h,ro,rd,bt,vec3(PXZ(54.0,-1.55),0.05,0.30),18.0);
    addBox(h,ro,rd,vec3(bt.x-PXZ(46.0,-1.55),bt.y*0.5,bt.z),vec3(0.05,bt.y*0.5,0.05),18.0);
    addBox(h,ro,rd,vec3(bt.x+PXZ(46.0,-1.55),bt.y*0.5,bt.z),vec3(0.05,bt.y*0.5,0.05),18.0);
    // Far woods (low, dark tree lines), the church tower at the end of the lane, and a crown behind the head.
    addTreeLine(h,ro,rd,-70.0,0.9,1.45,0.62,3.0,11.0);
    vec3 ch=P(66.0,358.0,-56.0);
    addBox(h,ro,rd,vec3(ch.x,1.27,ch.z),vec3(0.30,1.27,0.28),14.0);
    addBox(h,ro,rd,vec3(ch.x,2.62,ch.z),vec3(0.37,0.10,0.34),14.0);
    for(int k=0;k<4;k++) {
        float sx=(k&1)==0?-1.0:1.0,sz=(k&2)==0?-1.0:1.0;
        addBox(h,ro,rd,vec3(ch.x+sx*0.33,2.86,ch.z+sz*0.30),vec3(0.045,0.26,0.045),14.0);
    }
    addBox(h,ro,rd,vec3(ch.x-0.70,0.55,ch.z+0.05),vec3(0.55,0.55,0.30),14.0);
    addTreeLine(h,ro,rd,-48.0,0.35,1.35,0.80,8.0,11.0);
    // A rounder crown just behind the cow's head (painting px 105..155 x 340..378).
    vec3 cr=P(130.0,394.0,-40.0);
    addCrown(h,ro,rd,-40.0,cr.x,PX(27.0)*3.5,PX(58.0)*3.5,2.0,11.0);
    addCrown(h,ro,rd,-38.0,P(178.0,394.0,-38.0).x,PX(24.0)*3.4,PX(34.0)*3.4,7.0,11.0);
    // Nearby tree: a stout trunk, then the crown, clipped to a tight bounding box before marching.
    vec3 tc=P(250.0,232.0,-6.0);
    addBox(h,ro,rd,vec3(tc.x+0.02,1.45,tc.z),vec3(0.17,1.45,0.17),13.0);
    vec2 bounds=boxInterval(ro,rd,tc+vec3(0.0,-0.10,0.0),vec3(0.95,1.95,1.05));
    if(bounds.x<bounds.y && bounds.x<h.t && bounds.y>0.0) {
        float t=max(bounds.x,0.0),endT=min(bounds.y,h.t);
        for(int i=0;i<52;i++) {
            vec3 p=ro+rd*t;float d=tree(p);
            if(d<0.006) { h=Hit(t,treeNormal(p),11.0);break; }
            t+=max(d*0.62,0.005);
            if(t>endT)break;
        }
    }
    // Restrict the expensive anatomical evaluator to the actual cattle bounds.
    bounds=boxInterval(ro,rd,vec3(-0.55,1.58,0.0),vec3(3.05,1.66,1.02));
    if(bounds.x<bounds.y && bounds.x<h.t && bounds.y>0.0) {
        float t=max(bounds.x,0.0),endT=min(bounds.y,h.t);
        for(int i=0;i<COW_STEPS;i++) {
            vec3 p=ro+rd*t;vec2 d=cow(p);
            float eps=max(0.0008,t*0.00006);
            if(d.x<eps) { h=Hit(t,cowNormal(p,eps*0.9),d.y);break; }
            t+=max(d.x*0.82,0.0005);
            if(t>endT)break;
        }
    }
    O=vec4(encodeNormal(h.n),h.t,h.m);
}
