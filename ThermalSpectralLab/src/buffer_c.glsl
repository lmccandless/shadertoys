// Horizontal Gaussian bloom, persistent labels and mirrored controls. Image reads B directly.
#if QUALITY==0
#define BLOOM_TAPS 6
#else
#define BLOOM_TAPS 16
#endif
vec3 labelEye,labelForward,labelRight,labelUp;float hudHeight;int labelCount,labelTrials;
void projectLabel(int id,out vec2 anchor,out float radius){
 vec3 d=centre(id)-labelEye;float z=dot(d,labelForward);
 if(z<=0.1){anchor=vec2(-10000);radius=0.0;return;}
 anchor=vec2(440,SCENE_Y)+vec2(dot(d,labelRight)*880.0*iResolution.y/iResolution.x,dot(d,labelUp)*495.0)*1.55/z;
 radius=0.92/z*1.55*495.0;
}

vec2 labelGoal(int id,vec2 anchor,float radius,vec2 halfBox,float oldAngle,bool initial){
 float preferred=atan(anchor.y-SCENE_Y,anchor.x-440.0);
 if(initial)return vec2(preferred,0);
 vec4 old=texelFetch(iChannel1,ivec2(META+id,4),0);
 float best=1e20;vec2 goal=vec2(preferred,0);
 for(int trial=0;trial<labelTrials;trial++){
 int site=(iFrame*2+trial-2)%16;
 float angle=trial==0&&old.w>0.5?old.x:(trial<2?preferred:preferred+float(site)*PI/8.0);
 float extra=trial==0&&old.w>0.5?old.y:(trial<2?0.0:float((iFrame/8)%3)*28.0);
 vec2 dir=vec2(cos(angle),sin(angle));
 vec2 q=anchor+dir*(labelReach(radius,dir,halfBox)+extra);
 float change=atan(sin(angle-oldAngle),cos(angle-oldAngle));
 float cost=9.0*(1.0-cos(angle-preferred))+6.0*change*change+extra*0.35;
 vec2 outside=max(vec2(16.0+halfBox.x,hudHeight+23.0)-q,vec2(0))+max(q-vec2(864.0-halfBox.x,480.0),vec2(0));cost+=dot(outside,outside)*25.0;
 for(int k=0;k<labelCount;k++){
 // Neighbor bounds are already cached in row3; avoid a vertex loop inside every trial.
 vec4 projection=texelFetch(iChannel1,ivec2(META+k,3),0);vec2 a=projection.xy;float r=projection.z;
 if(projection.w<0.5||r<=0.0)continue;
 vec2 d=max(abs(q-a)-halfBox,vec2(0));float overlap=max(0.0,r+7.0-length(d));cost+=overlap*overlap*24.0;
 if(k!=id){vec4 s=texelFetch(iChannel1,ivec2(META+k,2),0);if(s.w>0.5){
 vec2 kd=vec2(cos(s.x),sin(s.x));vec2 label=a+kd*(labelReach(r,kd,halfBox)+s.y);
 vec2 box=max(2.0*halfBox+vec2(8,5)-abs(q-label),vec2(0));cost+=box.x*box.y*4.0;
 }}
 }
 if(cost<best){best=cost;goal=vec2(angle,extra);}
 }
 return goal;
}
// Compact text cache lives entirely inside the existing bloom-excluded metadata region.
int digits(int n){return n>=10000?5:(n>=1000?4:(n>=100?3:(n>=10?2:1)));}
uint decimalDigits(int n){uint w=uint(48+n/1000%10)|(uint(48+n/100%10)<<8u)|(uint(48+n/10%10)<<16u)|(uint(48+n%10)<<24u);return w>>uint((4-min(digits(n),4))*8);}
void byteAt(inout uvec4 w,int slot,uint b){if(slot<4)w.x|=b<<uint(slot*8);else if(slot<8)w.y|=b<<uint((slot-4)*8);else if(slot<12)w.z|=b<<uint((slot-8)*8);else w.w|=b<<uint((slot-12)*8);}
void appendNumber(inout uvec4 w,int start,int n){
 if(n>=10000){byteAt(w,start,uint(48+n/10000%10));start++;}
 uint encoded=decimalDigits(n),shift=uint((start%4)*8),first=encoded<<shift,second=shift>0u?encoded>>(32u-shift):0u;
 if(start<4){w.x|=first;w.y|=second;}else if(start<8){w.y|=first;w.z|=second;}else{w.z|=first;w.w|=second;}
}
void appendUnit(inout uvec4 w,int start,int unit){byteAt(w,start,32u);if(unit==0)byteAt(w,start+1,75u);else{byteAt(w,start+1,176u);byteAt(w,start+2,unit==1?67u:70u);}}
uvec4 symbol(int m){if(m==0)return uvec4(26433u,0,0,0);if(m==1)return uvec4(30017u,0,0,0);if(m==2)return uvec4(30019u,0,0,0);if(m==3)return uvec4(25926u,0,0,0);if(m==4)return uvec4(7497027u,0,0,0);return uvec4(16962u,0,0,0);}
void makeText(int textID,out uvec4 words,out int count){
 vec4 cam=texelFetch(iChannel2,ivec2(META,0),0),settings=texelFetch(iChannel2,ivec2((META+3),0),0),options=texelFetch(iChannel2,ivec2((META+4),0),0);
 vec4 zoom=texelFetch(iChannel2,ivec2((META+8),0),0),prefs=texelFetch(iChannel2,ivec2((META+15),0),0);
 int mode=int(texelFetch(iChannel2,ivec2((META+5),0),0).x+0.5),unit=clamp(int(prefs.z+0.5),0,2);
 words=uvec4(0);count=0;
 if(textID<6){
 int temp=int(displayTemperature(clamp((mode==1?1800.0:TEMPERATURE_K+float(textID)*TEMPERATURE_STEP_K)+cam.z,500.0,6500.0),unit)+0.5),d=digits(temp);
 int start=0;
 if(mode!=0){words=symbol(textID);start=textID==4?4:3;byteAt(words,start-1,32u);}
 appendNumber(words,start,temp);appendUnit(words,start+d,unit);count=start+d+(unit==0?2:3);
 }else if(textID==6){
 words=uvec4(1953066309u,32u,0u,0u);float v=exp2(6.0*(options.z-0.5));int n=int(v*100.0+0.5);byteAt(words,5,uint(48+n/100));byteAt(words,6,46u);byteAt(words,7,uint(48+n/10%10));byteAt(words,8,uint(48+n%10));byteAt(words,9,120u);count=10;
 }else if(textID==7){
 words=uvec4(1818458435u,8293u,0u,0u);int n=int(2.0*PI/max(options.w,0.01)+0.5),d=digits(n);appendNumber(words,6,n);byteAt(words,6+d,115u);count=7+d;
 }else{
 int id=textID-8;
 words=uvec4(0);
 if(id==0){float delta=cam.z*(unit==2?1.8:1.0);int n=int(abs(delta)+0.5),d=digits(n);words.x=delta<0.0?45u:43u;appendNumber(words,1,n);appendUnit(words,1+d,unit);count=d+1+(unit==0?2:3);}
 else if(id==1){int n=int(settings.y*100.0+0.501),d=digits(n);appendNumber(words,0,n);byteAt(words,d,37u);count=d+1;}
 else if(id==5){int n=int(2.0*PI/max(options.w,0.01)+0.5),d=digits(n);appendNumber(words,0,n);byteAt(words,d,32u);byteAt(words,d+1,115u);count=d+2;}
 else{float v=id==4?exp2(6.0*(options.z-0.5)):(id==6?16.0/zoom.x:(id==2?settings.z:settings.w));int n=int(v*100.0+0.5),whole=n/100,fraction=n%100;words.x=uint(48+whole)|(46u<<8u)|(uint(48+fraction/10)<<16u)|(uint(48+fraction%10)<<24u);words.y=120u;count=5;}

 }
}
vec4 makeSlider(int slot){
 vec4 cam=texelFetch(iChannel2,ivec2(META,0),0),settings=texelFetch(iChannel2,ivec2((META+3),0),0),options=texelFetch(iChannel2,ivec2((META+4),0),0);
 vec4 ui=texelFetch(iChannel2,ivec2((META+5),0),0),zoom=texelFetch(iChannel2,ivec2((META+8),0),0);
 int col=ui.y>0.5?slot:slot*3;
 int id=col==4?4:(col==5?5:(col==3?6:(ui.y>0.5?col+1:0)));vec2 range=sliderRange(id);float trackY=col>=4?44.0:12.0;
 float v=id==6?(22.0-zoom.x)/17.4:(id==0?(cam.z+800.0)/2800.0:(id==1?(settings.y-0.015)/0.585:(id==2?(log2(settings.z)+2.0)/4.0:(id==3?settings.w/2.0:(id==4?options.z:(options.w-0.25)/1.75)))));
 float x=mix(range.x,range.y,clamp(v,0.0,1.0));
 return vec4(range,x,float(id));
}
void mainImage(out vec4 O,in vec2 P){
 ivec2 p=ivec2(P);
 // Outside the scaled scene block and the META block nothing is read.
 float scale=clamp(texelFetch(iChannel2,ivec2(META+18,0),0).x,0.05,1.0);
 ivec2 size=sceneSize(iResolution.xy,scale);
 if((p.x>=size.x||p.y>=size.y)&&(p.x<META||p.x>META+18||p.y>4)){O=vec4(0);return;}
 if(p.y==0&&p.x>=META&&p.x<=META+18&&p.x!=(META+11)){O=texelFetch(iChannel2,p,0);return;}
 bool ready=passReady(texelFetch(iChannel0,ivec2((META+10),0),0),211.0)&&passReady(texelFetch(iChannel2,ivec2((META+10),0),0),154.0);
 if(!ready){O=vec4(0);return;}
 if(all(equal(p,ivec2((META+11),0)))){O=vec4(311,SPECTRAL_TAG,STATE_TAG,1);return;}
 bool textPixel=(p.y==1&&p.x>=META&&p.x<=(META+17))||(p.y>=2&&p.y<=4&&p.x>=(META+6)&&p.x<=(META+17));
 if(textPixel){
 int slot=p.y==1?p.x-META:18+(p.y-2)*12+p.x-(META+6);
 if(slot>=45){O=slot<51?makeSlider(slot-45):vec4(0);return;}
 uvec4 words;int count;makeText(slot/3,words,count);
 int part=slot%3;
 O=part==0?vec4(words&uvec4(65535u)):(part==1?vec4(words>>16u):vec4(float(count),0,0,0));return;
 }
 hudHeight=texelFetch(iChannel2,ivec2((META+15),0),0).y>0.5?0.0:UI_HEIGHT;
 if(p.x>=META&&p.x<(META+6)&&p.y>=2&&p.y<=4){
 labelTrials=clamp(int(texelFetch(iChannel2,ivec2((META+11),0),0).y+0.5),1,4);
 int id=p.x-META;vec4 cam=texelFetch(iChannel2,ivec2(META,0),0);
 vec3 target=texelFetch(iChannel2,ivec2((META+12),0),0).xyz;
 labelEye=target+texelFetch(iChannel2,ivec2((META+8),0),0).x*vec3(sin(cam.x)*cos(cam.y),sin(cam.y),cos(cam.x)*cos(cam.y));
 labelForward=normalize(target-labelEye);labelRight=normalize(cross(labelForward,vec3(0,1,0)));labelUp=cross(labelRight,labelForward);
 labelCount=clamp(int(texelFetch(iChannel2,ivec2((META+9),0),0).x+0.5),1,6);
 vec2 anchor;float radius;projectLabel(id,anchor,radius);
 if(p.y==3){O=vec4(anchor,radius,1);return;}
 int mode=int(texelFetch(iChannel2,ivec2((META+5),0),0).x+0.5);
 vec4 state=texelFetch(iChannel1,ivec2(META+id,2),0);bool initial=!passReady(texelFetch(iChannel1,ivec2((META+11),0),0),311.0)||state.w<0.5||state.z<1.0||state.z>64.0||any(isnan(state))||any(isinf(state));
 float preferred=atan(anchor.y-SCENE_Y,anchor.x-440.0),angle=initial?preferred:state.x;
 float blend=1.0-exp(-clamp(iTimeDelta,0.001,0.05)*18.0);
 int unit=int(texelFetch(iChannel2,ivec2((META+15),0),0).z+0.5);
 float T=clamp((mode==1?1800.0:TEMPERATURE_K+float(id)*TEMPERATURE_STEP_K)+cam.z,500.0,6500.0),value=displayTemperature(T,unit);
 float digitCount=value>=10000.0?5.0:(value>=1000.0?4.0:(value>=100.0?3.0:(value>=10.0?2.0:1.0)));
 float desiredWidth=3.75*(digitCount+(unit==0?2.0:3.0)+(mode==0?0.0:(id==4?4.0:3.0)))+1.5;
 float width=initial?desiredWidth:mix(state.z,desiredWidth,blend);
 vec2 goal=labelGoal(id,anchor,radius,vec2(width,9),angle,initial);
 if(p.y==4){O=vec4(goal,0,1);return;}
 float delta=atan(sin(goal.x-angle),cos(goal.x-angle));angle+=delta*blend;
 float extra=initial?goal.y:mix(state.y,goal.y,blend);
 O=vec4(atan(sin(angle),cos(angle)),extra,width,1);return;
 }
 // Dense separable Gaussian: each source pixel contributes a smooth kernel,
 // never a sparse constellation of displaced sphere images.
 // Runs only inside the scaled scene block; sigma stays 6 screen pixels.
 if(p.x>=size.x||p.y>=size.y){O=vec4(0);return;}
 float sigma=6.0*scale,stride=max(1.0,2.5*sigma/float(BLOOM_TAPS));
 vec3 sum=vec3(0);float weights=0.0;
 for(int tap=-BLOOM_TAPS;tap<=BLOOM_TAPS;tap++){
 int x=int(round(float(tap)*stride));float w=exp(-float(x*x)/(2.0*sigma*sigma));
 ivec2 q=clamp(p+ivec2(x,0),ivec2(0),size-1);
 if(q.x==(META+10)&&q.y==0)q.x-=20;
 sum+=bloomSource(texelFetch(iChannel0,q,0).rgb)*w;weights+=w;
 }
 O=vec4(sum/weights,1);
}
