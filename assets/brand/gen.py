import math
AMBER='#FFB020'; INK='#FFFFFF'
def mark(R=340, n=11, ratio=0.56, angle=24, band=1.35, accent='dot', cx=512, cy=512, ink=INK, ex=0.28, ey=0.30):
    p=2*R/n; h=p*ratio; w=p*band
    t=math.radians(angle)
    stripes=''.join('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f"/>'%(cx-R,cy-R+p*(i+.5)-h/2,2*R,h) for i in range(n))
    out=('<defs><mask id="m" maskUnits="userSpaceOnUse" x="-2000" y="-2000" width="6000" height="6000">'
         '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="#fff"/>'
         '<rect x="-2000" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="#000" transform="translate(%.2f %.2f) rotate(%d)"/>'
         '</mask></defs>'%(cx,cy,R,-w/2,2000+w/2,w,w/2,cx+R*ex,cy+R*ey,angle))
    out+='<g mask="url(#m)" fill="%s">%s</g>'%(ink,stripes)
    if accent=='dot':
        out+='<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>'%(cx+R*ex,cy+R*ey,w*0.3,AMBER)
    return out
def svg(body,bg='#000',tile=False):
    g='<rect x="100" y="100" width="824" height="824" rx="185" fill="#0B0B0C"/><rect x="101" y="101" width="822" height="822" rx="184" fill="none" stroke="#fff" stroke-opacity=".10" stroke-width="2"/>' if tile else '<rect width="1024" height="1024" fill="%s"/>'%bg
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">%s%s</svg>'%(g,body)
open('mark.svg','w').write(svg(mark()))
open('icon.svg','w').write(svg(mark(R=262),tile=True))
open('icon-small.svg','w').write(svg(mark(R=290,n=7,ratio=0.6,band=1.05),tile=True))
open('mark-light.svg','w').write(svg(mark(ink='#0B0B0C'),bg='#F5F5F4'))
T="font-family=\"-apple-system,'SF Pro Display',system-ui\" font-weight=\"650\""
def wordmark(ink):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="300" viewBox="0 0 1200 300">%s'
            '<text x="310" y="212" %s font-size="168" letter-spacing="-7" fill="%s">glidepath</text></svg>')%(mark(R=118,n=9,cx=150,cy=150,ink=ink),T,ink)
open('wordmark-light.svg','w').write(wordmark('#1D1D1F'))
open('wordmark-dark.svg','w').write(wordmark('#F5F5F7'))
S="font-family=\"-apple-system,'SF Pro Text',system-ui\""
social=('<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640"><rect width="1280" height="640" fill="#000"/>'
 + mark(R=220,n=11,cx=1010,cy=320) +
 '<text x="72" y="128" %s font-size="34" letter-spacing="-1" fill="#F5F5F7">glidepath</text>'%T +
 '<text x="72" y="300" %s font-weight="700" font-size="64" letter-spacing="-2.2" fill="#F5F5F7">PRs reviewed</text>'%T.replace(' font-weight="650"','') +
 '<text x="72" y="374" %s font-weight="700" font-size="64" letter-spacing="-2.2" fill="#F5F5F7">before you\'re back.</text>'%T.replace(' font-weight="650"','') +
 '<text x="72" y="438" %s font-size="26" fill="#A1A1A6">Scheduled Claude Code reviews for GitHub,</text>'%S +
 '<text x="72" y="474" %s font-size="26" fill="#A1A1A6">landing in your Mac\'s menu bar.</text>'%S +
 '<text x="72" y="558" font-family="ui-monospace,\'SF Mono\',monospace" font-size="21" fill="#F5F5F7">brew install yznki/tap/glidepath</text></svg>')
open('social.svg','w').write(social)
