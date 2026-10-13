"""Layer extraction and vertical reframing for the first-three-posters preview."""
import cv2, numpy as np
from pathlib import Path
ROOT=globals().get('ROOT',Path(__file__).resolve().parents[1])
WORK=globals().get('WORK',Path('/tmp/sweeda_reel_preview_18')); WORK.mkdir(parents=True,exist_ok=True)

def extract_wing(src,name,box,points):
 x0,y0,x1,y1=box; crop=src[y0:y1,x0:x1].copy(); h,w=crop.shape[:2]
 poly=np.zeros((h,w),np.uint8); cv2.fillPoly(poly,[np.array(points,np.int32)],255)
 gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
 g=np.full((h,w),cv2.GC_BGD,np.uint8); inside=poly>0; g[inside]=cv2.GC_PR_BGD
 certain=inside&((gray>48)|((hsv[:,:,1]>32)&(hsv[:,:,2]>34))); g[certain]=cv2.GC_FGD
 probable=inside&((gray>22)|((hsv[:,:,1]>16)&(hsv[:,:,2]>23))); g[probable&~certain]=cv2.GC_PR_FGD
 bgd=np.zeros((1,65),np.float64); fgd=np.zeros((1,65),np.float64)
 cv2.grabCut(crop,g,None,bgd,fgd,8,cv2.GC_INIT_WITH_MASK)
 mask=np.where((g==cv2.GC_FGD)|(g==cv2.GC_PR_FGD),255,0).astype(np.uint8)
 mask=cv2.bitwise_and(mask,poly)
 n,labels,stats,_=cv2.connectedComponentsWithStats((mask>127).astype(np.uint8),8)
 # Wings can contain 1-3 touching major pieces. Keep components >1% crop area,
 # but reject tiny calligraphic dots.
 keep=np.zeros_like(mask)
 for i in range(1,n):
  if stats[i,cv2.CC_STAT_AREA] >= max(45,int(h*w*.006)):
   keep[labels==i]=255
 if not np.any(keep) and n>1:
  keep[labels==(1+np.argmax(stats[1:,cv2.CC_STAT_AREA]))]=255
 mask=cv2.GaussianBlur(keep,(0,0),.65)
 rgba=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA); rgba[:,:,3]=mask
 cv2.imwrite(str(WORK/f'{name}.png'),rgba)
 return {'img':rgba,'x':x0,'y':y0,'mask':mask,'poly':poly}

def inpaint_wings(src,wings,name,radius=9):
 # The wings sit on a nearly black textile field. A procedural clean plate is
 # safer than content-aware fill here: inpainting samples nearby gold letters
 # and can smear them into the area revealed by a moving wing.
 m=np.zeros(src.shape[:2],np.uint8)
 for w in wings:
  core=(w['poly']>8).astype(np.uint8)*255
  core=cv2.dilate(core,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
  y,x=w['y'],w['x']; h,ww=core.shape
  m[y:y+h,x:x+ww]=cv2.max(m[y:y+h,x:x+ww],core)
 rng=np.random.default_rng(20260827+src.shape[0])
 replacement=np.zeros_like(src,dtype=np.float32)
 for y in range(src.shape[0]):
  row=src[y]
  lum=cv2.cvtColor(row[None,:,:],cv2.COLOR_BGR2GRAY)[0]
  vals=row[lum<32]
  med=np.median(vals,axis=0) if len(vals)>20 else np.array([12,12,12])
  replacement[y,:,:]=med
 noise=rng.normal(0,1.0,src.shape[:2]).astype(np.float32)
 for c in range(3): replacement[:,:,c]+=noise
 replacement=np.clip(replacement,0,255).astype(np.uint8)
 blend=cv2.GaussianBlur(m,(0,0),1.1).astype(np.float32)/255
 clean=(replacement*blend[:,:,None]+src*(1-blend[:,:,None])).astype(np.uint8)
 cv2.imwrite(str(WORK/f'{name}_clean.png'),clean)
 proof=clean.copy()
 for w in wings:
  fg=w['img']; a=fg[:,:,3:4].astype(np.float32)/255
  y,x=w['y'],w['x']; h,ww=fg.shape[:2]; roi=proof[y:y+h,x:x+ww].astype(np.float32)
  proof[y:y+h,x:x+ww]=(fg[:,:,:3]*a+roi*(1-a)).astype(np.uint8)
 cv2.imwrite(str(WORK/f'{name}_proof.png'),proof)
 return clean

# Poster 02 giant wings.
p2=cv2.imread(str(ROOT/'posts/poster_02_publish.png'))
l2=extract_wing(p2,'p2_left',(20,32,225,275),[(24,5),(45,55),(75,90),(115,115),(150,132),(171,153),(193,190),(193,239),(158,234),(126,214),(88,195),(52,170),(23,140),(7,96),(5,42)])
r2=extract_wing(p2,'p2_right',(543,32,748,275),[(181,5),(160,55),(130,90),(90,115),(55,132),(34,153),(12,190),(12,239),(47,234),(79,214),(117,195),(153,170),(182,140),(198,96),(200,42)])

# Removal plates are intentionally broader than alpha extraction so every
# original feather disappears while the central calligraphy remains intact.
l2['poly'][:]=0; cv2.fillPoly(l2['poly'],[np.array([(5,5),(175,5),(175,165),(204,188),(204,242),(0,242),(0,5)],np.int32)],255)
r2['poly'][:]=0; cv2.fillPoly(r2['poly'],[np.array([(30,5),(200,5),(204,5),(204,242),(0,242),(0,188),(30,165)],np.int32)],255)
clean2=inpaint_wings(p2,[l2,r2],'p2',11)

# Poster 03 smaller header wings.
p3=cv2.imread(str(ROOT/'posts/poster_03_appointments.png'))
l3=extract_wing(p3,'p3_left',(238,30,370,178),[(18,4),(31,32),(51,55),(78,67),(107,79),(130,99),(130,142),(101,142),(74,126),(48,110),(27,88),(10,57),(8,25)])
r3=extract_wing(p3,'p3_right',(654,30,786,178),[(114,4),(101,32),(81,55),(54,67),(25,79),(2,99),(2,142),(31,142),(58,126),(84,110),(105,88),(122,57),(124,25)])

l3['poly'][:]=0; cv2.fillPoly(l3['poly'],[np.array([(0,0),(112,0),(112,92),(131,108),(131,147),(0,147)],np.int32)],255)
r3['poly'][:]=0; cv2.fillPoly(r3['poly'],[np.array([(20,0),(131,0),(131,147),(0,147),(0,108),(20,92)],np.int32)],255)
clean3=inpaint_wings(p3,[l3,r3],'p3',8)

# Build a static 9:16 appointment composition from exact original crops.
rng=np.random.default_rng(20260827)
canvas=np.zeros((1920,1080,3),np.uint8)
# Deep black textile background and fine gold border.
base=np.array([11,11,12],np.float32)
noise=rng.normal(0,1.2,(1920,1080,1)).astype(np.float32)
canvas[:]=base
canvas=np.clip(canvas.astype(np.float32)+noise,0,255).astype(np.uint8)
cv2.rectangle(canvas,(22,22),(1057,1897),(38,126,192),2,cv2.LINE_AA)
cv2.rectangle(canvas,(28,28),(1051,1891),(18,63,98),1,cv2.LINE_AA)

def fit(img,w,h=None):
 ih,iw=img.shape[:2]
 if h is None: h=round(ih*w/iw)
 return cv2.resize(img,(w,h),interpolation=cv2.INTER_LANCZOS4)
def paste(dst,img,x,y,opacity=1,feather=0):
 h,w=img.shape[:2]; roi=dst[y:y+h,x:x+w]
 if feather<=0:
  if opacity>=1: roi[:]=img
  else: roi[:]=(img*opacity+roi*(1-opacity)).astype(np.uint8)
  return
 yy,xx=np.indices((h,w)); edge=np.minimum.reduce([xx,w-1-xx,yy,h-1-yy]).astype(np.float32)
 a=np.clip(edge/max(1,feather),0,1)*opacity
 a=(a*a*(3-2*a))[:,:,None]
 roi[:]=(img*a+roi*(1-a)).astype(np.uint8)
# Header includes cleaned central calligraphy, city and slogan.
header=clean3[24:252,210:814]
header=fit(header,900)
paste(canvas,header,90,65,feather=28)
# Main title exact crop.
title=p3[252:380,105:919]
title=fit(title,950)
paste(canvas,title,65,375,feather=22)
# Exact cards, reflowed into two tall rows.
boxes=[p3[390:680,150:505],p3[390:680,519:874],p3[688:974,150:505],p3[688:974,519:874]]
positions=[(55,555),(555,555),(55,990),(555,990)]
for im,(x,y) in zip(boxes,positions): paste(canvas,fit(im,470,384),x,y)
# Existing approved contact bar from poster 01, no newly typeset Arabic.
p1=cv2.imread(str(ROOT/'posts/poster_01_intro.png'))
contact=p1[1250:1370,170:598]
contact=fit(contact,720)
paste(canvas,contact,180,1655,feather=18)
cv2.imwrite(str(WORK/'p3_vertical_static.png'),canvas)
