// Stillness accumulation, reset as soon as the camera changes. No ghost trails.
// iChannel0: current C. iChannel1: previous D. iChannel2: current A.
void mainImage(out vec4 O,in vec2 F) {
    if(!isReady(iChannel0,63.25)||!isReady(iChannel2,61.25)) { O=vec4(0);return; }
    if(all(equal(ivec2(F),ivec2(0)))) { O=vec4(0,0,0,64.25);return; }
    vec3 c=texelFetch(iChannel0,ivec2(F),0).rgb;
    vec4 old=texelFetch(iChannel1,ivec2(F),0);
    float age=texelFetch(iChannel2,ivec2(2,0),0).w;
    bool reset=age<1.0||!isReady(iChannel1,64.25)||iFrame<1;
    float count=reset?1.0:min(old.a+1.0,64.0);
    O=vec4(reset?c:mix(old.rgb,c,1.0/count),count);
}
