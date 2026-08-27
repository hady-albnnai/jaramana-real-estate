"""Extract the independent wing layers and clean plates for posters 05-10."""
import cv2, numpy as np
from pathlib import Path
ROOT=globals().get('ROOT',Path(__file__).resolve().parents[1])
WORK=globals().get('WORK',Path('/tmp/sweeda_reel_60')); WORK.mkdir(parents=True,exist_ok=True)
CONFIG={
 5:{'boxes':[(25,28,205,220),(563,28,743,220)],
    'polys':[[(18,5),(55,20),(100,37),(140,56),(165,80),(178,112),(169,144),(150,169),(120,153),(84,136),(50,112),(27,80),(15,42)],[(162,5),(125,20),(80,37),(40,56),(15,80),(2,112),(11,144),(30,169),(60,153),(96,136),(130,112),(153,80),(165,42)]],
    'roots':[(169,145),(11,145)],'logo':(175,48,593,190)},
 6:{'boxes':[(38,30,178,205),(590,30,730,205)],
    'polys':[[(14,35),(38,52),(68,67),(98,83),(122,105),(137,137),(136,171),(115,174),(88,160),(60,145),(36,122),(18,88),(9,55)],[(126,35),(102,52),(72,67),(42,83),(18,105),(3,137),(4,171),(25,174),(52,160),(80,145),(104,122),(122,88),(131,55)]],
    'roots':[(126,148),(14,148)],'logo':(135,58,633,195)},
 7:{'boxes':[(20,18,210,225),(558,18,748,225)],
    'polys':[[(22,7),(48,38),(76,65),(110,85),(145,100),(171,123),(187,154),(185,195),(166,205),(140,190),(109,174),(76,155),(48,130),(27,97),(14,56)],[(168,7),(142,38),(114,65),(80,85),(45,100),(19,123),(3,154),(5,195),(24,205),(50,190),(81,174),(114,155),(142,130),(163,97),(176,56)]],
    'roots':[(176,174),(14,174)],'logo':(155,55,614,210)},
 8:{'boxes':[(55,50,180,215),(588,50,720,215)],
    'polys':[[(38,26),(57,45),(80,58),(103,73),(119,96),(124,126),(120,153),(106,162),(85,148),(63,132),(47,111),(37,83),(32,52)],[(94,26),(75,45),(52,58),(29,73),(13,96),(8,126),(12,153),(26,162),(47,148),(69,132),(85,111),(95,83),(100,52)]],
    'roots':[(116,139),(16,139)],'logo':(110,75,658,210)},
 9:{'boxes':[(48,40,180,215),(588,40,720,215)],
    'polys':[[(22,25),(42,45),(66,59),(90,72),(112,92),(126,116),(129,145),(119,160),(101,151),(79,137),(57,119),(41,96),(30,68)],[(110,25),(90,45),(66,59),(42,72),(20,92),(6,116),(3,145),(13,160),(31,151),(53,137),(75,119),(91,96),(102,68)]],
    'roots':[(120,142),(12,142)],'logo':(120,75,648,205)},
 10:{'boxes':[(18,35,200,270),(568,35,750,270)],
    'polys':[[(18,5),(42,35),(70,61),(105,82),(140,100),(166,125),(180,156),(180,202),(161,229),(132,234),(98,213),(66,188),(38,156),(17,115),(6,65)],[(164,5),(140,35),(112,61),(77,82),(42,100),(16,125),(2,156),(2,202),(21,229),(50,234),(84,213),(116,188),(144,156),(165,115),(176,65)]],
    'roots':[(169,195),(13,195)],'logo':(105,58,663,260)},
}

def extract(src,n,side,box,poly):
 x0,y0,x1,y1=box; crop=src[y0:y1,x0:x1].copy(); h,w=crop.shape[:2]
 region=np.zeros((h,w),np.uint8); cv2.fillPoly(region,[np.array(poly,np.int32)],255)
 gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
 g=np.full((h,w),cv2.GC_BGD,np.uint8); inside=region>0; g[inside]=cv2.GC_PR_BGD
 definite=inside&((gray>52)|((hsv[:,:,1]>35)&(hsv[:,:,2]>34))); g[definite]=cv2.GC_FGD
 probable=inside&((gray>21)|((hsv[:,:,1]>14)&(hsv[:,:,2]>22))); g[probable&~definite]=cv2.GC_PR_FGD
 bgd=np.zeros((1,65),np.float64); fgd=np.zeros((1,65),np.float64)
 cv2.grabCut(crop,g,None,bgd,fgd,8,cv2.GC_INIT_WITH_MASK)
 mask=np.where((g==cv2.GC_FGD)|(g==cv2.GC_PR_FGD),255,0).astype(np.uint8)
 mask=cv2.bitwise_and(mask,region)
 # Keep meaningful gold components inside the hand-drawn wing silhouette.
 num,lab,stats,_=cv2.connectedComponentsWithStats((mask>127).astype(np.uint8),8)
 keep=np.zeros_like(mask)
 for i in range(1,num):
  if stats[i,cv2.CC_STAT_AREA]>=max(30,int(h*w*.003)): keep[lab==i]=255
 if not np.any(keep) and num>1: keep[lab==1+np.argmax(stats[1:,4])]=255
 keep=cv2.GaussianBlur(keep,(0,0),.65)
 rgba=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA); rgba[:,:,3]=keep
 cv2.imwrite(str(WORK/f'p{n}_{side}.png'),rgba)
 return {'img':rgba,'box':box,'region':region}

def synth_clean(src,layers,n):
 mask=np.zeros(src.shape[:2],np.uint8)
 for L in layers:
  x0,y0,x1,y1=L['box']; r=cv2.dilate(L['region'],cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
  mask[y0:y1,x0:x1]=cv2.max(mask[y0:y1,x0:x1],r)
 rng=np.random.default_rng(700+n); repl=np.zeros_like(src,np.float32)
 for y,row in enumerate(src):
  lum=cv2.cvtColor(row[None,:,:],cv2.COLOR_BGR2GRAY)[0]; vals=row[lum<34]
  med=np.median(vals,axis=0) if len(vals)>20 else np.array([11,11,12]); repl[y]=med
 noise=rng.normal(0,1.0,src.shape[:2]); repl+=noise[:,:,None]; repl=np.clip(repl,0,255).astype(np.uint8)
 a=cv2.GaussianBlur(mask,(0,0),1.1).astype(np.float32)/255; clean=(repl*a[:,:,None]+src*(1-a[:,:,None])).astype(np.uint8)
 cv2.imwrite(str(WORK/f'p{n}_clean.png'),clean)
 return clean

def logo_overlay(src,box,n):
 x0,y0,x1,y1=box; crop=src[y0:y1,x0:x1].copy(); gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY).astype(np.float32); hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
 # Gold/white logo pixels only; black remains transparent, avoiding rectangles.
 a=np.maximum(np.clip((gray-24)/45,0,1),np.clip((hsv[:,:,1].astype(np.float32)-18)/75,0,1)*np.clip((hsv[:,:,2].astype(np.float32)-20)/65,0,1))
 a=cv2.GaussianBlur(a,(0,0),.5); rgba=cv2.cvtColor(crop,cv2.COLOR_BGR2BGRA); rgba[:,:,3]=(a*255).astype(np.uint8)
 cv2.imwrite(str(WORK/f'p{n}_logo.png'),rgba); return rgba

for n,c in CONFIG.items():
 src=cv2.imread(str(next((ROOT/'posts').glob(f'poster_{n:02d}_*.png'))))
 layers=[extract(src,n,'left',c['boxes'][0],c['polys'][0]),extract(src,n,'right',c['boxes'][1],c['polys'][1])]
 clean=synth_clean(src,layers,n); logo=logo_overlay(src,c['logo'],n)
 proof=clean.copy()
 for L in layers:
  fg=L['img']; x,y=L['box'][:2]; a=fg[:,:,3:4].astype(np.float32)/255; roi=proof[y:y+fg.shape[0],x:x+fg.shape[1]].astype(np.float32); proof[y:y+fg.shape[0],x:x+fg.shape[1]]=(fg[:,:,:3]*a+roi*(1-a)).astype(np.uint8)
 x,y=c['logo'][:2]; a=logo[:,:,3:4].astype(np.float32)/255; roi=proof[y:y+logo.shape[0],x:x+logo.shape[1]].astype(np.float32); proof[y:y+logo.shape[0],x:x+logo.shape[1]]=(logo[:,:,:3]*a+roi*(1-a)).astype(np.uint8)
 cv2.imwrite(str(WORK/f'p{n}_proof.png'),proof)
