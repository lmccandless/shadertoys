// Camera state + a one-time, seamless multiscale pigment/noise atlas.
// iChannel0: Buffer A (previous frame).
float periodicNoise(vec2 uv,float cells) {
    vec2 p=uv*cells,i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash12(mod(i,cells)),hash12(mod(i+vec2(1,0),cells)),f.x),
               mix(hash12(mod(i+vec2(0,1),cells)),hash12(mod(i+vec2(1,1),cells)),f.x),f.y);
}
void mainImage(out vec4 O,in vec2 F) {
    ivec2 ip=ivec2(F);
    bool valid=isReady(iChannel0,61.25)&&all(equal(ivec2(texelFetch(iChannel0,ivec2(0),0).xy),ivec2(iResolution.xy)));
    if(ip.y==0 && ip.x<4) {
        vec4 old=valid?texelFetch(iChannel0,ivec2(1,0),0):vec4(0);
        vec4 ctrl=valid?texelFetch(iChannel0,ivec2(2,0),0):vec4(iMouse.xy,0,0);
        vec2 goal=old.zw;
        float lastPress=valid?texelFetch(iChannel0,ivec2(3,0),0).z:-10.0;
        bool down=iMouse.z>0.0;
        if(down && ctrl.z<0.5) {
            if(valid && iTime-lastPress<0.32) goal=vec2(0);
            lastPress=iTime;
        }
        if(valid && down && ctrl.z>0.5) goal+=(iMouse.xy-ctrl.xy)/iResolution.xy*vec2(0.95,0.78);
        goal=clamp(goal,vec2(-ORBIT_LIMIT),vec2(ORBIT_LIMIT));
        float dt=clamp(iTimeDelta,1.0/240.0,1.0/20.0);
        vec2 angle=mix(old.xy,goal,1.0-exp(-dt*13.0));
        if(length(angle-goal)<0.00002) angle=goal;
        float age=(valid && length(angle-old.xy)<0.000002)?ctrl.w+1.0:0.0;
        if(ip.x==0) O=vec4(iResolution.xy,0,61.25);
        else if(ip.x==1) O=vec4(angle,goal);
        else if(ip.x==2) O=vec4(iMouse.xy,down?1.0:0.0,min(age,4096.0));
        else O=vec4(old.xy,lastPress,0);
        return;
    }
    if(valid) { O=texelFetch(iChannel0,ip,0); return; }
    vec2 uv=F/iResolution.xy;
    float n8=periodicNoise(uv,8.0),n16=periodicNoise(uv,16.0);
    float n32=periodicNoise(uv,32.0),n64=periodicNoise(uv,64.0);
    float n128=periodicNoise(uv,128.0),n256=periodicNoise(uv,256.0);
    O=vec4(0.52*n8+0.28*n16+0.14*n32+0.06*n64,
           0.56*n32+0.28*n64+0.16*n128,
           0.62*n128+0.38*n256,n256);
}
