#!/usr/bin/env python3
"""Build the approved 60-second vertical marketing reel and derivatives.

Install tools outside the repository:
  python3 -m pip install --target /tmp/reeldeps -r marketing/video_requirements.txt

Render:
  PYTHONPATH=/tmp/reeldeps python3 marketing/build_reel_60s.py

Outputs:
  reels_promo_60s.mp4          1080x1920, music + sound design
  reels_promo_silent.mp4       1080x1920, no audio (platform trend use)
  reels_promo_whatsapp.mp4      720x1280, compact distribution copy
"""
import cv2, numpy as np, math, wave, subprocess, sys
from pathlib import Path
sys.path.insert(0,'/tmp/reeldeps')
import imageio_ffmpeg
ROOT=Path(__file__).resolve().parent
WORK=Path('/tmp/sweeda_reel_60'); WORK.mkdir(parents=True,exist_ok=True)
FPS=30; DURATION=60.; N=int(FPS*DURATION)
OUT=ROOT/'reels_promo_60s.mp4'
# Rebuild independent wing layers and clean plates.
prep_script=ROOT/'video_tools/prepare_full_layers.py'
exec(compile(prep_script.read_bytes(),str(prep_script),'exec'))

# The approved 18-second opening is decoded sequentially to avoid retaining
# several gigabytes of full-HD raw frames in memory.
opening=cv2.VideoCapture(str(ROOT/'reel_preview_first_3_18s.mp4'))
assert opening.isOpened()

sources={n:cv2.imread(str(next((ROOT/'posts').glob(f'poster_{n:02d}_*.png')))) for n in range(4,11)}
clean={n:(cv2.imread(str(WORK/f'p{n}_clean.png')) if n>=5 else sources[n].copy()) for n in range(4,11)}
wings={n:(cv2.imread(str(WORK/f'p{n}_left.png'),-1),cv2.imread(str(WORK/f'p{n}_right.png'),-1)) for n in range(5,11)}
logos={n:cv2.imread(str(WORK/f'p{n}_logo.png'),-1) for n in range(5,11)}

def clamp(x,a=0.,b=1.): return max(a,min(b,x))
def smooth(u): u=clamp(u); return u*u*(3-2*u)
def easeout(u): u=clamp(u); return 1-(1-u)**3
def lerp(a,b,u): return a+(b-a)*u

def wing_motion(t,hero=False):
 closed=.78 if hero else .70
 if t<.20:return closed+0.04,15 if hero else 18
 if t<.40:
  u=smooth((t-.20)/.20); return lerp(closed+.04,closed,u),lerp(15 if hero else 18,19 if hero else 22,u)
 if t<1.15:
  u=easeout((t-.40)/.75); return lerp(closed,1.04,u),lerp(19 if hero else 22,-3.5,u)
 if t<1.52:
  u=smooth((t-1.15)/.37); return lerp(1.04,.993,u),lerp(-3.5,1.0,u)
 if t<1.82:
  u=smooth((t-1.52)/.30); return lerp(.993,1,u),lerp(1,0,u)
 breath=math.sin((t-1.82)*math.pi*.86)*math.exp(-(t-1.82)*.22)
 return 1+.0035*breath,-.30*breath

def deform(im,side,op,bend,t,root,maxd):
 h,w=im.shape[:2]; rootx,rooty=root; yy,xx=np.indices((h,w),dtype=np.float32)
 sx=rootx+(xx-rootx)/max(op,.55); q=np.clip(np.abs(sx-rootx)/maxd,0,1); sy=yy-bend*q**1.55
 out=cv2.remap(im,sx.astype(np.float32),sy.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT,borderValue=(0,0,0,0))
 # Premium center-to-tip reflection along the gold feathers.
 if .48<=t<=1.56:
  u=smooth((t-.48)/1.08); tip=2 if side=='left' else w-2; center=lerp(rootx,tip,u)
  band=np.exp(-((xx-center)/max(9,w*.07))**2); a=out[:,:,3]/255.; mix=(band*a*math.sin(math.pi*u)*.18)[:,:,None]
  gold=np.empty_like(out[:,:,:3],np.float32); gold[:]=[35,195,255]
  out[:,:,:3]=np.clip(out[:,:,:3]*(1-mix)+gold*mix,0,255).astype(np.uint8)
 shade=.80+.20*clamp((op-.70)/.30); out[:,:,:3]=np.clip(out[:,:,:3]*shade,0,255).astype(np.uint8)
 return out

def add_rgba(dst,fg,x,y,opacity=1.):
 h,w=fg.shape[:2]; H,W=dst.shape[:2]; x0=max(0,x);y0=max(0,y);x1=min(W,x+w);y1=min(H,y+h)
 if x1<=x0 or y1<=y0:return
 f=fg[y0-y:y1-y,x0-x:x1-x]; a=f[:,:,3:4].astype(np.float32)/255*opacity; roi=dst[y0:y1,x0:x1].astype(np.float32)
 dst[y0:y1,x0:x1]=np.clip(f[:,:,:3]*a+roi*(1-a),0,255).astype(np.uint8)

def add_wing(dst,im,x,y,side,op,bend,t,root,maxd):
 f=deform(im,side,op,bend,t,root,maxd); alpha=f[:,:,3]
 for layer,oy,color,amt in [(cv2.GaussianBlur(alpha,(0,0),8),1,(28,112,190),.11*clamp((op-.70)/.30)),(cv2.GaussianBlur(alpha,(0,0),4),4,(0,0,0),.52)]:
  h,w=f.shape[:2]; H,W=dst.shape[:2]; yy=y+oy;x0=max(0,x);y0=max(0,yy);x1=min(W,x+w);y1=min(H,yy+h)
  if x1>x0 and y1>y0:
   a=layer[y0-yy:y1-yy,x0-x:x1-x].astype(np.float32)/255*amt;roi=dst[y0:y1,x0:x1].astype(np.float32);c=np.empty_like(roi);c[:]=color
   dst[y0:y1,x0:x1]=np.clip(c*a[:,:,None]+roi*(1-a[:,:,None]),0,255).astype(np.uint8)
 add_rgba(dst,f,x,y)

def gold_cutout(src,box):
 x0,y0,x1,y1=box; crop=src[y0:y1,x0:x1].copy(); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
 h,s,v=cv2.split(hsv); mask=((h>=5)&(h<=42)&(s>38)&(v>52)).astype(np.uint8)*255; mask=cv2.GaussianBlur(mask,(0,0),.55)
 out=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA);out[:,:,3]=mask;return out,(x0,y0)
def pulse(t,start,d=.60):
 u=(t-start)/d; return math.sin(math.pi*u)**1.45 if 0<=u<=1 else 0

def apply_cutout_pulse(frame,item,q):
 if q<=0:return
 layer,(x,y)=item;sc=1+.042*q;nw,nh=round(layer.shape[1]*sc),round(layer.shape[0]*sc);fg=cv2.resize(layer,(nw,nh),interpolation=cv2.INTER_LANCZOS4)
 xx=round(x-(nw-layer.shape[1])/2);yy=round(y-(nh-layer.shape[0])/2-4*q);glow=fg.copy();glow[:,:,3]=cv2.GaussianBlur(glow[:,:,3],(0,0),4)
 add_rgba(frame,glow,xx,yy,.24*q);add_rgba(frame,fg,xx,yy,.76*q)

icon_boxes={
4:[(55,460,345,765),(405,460,715,765),(55,810,345,1125),(405,810,715,1125)],
5:[(45,650,355,935),(405,650,723,935),(45,960,355,1255),(405,960,723,1255)],
6:[(75,510,385,865),(380,510,700,865),(120,850,350,1170),(395,850,710,1170)],
7:[(45,430,360,765),(400,430,725,765),(45,755,360,1100),(400,755,725,1100)],
8:[(500,610,735,850),(500,825,735,1065),(500,1035,735,1285)],
9:[(55,650,360,950),(395,650,715,950),(55,930,360,1250),(395,930,715,1250)],
10:[(28,665,245,980),(515,665,740,980),(25,915,245,1225),(510,915,742,1225),(205,555,563,1240)],
}
icons={n:[gold_cutout(sources[n],b) for b in icon_boxes[n]] for n in icon_boxes}

# Side masks for the geometric ornaments on poster 04.
p4h=cv2.cvtColor(sources[4][:330],cv2.COLOR_BGR2HSV);hh,ss,vv=cv2.split(p4h);p4gold=((hh>=5)&(hh<=42)&(ss>40)&(vv>55)).astype(np.float32)
geo=np.zeros_like(p4gold);cv2.fillPoly(geo,[np.array([(5,0),(230,0),(190,70),(95,160),(40,320),(0,330)],np.int32),np.array([(763,0),(538,0),(578,70),(673,160),(728,320),(767,330)],np.int32)],1);p4gold*=geo

def ornament_glint(frame,t):
 if not .38<=t<=1.65:return
 u=smooth((t-.38)/1.27);x=np.arange(768,dtype=np.float32);centers=[lerp(20,210,u),lerp(748,558,u)]
 band=sum(np.exp(-((x-c)/24)**2) for c in centers)[None,:];a=p4gold*band*math.sin(math.pi*u)*.22
 roi=frame[:330].astype(np.float32);col=np.empty_like(roi);col[:]=[45,205,255];frame[:330]=np.clip(roi*(1-a[:,:,None])+col*a[:,:,None],0,255).astype(np.uint8)

def scene_frame(n,t):
 frame=clean[n].copy()
 if n==4:ornament_glint(frame,t)
 else:
  c=CONFIG[n];left,right=wings[n];hero=n==10;op,b=wing_motion(t,hero);opr,br=wing_motion(max(0,t-2/FPS),hero)
  lx,ly=c['boxes'][0][:2];rx,ry=c['boxes'][1][:2];lw=left.shape[1];rw=right.shape[1]
  add_wing(frame,left,lx,ly,'left',op,b,t,c['roots'][0],max(70,lw*.88));add_wing(frame,right,rx,ry,'right',opr,br,t,c['roots'][1],max(70,rw*.88))
  logo=logos[n];x,y=c['logo'][:2];add_rgba(frame,logo,x,y)
 # Context-specific icon rhythm. The final phone gets a slower, larger CTA pulse.
 starts=np.linspace(1.55,3.65,len(icons[n]))
 for item,st in zip(icons[n],starts):apply_cutout_pulse(frame,item,pulse(t,float(st),.68 if n==10 else .58))
 # Final CTA glow around the approved phone number.
 if n==10 and t>4.05:
  q=.5+.5*math.sin((t-4.05)*math.pi*1.2);ov=frame.copy();cv2.rectangle(ov,(206,1265),(562,1355),(72,185,245),-1,cv2.LINE_AA);frame=cv2.addWeighted(ov,.025+.035*q,frame,.975-.035*q,0)
 crop=frame[5:1370];out=cv2.resize(crop,(1080,1920),interpolation=cv2.INTER_LANCZOS4)
 z=1+.0045*smooth(clamp((t-1.0)/4.8));nw,nh=round(1080*z),round(1920*z);big=cv2.resize(out,(nw,nh),interpolation=cv2.INTER_LANCZOS4)
 return big[(nh-1920)//2:(nh-1920)//2+1920,(nw-1080)//2:(nw-1080)//2+1080]

def transition(a,b,u,direction):
 u=smooth(u);H,W=a.shape[:2];x=np.arange(W,dtype=np.float32);center=lerp(-150,W+150,u) if direction>0 else lerp(W+150,-150,u)
 m=np.clip(((center-x)/120+.5) if direction>0 else ((x-center)/120+.5),0,1);m=(m*m*(3-2*m))[None,:,None]
 out=a*(1-m)+b*m;band=np.exp(-((x-center)/55)**2)[None,:,None];gold=np.empty_like(out);gold[:]=[40,150,235]
 return np.clip(out*(1-band*.20)+gold*(band*.20),0,255).astype(np.uint8)

last_open=None
def visual_frame(i):
 global last_open
 g=i/FPS
 if g<18:
  ok,f=opening.read();
  if not ok: raise RuntimeError(f'opening decode ended at frame {i}')
  last_open=f
  if g<17.55:return f
  return transition(f,scene_frame(4,0),(g-17.55)/.45,1)
 n=min(10,4+int((g-18)//6));local=g-(18+(n-4)*6);cur=scene_frame(n,local)
 if n<10 and local>=5.55:return transition(cur,scene_frame(n+1,0),(local-5.55)/.45,1 if n%2==0 else -1)
 return cur

# Original 60-second soundtrack: continuous modal pad, light plucks, quiet
# percussion, wing cues and contextual chimes. No third-party copyrighted audio.
sr=48000;ns=int(sr*DURATION);tt=np.arange(ns)/sr;L=np.zeros(ns);R=np.zeros(ns)
chords=[[146.83,220,349.23],[130.81,196,329.63],[116.54,174.61,293.66],[146.83,220,349.23],[155.56,233.08,369.99]]
for k in range(10):
 start=k*6;end=min(60,start+6.35);sel=(tt>=start)&(tt<end);x=(tt[sel]-start)/(end-start);env=np.sin(np.pi*x)**.55;freqs=chords[k%len(chords)]
 for j,fr in enumerate(freqs):
  sig=(np.sin(2*np.pi*fr*tt[sel]+j*.55)+.18*np.sin(2*np.pi*fr*2*tt[sel]))*env*(.010/(j+1));L[sel]+=sig;R[sel]+=sig*(.96+j*.015)
# Hijaz-flavored plucked accents, deliberately sparse so text remains primary.
scale=[293.66,311.13,369.99,392.00,440.00,466.16,554.37,587.33];notes=[0,2,3,4,3,2,1,0,4,3,2,0]
for j,at in enumerate(np.arange(.9,59,1.5)):
 fr=scale[notes[j%len(notes)]];sel=(tt>=at)&(tt<at+.72);x=tt[sel]-at;env=np.exp(-x*5.8)*(1-np.exp(-x*40));sig=(np.sin(2*np.pi*fr*x)+.30*np.sin(2*np.pi*2*fr*x)+.10*np.sin(2*np.pi*3*fr*x))*env*.016
 pan=.35+.3*math.sin(j*.9);L[sel]+=sig*(1-pan*.45);R[sel]+=sig*(.72+pan*.28)
# Soft low pulse every 1.5 seconds.
for at in np.arange(0,60,1.5):
 sel=(tt>=at)&(tt<at+.28);x=tt[sel]-at;sig=np.sin(2*np.pi*(64-18*x)*x)*np.exp(-x*14)*.022;L[sel]+=sig;R[sel]+=sig
# Filtered wing/transition noise.
rng=np.random.default_rng(20260827);noise=rng.normal(0,1,ns);F=np.fft.rfft(noise);freq=np.fft.rfftfreq(ns,1/sr);shape=np.exp(-((freq-720)/1000)**2)*(1-np.exp(-(freq/90)**2))*np.exp(-(freq/5200)**4);bed=np.fft.irfft(F*shape,n=ns)
def whoosh(at,amp=.13,dur=1.05):
 sel=(tt>=at)&(tt<=at+dur);u=(tt[sel]-at)/dur;env=np.maximum(np.sin(np.pi*u),0)**1.7;L[sel]+=bed[sel]*env*amp;R[sel]+=bed[sel]*env*amp
for at in [k*6+.30 for k in range(10)]:whoosh(at,.145)
for at in [5.48+6*k for k in range(9)]:whoosh(at,.075,.62)
def chime(at,fr,amp=.018,dur=.65):
 sel=(tt>=at)&(tt<at+dur);x=tt[sel]-at;sig=(np.sin(2*np.pi*fr*x)+.42*np.sin(2*np.pi*2*fr*x))*np.exp(-x*5.4)*amp;L[sel]+=sig;R[sel]+=sig
for scene in range(10):
 for j in range(3):chime(scene*6+1.7+j*.72,660+110*((scene+j)%4),.012)
# Master fades and conservative headroom.
fade=np.minimum(np.clip(tt/.55,0,1),np.clip((60-tt)/1.1,0,1));L*=fade;R*=fade;peak=max(np.max(np.abs(L)),np.max(np.abs(R)),1e-9);L=L/peak*.50;R=R/peak*.50
wav=WORK/'soundtrack60.wav';stereo=np.column_stack([L,R]);
with wave.open(str(wav),'wb') as wf:wf.setnchannels(2);wf.setsampwidth(2);wf.setframerate(sr);wf.writeframes((stereo*32767).astype('<i2').tobytes())

ff=imageio_ffmpeg.get_ffmpeg_exe();cmd=[ff,'-y','-f','rawvideo','-pix_fmt','bgr24','-s','1080x1920','-r','30','-i','-','-i',str(wav),'-c:v','libx264','-preset','medium','-tune','stillimage','-crf','16','-profile:v','high','-pix_fmt','yuv420p','-movflags','+faststart','-c:a','aac','-b:a','192k','-ar','48000','-t','60',str(OUT)]
p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
try:
 for i in range(N):p.stdin.write(visual_frame(i).tobytes())
finally:p.stdin.close();opening.release()
err=p.stderr.read().decode();ret=p.wait()
if ret:print(err,file=sys.stderr);raise SystemExit(ret)
print(OUT);print(err.splitlines()[-1])
# Platform derivatives: lossless video-stream copy for silent/trend use, and a
# compact 720x1280 WhatsApp delivery file that remains under 5 MB in practice.
subprocess.run([ff,'-y','-hide_banner','-loglevel','error','-i',str(OUT),'-map','0:v:0','-c:v','copy','-an','-movflags','+faststart',str(ROOT/'reels_promo_silent.mp4')],check=True)
subprocess.run([ff,'-y','-hide_banner','-loglevel','error','-i',str(OUT),'-vf','scale=720:1280:flags=lanczos','-c:v','libx264','-preset','medium','-crf','27','-maxrate','1100k','-bufsize','2200k','-profile:v','high','-pix_fmt','yuv420p','-c:a','aac','-b:a','96k','-ar','48000','-movflags','+faststart',str(ROOT/'reels_promo_whatsapp.mp4')],check=True)
print(ROOT/'reels_promo_silent.mp4')
print(ROOT/'reels_promo_whatsapp.mp4')
