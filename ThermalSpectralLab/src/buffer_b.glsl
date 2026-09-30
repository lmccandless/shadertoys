// Deterministic finite-area transport. Geometry counts come from the scene header.
// GGX/Smith model: Filament; finite-sphere representative-point lobe: Karis 2013.
float roughControl,environmentControl,emissionControl,studioBlend,environmentSize,environmentMaxMip,autoLight;int floorMode;int materialControl,compareControl,sphereCount,pathDepth,ambientSamples;
int materialFor(int id){return compareControl==0?materialControl:id;}
float fifth(float x){float x2=x*x;return x2*x2*x;}
// Neutral white studio: a finite honeycomb ceiling field, not an external cubemap asset.
vec3 studioEnvironment(vec3 d,float rough){
 float base=0.035+0.075*smoothstep(-0.25,0.8,d.y);
 float glow=0.0;
 if(d.y>0.03){
 vec2 p=d.xz*(4.2/d.y),period=vec2(1.7320508,3.0);
 vec2 a=mod(p,period)-0.5*period,b=mod(p-0.5*period,period)-0.5*period;
 vec2 q=dot(a,a)<dot(b,b)?a:b;
 float edge=abs(max(abs(q.x),0.5*abs(q.x)+0.8660254*abs(q.y))-0.8660254);
 float width=0.025+rough*rough*0.60;
 float crop=1.0-smoothstep(3.8,5.2,max(abs(p.x),abs(p.y)*1.25));
 glow=4.0*exp(-0.5*edge*edge/(width*width))*(0.025/width)*crop*smoothstep(0.03,0.16,d.y);
 }
 return vec3(base+glow);
}
// One feathered soft key with a faint broad fill; no repeated panel pattern.
float softbox(vec3 d,vec3 axis,vec3 tangent,vec2 size,float rough){
 float z=dot(d,axis);vec2 q=vec2(dot(d,tangent),dot(d,cross(axis,tangent)))/max(z,0.001);
 float blur=0.16+rough*rough*1.2;
 vec2 mask=1.0-smoothstep(size,size+vec2(blur),abs(q));
 return mask.x*mask.y*smoothstep(0.0,0.1,z)*(size.x*size.y)/((size.x+0.5*blur)*(size.y+0.5*blur));
}
vec3 softEnvironment(vec3 d,float rough){
 float base=0.0008+0.0017*smoothstep(-0.4,0.75,d.y);
 float key=softbox(d,vec3(-0.6,0.8,0),vec3(0,0,1),vec2(0.90,0.50),rough);
 float f=max(dot(d,vec3(0.8,0.6,0)),0.0);f*=f;
 return vec3(base+1.8*key+0.04*f*f);
}
vec3 environment(vec3 d,float rough){
 // Piecewise smooth weights preserve the two previous looks and smoothly visit all three.
 float hexWeight=smoothstep(0.0,1.0,studioBlend)*(1.0-smoothstep(1.0,2.0,studioBlend));
 float softWeight=smoothstep(1.0,2.0,studioBlend),cubeWeight=1.0-smoothstep(0.0,1.0,studioBlend);
 vec3 c=vec3(0);
 if(cubeWeight>0.0001){
 float lod=clamp(log2(1.0+rough*rough*environmentSize*0.45),0.0,environmentMaxMip);
 vec3 cube=max(textureLod(iChannel1,d,lod).rgb,vec3(0));
 cube=mix(cube/12.92,pow((cube+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),cube));
 c+=cube*cubeWeight;
 }
 if(hexWeight>0.0001)c+=studioEnvironment(d,rough)*hexWeight;
 if(softWeight>0.0001)c+=softEnvironment(d,rough)*softWeight;
 return c*environmentControl*autoLight;
}
float intersection(vec3 o,vec3 d,out int id){
 float dist=1e5;id=-1;
 for(int m=0;m<sphereCount;m++){float h=sphere(o,d,centre(m),0.92);if(h<dist){dist=h;id=m;}}
 if(d.y< -0.0001){float h=-o.y/d.y;if(h>0.001&&h<dist){dist=h;id=6;}}
 return dist;
}
// D65-reference tristimulus reflectance; colored illumination remains an RGB approximation.
vec3 fresnelRGB(float c,int mat){
 if(mat==6)return vec3(0.04+0.96*fifth(1.0-c));
 if(mat>=4)return vec3(mat==4?ceramic(c):0.0);
 float q=clamp(c,0.0,1.0)*127.0;int lo=int(floor(q));
 return mix(texelFetch(iChannel0,ivec2(lo,64+mat),0).rgb,texelFetch(iChannel0,ivec2(min(lo+1,127),64+mat),0).rgb,fract(q));
}
float temperature(int id){return clamp((compareControl==1?1800.0:TEMPERATURE_K+float(id)*TEMPERATURE_STEP_K)+texelFetch(iChannel0,ivec2(META,0),0).z,500.0,6500.0);}
vec3 emission(int id,float mu){
 float T=temperature(id);vec3 x=thermal(iChannel0,materialFor(id),T,mu);
 return rgb(x)*thermalRadianceScale(emissionControl);
}
#if QUALITY==0
// Lite soft shadow: the same apparent-disk overlap, estimated from small-angle sines
// with a smooth ramp instead of the exact lens area (no asin/atan/acos per occluder).
float visibility(vec3 p,vec3 source,float radius,int lightID,int owner){
 vec3 q=source-p;float distance=length(q);vec3 direction=q/max(distance,0.001);
 float a=min(radius/max(distance,0.001),0.9999),transmission=1.0;
 for(int k=0;k<sphereCount;k++){
 if(k==lightID||k==owner)continue;
 vec3 o=centre(k)-p;float d=length(o);
 if(d>=distance||d<0.9201)continue;
 float c=dot(direction,o)/d;if(c<=0.0)continue;
 float b=min(0.92/d,0.9999),separation=sqrt(max(1.0-c*c,0.0));
 float t=clamp((a+b-separation)/(2.0*min(a,b)),0.0,1.0);
 transmission*=1.0-t*t*(3.0-2.0*t)*min(1.0,b*b/(a*a));
 }
 return transmission;
}
#else
// Fraction of one apparent angular disk covered by another. Exact planar disk overlap;
// angular-disk projection is an approximation to spherical-cap visibility.
float diskCover(float a,float b,float d){
 if(d>=a+b)return 0.0;
 if(d<=abs(a-b)){float r=min(a,b);return clamp(r*r/(a*a),0.0,1.0);}
 float d2=d*d,a2=a*a,b2=b*b;
 float x=clamp((d2+a2-b2)/(2.0*d*a),-1.0,1.0),y=clamp((d2+b2-a2)/(2.0*d*b),-1.0,1.0);
 float product=max(0.0,(-d+a+b)*(d+a-b)*(d-a+b)*(d+a+b));
 return clamp((a2*acos(x)+b2*acos(y)-0.5*sqrt(product))/(PI*a2),0.0,1.0);
}
float visibility(vec3 p,vec3 source,float radius,int lightID,int owner){
 vec3 q=source-p;float distance=length(q);vec3 direction=q/max(distance,0.001);
 float a=asin(clamp(radius/max(distance,0.001),0.0001,0.9999)),transmission=1.0;
 for(int k=0;k<sphereCount;k++){
 if(k==lightID||k==owner)continue;
 vec3 o=centre(k)-p;float d=length(o);
 if(d>=distance||d<0.9201)continue;
 vec3 od=o/d;float c=dot(direction,od);if(c<=0.0)continue;
 float b=asin(clamp(0.92/d,0.0001,0.9999));
 float separation=atan(length(cross(direction,od)),c);
 transmission*=1.0-diskCover(a,b,separation);
 }
 return transmission;
}
#endif
float ambientVisibility(vec3 p,vec3 n,int owner){
 float visible=1.0;
 for(int k=0;k<sphereCount;k++){
 if(k==owner)continue;
 vec3 q=centre(k)-p;float d2=max(dot(q,q),0.8465);float cosine=max(dot(n,q)*inversesqrt(d2),0.0);
 // Projected solid angle. Unlike a painted Gaussian, this follows actual geometry.
 float area=0.8464;
 visible*=1.0-clamp(area/d2*cosine,0.0,0.995);
 }
 if(owner<6)visible*=0.5+0.5*n.y; // Ground hemisphere occlusion; ground bounce is traced.
 return clamp(visible,0.015,1.0);
}
float ggxSpecular(float NoV,float NoL,float NoH,float alpha){
 float a2=alpha*alpha,den=1.0+(a2-1.0)*NoH*NoH;
 float D=a2/(PI*den*den);
 float gv=NoL*sqrt(NoV*NoV*(1.0-a2)+a2),gl=NoV*sqrt(NoL*NoL*(1.0-a2)+a2);
 return D*0.5/max(gv+gl,0.0001)*NoL;
}
void surfaceLighting(vec3 p,vec3 n,vec3 v,int owner,int mat,float rough,vec3 base,bool shadows,out vec3 diffuse,out vec3 specular,out float ao){
 float NoV=max(dot(n,v),0.001),alpha=max(rough*rough,0.002);vec3 reflection=reflect(-v,n);
 ao=ambientVisibility(p,n,owner);
 // One shared environment call inside a data-bounded loop instead of three inline trees.
 vec3 ambient=vec3(0);
 for(int tap=0;tap<ambientSamples;tap++){
 vec3 direction=tap==0?n:normalize(n+vec3(tap==1?1.0:-1.0,0.2,0));
 ambient+=environment(direction,0.95)*(ambientSamples==1?1.0:(tap==0?0.5:0.25));
 }
 ambient*=ao;
 diffuse=base*ambient;specular=vec3(0);
 for(int j=0;j<=sphereCount;j++){
 if(j==owner&&j<sphereCount)continue;
 bool lamp=j==sphereCount;vec3 source=lamp?vec3(-3.5,7,2):centre(j);
 vec3 q=source-p;float d2=max(dot(q,q),0.8465),distance=sqrt(d2);vec3 l=q/distance;
 vec3 energy=lamp?vec3(4.0*autoLight):texelFetch(iChannel0,ivec2(META+j,1),0).rgb;
 if(max(energy.r,max(energy.g,energy.b))<0.00001)continue;
 float vis=shadows?visibility(p+n*0.002,source,lamp?1.3:0.92,lamp?-1:j,owner):1.0;
 if(lamp){diffuse+=base*energy*max(dot(n,l),0.0)*1.69/d2*vis;continue;}
 float radius=0.92;
 float nl=dot(n,l),angular=radius/distance;
 // Smooth horizon clipping; the fully visible sphere uses its exact diffuse form factor.
 float cosine=nl>=angular?nl:(nl<=-angular?0.0:(nl+angular)*(nl+angular)/(4.0*angular));
 diffuse+=base*energy*(0.8464/d2)*cosine*vis;
 vec3 toRay=reflection*max(dot(q,reflection),0.0)-q;
 vec3 closest=q+toRay*clamp(radius/max(length(toRay),0.001),0.0,1.0);
 vec3 ls=normalize(closest),h=normalize(ls+v);float NoL=max(dot(n,ls),0.001),NoH=max(dot(n,h),0.0);
 float broadened=min(1.0,alpha+radius/(2.0*distance));
 vec3 F=fresnelRGB(max(dot(ls,h),0.001),mat);
 vec3 response=F*ggxSpecular(NoV,NoL,NoH,broadened)*(PI*0.8464/d2);
 specular+=energy*min(response,F)*vis;
 }
}
vec3 trace(vec3 o,vec3 d){
 vec3 radiance=vec3(0),weight=vec3(1);float coneRough=0.0;bool terminalEnvironment=false;
 for(int bounce=0;bounce<pathDepth;bounce++){
 int id;float dist=intersection(o,d,id);
 if(id<0){terminalEnvironment=true;break;}
 vec3 p=o+d*dist,v=-d,n=id<6?normalize(p-centre(id)):vec3(0,1,0);
 float nv=max(dot(n,v),0.0001);int mat=id==6?6:materialFor(id);
 if(id<6){radiance+=weight*emission(id,nv);if(mat==5)break;}
 float rough=id==6?(floorMode==0?0.19:(floorMode==1?0.43:0.82)):roughControl;
 vec3 base=id==6?vec3(floorMode==0?0.20:(floorMode==1?0.22:0.24)):(mat==4?vec3(DIELECTRIC_BASE):vec3(0));
 vec3 F=fresnelRGB(nv,mat),diffuse,specular;float ao;
 // Lite: soft shadows on the directly visible surface only; reflections are lit unshadowed.
 surfaceLighting(p,n,v,id,mat,rough,base,QUALITY>0||bounce==0,diffuse,specular,ao);
 // Retain exact specular ray paths near the mirror limit; transfer the broad lobe
 // to deterministic finite-area GGX lighting and filtered environment reflection.
 float delta=exp(-18.0*rough*rough),broad=1.0-delta;
 float specAO=clamp(pow(nv+ao,exp2(-16.0*rough-1.0))-1.0+ao,0.0,1.0);
 vec3 reflected=reflect(d,n);
 radiance+=weight*((vec3(1)-F)*diffuse+broad*(specular+F*environment(reflected,max(rough,coneRough))*specAO));
 weight*=F*delta;d=reflected;coneRough=max(coneRough,rough);
 o=p+n*0.003;
 if(max(weight.r,max(weight.g,weight.b))<0.0003)break;
 if(bounce==pathDepth-1)terminalEnvironment=true;
 }
 // Misses and exhausted paths share a single terminal environment evaluation.
 if(terminalEnvironment)radiance+=weight*environment(d,coneRough);
 return radiance;
}
void mainImage(out vec4 O,in vec2 P){
 bool ready=passReady(texelFetch(iChannel0,ivec2((META+10),0),0),154.0)&&texelFetch(iChannel0,ivec2(META,1),0).a==31.0&&texelFetch(iChannel0,ivec2((META+5),1),0).a==31.0;
 if(!ready){O=vec4(0);return;}
 if(all(equal(ivec2(P),ivec2((META+10),0)))){O=vec4(211,SPECTRAL_TAG,STATE_TAG,1);return;}
 // Only the lower-left scale*resolution block is traced; Image upsamples it.
 float scale=clamp(texelFetch(iChannel0,ivec2(META+18,0),0).x,0.05,1.0);
 ivec2 size=sceneSize(iResolution.xy,scale);
 if(P.x>=float(size.x)||P.y>=float(size.y)){O=vec4(0);return;}
 vec2 screen=P/scale; // Pixel-centre position in full-resolution screen space.
 vec4 settings=texelFetch(iChannel0,ivec2((META+3),0),0),options=texelFetch(iChannel0,ivec2((META+4),0),0),scene=texelFetch(iChannel0,ivec2((META+9),0),0);
 vec4 renderSettings=texelFetch(iChannel0,ivec2((META+16),0),0);floorMode=clamp(int(renderSettings.x+0.5),0,2);
 studioBlend=clamp(renderSettings.z,0.0,2.0);
 float referenceGain=max(texelFetch(iChannel0,ivec2((META+6),1),0).x,1e-12);
 // Presentation auto mode adapts EXTERNAL lighting with camera exposure, capped at64x.
 // This preserves reflective form without adding fake shading to emitted radiance.
 // All three environments and the lamp receive the same neutral scalar; raw mode is1x.
 autoLight=texelFetch(iChannel0,ivec2((META+2),0),0).y>0.0?min(1.0/referenceGain,64.0):1.0;
 ambientSamples=clamp(int(scene.w+0.5),1,3);sphereCount=clamp(int(scene.x+0.5),1,6);pathDepth=clamp(int(scene.z+0.5),1,4);int samples=clamp(int(scene.y+0.5),1,4);
 roughControl=settings.y;environmentControl=settings.w;emissionControl=options.z;materialControl=int(options.x+0.5);compareControl=int(texelFetch(iChannel0,ivec2((META+5),0),0).x+0.5);
 environmentSize=float(textureSize(iChannel1,0).x);environmentMaxMip=max(0.0,log2(environmentSize)-1.0);
 vec2 angles=texelFetch(iChannel0,ivec2(META,0),0).xy;
 vec3 target=texelFetch(iChannel0,ivec2((META+12),0),0).xyz,o=target+texelFetch(iChannel0,ivec2((META+8),0),0).x*vec3(sin(angles.x)*cos(angles.y),sin(angles.y),cos(angles.x)*cos(angles.y));
 vec3 forward=normalize(target-o),right=normalize(cross(forward,vec3(0,1,0))),up=cross(right,forward);vec3 color=vec3(0);
 for(int j=0;j<samples;j++){
 vec2 jitter=samples==1?vec2(0):vec2(j%2==0?-0.25:0.25,j<2?-0.25:0.25);
 vec2 uv=(screen+jitter/scale-vec2(0.5*iResolution.x,0.5*iResolution.y+(SCENE_Y-247.5)*iResolution.y/495.0))/iResolution.y;
 vec3 d=normalize(forward*1.55+right*uv.x+up*uv.y);color+=trace(o,d)/float(samples);
 }
 // Display normalization scales ALL scene radiance once, before bloom and SDR mapping.
 O=vec4(color*settings.z*max(referenceGain,1e-12),1);
}
