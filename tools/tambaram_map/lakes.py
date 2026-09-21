import cv2, numpy as np, json
from scipy import ndimage as ndi
img=cv2.imread("Tambaram-Municipal-Corporation-Ward-Map_Display-map.pdf.png")
full=np.load("wards_final.npy"); land=full>0
b,g,r=[img[...,i].astype(np.int16) for i in range(3)]
cyan=(b>=180)&(g>=130)&(b-r>=40)&(r<=215)&~((b>235)&(g>235)&(r>235))
cy=(cyan&land).astype(np.uint8)
blob=cv2.morphologyEx(cy,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(35,35)))
blob=ndi.binary_fill_holes(blob).astype(np.uint8)
n,lab,st,cen=cv2.connectedComponentsWithStats(blob,connectivity=8)
lakes=[]
for i in range(1,n):
    a=st[i,4]
    if a<15000: continue
    lakes.append({"id":len(lakes)+1,"area_px":int(a),"cx":float(cen[i][0]),"cy":float(cen[i][1]),
                  "bbox":[int(v) for v in st[i,:4]]})
json.dump(lakes,open("lakes_px.json","w"),indent=1)
vis=cv2.resize(img,(2000,1667),interpolation=cv2.INTER_AREA); s=2000/6000
for L in lakes:
    x,y,w,h=L["bbox"]; cv2.rectangle(vis,(int(x*s),int(y*s)),(int((x+w)*s),int((y+h)*s)),(0,0,255),2)
    cv2.putText(vis,f"L{L['id']}",(int(x*s),int(y*s)-4),cv2.FONT_HERSHEY_SIMPLEX,0.7,(0,0,255),2)
cv2.imwrite("lakes_view.png",vis)
for L in lakes: print(L["id"],L["area_px"],(int(L["cx"]/3.75),int(L["cy"]/3.75)))
