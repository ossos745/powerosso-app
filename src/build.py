import base64
s=open('src/app.src.html').read()
logo='data:image/webp;base64,'+base64.b64encode(open('assets/logo.webp','rb').read()).decode()
parser=open('src/parser.js').read().replace("if (typeof module!=='undefined') module.exports={parsePlan, LIFT};","")
open('index.html','w').write(s.replace('LOGO_SRC',logo).replace('/*PARSER*/',parser))
