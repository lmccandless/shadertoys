// Deferred painting: pigments, hair, foliage, thatch, sky and soft lighting.
// iChannel0: geometry B. iChannel1: pigment/camera A.
// Palettes are written in sRGB the way they were read off the painting, then linearised.
vec3 srgb(vec3 c) { return pow(c,vec3(2.2)); }
float texNoise(vec2 q) { return pigment(iChannel1,q).g; }
float grain3(vec3 p,vec3 n,float scale) {
    vec3 w=pow(abs(n),vec3(5.0));w/=max(dot(w,vec3(1)),0.001);
    return dot(w,vec3(pigment(iChannel1,p.yz*scale).g,
                      pigment(iChannel1,p.xz*scale).g,
                      pigment(iChannel1,p.xy*scale).g));
}
float fbm2(vec2 p) {
    return 0.5*pigment(iChannel1,p*0.11).r+0.3*pigment(iChannel1,p*0.23+0.37).g+0.2*pigment(iChannel1,p*0.61+0.71).g;
}
// The sky, read directly in painting pixels (800x668 reference, y down): teal-green overhead, a large
// warm cumulus with its sunlit shoulder near the tree, a grey-lilac cloud floor, then pale hills.
vec3 paintSky(vec2 sp) {
    float n0=pigment(iChannel1,sp*0.0021+vec2(0.31,0.07)).r;
    float n1=pigment(iChannel1,sp*0.0052+vec2(0.11,0.43)).g;
    float n2=pigment(iChannel1,sp*0.0135+vec2(0.71,0.29)).g;
    float wob=(n0-0.5)*46.0+(n1-0.5)*22.0;
    vec2 q=sp+vec2(wob,wob*0.7);
    // Cloud mass: a big billow, its sunlit lobe, a second shoulder and a low bank running to the horizon.
    float bank=smoothstep(150.0,250.0,q.y-0.06*(q.x-120.0))*0.85;
    float billow=1.0-smoothstep(0.35,1.0,length((q-vec2(178.0,182.0))/vec2(135.0,92.0)));
    float lobe=1.0-smoothstep(0.30,1.0,length((q-vec2(210.0,140.0))/vec2(70.0,54.0)));
    float side=1.0-smoothstep(0.30,1.0,length((q-vec2(86.0,196.0))/vec2(80.0,46.0)));
    float cloud=sat(max(max(bank,billow*1.1),max(lobe*1.2,side*0.95))+0.34*(n1-0.5)+0.18*(n2-0.5));
    cloud=smoothstep(0.22,0.80,cloud);
    vec3 teal=mix(srgb(vec3(0.53,0.65,0.49)),srgb(vec3(0.66,0.73,0.53)),smoothstep(0.0,190.0,sp.y)*0.9+0.12*n1);
    teal=mix(teal,srgb(vec3(0.60,0.68,0.50)),(1.0-smoothstep(-40.0,60.0,sp.x))*0.5);
    // Sunlit warm cream on the right/upper side of the billows, cooler grey-lilac underneath.
    float lit=sat(0.55+0.55*((q.x-140.0)/200.0)-0.55*((q.y-150.0)/170.0)+0.35*(n2-0.5));
    vec3 cream=mix(srgb(vec3(0.70,0.655,0.50)),srgb(vec3(0.90,0.79,0.50)),lit);
    cream=mix(cream,srgb(vec3(0.80,0.76,0.56)),0.55*bank*(1.0-billow));
    float floorShade=smoothstep(215.0,345.0,sp.y);
    cream=mix(cream,srgb(vec3(0.66,0.635,0.50)),floorShade*0.9);
    vec3 sky=mix(teal,cream,cloud);
    // Low, pale hills at the horizon (y ~ 352..362), lost in haze toward the right.
    float ridge=354.0+4.0*sin(sp.x*0.021+1.3)+2.5*sin(sp.x*0.057)+2.5*(n2-0.5);
    float hills=smoothstep(ridge-5.0,ridge+5.0,sp.y);
    sky=mix(sky,srgb(vec3(0.63,0.60,0.42)),hills*0.75);
    // Three distant birds, dark flecks in the teal above the billow.
    vec2 bp[3]; bp[0]=vec2(108.0,93.0); bp[1]=vec2(125.0,118.0); bp[2]=vec2(155.0,130.0);
    for(int i=0;i<3;i++) {
        vec2 d=(sp-bp[i])/vec2(6.0,3.0);
        float wing=abs(d.y+abs(d.x)*0.9-0.2*sqrt(abs(d.x)+0.001));
        sky=mix(sky,srgb(vec3(0.20,0.24,0.20)),(1.0-smoothstep(0.14,0.30,wing))*step(abs(d.x),1.0));
    }
    return sky;
}
float cattleShadow(vec3 p,vec3 light) {
    if(abs(p.x)>9.0 || p.z<-5.0 || p.y>3.4) return 1.0;
    float t=0.05,s=1.0;
    for(int i=0;i<SHADOW_STEPS;i++) {
        float d=cowMass(p+light*t);
        s=min(s,5.0*max(d,0.0)/t);
        if(d<0.001)return 0.0;
        t+=clamp(d,0.035,0.45);
        if(t>7.0)break;
    }
    return sat(s);
}
float cattleAO(vec3 p,vec3 n) {
    float a=0.0,weight=1.0,dist=0.09;
    for(int k=0;k<4;k++) {
        float d=cowMass(p+n*dist);
        a+=max(0.0,dist-d)*weight;
        dist+=0.16;weight*=0.53;
    }
    return sat(1.0-1.3*a);
}
vec3 bumpNormal(vec3 n,vec3 p,float height,float strength) {
    vec3 dx=dFdx(p),dy=dFdy(p);
    vec3 r1=cross(dy,n),r2=cross(n,dx);
    float det=dot(dx,r1);
    vec3 grad=(dFdx(height)*r1+dFdy(height)*r2)/max(abs(det),0.000001)*sign(det);
    return normalize(n-clamp(grad,vec3(-5),vec3(5))*strength);
}
float straw(vec2 p) {
    float aa=clamp(3.4*max(length(dFdx(p)),length(dFdy(p))),0.004,0.25);
    vec2 cell=floor(p*3.4),q=fract(p*3.4)-0.5;
    float angle=hash12(cell)*6.283;
    q=rot(angle)*q;
    float d=length(vec2(max(abs(q.x)-0.24,0.0),q.y));
    float width=0.010;
    return (1.0-smoothstep(width,width+aa*0.7,d))*min(1.0,width/max(aa*0.40,0.001))*step(0.52,hash12(cell+47.0));
}
void mainImage(out vec4 O,in vec2 F) {
    if(!isReady(iChannel0,62.25)||!isReady(iChannel1,61.25)) { O=vec4(0);return; }
    if(all(equal(ivec2(F),ivec2(0)))) { O=vec4(0,0,0,63.25);return; }
    vec4 g=texelFetch(iChannel0,ivec2(F),0);
    vec2 angles=texelFetch(iChannel1,ivec2(1,0),0).xy;
    vec3 ro;mat3 basis;float focal;
    camera(angles,iResolution.xy,ro,basis,focal);
    vec3 rd=cameraRay(F+jitter(iFrame),iResolution.xy,basis,focal);
    float mat=g.a;
    if(mat<0.5) {
        // The sky belongs to the painting more than to the room: it follows only a quarter of the orbit.
        vec3 ro0;mat3 b0;float f0;
        camera(angles*0.25,iResolution.xy,ro0,b0,f0);
        vec3 rs=cameraRay(F+jitter(iFrame),iResolution.xy,b0,f0);
        camera(vec2(0),iResolution.xy,ro0,b0,f0);
        vec3 v=transpose(b0)*rs;
        vec2 sp=vec2(400.0+v.x/v.z*1446.0,334.0-v.y/v.z*1446.0);
        O=vec4(paintSky(sp),1);return;
    }
    vec3 p=ro+rd*g.b,n=decodeNormal(g.rg),originalN=n;
    vec3 albedo=vec3(0.4),emission=vec3(0);
    float rough=0.8,bump=0.0,bumpStrength=0.0,ao=1.0,glow=0.0;
    float broad=grain3(p,n,0.14),medium=grain3(p,n,0.59),fine=grain3(p,n,2.4);
    if(mat<1.5) {
        // Ivory hide: warm cream over a cooler grey, mottled with the painting's silvery flecks.
        vec2 coat=vec2(p.x*0.80+0.075*sin(p.y*3.0),p.y*0.28+0.04*sin(p.x*3.8));
        vec4 hair=pigment(iChannel1,coat+vec2(p.z*0.14,0));
        float wisps=texNoise(coat*vec2(3.2,0.72)+vec2(0.07,0.11));
        float warm=0.46*broad+0.34*medium+0.20*hair.b;
        vec3 cream=srgb(vec3(0.95,0.865,0.665));
        vec3 grey=srgb(vec3(0.80,0.75,0.60));
        albedo=mix(grey,cream,smoothstep(0.10,0.70,warm));
        float fleck=smoothstep(0.62,0.78,0.6*hair.g+0.4*medium)*0.30;
        albedo=mix(albedo,srgb(vec3(0.70,0.69,0.62)),fleck);
        albedo*=0.96+0.08*wisps;
        // Short, loaded brush dabs running down the flank, lighter ivory ridges between darker ochre gaps.
        vec2 dab=vec2(p.x*7.5+0.9*sin(p.y*2.3),p.y*1.35);
        float dabs=noise2(dab)*0.6+noise2(dab*2.3+11.0)*0.4;
        albedo=mix(albedo*vec3(0.93,0.90,0.82),albedo*vec3(1.03,1.03,1.05),smoothstep(0.30,0.70,dabs));
        // Painterly modelling: the brisket and legs sit in cooler, browner shade; the flank is broad and pale.
        vec2 pp=pxOf(p);
        float chestShade=exp(-sq((pp.x-238.0)/34.0)-sq((pp.y-440.0)/70.0));
        albedo*=1.0-0.30*chestShade;
        albedo*=1.0-0.16*sat(n.y);
        float legShade=1.0-smoothstep(0.75,1.30,p.y);
        albedo*=1.0-0.40*legShade;
        albedo*=1.0-0.20*legShade*smoothstep(0.9,1.6,p.x);
        // Skin around the eye is pigmented, the muzzle is pinkish, the legs are cooler and thinner-haired.
        vec2 eye=(p.xy-P(180.5,341.0,0.0).xy)/vec2(PX(14.5),PX(12.0));
        float orbit=exp(-pow(dot(eye,eye),1.25)*1.5)*smoothstep(0.10,0.22,p.z);
        albedo=mix(albedo,srgb(vec3(0.40,0.20,0.10)),orbit*0.92);
        // the soft brow crease above the eye and the mouth line along the jaw
        vec2 pf=pxOf(p);
        float mouth=exp(-sq((pf.y-(383.5+0.06*(pf.x-145.0)))/1.5))*smoothstep(146.0,153.0,pf.x)*(1.0-smoothstep(170.0,186.0,pf.x))*smoothstep(0.06,0.14,p.z);
        albedo=mix(albedo,srgb(vec3(0.42,0.30,0.22)),mouth*0.75);
        vec2 mz=(p.xy-P(140.0,378.0,0.0).xy)/vec2(PX(9.5),PX(8.0));
        float nose=exp(-dot(mz,mz)*1.3);
        albedo=mix(albedo,srgb(vec3(0.66,0.40,0.34)),nose*0.9);
        vec2 nz=(p.xy-P(141.5,375.0,0.0).xy)/vec2(PX(3.2),PX(2.6));
        albedo=mix(albedo,srgb(vec3(0.30,0.16,0.14)),exp(-dot(nz,nz)*1.4)*smoothstep(0.05,0.16,p.z)*0.85);
        float belly=1.0-smoothstep(1.05,1.75,p.y);
        albedo=mix(albedo,albedo*vec3(0.80,0.78,0.66),0.35*belly);
        bump=hair.g*0.007+wisps*0.005+fine*0.003;
        bumpStrength=0.5;rough=0.85;
        ao=cattleAO(p+originalN*0.035,originalN);
    } else if(mat<2.5) {
        vec4 soil=pigment(iChannel1,p.xz*0.11);
        float mottled=0.64*soil.r+0.36*medium;
        vec3 dirt=mix(srgb(vec3(0.36,0.255,0.125)),srgb(vec3(0.50,0.375,0.20)),smoothstep(0.25,0.75,mottled));
        // Broad horizontal dabs of warmer and cooler earth, the way the painter loaded the foreground.
        float dabsG=noise2(vec2(p.x*1.9,p.z*5.2))*0.6+noise2(vec2(p.x*5.5+3.0,p.z*13.0))*0.4;
        dirt*=0.84+0.32*smoothstep(0.25,0.75,dabsG);
        albedo=dirt;
        float chalk=smoothstep(0.62,0.82,fine)*0.35;
        albedo=mix(albedo,srgb(vec3(0.55,0.44,0.26)),chalk);
        float hay=straw(p.xz+0.03*soil.gb)+0.9*straw(p.xz*1.7+0.4)+0.6*straw(p.xz*2.9+1.7);
        albedo=mix(albedo,srgb(vec3(0.80,0.66,0.40)),sat(hay)*0.72);
        bump=0.018*soil.g+0.010*medium+0.004*fine;
        bumpStrength=0.85;
        // The lane and paddock greens toward the far woods; everywhere the cow sits in its own shade.
        float zz=-p.z;
        float leftMask=1.0-smoothstep(-4.5,-1.0,p.x);
        float pasture=smoothstep(2.0,20.0,zz)*(0.45+0.55*leftMask);
        albedo=mix(albedo,srgb(vec3(0.33,0.31,0.17))*(0.85+0.3*broad),pasture);
        // A pale, sunlit strip of meadow, then the shaded, dark foot of the woods behind it.
        float meadow=smoothstep(14.0,22.0,zz)*(1.0-smoothstep(30.0,38.0,zz))*leftMask;
        albedo=mix(albedo,srgb(vec3(0.44,0.42,0.26))*(0.9+0.2*medium),meadow*0.85);
        float woodFoot=smoothstep(34.0,44.0,zz);
        albedo=mix(albedo,srgb(vec3(0.19,0.21,0.11)),woodFoot*(0.35+0.6*leftMask));
        float under=exp(-sq((p.x-0.15)*0.42)-sq((p.z+0.05)*1.15));
        ao=1.0-0.20*under;
        albedo*=1.0+0.14*exp(-sq((p.x+1.0)*0.30)-sq((p.z-2.6)*0.32));
        albedo*=1.0-0.28*smoothstep(0.8,3.4,p.x);
        float wall=exp(-max(p.z-WALL_Z,0.0)*1.6)*smoothstep(-1.7,-1.2,p.x);
        ao*=1.0-0.45*wall;
        // Under the roof the barn floor sits in soft shade; daylight falls in only through the open bay.
        float indoors=(1.0-smoothstep(1.2,2.6,p.z))*smoothstep(-1.7,-0.2,p.x);
        albedo*=1.0-0.34*indoors;
        albedo*=0.9+0.2*soil.g;
    } else if(mat<3.5) {
        vec4 plaster=pigment(iChannel1,p.xy*vec2(0.044,0.039));
        float washes=sat((plaster.r-0.5)*1.7+0.50+0.12*(medium-0.5));
        vec3 dark=srgb(vec3(0.19,0.15,0.09)),lit=srgb(vec3(0.29,0.245,0.135));
        albedo=mix(dark,lit,washes);
        float scratch=abs(texNoise(p.xy*vec2(0.83,0.25))-0.5);
        albedo*=0.94+0.12*fine;
        bump=0.017*plaster.g+0.006*fine+0.003*scratch;
        bumpStrength=0.75;
        ao=0.86;
        // Reflected ivory light: the barn glows warmly just behind the cow's back and dies away to the right.
        vec2 wp2=pxOf(p);
        glow=(1.0-smoothstep(40.0,360.0,length((wp2-vec2(350.0,292.0))/vec2(1.0,0.78))))*0.85
            +0.50*(1.0-smoothstep(0.0,260.0,length((wp2-vec2(345.0,235.0))/vec2(0.9,1.1))));
        glow*=0.70+0.60*plaster.r*plaster.r+0.25*(medium-0.5);
        float windowEdge=length(max(abs(wp2-vec2(640.0,200.0))-vec2(52.0,67.0),0.0))*PXU*1.15;
        ao*=1.0-0.30*exp(-windowEdge*18.0);
        ao*=1.0-0.40*smoothstep(4.7,5.9,p.y);
        ao*=1.0-0.32*exp(-abs(p.x+1.18)*8.0);
        ao*=1.0-0.35*exp(-max(p.y,0.0)*1.0)*smoothstep(-0.3,1.2,p.x);
    } else if(mat<5.5 || (mat>12.5 && mat<13.5)) {
        vec2 wp=p.xy*vec2(0.91,0.05)+p.z*0.07;
        vec4 wood=pigment(iChannel1,wp);
        albedo=mix(srgb(vec3(0.24,0.16,0.085)),srgb(vec3(0.42,0.30,0.16)),wood.g*wood.g+0.12*broad);
        bump=wood.g*0.024+fine*0.004;bumpStrength=0.9;
        if(mat>4.5 && mat<5.5) {
            // The shutter is a dark, cool recess: a low-contrast planked leaf edged with teal-black.
            albedo=mix(srgb(vec3(0.20,0.155,0.09)),srgb(vec3(0.31,0.24,0.13)),wood.g);
            vec2 sp2=pxOf(p);
            float board=fract((sp2.y-135.0)/21.0);
            float seam=1.0-smoothstep(0.02,0.07,min(board,1.0-board));
            albedo*=1.0-seam*0.35;
            albedo=mix(albedo,srgb(vec3(0.08,0.11,0.10)),smoothstep(0.30,0.52,abs(sp2.x-640.0)/50.0)*0.35);
            ao=0.8;
        }
        if(mat>12.5) {
            // The painted post: warm reddish where the light rakes its left edge, umber toward the wall, and
            // sunk in the eave's shadow above the brace foot (painting y < 175 px).
            vec2 pp2=pxOf(p);
            albedo*=1.55;
            albedo=mix(albedo,srgb(vec3(0.60,0.35,0.19)),0.70*(1.0-smoothstep(293.0,314.0,pp2.x)));
            albedo*=1.0-0.28*smoothstep(316.0,332.0,pp2.x);
            albedo*=1.0-0.50*smoothstep(180.0,140.0,pp2.y)*smoothstep(298.0,312.0,pp2.x);
            ao=0.9;
        }
    } else if(mat>18.5) {
        // Knee brace: a heavy timber deep in the eave's shadow, its lit edge just catching the light.
        vec4 wood=pigment(iChannel1,p.xy*0.45+p.z*0.11);
        albedo=mix(srgb(vec3(0.13,0.095,0.055)),srgb(vec3(0.25,0.175,0.10)),wood.g);
        bump=wood.g*0.012;bumpStrength=0.6;
        ao=0.8;
    } else if(mat<6.5) {
        // Eye: dark ring, amber iris, dark horizontal pupil, moist highlight from the lighting.
        vec2 eu=(p.xy-P(180.5,341.0,0.0).xy)/vec2(PX(5.4),PX(4.8));
        float r=length(eu);
        vec3 iris=mix(srgb(vec3(0.83,0.53,0.22)),srgb(vec3(0.53,0.24,0.08)),smoothstep(0.3,0.95,r));
        albedo=iris;
        float pupil=1.0-smoothstep(0.20,0.36,length(eu*vec2(0.72,1.6)));
        albedo=mix(albedo,srgb(vec3(0.07,0.035,0.02)),pupil);
        albedo=mix(albedo,srgb(vec3(0.19,0.085,0.04)),smoothstep(0.80,1.05,r));
        rough=0.08;
    } else if(mat<7.5) {
        float tip=sat((-p.x-3.05)*3.0);
        albedo=mix(srgb(vec3(0.90,0.83,0.63)),srgb(vec3(0.42,0.32,0.18)),tip*0.9);
        // The poll boss is ringed with warm ochre where the horn horn meets the hair.
        float rim=smoothstep(0.55,0.95,1.0-abs(originalN.y))*(1.0-tip);
        albedo=mix(albedo,srgb(vec3(0.80,0.56,0.28)),rim*0.55);
        albedo*=0.92+0.16*medium;rough=0.42;
    } else if(mat<8.5) {
        // Hoof: near-black horn over a pale, hairy pastern band.
        float band=smoothstep(0.03,0.075,p.y);
        albedo=mix(srgb(vec3(0.16,0.12,0.09)),srgb(vec3(0.56,0.52,0.40)),band);
        albedo*=0.75+0.5*medium;rough=0.5;
    } else if(mat<9.5) {
        albedo=srgb(vec3(0.70,0.48,0.40));rough=0.6;
    } else if(mat<10.5) {
        albedo=srgb(vec3(0.78,0.58,0.48))*(0.92+0.16*medium);rough=0.8;
    } else if(mat<11.5) {
        vec4 leaves=pigment(iChannel1,(p.xy+p.z*0.13)*0.33);
        float foliage=0.54*leaves.g+0.27*fine+0.19*leaves.r;
        if(g.b>30.0) {
            // Far woods: dark, blue-green masses with a faint lighter dapple.
            albedo=mix(srgb(vec3(0.15,0.185,0.115)),srgb(vec3(0.27,0.30,0.19)),smoothstep(0.3,0.8,foliage));
            albedo*=0.50+0.50*smoothstep(0.05,1.6,p.y);
        } else {
            // The near elm: olive-khaki where the light catches it, deep brown-green in the hollows.
            albedo=mix(srgb(vec3(0.20,0.19,0.10)),srgb(vec3(0.62,0.54,0.31)),smoothstep(0.25,0.85,foliage));
            albedo*=0.95+0.25*broad;
        }
        bump=0.038*leaves.g+0.013*fine;bumpStrength=0.50;
        ao=0.85;
    } else if(mat<12.5) {
        albedo=srgb(vec3(0.35,0.36,0.17));
    } else if(mat>13.5 && mat<15.5) {
        albedo=srgb(vec3(0.80,0.72,0.52))*(0.85+0.3*medium);
        if(abs(p.x+12.3)<0.096 && p.y>1.03 && p.y<1.28)albedo*=0.40;
    } else if(mat<16.5) {
        // Tail switch: pale hair going a little brownish at the wisp.
        albedo=mix(srgb(vec3(0.88,0.80,0.60)),srgb(vec3(0.60,0.50,0.32)),sat((1.1-p.y)*1.6));
        rough=0.9;
    } else if(mat<17.5) {
        // Thatch: layered, darkened reed with straw strokes.
        vec4 reed=abs(originalN.y)>0.6?pigment(iChannel1,vec2(p.x*0.35,p.z*0.10)):pigment(iChannel1,vec2(p.x*0.35,p.y*0.045));
        albedo=mix(srgb(vec3(0.34,0.25,0.13)),srgb(vec3(0.58,0.42,0.21)),reed.g);
        albedo*=0.85+0.5*broad;
        bump=reed.g*0.03;bumpStrength=1.0;ao=0.9;
    } else {
        albedo=srgb(vec3(0.30,0.22,0.12))*(0.6+0.6*fine);
        bump=texNoise(p.xy*vec2(2.7,0.16))*0.02;bumpStrength=0.7;
    }
    bumpStrength*=1.0-smoothstep(19.0,37.0,g.b);
    n=bumpNormal(n,p,bump,bumpStrength);
    if(mat>10.5 && mat<11.5 && g.b>28.0)n=normalize(mix(n,vec3(-0.1,0.8,0.55),0.68));
    vec3 light=normalize(vec3(-0.52,0.60,0.62));
    float shadow=cattleShadow(p+originalN*0.035,light);
    bool isHide=mat<1.5,isWall=mat>2.5&&mat<3.5;
    float wrap=isHide?0.38:((mat>10.5&&mat<12.5)?0.14:0.02);
    vec3 lightN=isHide?normalize(vec3(-0.38,0.36,0.85)):light;
    float ndl=sat((dot(n,lightN)+wrap)/(1.0+wrap));
    float sky=sat(0.5+0.5*n.y);
    vec3 ambient=mix(srgb(vec3(0.48,0.37,0.24)),srgb(vec3(0.62,0.66,0.58)),sky)*0.62;
    vec3 keyCol=srgb(vec3(1.0,0.93,0.76))*1.05;
    float shadowFloor=0.10;
    if(isHide) { ambient*=1.25; keyCol*=0.95; shadowFloor=0.42; }
    if(mat>1.5 && mat<2.5) shadowFloor=0.52;   // the painted ground is only gently darkened by the cow
    if(isWall) keyCol*=0.0;                      // the wall is lit by reflected glow, not by the key
    vec3 lit=albedo*(ambient*ao+keyCol*ndl*mix(shadowFloor,1.0,shadow));
    if(isWall) lit=albedo*(0.62*ao+1.85*glow*ao)*srgb(vec3(1.0,0.90,0.74));
    vec3 hv=normalize(light-rd);
    float spec=pow(max(dot(n,hv),0.0),mix(110.0,8.0,rough))*mix(0.50,0.014,rough)*ndl*shadow;
    lit+=vec3(1.0,0.93,0.70)*spec;
    if(mat>5.5 && mat<6.5) {
        float wet=pow(max(dot(n,hv),0.0),120.0)*shadow;
        lit+=vec3(0.95,0.95,0.85)*wet*1.6;
    }
    if(isHide) {
        float fuzz=pow(1.0-sat(dot(n,-rd)),3.0)*sat(dot(light,-rd)*0.4+0.6);
        lit+=albedo*fuzz*0.07*shadow;
    }
    lit+=emission;
    lit*=1.0-0.22*smoothstep(4.6,6.2,p.y)*smoothstep(-2.0,-0.9,p.x)*step(-4.5,p.z);
    float far=max(g.b-18.0,0.0);
    float fog=1.0-exp(-far*0.025);
    fog*=(mat>10.5 && mat<11.5)?0.30:(mat>10.5?1.0:0.55);
    vec3 haze=srgb(vec3(0.62,0.63,0.47))*0.75;
    lit=mix(lit,haze,fog*0.78);
    O=vec4(max(lit,0.0),1);
}
