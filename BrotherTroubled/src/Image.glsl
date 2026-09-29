// Edge-preserving oil glazes, restrained halation, a filmic shoulder and linen tooth.
// iChannel0: accumulated D. iChannel1: geometry B. iChannel2: pigment A.
vec3 painted(vec2 uv,vec2 pixel) {
    vec3 center=textureLod(iChannel0,uv,0.0).rgb;
    float depth=textureLod(iChannel1,uv,0.0).b;
    float material=textureLod(iChannel1,uv,0.0).a;
    float radius=mix(1.55,2.15,step(10.5,material));
    vec3 m0=vec3(0),m1=vec3(0),m2=vec3(0),m3=vec3(0);
    vec4 variance=vec4(0),weight=vec4(0);
    // Four overlapping quadrants reuse the same 25 fetches, no dynamic arrays.
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        vec2 off=vec2(float(x),float(y))*pixel*radius*0.5;
        vec2 at=clamp(uv+off,pixel*2.5,1.0-pixel*1.5);
        vec3 c=textureLod(iChannel0,at,0.0).rgb;
        float z=textureLod(iChannel1,at,0.0).b;
        float w=exp(-abs(z-depth)*9.0)*exp(-float(x*x+y*y)*0.14);
        float v=luminance(c);v*=v;
        if(x<=0 && y<=0) {m0+=c*w;variance.x+=v*w;weight.x+=w;}
        if(x>=0 && y<=0) {m1+=c*w;variance.y+=v*w;weight.y+=w;}
        if(x>=0 && y>=0) {m2+=c*w;variance.z+=v*w;weight.z+=w;}
        if(x<=0 && y>=0) {m3+=c*w;variance.w+=v*w;weight.w+=w;}
    }
    weight=max(weight,0.001);
    m0/=weight.x;m1/=weight.y;m2/=weight.z;m3/=weight.w;
    vec4 means=vec4(luminance(m0),luminance(m1),luminance(m2),luminance(m3));
    variance=max(variance/weight-means*means,0.0);
    vec4 certainty=1.0/(1.0+sq(250.0)*variance*variance);
    vec3 smoothColor=(m0*certainty.x+m1*certainty.y+m2*certainty.z+m3*certainty.w)/dot(certainty,vec4(1));
    float protect=(material>5.5 && material<10.5)?0.35:((material>0.5 && material<1.5)?0.55:1.0);
    return mix(center,smoothColor,PAINT_AMOUNT*protect);
}
vec3 brushGlaze(vec3 color,vec2 fc,vec2 pixel) {
    vec4 geom=textureLod(iChannel1,fc*pixel,0.0);
    float material=geom.a;
    if(material>5.5 && material<10.5)return color;
    // Loose paint is deposited in short, overlapping, irregular bristle marks.
    // Its color is sampled from the rendered form; depth rejection protects silhouettes.
    float angle=material<0.5?0.17:(material<1.5?1.17:(material<2.5?0.14:1.49));
    mat2 frame=rot(angle);
    float resolutionScale=max(iResolution.y/668.0,0.6);
    vec2 size=vec2(8.0,3.2)*resolutionScale;
    vec2 q=frame*fc;
    for(int layer=0;layer<2;layer++) {
        vec2 shift=vec2(float(layer)*0.47,float(layer)*0.53);
        vec2 grid=floor(q/size+shift);
        vec2 random=hash22(grid+float(layer)*73.0);
        vec2 center=(grid+0.5-shift+(random-0.5)*0.38)*size;
        vec2 delta=(q-center)/size;
        float daub=1.0-smoothstep(0.34,0.54,length(delta*vec2(1.0,1.25)));
        float fringe=0.8+0.2*sin(delta.x*43.0+random.x*6.283);
        vec2 target=clamp(transpose(frame)*center*pixel,pixel*2.5,1.0-pixel*1.5);
        float z=textureLod(iChannel1,target,0.0).b;
        vec3 ink=textureLod(iChannel0,target,0.0).rgb;
        float safe=exp(-abs(z-geom.b)*24.0)*exp(-abs(luminance(ink)-luminance(color))*18.0);
        ink*=mix(vec3(0.966,0.970,0.944),vec3(1.048,1.023,1.009),random.y);
        color=mix(color,ink,PAINT_AMOUNT*0.52*daub*fringe*safe);
    }
    return color;
}
// Short bristle dashes laid on the canvas itself (not on the object): the way the painter built the
// woolly coat and the straw-strewn floor. Returns a signed amount: > 0 light ridge, < 0 dark gap.
float dashLayer(vec2 fc,float cell,float seed,float ang,float spread,float len,float wid,float density) {
    float acc=0.0;
    vec2 g=floor(fc/cell);
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++) {
        vec2 id=g+vec2(float(i),float(j));
        vec3 r=vec3(hash12(id+seed),hash12(id+seed+17.0),hash12(id+seed+41.0));
        if(r.z>density) continue;
        vec2 c=(id+0.15+0.7*r.xy)*cell;
        vec2 d=rot(ang+(r.x-0.5)*spread)*(fc-c);
        float along=1.0-smoothstep(len*0.55,len,abs(d.x));
        float across=1.0-smoothstep(wid,wid*2.0,abs(d.y+(r.y-0.5)*0.5*d.x*d.x/len));
        acc+=(r.y>0.46?1.0:-1.0)*along*across*(0.55+0.45*r.z/density);
    }
    return clamp(acc,-1.0,1.0);
}
vec3 bristles(vec3 c,vec2 fc,float material) {
    float k=max(iResolution.y/668.0,0.6);
    if(material>0.5 && material<1.5) {
        float a=dashLayer(fc,6.0*k,3.0,1.30,1.0,9.0*k,1.1*k,0.62);
        a=clamp(a+0.8*dashLayer(fc+13.0,4.0*k,29.0,1.15,1.4,6.0*k,0.9*k,0.55),-1.0,1.0);
        c=mix(c,c*vec3(0.83,0.83,0.70),0.75*sat(-a));
        c=mix(c,c*vec3(1.08,1.075,1.04)+0.015,0.65*sat(a));
    } else if(material>1.5 && material<2.5) {
        float a=dashLayer(fc,13.0*k,5.0,0.10,2.2,17.0*k,1.2*k,0.36);
        a+=0.8*dashLayer(fc+31.0,9.0*k,61.0,0.55,3.0,9.0*k,1.0*k,0.28);
        c=mix(c,c*vec3(0.80,0.76,0.68),0.38*sat(-a));
        c=mix(c,c+vec3(0.08,0.06,0.025),0.38*sat(a));
    }
    return c;
}
// Near-identity tone curve with a soft knee: palettes are authored in display values, so only the
// brightest highlights are rolled off (on the largest channel, which keeps their hue).
vec3 filmic(vec3 c) {
    c*=EXPOSURE;
    float m=max(c.r,max(c.g,c.b)),k=0.80;
    float s=m<k?1.0:(k+(1.0-k)*(1.0-exp(-(m-k)/(1.0-k))))/m;
    return clamp(c*s,0.0,1.0);
}
// Fine craquelure: the edges of a jittered cell network, a faint dark hairline in aged varnish.
float craquelure(vec2 p) {
    vec2 g=floor(p),f=fract(p);
    float d1=8.0,d2=8.0;
    for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++) {
        vec2 o=vec2(float(i),float(j)),r=o+hash22(g+o)-f;
        float d=dot(r,r);
        if(d<d1){d2=d1;d1=d;} else if(d<d2) d2=d;
    }
    return 1.0-smoothstep(0.0,0.06,sqrt(d2)-sqrt(d1));
}
// Aged-oil grade: a yellowed varnish veil, umber-lifted blacks, a soft highlight shoulder and a little
// less chroma, the way a 19th-century canvas photographs under gallery light.
vec3 varnish(vec3 c) {
    float l=luminance(c);
    c=mix(vec3(l),c,0.90);
    c=c/(1.0+0.12*max(c-0.78,0.0)/0.22);
    c*=vec3(1.015,0.995,0.935);
    vec3 d=1.0-c;
    return c+vec3(0.060,0.047,0.028)*d*d*d;
}
void mainImage(out vec4 O,in vec2 F) {
    if(!isReady(iChannel0,64.25)) { O=vec4(0.075,0.059,0.031,1);return; }
    vec2 pixel=1.0/iResolution.xy,uv=clamp(F*pixel,pixel*2.5,1.0-pixel*1.5);
    vec3 c=brushGlaze(painted(uv,pixel),uv*iResolution.xy,pixel);
    c=bristles(c,F,textureLod(iChannel1,uv,0.0).a);
    vec3 glow=vec3(0);
    for(int i=0;i<8;i++) {
        float a=float(i)*0.785398;
        vec2 off=vec2(cos(a),sin(a))*pixel*7.0;
        vec3 s=textureLod(iChannel0,clamp(uv+off,pixel*2.5,1.0-pixel*1.5),0.0).rgb;
        glow+=s*smoothstep(0.50,1.05,luminance(s));
    }
    c+=glow*(0.028/8.0)*vec3(1.0,0.88,0.62);
    c=pow(filmic(c),vec3(1.0/2.2));
    // Canvas-fixed paint relief is subtle enough not to obscure the eye or coat.
    vec4 tooth=pigment(iChannel2,uv*vec2(1.17,0.89)+vec2(0.043,0.071));
    float weave=sin(F.x*2.12)*sin(F.y*2.12);
    vec2 strokeUV=rot(0.32)*uv*vec2(4.2,1.25)+vec2(tooth.r*0.08,tooth.g*0.09);
    float stroke=pigment(iChannel2,strokeUV).g;
    float bristles=tooth.b-0.5;
    c*=1.0+PAINT_AMOUNT*0.075*(stroke-0.5);
    c*=1.0+PAINT_AMOUNT*(bristles*0.11+weave*0.008);
    // Impasto grain: dry-brushed pigment catches on the canvas tooth, strongest in the light passages.
    float grain=0.6*(hash12(F)-0.5)+0.4*(hash12(floor(F*0.5)+7.0)-0.5);
    c*=1.0+0.16*grain*(0.4+0.6*luminance(c));
    c*=1.0-0.055*craquelure(F/(9.0*max(iResolution.y/668.0,0.6)))*smoothstep(0.15,0.6,luminance(c));
    c=varnish(c);
    c+=(hash12(F)-0.5)*0.0030;
    // Vignette: darker toward the barn's right-hand depths and the lower corners, as in the painting.
    vec2 v=(F-0.5*iResolution.xy)/iResolution.xy;
    float vignette=1.0-0.30*dot(v*vec2(0.9,1.0),v*vec2(0.9,1.0));
    vignette*=1.0-0.14*smoothstep(0.05,0.5,v.x)*smoothstep(-0.2,0.5,v.y);
    c*=vignette;
    O=vec4(sat(c),1);
}
