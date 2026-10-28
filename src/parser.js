// Powerosso: lector del formato de planificación (hoja tipo "HIPERTROFIA").
// Recibe una matriz de filas (array de arrays, como XLSX.utils.sheet_to_json(ws,{header:1})) y devuelve el plan.
function parsePlan(rows, sheetName, firstRow){
  firstRow = firstRow || 1;
  const S = v => (v === null || v === undefined) ? '' : String(v).trim();
  const up = v => S(v).toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g,'');
  const plan = {sheet: sheetName, macro: sheetName, title:'', details:'', params:{}, weeks:[], warnings:[]};
  let week=null, day=null, cols=null, titleCol=1;
  // La columna del título es la de la primera cabecera "EJERCICIO" (si no hay, la primera con "SEMANA n")
  // (la columna donde más se repite "EJERCICIO": así no la confunde una tabla de récords al lado)
  const cnt={}; for (const r of rows) (r||[]).forEach((c,i)=>{ if(up(c)==='EJERCICIO') cnt[i]=(cnt[i]||0)+1 });
  const best=Object.keys(cnt).sort((a,b)=>cnt[b]-cnt[a]||a-b)[0]; const found=best!==undefined; if(found) titleCol=+best;
  if(!found) for (const r of rows){ const i=(r||[]).findIndex(c=>/^SEMANA\s*\d+/.test(up(c))); if(i>=0){titleCol=i;break;} }
  const rest = txt => {
    const t = up(txt); if(!t) return null;
    const m = t.match(/(\d+(?:[.,]\d+)?)\s*(?:-|–|A)?\s*(\d+(?:[.,]\d+)?)?\s*(MIN|S|SEG)/);
    if(!m) return null;
    const k = m[3]==='MIN'?60:1, a=parseFloat(m[1].replace(',','.'))*k, b=m[2]?parseFloat(m[2].replace(',','.'))*k:a;
    return {min:Math.round(a), max:Math.round(b), text:S(txt)};
  };
  const repsNum = r => { const t=up(r); if(t==='AMRAP') return 10; const m=t.match(/\d+/g); if(!m) return 0; return m.length>1?(+m[0]+ +m[1])/2:+m[0]; };
  rows.forEach((r, idx) => {
    { const i=(r||[]).findIndex(c=>up(c)==='1RM'); if(i>=0 && rows[idx+1]) for(let c=i+1;c<r.length;c++){ if(S(r[c]) && typeof rows[idx+1][c]==='number') plan.params['1RM '+S(r[c])+' (kg)']=rows[idx+1][c]; } }
    r = r || []; const b = S(r[titleCol]), B = up(r[titleCol]), rowN = idx+firstRow;
    // parámetros a la derecha (pares etiqueta/valor)
    for (let c=titleCol+12;c<r.length-1;c++){ if(typeof r[c+1]==='number' && /1RM|BILBO|\(KG\)/.test(up(r[c])) && !(S(r[c]) in plan.params)) plan.params[S(r[c])]=r[c+1]; }
    if(!b) return;
    // "SEMANA 3 – ...", "HIPERTROFIA SEMANA 3 (RPE 7)" o "SEMANA 3(8 DE JUNIO)"
    const wm = B.match(/^(?:(?:HIPERTROFIA|FUERZA\s*BASE|VOLUMEN|PEAKING|TAP+ERING|DESCARGA)(?:\s*\d+)?\s+)?SEMANA\s*(\d+)\b\s*[–-]?\s*(.*)$/);
    if (wm){ week={n:+wm[1], label:S(b).replace(/^.*?SEMANA\s*\d+\s*[–-]?\s*/i,'').replace(/^\((.*)\)$/,'$1'), deload:/DESCARGA/.test(B), days:[]}; plan.weeks.push(week); day=null; return; }
    const dm = B.match(/^DIA\s*(\d+)\s*[–:-]?\s*(.*)$/);
    if (dm){ if(!week){ plan.warnings.push({row:rowN,msg:'Día antes de la primera semana'}); return; }
      const restTxt=S(b).replace(/^D[IÍií]A\s*\d+\s*[–:-]?\s*/i,''); const ci=restTxt.indexOf(':');
      const WD=/^(LUNES|MARTES|MI[EÉ]RCOLES|JUEVES|VIERNES|S[AÁ]BADO|DOMINGO)\b/i;
      const wd=ci>0?restTxt.slice(0,ci).trim():''; const isWd=WD.test(wd)&&wd.replace(WD,'').trim()==='';
      const lead=!isWd&&ci<0&&restTxt.match(WD);   // "DÍA 4: SÁBADO(FULLBODY)" o "DÍA 1: LUNES"
      day={n:+dm[1], weekday:isWd?wd:lead?lead[1]:'', focus:isWd?restTxt.slice(ci+1).trim():lead?restTxt.slice(lead[0].length).replace(/^[\s(–:-]+|\)\s*$/g,'').trim():restTxt, exercises:[]}; week.days.push(day);
      if(r.slice(titleCol+1).some(v=>/^D[IÍ]A\s*\d+/i.test(S(v)))) plan.warnings.push({row:rowN, where:`Semana ${week.n}`, kind:'check', msg:'Hay una segunda tabla de día al lado (más a la derecha); la app solo carga la de la izquierda'});
      return; }
    if (B==='EJERCICIO'){ cols={}; let stop=false; r.forEach((h,c)=>{ const H=up(h); if(c>titleCol && H==='EJERCICIO') stop=true; if(stop||c<=titleCol) return;
        const k=/^PESO/.test(H)?'kg':H==='SERIES'?'sets':/^REP(ETICION|S\b|$)/.test(H)?'reps':/^RPE(\s*\(@\))?$/.test(H)?'rpe':/^DESCANSO/.test(H)?'rest':/^%/.test(H)?'pct':/^RANGO/.test(H)?'range':null;
        if(k && (cols[k]===undefined || k==='range')) cols[k]=c; }); return; }
    if (!week){ if(!plan.title) plan.title=b; else if(!plan.details) plan.details=b; return; }
    if (!day || !cols || /^OBJETIVO/.test(B)) return;
    const g = k => cols[k]===undefined?undefined:r[cols[k]];
    // RPE sobre 10 en la planilla: 10,5 y 11 se muestran como 9; 11,5 o más como 10
    const rpeFix=v=>v>10?(v<=11?9:10):v;
    const rpeIn=g('rpe'), rpeRaw=typeof rpeIn==='number'?rpeFix(rpeIn):(S(rpeIn)?S(rpeIn).replace(/\d+(?:[.,]\d+)?/g,m=>{ const v=parseFloat(m.replace(',','.')); return v>10?String(rpeFix(v)):m }):rpeIn);
    const kgRaw=g('kg'), setsRaw=g('sets'), repsRaw=g('reps'), restRaw=g('rest');
    const ex = {name:b, row:rowN, kg: typeof kgRaw==='number'?kgRaw:null, load: typeof kgRaw==='number'?null:(S(kgRaw)||null),
      sets: typeof setsRaw==='number'?setsRaw:(parseInt(setsRaw)||null), reps:S(repsRaw), repsN:repsNum(repsRaw),
      rpe: typeof rpeRaw==='number'?rpeRaw:(S(rpeRaw)||null), rpeN: typeof rpeRaw==='number'?rpeRaw:(parseFloat(S(rpeRaw).split('-').pop().replace(',','.'))||null),
      rest: rest(restRaw), pct: typeof g('pct')==='number'?g('pct'):null, range:S(g('range'))||null };
    const where = `Semana ${week.n} · Día ${day.n} · ${b}`;
    const miss=[]; if(ex.kg===null && !ex.load) miss.push('peso'); if(!ex.sets) miss.push('series'); if(!ex.reps) miss.push('repeticiones'); if(ex.rpe===null && (cols.rpe===undefined || LIFT(b)!=='Accesorio')) miss.push('RPE'); if(!ex.rest && cols.rest!==undefined) miss.push('descanso');
    if(miss.length) plan.warnings.push({row:rowN, where, msg:'Falta '+miss.join(', ')});
    if(!ex.sets) ex.sets=1;
    if(!ex.rest) ex.rest={min:120,max:120,text:'2 min (por defecto)'};
    // back-off: comprobar que el peso cuadra con lo que dice el nombre (TOPSET −15 kg / +5 kg)
    const bo = B.match(/TOPSET\s*([−\-+])\s*(\d+(?:[.,]\d+)?)\s*KG/);
    if (bo && ex.kg!==null){
      const top=[...day.exercises].reverse().find(e=>/TOPSET/.test(up(e.name)) && !/BACK/.test(up(e.name)) && e.kg!==null);
      if(top){ const d=parseFloat(bo[2].replace(',','.'))*(bo[1]==='+'?1:-1), expect=top.kg+d;
        if(Math.abs(expect-ex.kg)>0.01) plan.warnings.push({row:rowN, where, kind:'check', msg:`El nombre dice TOPSET ${bo[1]==='+'?'+':'−'}${bo[2]} kg (${top.kg} → ${expect} kg), pero el peso es ${ex.kg} kg`}); }
    }
    if(cols.range!==undefined && r.slice(cols.range+2).some(v=>/^\d+(\s*-\s*\d+)?\s*(min|s)$/i.test(S(v)))) plan.warnings.push({row:rowN, where, kind:'check', msg:'Hay datos sueltos a la derecha de la tabla en esta fila; no se cargaron'});
    day.exercises.push(ex);
  });
  if(plan.weeks.length && !rows.some(r=>(r||[]).some(c=>/^DESCANSO/.test(up(c))))) plan.warnings.unshift({row:firstRow, where:'Toda la hoja', msg:'La hoja no tiene columna DESCANSO: el temporizador usa 2 min por defecto'});
  const m=up(sheetName).replace(/^BLOQUE\s+(DE\s+)?/,'').replace(/[-_ ]FB$/,'').trim(); plan.macro=m||sheetName;
  return plan;
}
const LIFT = n => { const t=n.toUpperCase(); if(/BANCA|BENCH/.test(t)) return 'Banca'; if(/DEADLIFT|BLOCKPULL|PESO MUERTO/.test(t)&&!/RUMANO/.test(t)) return 'Peso muerto'; if(/SQUAT|SENTADILLA/.test(t)&&!/BELT/.test(t)) return 'Sentadilla'; return 'Accesorio'; };
if (typeof module!=='undefined') module.exports={parsePlan, LIFT};
