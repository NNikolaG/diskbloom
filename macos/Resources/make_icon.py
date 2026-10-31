"""Generise AppIcon.svg: minimalisticki donut grafikon na indigo podlozi.
Renderovanje u PNG (1024x1024): bilo koji SVG renderer, npr.
  rsvg-convert -w 1024 AppIcon.svg -o AppIcon.png
"""
import math, os

C = 512
GAP = 5          # razmak izmedju delova, u stepenima
R, W = 210, 130  # poluprecnik i debljina prstena
# (pocetak, kraj) u stepenima od 12 sati, i providnost bele boje
SEGMENTS = [((0, 200), 1.0), ((200, 290), 0.7), ((290, 330), 0.45), ((330, 360), 0.22)]


def pt(a, r):
    t = math.radians(a - 90)
    return C + r * math.cos(t), C + r * math.sin(t)


def arc(a0, a1, r):
    (x0, y0), (x1, y1) = pt(a0, r), pt(a1, r)
    return f"M{x0:.2f},{y0:.2f}A{r},{r} 0 {1 if a1 - a0 > 180 else 0} 1 {x1:.2f},{y1:.2f}"


rings = "\n".join(
    f'  <path d="{arc(a + GAP / 2, b - GAP / 2, R)}" fill="none" stroke="#fff" stroke-opacity="{o}" stroke-width="{W}"/>'
    for (a, b), o in SEGMENTS
)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
 <defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
   <stop offset="0" stop-color="#6d6af5"/><stop offset="1" stop-color="#4338ca"/>
  </linearGradient>
  <filter id="sh" x="-20%" y="-20%" width="140%" height="140%">
   <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/>
  </filter>
 </defs>
 <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)" filter="url(#sh)"/>
{rings}
</svg>
'''
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.svg"), "w") as f:
    f.write(svg)
