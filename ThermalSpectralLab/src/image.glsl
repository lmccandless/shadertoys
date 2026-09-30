// SDF atlas technique: shadertoy.com/view/ldfcDr (CC0).
// One selected text run per fragment, one shared glyph path; no duplicated font trees.
// Text holds one character code per ivec4 component (12 max). Nothing is packed into
// 32-bit integers or carried through a buffer, so it reads the same on GPUs with 16-bit or
// float-emulated integers and on devices whose buffers are half-float.
struct TextRun{vec2 origin;float size;ivec4 c0,c1,c2;int count;vec3 ink;};
void setText(inout TextRun r,ivec4 a,ivec4 b,ivec4 c,int n){r.c0=a;r.c1=b;r.c2=c;r.count=n;}
void setText(inout TextRun r,ivec4 a,ivec4 b,int n){setText(r,a,b,ivec4(0),n);}
void setText(inout TextRun r,ivec4 a,int n){setText(r,a,ivec4(0),ivec4(0),n);}
// Branch-free: each slot is written once, so adding into the zeroed lanes is exact.
void putChar(inout TextRun r,int i,int ch){
 r.c0+=ivec4(equal(ivec4(i),ivec4(0,1,2,3)))*ch;
 r.c1+=ivec4(equal(ivec4(i),ivec4(4,5,6,7)))*ch;
 r.c2+=ivec4(equal(ivec4(i),ivec4(8,9,10,11)))*ch;
}
int digitCount(int n){return n>=10000?5:(n>=1000?4:(n>=100?3:(n>=10?2:1)));}
void putNumber(inout TextRun r,int start,int n){
 int d=digitCount(n),div=d==5?10000:(d==4?1000:(d==3?100:(d==2?10:1)));
 for(int k=0;k<5;k++){putChar(r,start+k,k<d?48+n/div%10:0);div=max(div/10,1);}
}
void putUnit(inout TextRun r,int start,int unit){putChar(r,start,32);if(unit==0)putChar(r,start+1,75);else{putChar(r,start+1,176);putChar(r,start+2,unit==1?67:70);}}
float glyph(vec2 q,int ch,float size){
 if(ch==176){float r=length(q-vec2(0.12,0.43)*size);return 1.0-smoothstep(0.035*size,0.035*size+0.65*495.0/iResolution.y,abs(r-0.085*size));}
 vec2 uv=q/size+vec2(0.30,0.20);
 if(any(lessThan(uv,vec2(0.01)))||any(greaterThan(uv,vec2(0.99))))return 0.0;
 uv.y=1.0-uv.y;
 float d=textureLod(iChannel3,(vec2(ch%16,ch/16)+uv)/16.0,0.0).a-0.5-1.0/256.0;
 float aa=0.65*495.0/iResolution.y/size;return 1.0-smoothstep(-aa,aa,d);
}
float coverage(vec2 p,TextRun run){
 int slot=int(floor((p.x-run.origin.x)/(run.size*0.5)));
 if(slot<0||slot>=run.count)return 0.0;
 ivec4 w=slot<4?run.c0:(slot<8?run.c1:run.c2);int k=slot%4;
 return glyph(p-run.origin-vec2(float(slot)*run.size*0.5,0),k==0?w.x:(k==1?w.y:(k==2?w.z:w.w)),run.size);
}
float stroke(vec2 p,vec2 a,vec2 b,float width){vec2 v=b-a;float t=clamp(dot(p-a,v)/max(dot(v,v),0.001),0.0,1.0);return 1.0-smoothstep(width,width+0.65,length(p-a-t*v));}
void setSymbol(inout TextRun r,int m){
 if(m==0)setText(r,ivec4(65,103,0,0),2);else if(m==1)setText(r,ivec4(65,117,0,0),2);else if(m==2)setText(r,ivec4(67,117,0,0),2);
 else if(m==3)setText(r,ivec4(70,101,0,0),2);else if(m==4)setText(r,ivec4(67,101,114,0),3);else{setText(r,ivec4(66,66,0,0),2);}
}
// Slider descriptors are still cached by C (plain floats, exact in half precision).
ivec2 textCell(int slot){return slot<18?ivec2(META+slot,1):ivec2((META+6)+(slot-18)%12,2+(slot-18)/12);}
float labelTemperature(int id,int mode,float offset){return clamp((mode==1?1800.0:TEMPERATURE_K+float(id)*TEMPERATURE_STEP_K)+offset,500.0,6500.0);}
int labelLength(int id){
 int mode=int(texelFetch(iChannel2,ivec2(META+5,0),0).x+0.5),unit=clamp(int(texelFetch(iChannel2,ivec2(META+15,0),0).z+0.5),0,2);
 int temp=int(displayTemperature(labelTemperature(id,mode,texelFetch(iChannel2,ivec2(META,0),0).z),unit)+0.5);
 return (mode!=0?(id==4?4:3):0)+digitCount(temp)+(unit==0?2:3);
}
// Live text: 0-5 sphere labels, 6-7 advanced readouts, 8-14 slider readouts.
// State comes from C's row-0 copy of A.
void makeText(inout TextRun r,int textID){
 vec4 cam=texelFetch(iChannel2,ivec2(META,0),0),settings=texelFetch(iChannel2,ivec2(META+3,0),0),options=texelFetch(iChannel2,ivec2(META+4,0),0);
 vec4 zoom=texelFetch(iChannel2,ivec2(META+8,0),0),prefs=texelFetch(iChannel2,ivec2(META+15,0),0);
 int mode=int(texelFetch(iChannel2,ivec2(META+5,0),0).x+0.5),unit=clamp(int(prefs.z+0.5),0,2);
 setText(r,ivec4(0),0);
 if(textID<6){
 int temp=int(displayTemperature(labelTemperature(textID,mode,cam.z),unit)+0.5),d=digitCount(temp),start=0;
 if(mode!=0){setSymbol(r,textID);start=textID==4?4:3;putChar(r,start-1,32);}
 putNumber(r,start,temp);putUnit(r,start+d,unit);r.count=start+d+(unit==0?2:3);
 }else if(textID==6){
 setText(r,ivec4(69,109,105,116),ivec4(32,0,0,0),5);int n=int(exp2(6.0*(options.z-0.5))*100.0+0.5);
 putChar(r,5,48+n/100%10);putChar(r,6,46);putChar(r,7,48+n/10%10);putChar(r,8,48+n%10);putChar(r,9,120);r.count=10;
 }else if(textID==7){
 setText(r,ivec4(67,121,99,108),ivec4(101,32,0,0),6);int n=int(2.0*PI/max(options.w,0.01)+0.5),d=digitCount(n);putNumber(r,6,n);putChar(r,6+d,115);r.count=7+d;
 }else{
 int id=textID-8;
 if(id==0){float delta=cam.z*(unit==2?1.8:1.0);int n=int(abs(delta)+0.5),d=digitCount(n);putChar(r,0,delta<0.0?45:43);putNumber(r,1,n);putUnit(r,1+d,unit);r.count=d+1+(unit==0?2:3);}
 else if(id==1){int n=int(settings.y*100.0+0.501),d=digitCount(n);putNumber(r,0,n);putChar(r,d,37);r.count=d+1;}
 else if(id==5){int n=int(2.0*PI/max(options.w,0.01)+0.5),d=digitCount(n);putNumber(r,0,n);putChar(r,d,32);putChar(r,d+1,115);r.count=d+2;}
 else{float v=id==4?exp2(6.0*(options.z-0.5)):(id==6?16.0/zoom.x:(id==2?settings.z:settings.w));int n=int(v*100.0+0.5),fraction=n%100;
 putChar(r,0,48+n/100);putChar(r,1,46);putChar(r,2,48+fraction/10);putChar(r,3,48+fraction%10);putChar(r,4,120);r.count=5;}
 }
}
void mainImage(out vec4 O,in vec2 P){
 vec2 uv=P/iResolution.xy,p=P*vec2(880,495)/iResolution.xy,mouse=iMouse.xy*vec2(880,495)/iResolution.xy;
 vec4 cam=texelFetch(iChannel2,ivec2(META,0),0),settings=texelFetch(iChannel2,ivec2((META+3),0),0),options=texelFetch(iChannel2,ivec2((META+4),0),0),ui=texelFetch(iChannel2,ivec2((META+5),0),0);
 vec4 zoom=texelFetch(iChannel2,ivec2((META+8),0),0),prefs=texelFetch(iChannel2,ivec2((META+15),0),0);
 vec4 renderSettings=texelFetch(iChannel2,ivec2((META+16),0),0);int floorChoice=clamp(int(renderSettings.x+0.5),0,2);
 vec4 scene=texelFetch(iChannel2,ivec2((META+9),0),0);int labelCount=clamp(int(scene.x+0.5),1,6),sliderCount=ui.y>0.5?6:2;
 int unit=clamp(int(prefs.z+0.5),0,2);
 int mode=int(ui.x+0.5),material=int(options.x+0.5);
 TextRun run;run.origin=vec2(0);run.size=14.0;setText(run,ivec4(0),0);run.ink=vec3(0.90);
 // Live text is chosen below and built once, after selection: one makeText call site.
 int liveText=-1,align=0;float alignX=0.0;
 // No frame-zero assumption: every pass proves that its actual inputs are ready.
 bool ready=passReady(texelFetch(iChannel0,ivec2((META+10),0),0),211.0)&&passReady(texelFetch(iChannel2,ivec2((META+11),0),0),311.0)&&passReady(texelFetch(iChannel1,ivec2((META+10),0),0),419.0);
 vec3 c=vec3(0.018);
 if(!ready){
run.origin=vec2(413,250);setText(run,ivec4(76,111,97,100),ivec4(105,110,103,0),7);run.size=14.0;
 for(int k=0;k<3;k++){
 bool ok=k==0?passReady(texelFetch(iChannel0,ivec2((META+10),0),0),211.0):(k==1?passReady(texelFetch(iChannel2,ivec2((META+11),0),0),311.0):passReady(texelFetch(iChannel1,ivec2((META+10),0),0),419.0));
 c=mix(c,vec3(ok?0.7:0.15),stroke(p,vec2(410.0+float(k)*22.0,237),vec2(425.0+float(k)*22.0,237),0.4));
 }
 }else{
 bool panel=prefs.y>0.5?(p.x>=844.0&&p.y<=32.0):p.y<=UI_HEIGHT;
 // Scene stays sharp in B; C and D form a real horizontal/vertical Gaussian.
 // B, C and D hold the scene in their lower-left scale*resolution block: upsample it.
 float scale=clamp(texelFetch(iChannel2,ivec2(META+18,0),0).x,0.05,1.0);
 vec2 sceneUV=min(uv*scale,(vec2(sceneSize(iResolution.xy,scale))-0.5)/iResolution.xy);
 sceneUV.y=max(sceneUV.y,1.5/iResolution.y); // Row 0 carries B's pass marker.
 c=texture(iChannel0,sceneUV).rgb;
 // Redistribute 3.5% of bright radiance through the normalized blur, in one unit system.
 if(P.y*scale>6.5)c+=0.035*(texture(iChannel1,sceneUV).rgb-bloomSource(c));
 c*=EXPOSURE;
 // Keep signed scene-linear RGB until gamut mapping; clipping it earlier shifts chromaticity.
 float Y=max(dot(c,RGB_LUMA),0.0),low=min(c.r,min(c.g,c.b));
 if(low<0.0)c=vec3(Y)+(c-vec3(Y))*clamp(Y/max(Y-low,1e-30),0.0,1.0);
 c=max(c,vec3(0));
 // Luminance compression preserves brightness ordering across different source colors.
 // Peak compression incorrectly made a hotter/brighter orange source darker than green.
 float displayY=Y/(1.0+Y);c/=1.0+Y;
 // Fit highlights into SDR around the mapped luminance, after all linear light is added.
 // Out-of-gamut highlights necessarily lose saturation; in-gamut mixtures keep their hue.
 float peak=max(c.r,max(c.g,c.b));
 float chroma=min(1.0,(1.0-displayY)/max(peak-displayY,1e-12));
 c=vec3(displayY)+(c-vec3(displayY))*chroma;
 c*=1.0-0.15*dot(uv-0.5,uv-0.5);c=clamp(c,0.0,1.0);
 c=mix(12.92*c,1.055*pow(c,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
 if(!panel){
 // Cheap reject: only pixels inside some label's leader/underline/text bounds pay for
 // the mask and stroke loops below. Everything those loops draw lies inside these boxes.
 bool nearLabel=false;
 if(prefs.x>0.5){
 for(int k=0;k<labelCount;k++){
 vec4 projection=texelFetch(iChannel2,ivec2(META+k,3),0),state=texelFetch(iChannel2,ivec2(META+k,2),0);
 if(projection.w<0.5||state.w<0.5||projection.z<=0.0||state.z<1.0||state.z>64.0)continue;
 vec2 anchor=projection.xy,dir=vec2(cos(state.x),sin(state.x));float width=state.z;
 vec2 label=anchor+dir*(labelReach(projection.z,dir,vec2(width,9))+state.y);
 vec2 lo=min(anchor,label-vec2(width+8.0,14.0))-4.0,hi=max(anchor,label+vec2(width+8.0,14.0))+4.0;
 if(all(greaterThan(p,lo))&&all(lessThan(p,hi)))nearLabel=true;
 }
 }
 if(nearLabel){
 // Retain the original polar placement. One shared mask protects every text box.
 float leaderMask=1.0;
 for(int k=0;k<labelCount;k++){
 vec4 a=texelFetch(iChannel2,ivec2(META+k,3),0),s=texelFetch(iChannel2,ivec2(META+k,2),0);
 if(a.w<0.5||s.w<0.5||a.z<=0.0||s.z<1.0||s.z>64.0)continue;
 if(any(isnan(a))||any(isinf(a))||any(isnan(s))||any(isinf(s)))continue;
 leaderMask*=smoothstep(a.z+1.0,a.z+3.0,length(p-a.xy));
 vec2 dir=vec2(cos(s.x),sin(s.x));
 vec2 label=a.xy+dir*(labelReach(a.z,dir,vec2(s.z,9))+s.y);
 float textWidth=3.75*float(labelLength(k));
 vec2 outside=max(abs(p-label-vec2(0,2.5))-vec2(max(s.z,textWidth)+4.0,10.5),vec2(0));
 leaderMask*=smoothstep(0.0,1.5,length(outside));
 }
 for(int j=0;j<labelCount;j++){
 vec4 projection=texelFetch(iChannel2,ivec2(META+j,3),0),state=texelFetch(iChannel2,ivec2(META+j,2),0);
 // A cold or stale cache must never draw a screen-sized, invalid leader.
 if(projection.w<0.5||state.w<0.5||projection.z<=0.0||state.z<1.0||state.z>64.0)continue;
 if(any(isnan(projection))||any(isinf(projection))||any(isnan(state))||any(isinf(state)))continue;
 vec2 anchor=projection.xy,dir=vec2(cos(state.x),sin(state.x));float width=state.z;
 vec2 label=anchor+dir*(labelReach(projection.z,dir,vec2(width,9))+state.y);
 vec2 end=label+vec2(anchor.x<label.x?-width:width,-10.0),begin=anchor+(end-anchor)/max(length(end-anchor),0.001)*(projection.z+4.0);
 float line=stroke(p,begin,end,0.12),shadow=stroke(p-vec2(0.5,-1.0),begin,end,0.75);
 vec2 ua=label+vec2(-width,-10),ub=label+vec2(width,-10);
 c=mix(c,vec3(0.015),max(shadow,stroke(p-vec2(0.5,-1),ua,ub,0.65))*0.28*leaderMask);
 c=mix(c,vec3(0.78),max(line,stroke(p,ua,ub,0.12))*0.58*leaderMask);
 c=mix(c,vec3(0.88),0.6*(1.0-smoothstep(0.55,1.4,length(p-begin)))*leaderMask);
 if(abs(p.x-label.x)<width+5.0&&p.y>=label.y-5.0&&p.y<label.y+12.0){
 liveText=j;run.size=15.0;run.origin=label+vec2(0,-3.5);align=1;alignX=label.x;
 }
 }
 }
 }else{
 vec3 ink=vec3(0.92),muted=vec3(0.64);run.ink=ink;
 int hover=uiHit(iMouse.xy,iResolution.xy,ui.y,prefs);
 // Collapse/restore remains accessible when everything else is hidden.
 float cy=prefs.y>0.5?16.0:52.0,flip=prefs.y>0.5?1.0:-1.0;
 vec2 arrow=vec2(864,cy);
 c=mix(c,vec3(0.01),0.5*max(stroke(p-vec2(0.5,-0.8),arrow+vec2(-4,-flip*2.0),arrow+vec2(0,flip*2.0),0.6),stroke(p-vec2(0.5,-0.8),arrow+vec2(0,flip*2.0),arrow+vec2(4,-flip*2.0),0.6)));
 c=mix(c,hover==15?vec3(1):ink,max(stroke(p,arrow+vec2(-4,-flip*2.0),arrow+vec2(0,flip*2.0),0.3),stroke(p,arrow+vec2(0,flip*2.0),arrow+vec2(4,-flip*2.0),0.3)));
 if(prefs.y<0.5){
 // Compact selector row. No footer or redundant section headings.
 float tab=ui.z,tx=tab<1.0?mix(40.0,93.5,tab):mix(93.5,141.5,tab-1.0),tw=tab<1.0?mix(20.0,13.5,tab):13.5;
 c=mix(c,ink,0.65*stroke(p,vec2(tx-tw,44),vec2(tx+tw,44),0.2));
 c=mix(c,muted,max(stroke(p,vec2(68,49),vec2(72,57),0.1),stroke(p,vec2(116,49),vec2(120,57),0.1)));
 if(ui.y<0.5&&mode==0){float x=194.0+float(material)*30.0;c=mix(c,ink,stroke(p,vec2(x-1.0,44),vec2(x+(material==4?19.0:12.0),44),0.2));}
 float ux=404.0+float(unit)*28.0;c=mix(c,ink,0.65*stroke(p,vec2(ux-1.0,44),vec2(ux+(unit==0?7.0:12.0),44),0.2));
 c=mix(c,muted,max(stroke(p,vec2(421,49),vec2(424,56),0.1),stroke(p,vec2(449,49),vec2(452,56),0.1)));
 if(prefs.x>0.5)c=mix(c,ink,0.65*stroke(p,vec2(515,44),vec2(557,44),0.2));
 for(int slot=0;slot<sliderCount;slot++){
 vec4 descriptor=texelFetch(iChannel2,textCell(45+slot),0);int id=int(descriptor.w);
 vec2 range=descriptor.xy;float trackY=id==4||id==5?44.0:12.0;float x=descriptor.z,radius=hover==id?3.6:2.9;
 c=mix(c,vec3(0.015),0.45*stroke(p,vec2(range.x,trackY-0.8),vec2(range.y,trackY-0.8),0.9));
 c=mix(c,vec3(0.72),0.4*stroke(p,vec2(range.x,trackY),vec2(range.y,trackY),0.25));
 c=mix(c,vec3(0.87),0.72*stroke(p,vec2(range.x,trackY),vec2(x,trackY),0.35));
 c=mix(c,vec3(0.015),0.48*(1.0-smoothstep(radius,radius+1.3,length(p-vec2(x+0.4,trackY-1.0)))));
 c=mix(c,ink,1.0-smoothstep(radius-0.45,radius+0.3,length(p-vec2(x,trackY))));
 }
 if(ui.y<0.5){
 float fx=310.0+56.0*float(floorChoice);c=mix(c,ink,0.65*stroke(p,vec2(fx-1.0,5),vec2(fx+33.75,5),0.2));
 c=mix(c,muted,max(stroke(p,vec2(351,8),vec2(354,15),0.1),stroke(p,vec2(407,8),vec2(410,15),0.1)));
 int lightChoice=clamp(int(renderSettings.y+0.5),0,2);float lx=lightChoice==0?500.0:(lightChoice==1?547.0:610.0);float lw=lightChoice==1?40.5:27.0;
 c=mix(c,ink,0.65*stroke(p,vec2(lx-1.0,5),vec2(lx+lw,5),0.2));c=mix(c,muted,max(stroke(p,vec2(533,8),vec2(536,15),0.1),stroke(p,vec2(596,8),vec2(599,15),0.1)));
 }
 float play;if(options.y>0.5){vec2 a=abs(p-vec2(618,54));play=(1.0-smoothstep(4.2,4.9,a.y))*(1.0-smoothstep(0.75,1.4,abs(a.x-2.3)));}else{vec2 a=p-vec2(618,54);play=1.0-smoothstep(0.0,0.7,max(abs(a.y)+a.x*0.65-3.7,-a.x-3.0));}c=mix(c,ink,play);
 float moreFlip=ui.y>0.5?1.0:-1.0;vec2 moreArrow=vec2(817,54);c=mix(c,muted,max(stroke(p,moreArrow+vec2(-3,-moreFlip*1.5),moreArrow+vec2(0,moreFlip*1.5),0.15),stroke(p,moreArrow+vec2(0,moreFlip*1.5),moreArrow+vec2(3,-moreFlip*1.5),0.15)));
 run.size=13.5;
 if(p.y>=38.0){
 run.origin.y=50.0;
 if(p.x<76.0){run.origin.x=20.0;setText(run,ivec4(83,105,110,103),ivec4(108,101,0,0),6);run.ink=mode==0||hover==10?ink:muted;}
 else if(p.x<122.0){run.origin.x=80.0;setText(run,ivec4(86,105,101,119),4);run.ink=mode==1||hover==11?ink:muted;}
 else if(p.x<174.0){run.origin.x=128.0;setText(run,ivec4(82,97,109,112),4);run.ink=mode==2||hover==12?ink:muted;}
 else if(p.x<384.0){
 if(ui.y>0.5){
 if(p.x<284.0){run.origin.x=194.0;liveText=6;}
 else{run.origin.x=294.0;liveText=7;}
 }else{int m=clamp(int((p.x-188.0)/30.0),0,5);run.origin.x=194.0+float(m)*30.0;setSymbol(run,m);run.ink=mode==0&&m==material?ink:muted;}
 }
 else if(p.x<492.0){int u=clamp(int((p.x-394.0)/28.0),0,2);run.origin.x=404.0+float(u)*28.0;if(u==0)setText(run,ivec4(75,0,0,0),1);else setText(run,ivec4(176,u==1?67:70,0,0),2);run.ink=u==unit?ink:muted;}
 else if(p.x<592.0){run.origin.x=516.0;setText(run,ivec4(76,97,98,101),ivec4(108,115,0,0),6);run.ink=prefs.x>0.5||hover==14?ink:muted;}
 else if(p.x<681.0){run.origin.x=634.0;if(options.y>0.5){setText(run,ivec4(80,97,117,115),ivec4(101,0,0,0),5);}else{setText(run,ivec4(80,108,97,121),4);}}
 else if(p.x>=764.0&&p.x<837.0){run.origin.x=774.0;if(ui.y>0.5){setText(run,ivec4(66,97,99,107),4);}else{setText(run,ivec4(77,111,114,101),4);}}
 }else if(p.y>=21.0){
 int col=p.x<295.0?0:(p.x<485.0?1:(p.x<665.0?2:3)),id=col==3?6:(ui.y>0.5?col+1:(col==0?0:(col==1?17:18)));vec2 range=col==0?vec2(20,280):(col==1?vec2(310,470):(col==2?vec2(500,650):vec2(680,845)));run.origin=vec2(range.x,29.0);
 float readout=range.y-(col==0?91.0:49.0);
 if(p.x<readout||id==17||id==18){
 run.ink=muted;
 if(id==17){setText(run,ivec4(70,108,111,111),ivec4(114,0,0,0),5);run.ink=muted;}
 else if(id==18){setText(run,ivec4(76,105,103,104),ivec4(116,105,110,103),8);run.ink=muted;}
 else if(id==0){setText(run,ivec4(72,101,97,116),ivec4(32,111,102,102),ivec4(115,101,116,0),11);}
 else if(id==1){setText(run,ivec4(82,111,117,103),ivec4(104,110,101,115),ivec4(115,0,0,0),9);}
 else if(id==2){bool norm=texelFetch(iChannel2,ivec2((META+2),0),0).y>0.0;if(norm)setText(run,ivec4(69,120,112,32),ivec4(84,45,97,117),ivec4(116,111,0,0),10);else setText(run,ivec4(69,120,112,32),ivec4(84,45,110,111),ivec4(114,109,48,37),12);run.ink=hover==20?ink:muted;}
 else if(id==3){setText(run,ivec4(69,110,118,105),ivec4(114,111,110,109),ivec4(101,110,116,0),11);}
 else if(id==4){setText(run,ivec4(69,109,105,115),ivec4(115,105,111,110),8);}
 else if(id==5){setText(run,ivec4(67,121,99,108),ivec4(101,32,115,112),ivec4(101,101,100,0),11);}
 else{setText(run,ivec4(90,111,111,109),4);}
 }else{
 liveText=8+id;align=2;alignX=range.y;
 }
 }else if(ui.y<0.5&&p.y>=4.0){
 run.size=13.5;run.origin.y=8.0;
 if(p.x>=295.0&&p.x<485.0){int f=clamp(int((p.x-310.0)/56.0),0,2);run.origin.x=310.0+56.0*float(f);if(f==0)setText(run,ivec4(71,108,111,115),ivec4(115,0,0,0),5);else if(f==1)setText(run,ivec4(83,97,116,105),ivec4(110,0,0,0),5);else setText(run,ivec4(77,97,116,116),ivec4(101,0,0,0),5);run.ink=f==floorChoice?ink:muted;}
 else if(p.x>=485.0&&p.x<665.0){int light=p.x<536.0?0:(p.x<600.0?1:2);run.origin.x=light==0?500.0:(light==1?547.0:610.0);if(light==0)setText(run,ivec4(67,117,98,101),4);else if(light==1)setText(run,ivec4(83,116,117,100),ivec4(105,111,0,0),6);else setText(run,ivec4(83,111,102,116),4);run.ink=light==int(renderSettings.y+0.5)?ink:muted;}
 }
 }
 }
 } // Loading and the live UI use the same glyph path.
 if(liveText>=0){
 makeText(run,liveText);
 if(align>0)run.origin.x=alignX-float(run.count)*run.size*(align==1?0.25:0.5);
 }
 // The entire display shares these two atlas samples, including the soft shadow.
 // One data-bounded glyph tree supplies the unchanged shadow and foreground samples.
 int glyphLayers=ready?clamp(int(ui.w+0.5),1,2):2;
 float shadow=0.0,ink=0.0;
 for(int layer=0;layer<glyphLayers;layer++){
 vec2 q=layer==0?p-vec2(0.55,-0.85):p;
 float value=coverage(q,run);
 if(layer==0)shadow=value;else ink=value;
 }
 c=mix(c,vec3(0.01),shadow*0.65);
 c=mix(c,run.ink,ink);O=vec4(c,1);
}
