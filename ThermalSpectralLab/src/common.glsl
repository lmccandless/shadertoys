/*! Thermal Spectral Lab © 2026 Logan McCandless @LoganM78494 @wotanrd 
Original shader code: CC BY-NC-ND 4.0 
https://creativecommons.org/licenses/by-nc-nd/4.0/
*/
// Thermal Spectral Lab. Inspired by Maximilian Tarpini (2026), Wilkie & Weidlich (2011). https://www.linkedin.com/pulse/thermal-light-emission-from-glowing-objects-maximilian-tarpini-m7kpe/
// Optical constants: Johnson & Christy 1972/1974, refractiveindex.info (CC0).
// Spectral CIE 1931 2 degree data. Original implementation; no external assets.
// Roughness trapping is an approximation, not the article's unpublished calibrated fit.
//
// LITE BUILD. QUALITY 0 (default) is the mobile-friendly transport: one ray per pixel,
// one reflection bounce, cheap soft shadows and a lighter bloom, rendered at an
// adaptive resolution. QUALITY 1 restores the original 4xAA, 4-bounce transport with
// exact disk-overlap shadows. Set RENDER_SCALE to a fixed value (e.g. 1.0) to turn the
// adaptive resolution off; 0.0 = adaptive between MIN_SCALE and MAX_SCALE.
#define QUALITY 0
#define RENDER_SCALE 0.0
#define MIN_SCALE 0.35
#define MAX_SCALE 1.0
#define TEMPERATURE_K 500.0
#define TEMPERATURE_STEP_K 500.0
#define MATERIAL 1 // 0 silver, 1 gold, 2 copper, 3 iron, 4 ceramic, 5 blackbody
#define ENVIRONMENT_STRENGTH 0.65
#define ROUGHNESS 0.045
#define EMISSION_LEVEL 0.5 // Slider midpoint = 1x emitted radiance
#define EMISSION_GAIN 5.0
#define EXPOSURE 1.0
#define AUTO_HEAT 1.0
#define HEAT_SPEED 1.0471975512 // Radians/second: six-second full temperature cycle.
const float PI=3.14159265359;
float conductor(float c,vec2 nk){
 float n=nk.x,k=nk.y,c2=c*c,s2=1.0-c2;
 float t=n*n-k*k-s2;
 float a2b2=sqrt(t*t+4.0*n*n*k*k);
 float a=sqrt(max(0.0,0.5*(a2b2+t)));
 float rs=(a2b2+c2-2.0*a*c)/(a2b2+c2+2.0*a*c);
 float rp=rs*(c2*a2b2+s2*s2-2.0*a*c*s2)/(c2*a2b2+s2*s2+2.0*a*c*s2);
 return clamp(0.5*(rs+rp),0.0,1.0);
}
float ceramic(float c){
 float ct=sqrt(1.0-(1.0-c*c)/2.25);
 float rs=(c-1.5*ct)/(c+1.5*ct),rp=(1.5*c-ct)/(1.5*c+ct);
 return 0.5*(rs*rs+rp*rp);
}
// Six spheres of radius0.92 share the same ground clearance.
vec3 centre(int m){
 float x=m==0||m==3?0.0:(m<3?2.554774941:-2.554774941);
 float z=m==0?2.95:(m==3?-2.95:(m==1||m==5?1.475:-1.475));return vec3(x,0.93,z);
}
float sphere(vec3 o,vec3 d,vec3 c,float r){vec3 q=o-c;float b=dot(q,d),h=b*b-dot(q,q)+r*r;return h<0.0?1e5:(-b-sqrt(h)>0.001?-b-sqrt(h):1e5);}
// Accuracy model: smooth opaque Fresnel emissivity; no empirical roughness trapping.
// Cer is a gray n=1.5 dielectric with diffuse base0.32, not measured ceramic data.
// 48 samples at 10nm (360-830nm). Against the 95-sample 5nm integral this changes
// emitted Y by <0.1% and D65 reflectance by <0.07%; each sample carries weight 2.
const int SPECTRAL_COUNT=48;
const float SPECTRAL_START_NM=360.0;
const float SPECTRAL_STEP_NM=10.0;
const float DIELECTRIC_BASE=0.32;
const vec3 RGB_LUMA=vec3(0.2126390059,0.7151686788,0.0721923154);
const float D65_Y_SUM=2113.457307;
const vec3 D65_WHITE_RGB=vec3(1.0000732246,0.99998751391,0.99990801255);
// Compact layout, valid on any canvas of at least 211x68 pixels:
// emission LUTs are 64(T)x32(mu) tiles, three across and two high (x<192, y<64);
// D65 reflectance rows for the four metals sit at y=64..67 (x<128);
// all per-frame state lives in the META block, x=META..META+18, y<5.
const int LUT_T=64;
const int META=192;
ivec2 lutTile(int m){return ivec2((m%3)*LUT_T,(m/3)*32);}
vec3 thermal(sampler2D lut,int m,float T,float mu){
 // Log radiance is nearly linear in reciprocal temperature (Wien limit).
 float u=(1.0/500.0-1.0/clamp(T,500.0,6500.0))/(1.0/500.0-1.0/6500.0);
 float cosine=clamp(mu,0.0,1.0);vec2 q=vec2(u*float(LUT_T-1),sqrt(cosine)*31.0);
 ivec2 o=lutTile(m),b=ivec2(floor(q)),z=o+b,hi=o+ivec2(LUT_T-1,31);vec2 f=fract(q);
 float mu0=float(b.y)/31.0,mu1=float(min(b.y+1,31))/31.0;mu0*=mu0;mu1*=mu1;
 f.y=clamp((cosine-mu0)/max(mu1-mu0,1e-8),0.0,1.0);
 vec3 a=mix(texelFetch(lut,z,0).xyz,texelFetch(lut,min(z+ivec2(1,0),hi),0).xyz,f.x);
 vec3 b1=mix(texelFetch(lut,min(z+ivec2(0,1),hi),0).xyz,texelFetch(lut,min(z+ivec2(1),hi),0).xyz,f.x);
 // Angular emissivity approaches zero linearly; interpolating its log is incorrect.
 return mix(exp(a),exp(b1),f.y);
}
vec3 rgb(vec3 x){return vec3(dot(x,vec3(3.2409699419,-1.5373831776,-0.4986107603)),dot(x,vec3(-0.9692436363,1.8759675015,0.0415550574)),dot(x,vec3(0.0556300797,-0.2039769589,1.0569715142)));}
// Fixed scene radiance unit:2000K blackbody Y using the 95-point 5nm integral
// (the 10nm table is weighted to the same units).
// This reference unit is not per-temperature normalization or absolute display calibration.
float thermalRadianceScale(float level){return (EMISSION_GAIN/679.00967447)*exp2(6.0*(level-0.5));}

// Shared compact layout; Common has no Shadertoy uniforms.
const float UI_HEIGHT=68.0;
const float SCENE_Y=288.0;
const float CAMERA_DISTANCE=9.4117647059; //16/1.70: reference screenshot zoom.
vec2 sliderRange(int id){if(id==6)return vec2(680,845);if(id==4)return vec2(194,274);if(id==5)return vec2(294,374);if(id==2)return vec2(310,470);if(id==3)return vec2(500,650);return vec2(20,280);}
float sliderValue(vec2 m,int id){vec2 r=sliderRange(max(id,0));return clamp((m.x-r.x)/(r.y-r.x),0.0,1.0);}
int uiHit(vec2 m,vec2 size,float advanced,vec4 prefs){
 vec2 q=m*vec2(880,495)/size;
 if(prefs.y>0.5)return q.x>=844.0&&q.y>=0.0&&q.y<=32.0?15:-1;
 if(q.y<0.0||q.y>UI_HEIGHT)return -1;
 if(advanced>0.5&&q.y>=21.0&&q.y<38.0&&q.x>=310.0&&q.x<416.0)return 20; // Temperature-normalization label toggle.
 if(q.y<38.0){int col=q.x<295.0?0:(q.x<485.0?1:(q.x<665.0?2:3));return col==3?6:(advanced>0.5?col+1:(col==0?0:(col==1?17:18)));}
 if(q.x>=844.0)return 15;
 if(q.x>=764.0&&q.x<837.0)return 13;
 if(q.x>=606.0&&q.x<681.0)return 7;
 if(q.x>=504.0&&q.x<582.0)return 14;
 if(q.x>=394.0&&q.x<478.0)return 16;
 if(q.x>=188.0&&q.x<384.0)return advanced>0.5?(q.x<284.0?4:5):8;
 if(q.x>=20.0&&q.x<166.0)return q.x<76.0?10:(q.x<122.0?11:12);
 return 9;
}
float displayTemperature(float kelvin,int unit){return unit==0?kelvin:(unit==1?kelvin-273.15:(kelvin-273.15)*1.8+32.0);}
float labelReach(float radius,vec2 dir,vec2 halfBox){return radius+18.0+dot(abs(dir),halfBox);}

// Distinct non-unit signatures reject unbound/dummy channels and stale buffer history.
const float SPECTRAL_TAG=21.0;
const float STATE_TAG=31.0;
bool spectralReady(vec4 h){return all(lessThan(abs(h-vec4(1387,float(SPECTRAL_COUNT),SPECTRAL_TAG,1)),vec4(0.1)));}
bool passReady(vec4 h,float stage){return all(lessThan(abs(h-vec4(stage,SPECTRAL_TAG,STATE_TAG,1)),vec4(0.1)));}
// Render scale: B, C and D draw the scene into the lower-left scale*resolution block.
ivec2 sceneSize(vec2 res,float scale){return max(ivec2(ceil(res*scale)),ivec2(1));}
vec3 bloomSource(vec3 c){float y=max(dot(c,RGB_LUMA),0.0);return c*smoothstep(1.0,2.0,y);}
