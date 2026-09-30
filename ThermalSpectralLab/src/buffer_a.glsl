// Camera springs, controls, emitter averages and exact spectral integration.
float keyDown(int code){return step(0.5,texelFetch(iChannel2,ivec2(code,0),0).r);}
float keyPressed(int code){return step(0.5,texelFetch(iChannel2,ivec2(code,1),0).r);}
void mainImage(out vec4 O,in vec2 P){
 ivec2 p=ivec2(P);
 // Everything A owns lies in x<=META+18, y<68: the rest of the buffer is idle.
 if(p.x>META+18||p.y>=68){O=vec4(0);return;}
 bool dataReady=spectralReady(texelFetch(iChannel1,ivec2(SPECTRAL_COUNT,0),0));
 if(p.y==0 && p.x>=META && p.x<=META+18){
 vec4 old=texelFetch(iChannel0,ivec2(META,0),0),prev=texelFetch(iChannel0,ivec2((META+1),0),0);
 vec4 c0=texelFetch(iChannel0,ivec2((META+3),0),0),c1=texelFetch(iChannel0,ivec2((META+4),0),0),uiState=texelFetch(iChannel0,ivec2((META+5),0),0);
 vec4 targetState=texelFetch(iChannel0,ivec2((META+6),0),0),spring=texelFetch(iChannel0,ivec2((META+7),0),0);
 vec4 zoom=texelFetch(iChannel0,ivec2((META+8),0),0);
 vec4 pan=texelFetch(iChannel0,ivec2((META+12),0),0),panGoal=texelFetch(iChannel0,ivec2((META+13),0),0),panSpring=texelFetch(iChannel0,ivec2((META+14),0),0),prefs=texelFetch(iChannel0,ivec2((META+15),0),0);
 vec4 renderSettings=texelFetch(iChannel0,ivec2((META+16),0),0),zoomKey=texelFetch(iChannel0,ivec2((META+17),0),0),resolution=texelFetch(iChannel0,ivec2(META+18,0),0);
 float tempNorm=texelFetch(iChannel0,ivec2((META+2),0),0).y;
 bool initial=old.w!=STATE_TAG||any(isnan(old))||any(isinf(old))||zoom.x<4.0||zoom.x>23.0;
 if(initial){old=vec4(2.625,0.50,-800,STATE_TAG);c0=vec4(-800,ROUGHNESS,1.15,ENVIRONMENT_STRENGTH);c1=vec4(float(MATERIAL),AUTO_HEAT,EMISSION_LEVEL,HEAT_SPEED);uiState=vec4(1,0,1,2);targetState=vec4(old.xy,0,-10);spring=vec4(0,0,1,1);zoom=vec4(CAMERA_DISTANCE,CAMERA_DISTANCE,0,1);pan=vec4(0,0.25,0,STATE_TAG);panGoal=pan;panSpring=vec4(0);prefs=vec4(1,0,0,1);renderSettings=vec4(0,2,2,0);zoomKey=vec4(0);tempNorm=0.35;resolution=vec4(0);}
 float dt=clamp(iTimeDelta,0.001,0.05),mode=uiState.x,advanced=uiState.y;
 vec4 previousOptions=c1,previousPrefs=prefs,previousRender=renderSettings;
 if(initial)prev=vec4(0,0,0,-1);
 bool down=iMouse.z>0.0,newClick=down&&prev.z<=0.0;
 int hit=down?(newClick?uiHit(abs(iMouse.zw),iResolution.xy,advanced,prefs):int(prev.w)):-1;
 vec2 q=iMouse.xy*vec2(880,495)/iResolution.xy;float x=sliderValue(q,hit);
 bool animatedBefore=c1.y>0.5;
 if(down){
 if(hit==0){c0.x=mix(-800.0,2000.0,x);c1.y=0.0;}
 if(hit==1)c0.y=mix(0.015,0.6,x);
 if(hit==2)c0.z=exp2(mix(-2.0,2.0,x));
 if(hit==3)c0.w=mix(0.0,2.0,x);
 if(hit==4)c1.z=x;
 if(hit==6)zoom.y=mix(22.0,4.6,x);
 if(hit==5)c1.w=mix(0.25,2.0,x);
 if(hit==8&&newClick){c1.x=float(clamp(int((q.x-188.0)/30.0),0,5));mode=0.0;}
 if(hit>=10&&hit<=12&&newClick)mode=float(hit-10);
 if(hit==16&&newClick)prefs.z=float(clamp(int((q.x-394.0)/28.0),0,2));
 if(hit==17&&newClick)renderSettings.x=q.y<21.0?float(clamp(int((q.x-310.0)/56.0),0,2)):mod(renderSettings.x+1.0,3.0);
 if(hit==18&&newClick)renderSettings.y=q.y<21.0?(q.x<536.0?0.0:(q.x<600.0?1.0:2.0)):mod(renderSettings.y+1.0,3.0);
 }
 // Keyboard row 1 supplies press edges: toggles never repeat while held.
 if((newClick&&hit==7)||keyPressed(80)>0.5){if(c1.y>0.5)c0.x=old.z;c1.y=1.0-c1.y;}
 if((newClick&&hit==13)||keyPressed(82)>0.5)advanced=1.0-advanced;
 if((newClick&&hit==14)||keyPressed(76)>0.5)prefs.x=1.0-prefs.x;
 if((newClick&&hit==15)||keyPressed(73)>0.5)prefs.y=1.0-prefs.y;
 if(keyPressed(49)>0.5)mode=0.0;
 if(keyPressed(50)>0.5)mode=1.0;
 if(keyPressed(51)>0.5)mode=2.0;
 if(keyPressed(77)>0.5){c1.x=mod(c1.x+1.0,6.0);mode=0.0;}
 if(keyPressed(71)>0.5)renderSettings.x=mod(renderSettings.x+1.0,3.0);
 if(keyPressed(72)>0.5)renderSettings.y=mod(renderSettings.y+1.0,3.0);
 if((newClick&&hit==20)||keyPressed(78)>0.5)tempNorm=tempNorm>0.0?0.0:0.35;
 if(keyPressed(85)>0.5)prefs.z=mod(prefs.z+1.0,3.0);
 // Resume from the current temperature and keep the previous sweep direction.
 if(!animatedBefore&&c1.y>0.5){
 float phase=acos(clamp((-50.0-old.z)/750.0,-1.0,1.0));
 targetState.z=sin(targetState.z)>=0.0?phase:2.0*PI-phase;spring.w=0.0;
 }
 bool dragging=down&&hit==-1;
 if((dragging&&newClick)||(animatedBefore&&c1.y<0.5)){targetState.xy=old.xy;spring.z=0.0;}
 if(dragging){
 targetState.w=iTime;
 if(prev.z>0.0){vec2 delta=(iMouse.xy-prev.xy)*vec2(880,495)/iResolution.xy;targetState.xy+=delta*vec2(-0.0048,0.0034);}
 }
 // Translate the orbit center in the camera's ground-plane axes.
 vec2 keys=vec2(max(keyDown(68),keyDown(39))-max(keyDown(65),keyDown(37)),max(keyDown(87),keyDown(38))-max(keyDown(83),keyDown(40)));
 keys/=max(1.0,length(keys));
 if(dot(keys,keys)>0.0){
 vec2 right=vec2(cos(old.x),-sin(old.x)),forward=-vec2(sin(old.x),cos(old.x));
 panGoal.xz+=(right*keys.x+forward*keys.y)*2.8*dt;targetState.w=iTime;
 }
 float panOmega=10.0,pe=exp(-panOmega*dt);vec3 pd=pan.xyz-panGoal.xyz,pt=(panSpring.xyz+panOmega*pd)*dt;
 pan.xyz=panGoal.xyz+(pd+pt)*pe;panSpring.xyz=(panSpring.xyz-panOmega*pt)*pe;
 targetState.y=clamp(targetState.y,0.18,1.48);
 // Stored phase freezes on pause; a cosine starts gently at exactly1000 K in View.
 if(c1.y>0.5&&!initial)targetState.z=mod(targetState.z+dt*c1.w,2.0*PI);
 float axis=keyDown(81)-keyDown(69);
 // zoomKey.z/w are the tour's idle clock/step; x/y retain manual zoom inertia.
 bool manualTour=keyPressed(78)>0.5||down||dot(keys,keys)>0.0||axis!=0.0||mode!=uiState.x||advanced!=uiState.y||any(notEqual(c1,previousOptions))||any(notEqual(prefs,previousPrefs))||any(notEqual(renderSettings.xy,previousRender.xy));
 if(manualTour){targetState.w=iTime;zoomKey.z=0.0;}
 else if(c1.y>0.5){
 zoomKey.z+=dt;
 // Change one feature per 24s stop, near the cool end of the thermal cycle.
 if(zoomKey.z>=24.0&&cos(targetState.z)>0.98){
 zoomKey.z=0.0;zoomKey.w=mod(zoomKey.w+1.0,8.0);int stop=int(zoomKey.w+0.5);
 if(stop==1)renderSettings.y=1.0;
 else if(stop==2)renderSettings.x=1.0;
 else if(stop==3)mode=2.0;
 else if(stop==4)renderSettings.x=2.0;
 else if(stop==5)renderSettings.y=0.0;
 else if(stop==6)mode=1.0;
 else if(stop==7)renderSettings.y=2.0;
 else renderSettings.x=0.0;
 }
 }
 float orbit=c1.y>0.5&&!down&&iTime-targetState.w>4.0?1.0:0.0;
 spring.z=mix(spring.z,orbit,1.0-exp(-dt*2.0));
 // Camera xz=(sin(yaw),cos(yaw)); decreasing yaw is clockwise viewed from +Y.
 if(orbit>0.5)targetState.x-=dt*spring.z*(2.0*PI/48.0);
 vec2 desired=targetState.xy;desired.y=clamp(desired.y,0.18,1.48);
 // Exact critically damped spring integration: no frame-dependent lerp stiffness.
 float omega=13.0,e=exp(-omega*dt);vec2 error=old.xy-desired,temp=(spring.xy+omega*error)*dt;
 vec2 angles=desired+(error+temp)*e;spring.xy=(spring.xy-omega*temp)*e;
 // Q backs away, E moves closer. Logarithmic speed feels consistent at all distances.
 if(axis!=0.0&&axis!=zoomKey.y)zoomKey.x=0.0;
 float ramp=axis==0.0?12.0:3.2;
 zoomKey.x=mix(zoomKey.x,axis*0.72,1.0-exp(-dt*ramp));zoomKey.y=axis;
 if(down&&hit==6)zoomKey.x=0.0;
 else zoom.y=clamp(zoom.y*exp(zoomKey.x*dt),4.6,22.0);
 if(axis!=0.0)targetState.w=iTime;
 renderSettings.z=mix(renderSettings.z,renderSettings.y,1.0-exp(-dt*7.0));
 float zd=zoom.x-zoom.y,zt=(zoom.z+omega*zd)*dt;zoom.x=zoom.y+(zd+zt)*e;zoom.z=(zoom.z-omega*zt)*e;
 float heatTarget=c1.y>0.5?-50.0-750.0*cos(targetState.z):c0.x;
 // Initial autoplay follows the exact sweep; resume blends in over one third second.
 if(c1.y>0.5)spring.w=min(1.0,spring.w+dt*3.0);
 float heat=initial?heatTarget:mix(old.z,heatTarget,c1.y>0.5?spring.w:1.0-exp(-dt*7.0));
 // Adaptive render scale: x = scale, y = smoothed frame time, z = settle timer.
 // Shrinks below ~25 fps, grows above ~45 fps; a 30 fps vsync cap is left alone.
 if(resolution.x<MIN_SCALE||resolution.x>MAX_SCALE||resolution.y<=0.0)resolution=vec4(clamp(0.5,MIN_SCALE,MAX_SCALE),1.0/60.0,-1.5,0);
 resolution.y=mix(resolution.y,clamp(iTimeDelta,0.001,0.25),0.08);resolution.z+=clamp(iTimeDelta,0.0,0.25);
 if(resolution.z>0.75){
 float next=resolution.y>1.0/25.0?resolution.x*0.8:(resolution.y<1.0/45.0?resolution.x*1.12:resolution.x);
 next=clamp(next,MIN_SCALE,MAX_SCALE);
 if(next!=resolution.x){resolution.x=next;resolution.z=0.0;}
 }
 if(RENDER_SCALE>0.0)resolution.x=clamp(RENDER_SCALE,0.05,1.0);
 if(p.x==META)O=vec4(angles,heat,STATE_TAG);
 else if(p.x==(META+1))O=vec4(iMouse.xy,iMouse.z,float(hit));
 else if(p.x==(META+2))O=vec4(abs(heat-old.z),tempNorm,dragging?1.0:0.0,1);
 else if(p.x==(META+3))O=c0;
 else if(p.x==(META+4))O=c1;
 else if(p.x==(META+5))O=vec4(mode,advanced,mix(uiState.z,mode,1.0-exp(-dt*18.0)),2); // Fourth component: text coverage layer count.
 else if(p.x==(META+6))O=targetState;
 else if(p.x==(META+7))O=spring;
 else if(p.x==(META+8))O=zoom;
 else if(p.x==META+18)O=resolution;
#if QUALITY==0
 else if(p.x==(META+9))O=vec4(6,1,3,1); // Geometry, AA, path depth, ambient direction count.
#else
 else if(p.x==(META+9))O=vec4(6,4,4,3); // Geometry, AA, path depth, ambient direction count.
#endif
 else if(p.x==(META+12))O=pan;
 else if(p.x==(META+13))O=panGoal;
 else if(p.x==(META+14))O=panSpring;
 else if(p.x==(META+15))O=prefs;
 else if(p.x==(META+16))O=vec4(renderSettings.xyz,0);
 else if(p.x==(META+17))O=zoomKey;
 else if(p.x==(META+11))O=vec4(8,4,0,0); // Emitter quadrature and label trial counts.
 else{
 bool valid=dataReady&&texelFetch(iChannel0,ivec2(0,0),0).a==SPECTRAL_TAG&&texelFetch(iChannel0,ivec2(3*LUT_T-1,0),0).a==SPECTRAL_TAG&&texelFetch(iChannel0,ivec2(0,63),0).a==SPECTRAL_TAG&&texelFetch(iChannel0,ivec2(3*LUT_T-1,63),0).a==SPECTRAL_TAG&&texelFetch(iChannel0,ivec2(0,64),0).a==SPECTRAL_TAG&&texelFetch(iChannel0,ivec2(127,67),0).a==SPECTRAL_TAG;
 O=vec4(154,SPECTRAL_TAG,valid?STATE_TAG:0.0,1);
 }
 return;
 }
 // One scene-wide exposure reference from the six existing emitter caches.
 // No per-object normalization: View material/temperature radiance ratios remain shared.
 if(p.y==1&&p.x==(META+6)){
 if(!passReady(texelFetch(iChannel0,ivec2((META+10),0),0),154.0)){O=vec4(1,0,0,31);return;}
 float strength=clamp(texelFetch(iChannel0,ivec2((META+2),0),0).y,0.0,0.35);
 float level=texelFetch(iChannel0,ivec2((META+4),0),0).z;
 float nominal=exp2(-6.0*(level-0.5));
 int count=clamp(int(texelFetch(iChannel0,ivec2((META+9),0),0).x+0.5),1,6);
 float referenceY=0.0,referencePeak=0.0;
 for(int k=0;k<count;k++){
 vec3 energy=texelFetch(iChannel0,ivec2(META+k,1),0).rgb*nominal;
 referenceY=max(referenceY,dot(energy,RGB_LUMA));
 referencePeak=max(referencePeak,max(energy.r,max(energy.g,energy.b)));
 }
 float gain=min(pow(EMISSION_GAIN/max(referenceY,1e-12),strength),2.0);
 if(strength>0.0)gain=min(gain,8.0/max(referencePeak,1e-12));
 O=vec4(gain,referenceY,referencePeak,31);return;
 }
 // Cache each emitter's unchanged projected-disk mean once per frame.
 if(p.y==1&&p.x>=META&&p.x<=(META+5)){
 if(!dataReady||!passReady(texelFetch(iChannel0,ivec2((META+10),0),0),154.0)){O=vec4(0);return;}
 int id=p.x-META;vec4 camera=texelFetch(iChannel0,ivec2(META,0),0),options=texelFetch(iChannel0,ivec2((META+4),0),0);
 int mode=int(texelFetch(iChannel0,ivec2((META+5),0),0).x+0.5),mat=mode==0?int(options.x+0.5):id;
 float T=clamp((mode==1?1800.0:TEMPERATURE_K+float(id)*TEMPERATURE_STEP_K)+camera.z,500.0,6500.0);
 int samples=clamp(int(texelFetch(iChannel0,ivec2((META+11),0),0).x+0.5),1,8);vec3 mean=vec3(0);
 for(int k=0;k<samples;k++)mean+=rgb(thermal(iChannel0,mat,T,sqrt((float(k)+0.5)/float(samples))))/float(samples);
 O=vec4(mean*thermalRadianceScale(options.z),31);return;
 }
 // Rows 64..67 cache D65-reference metallic reflectance; emission tiles occupy x<192,y<64.
 bool reflection=p.y>=64&&p.y<68&&p.x<128;
 if(!reflection&&(p.x>=3*LUT_T||p.y>=64)){O=vec4(0);return;}
 if(!dataReady){O=vec4(0);return;}
 if(texelFetch(iChannel0,p,0).a==SPECTRAL_TAG){O=texelFetch(iChannel0,p,0);return;}
 int count=int(texelFetch(iChannel1,ivec2(SPECTRAL_COUNT,0),0).y);
 if(count==0){O=vec4(0);return;}
 int m=reflection?p.y-64:p.x/LUT_T+3*(p.y/32);
 float fraction=reflection?float(p.x)/127.0:float(p.x%LUT_T)/float(LUT_T-1);
 float T=1.0/mix(1.0/500.0,1.0/6500.0,fraction);
 float angular=float(p.y%32)/31.0;float mu=reflection?fraction:angular*angular;vec3 xyz=vec3(0);
 float sampleWeight=SPECTRAL_STEP_NM/5.0; // Per-sample weight in the original 5nm units.
 for(int j=0;j<count;j++){
 vec4 cmf=texelFetch(iChannel1,ivec2(j,0),0);
 vec2 nk=texelFetch(iChannel1,ivec2(j,min(m+1,4)),0).xy;
 float R=m<4?conductor(mu,nk):(m==4?ceramic(mu):0.0);
 if(reflection){xyz+=cmf.xyz*(cmf.w*R*sampleWeight);}
 else{
 float wavelength=(SPECTRAL_START_NM+SPECTRAL_STEP_NM*float(j))*1e-9;
 float w2=wavelength*wavelength,w5=w2*w2*wavelength;
 float B=1.191042972e-16/(w5*(exp(0.01438776877/(wavelength*T))-1.0));
 float epsilon=(1.0-R)*(m==4?1.0-DIELECTRIC_BASE:1.0);
 xyz+=cmf.xyz*(B*epsilon*sampleWeight);
 }
 }
 if(reflection)O=vec4(clamp(rgb(xyz/D65_Y_SUM)/D65_WHITE_RGB,0.0,1.0),SPECTRAL_TAG);
 else O=vec4(log(max(xyz*5e-9,vec3(1e-30))),SPECTRAL_TAG);
}
