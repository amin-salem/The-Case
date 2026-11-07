"""Offline candidate discovery, NOT identity recognition. Requires Pillow/numpy/scipy."""
from pathlib import Path
import json,numpy as np
from scipy.fft import dctn
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];O=R/'docs/reviews/portrait-quality';O.mkdir(parents=True,exist_ok=True)
features={}
for p in sorted((R/'app/assets/portraits').glob('*.webp')):
 im=Image.open(p).convert('L');w,h=im.size
 # Fixed central face-region crop reduces clothing/background dominance.
 crop=im.crop((int(.20*w),int(.10*h),int(.82*w),int(.73*h))).resize((64,64))
 a=np.array(crop,dtype=float)/255;low=dctn(np.array(crop.resize((32,32)),float),norm='ortho')[:8,:8].flatten()[1:];ph=low>np.median(low)
 gy,gx=np.gradient(a);ang=(np.arctan2(gy,gx)%np.pi)*9/np.pi;mag=np.hypot(gx,gy);v=[]
 for y in range(0,64,8):
  for x in range(0,64,8):
   hist=np.bincount(np.floor(ang[y:y+8,x:x+8]).astype(int).ravel().clip(0,8),weights=mag[y:y+8,x:x+8].ravel(),minlength=9);hist/=np.linalg.norm(hist)+1e-8;v.extend(hist)
 v=np.array(v);v/=np.linalg.norm(v)+1e-8;features[p.stem]=(ph,v)
pairs=[]
keys=sorted(features)
for i,k in enumerate(keys):
 for l in keys[i+1:]:
  if k[0]!=l[0]:continue
  a,b=features[k],features[l];hd=int(np.count_nonzero(a[0]!=b[0]));cos=float(a[1]@b[1])
  if hd<=10 or cos>=.88:pairs.append(dict(a=k,b=l,phash_distance=hd,hog_cosine=round(cos,5),decision='pending'))
pairs.sort(key=lambda p:(-p['hog_cosine'],p['phash_distance']))
(O/'machine-candidates.json').write_text(json.dumps({'method':'63-bit DCT pHash plus 576-dimensional gradient-orientation histogram of fixed face crop. Not a learned face embedding or identity test.','threshold':'same gender key AND (pHash Hamming <=10 OR face-crop HOG cosine >=0.88)','candidates':pairs},indent=2))
for start in range(0,len(pairs),12):
 batch=pairs[start:start+12];sheet=Image.new('RGB',(900,((len(batch)+2)//3)*200),'#eeeeee');d=ImageDraw.Draw(sheet)
 for j,pair in enumerate(batch):
  x=j%3*300;y=j//3*200
  for offset,key in [(0,pair['a']),(140,pair['b'])]:
   im=Image.open(R/'app/assets/portraits'/f'{key}.webp');im.thumbnail((135,155));sheet.paste(im,(x+offset,y));d.text((x+offset,y+157),key,fill='black')
  d.text((x,y+174),f"{start+j} ph={pair['phash_distance']} hog={pair['hog_cosine']}",fill='black')
 sheet.save(O/f'candidates-{start//12+1}.jpg',quality=88)
print('Candidates',len(pairs));print(json.dumps(pairs[:6]))
