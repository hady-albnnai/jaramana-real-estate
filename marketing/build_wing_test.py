#!/usr/bin/env python3
"""Build the six-second wing-rig proof for the first marketing poster.

Dependencies (kept outside the repository):
  python3 -m pip install --target /tmp/reeldeps pillow numpy \
      opencv-python-headless imageio-ffmpeg

Run:
  PYTHONPATH=/tmp/reeldeps python3 marketing/build_wing_test.py

The renderer preserves the Arabic artwork, extracts both original wings as
independent alpha layers, reconstructs the dark clean plate, applies a
root-anchored flexible opening motion, then exports a 1080x1920 H.264/AAC MP4.
"""
import cv2, numpy as np, math, wave, subprocess, os, sys
from pathlib import Path
sys.path.insert(0,'/tmp/reeldeps')
import imageio_ffmpeg

FPS=30
DURATION=6.0
N=int(FPS*DURATION)
ROOT=Path(__file__).resolve().parent
SRC=str(ROOT/'posts/poster_01_intro.png')
OUT=str(ROOT/'wing_animation_test_6s.mp4')
WORK=Path('/tmp/sweeda_reel_wings')
WORK.mkdir(parents=True,exist_ok=True)

# Extract the original wings and reconstruct the clean poster background.
src=cv2.imread(SRC,cv2.IMREAD_COLOR)
H,W=src.shape[:2]
rng=np.random.default_rng(20260827)
# synthesize top dark textile background from row medians + subtle multi-scale grain
bg=src.copy()
top=np.empty((235,W,3),np.float32)
for y in range(235):
    yy=min(y,H-1)
    row=src[yy]
    lum=cv2.cvtColor(row[None,:,:],cv2.COLOR_BGR2GRAY)[0]
    vals=row[lum<32]
    med=np.median(vals,axis=0) if len(vals)>30 else np.array([12,12,12])
    top[y,:,:]=med
noise=rng.normal(0,1,(235,W)).astype(np.float32)
low=cv2.GaussianBlur(rng.normal(0,1,(235,W)).astype(np.float32),(0,0),18)*2.0
for c in range(3): top[:,:,c]+=noise*0.9+low
top=np.clip(top,0,255).astype(np.uint8)
top=top.astype(np.uint8)
bg[:235]=top
# Bring back only the central gold calligraphy and diamonds, excluding wing areas.
gray=cv2.cvtColor(src,cv2.COLOR_BGR2GRAY).astype(np.float32)
hsv=cv2.cvtColor(src,cv2.COLOR_BGR2HSV)
feature=np.zeros((H,W),np.float32)
region=np.zeros((H,W),np.uint8)
cv2.fillPoly(region,[np.array([(168,44),(600,44),(600,220),(168,220)],np.int32)],255)
# brightness/color alpha: preserve gold, white gems and dark-gold antialias.
a=np.clip((gray-18)/42,0,1)
colored=np.clip((hsv[:,:,1].astype(np.float32)-12)/70,0,1)*np.clip((hsv[:,:,2].astype(np.float32)-18)/55,0,1)
feature=np.maximum(a,colored)* (region/255)
feature=cv2.GaussianBlur(feature,(0,0),0.45)
feature=np.clip(feature,0,1)[:,:,None]
bg=(src*feature+bg*(1-feature)).astype(np.uint8)
# transition to untouched source below top region
for y in range(215,236):
    t=(y-215)/20
    bg[y]=(bg[y]*(1-t)+src[y]*t).astype(np.uint8)
cv2.imwrite(str(WORK/'clean_plate2.png'),bg)

# Tight wing extraction with GrabCut and hand exclusion curves.
def extract(name,x0,y0,x1,y1,points):
 crop=src[y0:y1,x0:x1].copy(); h,w=crop.shape[:2]
 poly=np.zeros((h,w),np.uint8); cv2.fillPoly(poly,[np.array(points,np.int32)],255)
 gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
 g=np.full((h,w),cv2.GC_BGD,np.uint8); inside=poly>0; g[inside]=cv2.GC_PR_BGD
 certain=inside&((gray>50)|((hsv[:,:,1]>35)&(hsv[:,:,2]>36))); g[certain]=cv2.GC_FGD
 probable=inside&((gray>23)|((hsv[:,:,1]>18)&(hsv[:,:,2]>24))); g[probable&~certain]=cv2.GC_PR_FGD
 bgd=np.zeros((1,65),np.float64); fgd=np.zeros((1,65),np.float64)
 cv2.grabCut(crop,g,None,bgd,fgd,8,cv2.GC_INIT_WITH_MASK)
 mask=np.where((g==cv2.GC_FGD)|(g==cv2.GC_PR_FGD),255,0).astype(np.uint8)
 mask=cv2.bitwise_and(mask,poly)
 n, labels, stats, _ = cv2.connectedComponentsWithStats((mask>127).astype(np.uint8),8)
 if n>1:
  biggest=1+np.argmax(stats[1:,cv2.CC_STAT_AREA])
  mask=np.where(labels==biggest,255,0).astype(np.uint8)
 mask=cv2.GaussianBlur(mask,(0,0),0.6)
 rgba=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA); rgba[:,:,3]=mask
 cv2.imwrite(str(WORK/f'{name}2.png'),rgba)
 return rgba
left=extract('wing_left',20,20,205,235,[(21,13),(33,44),(50,64),(75,79),(111,90),(139,92),(153,83),(153,104),(146,122),(155,143),(153,163),(144,184),(132,199),(104,196),(76,187),(52,171),(33,149),(16,121),(7,87),(12,52)])
right=extract('wing_right',565,20,748,235,[(162,13),(171,47),(176,80),(168,112),(154,142),(134,168),(111,188),(83,199),(58,198),(44,184),(37,163),(40,139),(48,116),(62,98),(81,83),(108,70),(139,47)])
# proof
proof=bg.copy()
for fg,x,y in [(left,20,20),(right,565,20)]:
 a=fg[:,:,3:4].astype(np.float32)/255
 roi=proof[y:y+fg.shape[0],x:x+fg.shape[1]].astype(np.float32)
 proof[y:y+fg.shape[0],x:x+fg.shape[1]]=(fg[:,:,:3]*a+roi*(1-a)).astype(np.uint8)
cv2.imwrite(str(WORK/'recomposite2.png'),proof)

plate=cv2.imread(str(WORK/'clean_plate2.png'),cv2.IMREAD_COLOR)
left=cv2.imread(str(WORK/'wing_left2.png'),cv2.IMREAD_UNCHANGED)
right=cv2.imread(str(WORK/'wing_right2.png'),cv2.IMREAD_UNCHANGED)

# Restore transparent RGB to black to avoid edge color contamination.
for im in (left,right):
    im[:,:,:3]=np.where((im[:,:,3:4]>0),im[:,:,:3],0)

# Keyframe helpers.
def clamp(x,a=0.0,b=1.0): return max(a,min(b,x))
def smooth(u):
    u=clamp(u); return u*u*(3-2*u)
def ease_out_cubic(u):
    u=clamp(u); return 1-(1-u)**3
def lerp(a,b,u): return a+(b-a)*u

def motion(t):
    if t < .25:
        return .74, 17.0
    if t < .43: # anticipation inward
        u=smooth((t-.25)/.18); return lerp(.74,.68,u),lerp(17,21,u)
    if t < 1.16: # decisive opening
        u=ease_out_cubic((t-.43)/.73); return lerp(.68,1.045,u),lerp(21,-4,u)
    if t < 1.52: # first settle
        u=smooth((t-1.16)/.36); return lerp(1.045,.992,u),lerp(-4,1.2,u)
    if t < 1.82:
        u=smooth((t-1.52)/.30); return lerp(.992,1.0,u),lerp(1.2,0,u)
    # Almost imperceptible breathing after the hero motion.
    breath=math.sin((t-1.82)*math.pi*0.9)*math.exp(-(t-1.82)*.25)
    return 1.0+0.0035*breath, -0.35*breath

def deform(im, side, openness, bend, t):
    h,w=im.shape[:2]
    if side=='left':
        rootx,rooty=144.0,168.0; maxd=132.0
    else:
        rootx,rooty=41.0,168.0; maxd=132.0
    yy,xx=np.indices((h,w),dtype=np.float32)
    # Inverse map for root-anchored foreshortening.
    sx=rootx+(xx-rootx)/max(openness,.5)
    q=np.clip(np.abs(sx-rootx)/maxd,0,1)
    sy=yy-bend*(q**1.55)
    out=cv2.remap(im,sx.astype(np.float32),sy.astype(np.float32),cv2.INTER_CUBIC,
                  borderMode=cv2.BORDER_CONSTANT,borderValue=(0,0,0,0))
    # Golden highlight travels from the roots toward the feather tips.
    if .50 <= t <= 1.55:
        u=smooth((t-.50)/1.05)
        center=lerp(rootx, 11 if side=='left' else w-11, u)
        band=np.exp(-((xx-center)/16.0)**2).astype(np.float32)
        a=(out[:,:,3].astype(np.float32)/255.0)
        strength=36.0*math.sin(math.pi*u)
        gold=np.zeros_like(out[:,:,:3],dtype=np.float32)
        gold[:]=[32,185,255] # BGR warm specular
        rgb=out[:,:,:3].astype(np.float32)
        mix=(band*a*strength/255.0)[:,:,None]
        out[:,:,:3]=np.clip(rgb*(1-mix)+gold*mix,0,255).astype(np.uint8)
    # Closed wings are fractionally darker, reinforcing 3-D foreshortening.
    shade=.78+.22*clamp((openness-.68)/.32)
    out[:,:,:3]=np.clip(out[:,:,:3].astype(np.float32)*shade,0,255).astype(np.uint8)
    return out

def add_rgba(dst, fg, x, y, opacity=1.0):
    h,w=fg.shape[:2]; H,W=dst.shape[:2]
    x0=max(0,x); y0=max(0,y); x1=min(W,x+w); y1=min(H,y+h)
    if x1<=x0 or y1<=y0:return
    f=fg[y0-y:y1-y,x0-x:x1-x]
    a=f[:,:,3:4].astype(np.float32)/255.0*opacity
    roi=dst[y0:y1,x0:x1].astype(np.float32)
    dst[y0:y1,x0:x1]=np.clip(f[:,:,:3].astype(np.float32)*a+roi*(1-a),0,255).astype(np.uint8)

def add_wing(dst, wing, x,y, side, openness,bend,t):
    f=deform(wing,side,openness,bend,t)
    alpha=f[:,:,3]
    # Soft raised shadow and gold aura make the cutout sit naturally above the poster.
    shadow=cv2.GaussianBlur(alpha,(0,0),4.2)
    aura=cv2.GaussianBlur(alpha,(0,0),8.5)
    h,w=f.shape[:2]
    H,W=dst.shape[:2]
    for layer,offy,color,amount in [
        (aura,1,(35,105,170),0.13*clamp((openness-.68)/.32)),
        (shadow,4,(0,0,0),0.56),
    ]:
        yy=y+offy; x0=max(0,x); y0=max(0,yy); x1=min(W,x+w); y1=min(H,yy+h)
        if x1<=x0 or y1<=y0: continue
        a=layer[y0-yy:y1-yy,x0-x:x1-x].astype(np.float32)/255.0*amount
        roi=dst[y0:y1,x0:x1].astype(np.float32)
        c=np.empty_like(roi); c[:]=color
        dst[y0:y1,x0:x1]=np.clip(c*a[:,:,None]+roi*(1-a[:,:,None]),0,255).astype(np.uint8)
    add_rgba(dst,f,x,y)

# Logo mask for a controlled glow behind the calligraphy.
g=cv2.cvtColor(plate,cv2.COLOR_BGR2GRAY)
hsv=cv2.cvtColor(plate,cv2.COLOR_BGR2HSV)
logo=np.zeros_like(g)
reg=np.zeros_like(g); cv2.rectangle(reg,(160,45),(607,220),255,-1)
logo[((g>44)|((hsv[:,:,1]>45)&(hsv[:,:,2]>38)))&(reg>0)]=255
logo=cv2.GaussianBlur(logo,(0,0),10)

# Fixed deterministic spark particles around wing tips.
rng=np.random.default_rng(950199)
particles=[]
for side in (-1,1):
    for _ in range(8):
        x=(70 if side<0 else 698)+rng.uniform(-42,42)
        y=92+rng.uniform(-40,95)
        delay=rng.uniform(.78,1.35)
        particles.append((x,y,delay,rng.uniform(1.0,2.0),side))

def make_frame(i):
    t=i/FPS
    op,bend=motion(t)
    frame=plate.copy()
    # Warm halo peaks as the wings reach full extension.
    halo=math.exp(-((t-1.02)/.48)**2)*.18
    if halo>.002:
        a=(logo.astype(np.float32)/255.0*halo)[:,:,None]
        c=np.empty_like(frame,dtype=np.float32); c[:]=[25,125,210]
        frame=np.clip(c*a+frame*(1-a),0,255).astype(np.uint8)
    add_wing(frame,left,20,20,'left',op,bend,t)
    # 2-frame follow-through offset at the right feather tips, not at the roots.
    op_r,bend_r=motion(max(0,t-2/FPS))
    add_wing(frame,right,565,20,'right',op_r,bend_r,t)
    # Sparse gold dust appears only during the opening and dies immediately.
    for x,y,delay,r,side in particles:
        age=t-delay
        if 0<=age<=1.0:
            alpha=math.sin(math.pi*age)*0.72
            drift=age*(10+4*r)
            px=int(x+side*drift); py=int(y-age*12)
            rad=max(1,int(r*(1-age*.35)))
            overlay=frame.copy(); cv2.circle(overlay,(px,py),rad,(80,205,255),-1,cv2.LINE_AA)
            frame=cv2.addWeighted(overlay,alpha,frame,1-alpha,0)
    # Elegant fade-in; the final 0.4s gently settles to 92%, ready for a transition.
    vis=smooth(t/.38)
    if t>5.55: vis=lerp(1.0,.92,smooth((t-5.55)/.45))
    frame=(frame.astype(np.float32)*vis).astype(np.uint8)
    # Crop only 11 vertical source pixels to reach exact 9:16; no text is lost.
    frame=frame[5:1370]
    return cv2.resize(frame,(1080,1920),interpolation=cv2.INTER_LANCZOS4)

# Soft stereo wing-whoosh proof sound (no copyrighted music in the motion test).
sr=48000
samples=int(sr*DURATION)
tt=np.arange(samples)/sr
rng=np.random.default_rng(20260827)
noise=rng.normal(0,1,samples)
F=np.fft.rfft(noise); freq=np.fft.rfftfreq(samples,1/sr)
shape=np.exp(-((freq-720)/950)**2)*(1-np.exp(-(freq/90)**2))*np.exp(-(freq/5200)**4)
whoosh=np.fft.irfft(F*shape,n=samples)
env=np.zeros(samples)
start,end=.34,1.55
sel=(tt>=start)&(tt<=end)
u=(tt[sel]-start)/(end-start)
env[sel]=(np.sin(np.pi*u)**1.65)
sub=np.sin(2*np.pi*(68+12*np.clip((tt-.42)/.8,0,1))*tt)*env
shimmer=(np.sin(2*np.pi*880*tt)+.55*np.sin(2*np.pi*1320*tt))*np.exp(-((tt-1.18)/.46)**2)
audio=whoosh*env*.68+sub*.12+shimmer*.035
# tiny tail shimmer
audio+=np.sin(2*np.pi*1760*tt)*np.exp(-((tt-1.52)/.34)**2)*.012
audio/=max(np.max(np.abs(audio)),1e-9); audio*=.42
stereo=np.column_stack([audio,audio])
with wave.open(str(WORK/'wing_whoosh.wav'),'wb') as wf:
    wf.setnchannels(2); wf.setsampwidth(2); wf.setframerate(sr)
    wf.writeframes((stereo*32767).astype('<i2').tobytes())

ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
cmd=[ffmpeg,'-y','-f','rawvideo','-pix_fmt','bgr24','-s','1080x1920','-r',str(FPS),'-i','-',
     '-i',str(WORK/'wing_whoosh.wav'),'-c:v','libx264','-preset','medium','-crf','18',
     '-profile:v','high','-pix_fmt','yuv420p','-movflags','+faststart','-c:a','aac','-b:a','192k',
     '-ar','48000','-t',f'{DURATION:.3f}',OUT]
proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
try:
    for i in range(N):
        proc.stdin.write(make_frame(i).tobytes())
finally:
    if proc.stdin: proc.stdin.close()
stderr=proc.stderr.read().decode('utf-8','replace')
ret=proc.wait()
if ret:
    print(stderr,file=sys.stderr); raise SystemExit(ret)
print(OUT)
print(stderr.splitlines()[-1] if stderr.splitlines() else 'rendered')
