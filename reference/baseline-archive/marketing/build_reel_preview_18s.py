#!/usr/bin/env python3
"""Render the 18-second motion proof for marketing posters 01-03.

Install dependencies outside the repository, then run:
  python3 -m pip install --target /tmp/reeldeps -r marketing/video_requirements.txt
  PYTHONPATH=/tmp/reeldeps python3 marketing/build_reel_preview_18s.py

Output: marketing/reel_preview_first_3_18s.mp4
"""
import cv2, numpy as np, math, wave, subprocess, sys
from pathlib import Path
sys.path.insert(0,'/tmp/reeldeps')
import imageio_ffmpeg
ROOT=Path(__file__).resolve().parent
WORK=Path('/tmp/sweeda_reel_preview_18')
WORK.mkdir(parents=True,exist_ok=True)
FPS=30; DURATION=18.0; N=int(FPS*DURATION)
OUT=ROOT/'reel_preview_first_3_18s.mp4'
# Rebuild source layers deterministically.
prep_script=ROOT/'video_tools/prepare_preview_layers.py'
exec(compile(prep_script.read_bytes(),str(prep_script),'exec'))

# Approved first-scene render.
cap=cv2.VideoCapture(str(ROOT/'wing_animation_test_6s.mp4'))
scene1=[]
while True:
 ok,f=cap.read()
 if not ok: break
 scene1.append(f)
cap.release()
assert len(scene1)==180, len(scene1)

p2clean=cv2.imread(str(WORK/'p2_clean.png'))
p2l=cv2.imread(str(WORK/'p2_left.png'),cv2.IMREAD_UNCHANGED)
p2r=cv2.imread(str(WORK/'p2_right.png'),cv2.IMREAD_UNCHANGED)
p3clean=cv2.imread(str(WORK/'p3_clean.png'))
p3l=cv2.imread(str(WORK/'p3_left.png'),cv2.IMREAD_UNCHANGED)
p3r=cv2.imread(str(WORK/'p3_right.png'),cv2.IMREAD_UNCHANGED)
p1=cv2.imread(str(ROOT/'posts/poster_01_intro.png'))
p2orig=cv2.imread(str(ROOT/'posts/poster_02_publish.png'))
p3orig=cv2.imread(str(ROOT/'posts/poster_03_appointments.png'))

def clamp(x,a=0.,b=1.): return max(a,min(b,x))
def smooth(u): u=clamp(u); return u*u*(3-2*u)
def easeout(u): u=clamp(u); return 1-(1-u)**3
def lerp(a,b,u): return a+(b-a)*u

def wing_motion(t):
 if t<.20:return .73,18
 if t<.40:
  u=smooth((t-.20)/.20); return lerp(.73,.67,u),lerp(18,22,u)
 if t<1.15:
  u=easeout((t-.40)/.75); return lerp(.67,1.045,u),lerp(22,-4,u)
 if t<1.52:
  u=smooth((t-1.15)/.37); return lerp(1.045,.992,u),lerp(-4,1.2,u)
 if t<1.82:
  u=smooth((t-1.52)/.30); return lerp(.992,1,u),lerp(1.2,0,u)
 breath=math.sin((t-1.82)*math.pi*.9)*math.exp(-(t-1.82)*.22)
 return 1+.0035*breath,-.35*breath

def deform(im,side,op,bend,t,rootx,rooty,maxd):
 h,w=im.shape[:2]; yy,xx=np.indices((h,w),dtype=np.float32)
 sx=rootx+(xx-rootx)/max(op,.5); q=np.clip(np.abs(sx-rootx)/maxd,0,1); sy=yy-bend*q**1.55
 out=cv2.remap(im,sx.astype(np.float32),sy.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT,borderValue=(0,0,0,0))
 # center-to-tip gold sweep
 if .48<=t<=1.56:
  u=smooth((t-.48)/1.08); tip=3 if side=='left' else w-3; center=lerp(rootx,tip,u)
  band=np.exp(-((xx-center)/max(10,w*.075))**2); a=out[:,:,3]/255.; strength=math.sin(math.pi*u)*.18
  mix=(band*a*strength)[:,:,None]; gold=np.zeros_like(out[:,:,:3],np.float32); gold[:]=[35,195,255]
  out[:,:,:3]=np.clip(out[:,:,:3]*(1-mix)+gold*mix,0,255).astype(np.uint8)
 shade=.79+.21*clamp((op-.67)/.33); out[:,:,:3]=np.clip(out[:,:,:3]*shade,0,255).astype(np.uint8)
 return out

def add_rgba(dst,fg,x,y,opacity=1.):
 h,w=fg.shape[:2]; H,W=dst.shape[:2]; x0=max(0,x);y0=max(0,y);x1=min(W,x+w);y1=min(H,y+h)
 if x1<=x0 or y1<=y0:return
 f=fg[y0-y:y1-y,x0-x:x1-x]; a=f[:,:,3:4].astype(np.float32)/255*opacity
 roi=dst[y0:y1,x0:x1].astype(np.float32); dst[y0:y1,x0:x1]=np.clip(f[:,:,:3]*a+roi*(1-a),0,255).astype(np.uint8)

def add_wing(dst,im,x,y,side,op,bend,t,root,maxd,scale=1.):
 f=deform(im,side,op,bend,t,*root,maxd)
 if scale!=1:
  f=cv2.resize(f,(round(f.shape[1]*scale),round(f.shape[0]*scale)),interpolation=cv2.INTER_LANCZOS4)
 alpha=f[:,:,3]; aura=cv2.GaussianBlur(alpha,(0,0),8*scale); shadow=cv2.GaussianBlur(alpha,(0,0),4*scale)
 for layer,oy,color,amt in [(aura,1,(28,112,190),.11*clamp((op-.67)/.33)),(shadow,4,(0,0,0),.52)]:
  h,w=f.shape[:2]; H,W=dst.shape[:2]; yy=y+oy; x0=max(0,x);y0=max(0,yy);x1=min(W,x+w);y1=min(H,yy+h)
  if x1>x0 and y1>y0:
   a=layer[y0-yy:y1-yy,x0-x:x1-x].astype(np.float32)/255*amt; roi=dst[y0:y1,x0:x1].astype(np.float32); c=np.empty_like(roi); c[:]=color
   dst[y0:y1,x0:x1]=np.clip(c*a[:,:,None]+roi*(1-a[:,:,None]),0,255).astype(np.uint8)
 add_rgba(dst,f,x,y)

def pulse(t,start,d=.62):
 u=(t-start)/d
 if not 0<=u<=1:return 0
 return math.sin(math.pi*u)**1.4

def gold_cutout(src,box):
 x0,y0,x1,y1=box; crop=src[y0:y1,x0:x1].copy(); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV); gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY)
 mask=(((hsv[:,:,1]>36)&(hsv[:,:,2]>54))|(gray>148)).astype(np.uint8)*255
 mask=cv2.GaussianBlur(mask,(0,0),.5); out=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA); out[:,:,3]=mask
 return out,(x0,y0)

# Poster 2 exact gold icon layers.
p2icons=[gold_cutout(p2orig,b) for b in [(78,535,330,740),(435,535,704,745),(75,875,325,1055),(430,875,707,1070)]]

def scene2_frame(t):
 frame=p2clean.copy(); op,b=wing_motion(t); opr,br=wing_motion(max(0,t-2/FPS))
 add_wing(frame,p2l,20,32,'left',op,b,t,(181,205),176)
 add_wing(frame,p2r,543,32,'right',opr,br,t,(24,205),176)
 # Individually wake the four service icons without moving their text.
 for (layer,(x,y)),st in zip(p2icons,[1.68,2.32,2.96,3.60]):
  q=pulse(t,st); 
  if q<=0: continue
  sc=1+.045*q; nw,nh=round(layer.shape[1]*sc),round(layer.shape[0]*sc)
  fg=cv2.resize(layer,(nw,nh),interpolation=cv2.INTER_LANCZOS4)
  xx=round(x-(nw-layer.shape[1])/2); yy=round(y-(nh-layer.shape[0])/2-5*q)
  # tiny gold halo
  glow=fg.copy(); glow[:,:,3]=cv2.GaussianBlur(glow[:,:,3],(0,0),4)
  add_rgba(frame,glow,xx,yy,.22*q); add_rgba(frame,fg,xx,yy,.72*q)
 # Gentle poster breathing, 0.6% maximum.
 crop=frame[5:1370]; out=cv2.resize(crop,(1080,1920),interpolation=cv2.INTER_LANCZOS4)
 z=1+.006*smooth(clamp((t-1.2)/4.5)); nw,nh=round(1080*z),round(1920*z); big=cv2.resize(out,(nw,nh),interpolation=cv2.INTER_LANCZOS4)
 return big[(nh-1920)//2:(nh-1920)//2+1920,(nw-1080)//2:(nw-1080)//2+1080]

# Poster 3 exact layer crops and a true vertical canvas.
def resize_w(img,w,h=None):
 ih,iw=img.shape[:2]; h=round(ih*w/iw) if h is None else h
 return cv2.resize(img,(w,h),interpolation=cv2.INTER_LANCZOS4)
def feather_alpha(h,w,n):
 yy,xx=np.indices((h,w)); edge=np.minimum.reduce([xx,w-1-xx,yy,h-1-yy]).astype(np.float32); a=np.clip(edge/max(1,n),0,1); return a*a*(3-2*a)
def layer_bgra(img,feather=0):
 o=cv2.cvtColor(img,cv2.COLOR_BGR2BGRA); o[:,:,3]=255 if not feather else (feather_alpha(*img.shape[:2],feather)*255).astype(np.uint8); return o
header=resize_w(p3clean[24:252,210:814],900); headerL=layer_bgra(header,28)
title=resize_w(p3orig[252:380,105:919],950); titleL=layer_bgra(title,22)
cards=[resize_w(x,470,384) for x in [p3orig[390:680,150:505],p3orig[390:680,519:874],p3orig[688:974,150:505],p3orig[688:974,519:874]]]
cardL=[layer_bgra(x,8) for x in cards]
contact=resize_w(p1[1250:1370,170:598],720); contactL=layer_bgra(contact,18)
rng=np.random.default_rng(113)
base3=np.zeros((1920,1080,3),np.float32); base3[:]=[10,10,11]; base3+=rng.normal(0,1.15,(1920,1080,1)); base3=np.clip(base3,0,255).astype(np.uint8)
cv2.rectangle(base3,(22,22),(1057,1897),(38,126,192),2,cv2.LINE_AA); cv2.rectangle(base3,(28,28),(1051,1891),(18,63,98),1,cv2.LINE_AA)

def animated_layer(dst,layer,x,y,t,start,d=.5,rise=22,scale0=.965):
 u=smooth((t-start)/d)
 if u<=0:return
 sc=lerp(scale0,1,u); nw,nh=round(layer.shape[1]*sc),round(layer.shape[0]*sc); fg=cv2.resize(layer,(nw,nh),interpolation=cv2.INTER_LANCZOS4)
 xx=round(x+(layer.shape[1]-nw)/2); yy=round(y+(layer.shape[0]-nh)/2+rise*(1-u)); add_rgba(dst,fg,xx,yy,u)

def scene3_frame(t):
 f=base3.copy(); add_rgba(f,headerL,90,65)
 op,b=wing_motion(t); opr,br=wing_motion(max(0,t-2/FPS)); sc=900/604
 # original positions relative to the header crop
 add_wing(f,p3l,round(90+(238-210)*sc),round(65+(30-24)*sc),'left',op,b,t,(118,119),112,sc)
 add_wing(f,p3r,round(90+(654-210)*sc),round(65+(30-24)*sc),'right',opr,br,t,(14,119),112,sc)
 animated_layer(f,titleL,65,375,t,.25,.55,10,.98)
 for L,(x,y),st in zip(cardL,[(55,555),(555,555),(55,990),(555,990)],[1.15,1.48,1.82,2.15]): animated_layer(f,L,x,y,t,st,.48,24,.96)
 animated_layer(f,contactL,180,1655,t,2.85,.60,16,.98)
 # contextual glints: calendar, bell, star.
 for cx,cy,st in [(248,635,2.65),(748,635,3.15),(748,1075,3.68)]:
  q=pulse(t,st,.48)
  if q:
   ov=f.copy(); cv2.circle(ov,(cx,cy),round(10+22*q),(95,220,255),-1,cv2.LINE_AA); f=cv2.addWeighted(ov,.10*q,f,1-.10*q,0)
 return f

def transition(a,b,u,direction=1):
 u=smooth(u); H,W=a.shape[:2]; x=np.arange(W,dtype=np.float32)
 center=lerp(-150,W+150,u) if direction>0 else lerp(W+150,-150,u)
 m=np.clip(((center-x)/120+.5) if direction>0 else ((x-center)/120+.5),0,1)
 m=(m*m*(3-2*m))[None,:,None]
 out=(a*(1-m)+b*m).astype(np.float32)
 band=np.exp(-((x-center)/55)**2)[None,:,None]
 gold=np.zeros_like(out); gold[:]=[40,150,235]
 out=out*(1-band*.20)+gold*(band*.20)
 return np.clip(out,0,255).astype(np.uint8)

def frame_at(i):
 g=i/FPS
 if g<5.55:return scene1[min(i,179)]
 if g<6.0:
  u=(g-5.55)/.45; return transition(scene1[min(i,179)],scene2_frame(g-5.55),u,1)
 if g<11.55:return scene2_frame(g-5.55)
 if g<12.0:
  u=(g-11.55)/.45; return transition(scene2_frame(g-5.55),scene3_frame(g-11.55),u,-1)
 return scene3_frame(g-11.55)

# Original lightweight cinematic sound design: ambient pad + wing/transition cues.
sr=48000; ns=int(sr*DURATION); tt=np.arange(ns)/sr; audio=np.zeros(ns)
def tone(freq,start,end,amp=.02,phase=0):
 sel=(tt>=start)&(tt<end); x=(tt[sel]-start)/(end-start); env=np.sin(np.pi*x)**.65
 sig=(np.sin(2*np.pi*freq*tt[sel]+phase)+.23*np.sin(2*np.pi*freq*2*tt[sel]+phase*.5))*env
 audio[sel][:] # keep lint calm
 return sel,sig*amp
for start,freqs in [(0,[146.83,220,349.23]),(6,[116.54,174.61,293.66]),(12,[130.81,196,329.63])]:
 for j,fr in enumerate(freqs):
  sel,sig=tone(fr,start,min(18,start+6.4),.012/(j+1),j*.7); audio[sel]+=sig
# filtered whoosh helper
rng=np.random.default_rng(20260827); noise=rng.normal(0,1,ns); F=np.fft.rfft(noise); freq=np.fft.rfftfreq(ns,1/sr); shp=np.exp(-((freq-720)/1000)**2)*(1-np.exp(-(freq/90)**2))*np.exp(-(freq/5200)**4); bed=np.fft.irfft(F*shp,n=ns)
def add_whoosh(at,amp=.18,dur=1.15):
 sel=(tt>=at)&(tt<=at+dur); u=(tt[sel]-at)/dur; audio[sel]+=bed[sel]*(np.maximum(np.sin(np.pi*u),0)**1.7)*amp
for at in [.32,5.48,5.82,11.48,11.82]:add_whoosh(at,.17 if at in [.32,5.82,11.82] else .10)
def chime(at,fr,amp=.025,dur=.7):
 sel=(tt>=at)&(tt<at+dur); x=tt[sel]-at; audio[sel]+=(np.sin(2*np.pi*fr*x)+.45*np.sin(2*np.pi*2*fr*x))*np.exp(-x*5)*amp
for at,fr in [(7.65,660),(8.3,784),(8.95,988),(9.6,880),(14.2,740),(14.7,1110),(15.7,880)]:chime(at,fr)
audio/=max(np.max(np.abs(audio)),1e-9); audio*=.48
stereo=np.column_stack([audio,audio]); wav=WORK/'preview18.wav'
with wave.open(str(wav),'wb') as wf: wf.setnchannels(2);wf.setsampwidth(2);wf.setframerate(sr);wf.writeframes((stereo*32767).astype('<i2').tobytes())
ff=imageio_ffmpeg.get_ffmpeg_exe(); cmd=[ff,'-y','-f','rawvideo','-pix_fmt','bgr24','-s','1080x1920','-r','30','-i','-','-i',str(wav),'-c:v','libx264','-preset','medium','-crf','18','-profile:v','high','-pix_fmt','yuv420p','-movflags','+faststart','-c:a','aac','-b:a','192k','-ar','48000','-t','18',str(OUT)]
p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
try:
 for i in range(N): p.stdin.write(frame_at(i).tobytes())
finally:p.stdin.close()
err=p.stderr.read().decode(); ret=p.wait()
if ret:print(err,file=sys.stderr);raise SystemExit(ret)
print(OUT);print(err.splitlines()[-1])
