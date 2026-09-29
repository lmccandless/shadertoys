// Final finish. Everything here either follows the image itself (depth-aware glaze smoothing, halation) or
// the frame (tone, varnish, vignette), so nothing slides over the scene when the camera orbits. All brush,
// grain and impasto texture is anchored to the surfaces in Buffer C.
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
    float protect=(material>5.5 && material<10.5)?0.35:((material>0.5 && material<1.5)?0.30:0.75);
    return mix(center,smoothColor,PAINT_AMOUNT*protect);
}
// Near-identity tone curve with a soft knee: palettes are authored in display values, so only the
// brightest highlights are rolled off (on the largest channel, which keeps their hue).
vec3 filmic(vec3 c) {
    c*=EXPOSURE;
    float m=max(c.r,max(c.g,c.b)),k=0.80;
    float s=m<k?1.0:(k+(1.0-k)*(1.0-exp(-(m-k)/(1.0-k))))/m;
    return clamp(c*s,0.0,1.0);
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
    vec3 c=painted(uv,pixel);
    vec3 glow=vec3(0);
    for(int i=0;i<8;i++) {
        float a=float(i)*0.785398;
        vec2 off=vec2(cos(a),sin(a))*pixel*7.0;
        vec3 s=textureLod(iChannel0,clamp(uv+off,pixel*2.5,1.0-pixel*1.5),0.0).rgb;
        glow+=s*smoothstep(0.50,1.05,luminance(s));
    }
    c+=glow*(0.028/8.0)*vec3(1.0,0.88,0.62);
    c=pow(filmic(c),vec3(1.0/2.2));
    c=varnish(c);
    c+=(hash12(F)-0.5)*0.0030;   // sub-quantisation dither against banding only
    // Vignette: darker toward the barn's right-hand depths and the lower corners, as in the painting.
    vec2 v=(F-0.5*iResolution.xy)/iResolution.xy;
    float vignette=1.0-0.30*dot(v*vec2(0.9,1.0),v*vec2(0.9,1.0));
    vignette*=1.0-0.14*smoothstep(0.05,0.5,v.x)*smoothstep(-0.2,0.5,v.y);
    O=vec4(sat(c*vignette),1);
}
