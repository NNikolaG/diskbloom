import math, colorsys
C=512
def pt(a,r): 
    t=math.radians(a-90); return (C+r*math.cos(t), C+r*math.sin(t))
def arc(a0,a1,r0,r1):
    big=1 if a1-a0>180 else 0
    p0,p1,p2,p3=pt(a0,r1),pt(a1,r1),pt(a1,r0),pt(a0,r0)
    return (f"M{p0[0]:.2f},{p0[1]:.2f}A{r1},{r1} 0 {big} 1 {p1[0]:.2f},{p1[1]:.2f}"
            f"L{p2[0]:.2f},{p2[1]:.2f}A{r0},{r0} 0 {big} 0 {p3[0]:.2f},{p3[1]:.2f}Z")
def col(h,l,s=0.68):
    r,g,b=colorsys.hls_to_rgb(h%1,l,s); return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"
# (udeo, deca udeli, unuci?)
tree=[(0.34,[0.5,0.3,0.2],[1,1,0]),(0.24,[0.6,0.4],[1,0]),(0.17,[0.55,0.45],[1,1]),(0.14,[1.0],[1]),(0.11,[0.6,0.4],[0,1])]
hues=[0.52,0.60,0.73,0.92,0.09]   # cijan, plava, ljubicasta, roze, cilibar
GAP=3.4
rings=[(124,190),(212,264),(286,322)]
paths=[]
a=0
for (frac,kids,gk),h in zip(tree,hues):
    span=frac*360
    paths.append((arc(a+GAP/2,a+span-GAP/2,*rings[0]),col(h,0.64)))
    b=a
    for k,(kf,g) in enumerate(zip(kids,gk)):
        ks=span*kf
        paths.append((arc(b+GAP/2,b+ks-GAP/2,*rings[1]),col(h,0.56-0.05*k)))
        if g:
            gs=ks*0.72
            paths.append((arc(b+GAP/2,b+gs-GAP/2,*rings[2]),col(h,0.48-0.04*k,0.6)))
        b+=ks
    a+=span
body="\n".join(f'<path d="{d}" fill="{c}" stroke="{c}" stroke-width="10" stroke-linejoin="round"/>' for d,c in paths)
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#262a45"/><stop offset="1" stop-color="#0c0e1c"/>
 </linearGradient>
 <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
 </radialGradient>
 <radialGradient id="core" cx="0.42" cy="0.38" r="0.7">
  <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#dfe4f2"/>
 </radialGradient>
 <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
 </linearGradient>
 <filter id="sh" x="-20%" y="-20%" width="140%" height="140%">
  <feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.45"/>
 </filter>
 <clipPath id="sq"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
</defs>
<g filter="url(#sh)"><rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/></g>
<g clip-path="url(#sq)">
 <circle cx="512" cy="512" r="380" fill="url(#glow)"/>
 <g transform="rotate(-18 512 512)">{body}</g>
 <circle cx="512" cy="512" r="96" fill="url(#core)"/>
 <rect x="100" y="100" width="824" height="412" fill="url(#sheen)"/>
</g>
<rect x="101" y="101" width="822" height="822" rx="184" fill="none" stroke="#ffffff" stroke-opacity="0.12" stroke-width="2"/>
</svg>'''
open(__import__('os').path.join(__import__('os').path.dirname(__file__),'AppIcon.svg'),'w').write(svg)
