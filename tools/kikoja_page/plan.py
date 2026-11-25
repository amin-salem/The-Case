# builds the two house SVGs (architectural night plan) for Plan.dc.html
H = {
 'qolhak': dict(h=200, rooms=[('lib',200,0,'wood'),('salon',100,0,'wood'),('yard',0,0,'garden'),('study',200,100,'wood'),('hall',100,100,'stone'),('kitchen',0,100,'tile')],
   doors=[('lib','salon'),('salon','yard'),('salon','hall'),('lib','study'),('study','hall'),('hall','kitchen'),('kitchen','yard')]),
 'kashan': dict(h=300, rooms=[('upper',200,0,'wood'),('porch',100,0,'stone'),('shah',0,0,'wood'),('mkitchen',200,100,'tile'),('court',100,100,'garden'),('klib',0,100,'wood'),('store',200,200,'stone'),('hashti',100,200,'stone'),('guest',0,200,'wood')],
   doors=[('upper','porch'),('porch','shah'),('porch','court'),('court','mkitchen'),('court','klib'),('court','hashti'),('mkitchen','store'),('store','hashti'),('hashti','guest'),('klib','guest')]),
}
GOLD='#C9A15E'; LN='stroke="#A39C8C" stroke-opacity=".55" stroke-width=".9"'
DEFS='''<defs>
<pattern id="pw" width="100" height="9" patternUnits="userSpaceOnUse"><rect width="100" height="9" fill="#23201B"/><path d="M0 8.5H100M30 0V9M78 0V9" stroke="#2D2922" stroke-width=".8"/></pattern>
<pattern id="pt" width="12" height="12" patternUnits="userSpaceOnUse"><rect width="12" height="12" fill="#1D1F22"/><rect width="6" height="6" fill="#24262A"/><rect x="6" y="6" width="6" height="6" fill="#24262A"/></pattern>
<pattern id="pg" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="#151D18"/><circle cx="3" cy="3" r=".9" fill="#22301F"/><circle cx="8" cy="7.5" r=".8" fill="#1F2B1E"/></pattern>
<pattern id="ps" width="16" height="8" patternUnits="userSpaceOnUse"><rect width="16" height="8" fill="#201E1B"/><path d="M0 .4H16M0 4.4H16M4 .4V4.4M12 4.4V8.4" stroke="#2A2723" stroke-width=".7"/></pattern>
</defs>'''
FILL={'wood':'url(#pw)','tile':'url(#pt)','garden':'url(#pg)','stone':'url(#ps)'}
def r(x,y,w,h,fill='#2E2B26',rx=1.5,extra=''): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" {LN} {extra}/>'
def c(x,y,rad,fill='#2E2B26',extra=''): return f'<circle cx="{x}" cy="{y}" r="{rad}" fill="{fill}" {LN} {extra}/>'
def books(x,y,w,h,vert=False):
    s=r(x,y,w,h,'#3A3024')
    if vert: s+=''.join(f'<path d="M{x} {y+i}H{x+w}" stroke="#5A4A36" stroke-width=".6"/>' for i in range(3,h,3))
    else: s+=''.join(f'<path d="M{x+i} {y}V{y+h}" stroke="#5A4A36" stroke-width=".6"/>' for i in range(3,w,3))
    return s
def rug(x,y,w,h,base='#2F2320',edge='#7A5A3E'):
    return r(x,y,w,h,base,1)+f'<rect x="{x+3}" y="{y+3}" width="{w-6}" height="{h-6}" fill="none" stroke="{edge}" stroke-opacity=".7" stroke-width=".8"/>'
def pool(x,y,w,h):
    return r(x,y,w,h,'#173039',5,'')+f'<rect x="{x+3}" y="{y+3}" width="{w-6}" height="{h-6}" rx="3" fill="none" stroke="#3E7585" stroke-width=".8"/><path d="M{x+8} {y+h/2-3}q5 -3 10 0t10 0M{x+12} {y+h/2+4}q5 -3 10 0" stroke="#4F8C9C" stroke-opacity=".6" stroke-width=".7" fill="none"/>'
def tree(x,y,rad): return c(x,y,rad,'#1B2A1E','stroke-dasharray="2 1.6"')+c(x,y,rad*.35,'#24382A')
def F(kind,x,y):
    if kind in('lib','klib'): return books(x+8,y+8,84,7)+books(x+85,y+20,7,58,True)+r(x+26,y+52,18,16,'#3A332A',4)+c(x+56,y+62,5,'#33302A')
    if kind=='salon': return rug(x+16,y+32,68,48)+r(x+20,y+14,60,11,'#35312B',3)+r(x+10,y+38,10,16,'#35312B',3)+r(x+80,y+38,10,16,'#35312B',3)+r(x+38,y+48,24,14,'#3C342B',2)
    if kind=='yard': return pool(x+30,y+36,40,28)+tree(x+17,y+18,11)+tree(x+82,y+80,13)+r(x+12,y+74,22,6,'#3A332A',1)
    if kind=='study': return r(x+24,y+22,52,20,'#3B2E22',2)+r(x+30,y+26,12,9,'#CFC6B0',.5,'fill-opacity=".5"')+c(x+50,y+54,7,'#35312B')+c(x+68,y+30,3.2,'#E0A526','fill-opacity=".9"')+books(x+8,y+66,7,26,True)
    if kind=='hall': return rug(x+12,y+40,76,20,'#2C2220','#6B4A36')+''.join(f'<path d="M{x+10} {y+42+i*4}h2M{x+88} {y+42+i*4}h2" stroke="#6B4A36" stroke-width=".6"/>' for i in range(5))+tree(x+86,y+14,6)
    if kind in('kitchen','mkitchen'): return r(x+8,y+8,84,12,'#2B2D30',1)+r(x+8,y+8,12,60,'#2B2D30',1)+''.join(c(x+40+i*9,y+14,2.6,'#1A1B1D') for i in range(4))+r(x+46,y+50,30,24,'#3C342B',2)+''.join(r(a,b,7,5,'#33302A',1) for a,b in [(x+50,y+44),(x+64,y+44),(x+50,y+75),(x+64,y+75)])
    if kind=='upper': return r(x+14,y+16,38,56,'#2F2C27',3)+r(x+18,y+20,30,10,'#3D3A33',2)+r(x+64,y+16,22,14,'#3A3024',1.5)+rug(x+58,y+50,30,36)
    if kind=='porch': return rug(x+18,y+16,64,40,'#2E2421','#7A5A3E')+''.join(c(x+14+i*24,y+82,4.2,'#3A352D') for i in range(4))
    if kind=='shah': return rug(x+10,y+10,80,80,'#33201F','#8A5A40')+f'<path d="M{x+50} {y+30}L{x+70} {y+50}L{x+50} {y+70}L{x+30} {y+50}Z" fill="#4A2B26" stroke="#9A6A48" stroke-opacity=".8" stroke-width=".8"/>'+c(x+50,y+50,4,'#9A6A48')
    if kind=='court': return r(x+6,y+18,12,64,'#1B2A1E',2)+r(x+82,y+18,12,64,'#1B2A1E',2)+pool(x+26,y+24,48,52)+c(x+50,y+50,3,'#4F8C9C')
    if kind=='store': return ''.join(r(a,b,16,16,'#3A3024',1)+f'<path d="M{a} {b}l16 16M{a+16} {b}l-16 16" stroke="#5A4A36" stroke-width=".7"/>' for a,b in [(x+12,y+12),(x+30,y+12),(x+12,y+30)])+c(x+72,y+70,8,'#3A332A')+c(x+82,y+56,6,'#3A332A')
    if kind=='hashti':
        import math
        pts=' '.join(f'{x+50+30*math.cos(math.pi/8+k*math.pi/4):.1f},{y+50+30*math.sin(math.pi/8+k*math.pi/4):.1f}' for k in range(8))
        pts2=' '.join(f'{x+50+9*math.cos(math.pi/8+k*math.pi/4):.1f},{y+50+9*math.sin(math.pi/8+k*math.pi/4):.1f}' for k in range(8))
        return f'<polygon points="{pts}" fill="none" stroke="#A39C8C" stroke-opacity=".5" stroke-width=".9"/><polygon points="{pts2}" fill="#173039" stroke="#3E7585" stroke-width=".8"/>'
    if kind=='guest': return rug(x+16,y+22,68,56,'#2C2422','#7A5A3E')+r(x+12,y+10,76,8,'#35312B',3)+r(x+10,y+22,8,56,'#35312B',3)
    return ''
def svg(name):
    d=H[name]; h=d['h']; pos={k:(x,y) for k,x,y,_ in d['rooms']}
    out=[f'<svg viewBox="-6 -6 312 {h+12}" width="100%" height="100%" preserveAspectRatio="none" aria-hidden="true" style="position:absolute;inset:0;display:block">',DEFS,f'<rect x="-6" y="-6" width="312" height="{h+12}" fill="#111214"/>']
    for k,x,y,fl in d['rooms']: out.append(f'<rect x="{x}" y="{y}" width="100" height="100" fill="{FILL[fl]}"/>')
    for k,x,y,fl in d['rooms']: out.append(F(k,x,y))
    doors={frozenset(p) for p in d['doors']}
    keys=list(pos)
    for i,a in enumerate(keys):
        for b in keys[i+1:]:
            (ax,ay),(bx,by)=pos[a],pos[b]
            if ay==by and abs(ax-bx)==100: X=max(ax,bx); seg=('v',X,ay)
            elif ax==bx and abs(ay-by)==100: Y=max(ay,by); seg=('h',ax,Y)
            else: continue
            door=frozenset((a,b)) in doors
            if seg[0]=='v':
                X,Y0=seg[1],seg[2]
                if door:
                    out.append(f'<path d="M{X} {Y0}V{Y0+39}M{X} {Y0+61}V{Y0+100}" stroke="{GOLD}" stroke-width="3.2" stroke-linecap="square"/>')
                    out.append(f'<path d="M{X} {Y0+39}H{X+21}" stroke="{GOLD}" stroke-width="1.4" stroke-opacity=".8"/><path d="M{X+21} {Y0+39}A21 21 0 0 1 {X} {Y0+60}" fill="none" stroke="{GOLD}" stroke-opacity=".45" stroke-width=".8" stroke-dasharray="2 1.5"/>')
                else: out.append(f'<path d="M{X} {Y0}V{Y0+100}" stroke="{GOLD}" stroke-width="3.2"/>')
            else:
                X0,Y=seg[1],seg[2]
                if door:
                    out.append(f'<path d="M{X0} {Y}H{X0+39}M{X0+61} {Y}H{X0+100}" stroke="{GOLD}" stroke-width="3.2" stroke-linecap="square"/>')
                    out.append(f'<path d="M{X0+39} {Y}V{Y-21}" stroke="{GOLD}" stroke-width="1.4" stroke-opacity=".8"/><path d="M{X0+39} {Y-21}A21 21 0 0 1 {X0+60} {Y}" fill="none" stroke="{GOLD}" stroke-opacity=".45" stroke-width=".8" stroke-dasharray="2 1.5"/>')
                else: out.append(f'<path d="M{X0} {Y}H{X0+100}" stroke="{GOLD}" stroke-width="3.2"/>')
    out.append(f'<rect x="0" y="0" width="300" height="{h}" fill="none" stroke="{GOLD}" stroke-width="5" stroke-linejoin="round"/>')
    # front door on outer wall + compass
    out.append(f'<path d="M140 {h}h20" stroke="#111214" stroke-width="6"/><path d="M140 {h+1}h20" stroke="{GOLD}" stroke-width="1" stroke-dasharray="2 2"/>')
    out.append('</svg>')
    return ''.join(out)
import sys
print(svg(sys.argv[1]))
