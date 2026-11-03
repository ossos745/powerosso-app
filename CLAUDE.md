# CLAUDE.md — Powerosso App

Guía para que Claude Code entienda este proyecto desde cero. Léela completa antes de tocar código.

## Quién y para qué

- **Dueño:** Benjamín Osses (GitHub `BenjaminOsses`; el repo vive en la cuenta `ossos745`). Powerlifter de élite y coach, con estudios de personal trainer e Ingeniería Civil.
- **Idioma:** Benjamín escribe en español. **Responder siempre en español**, en frases simples. Los textos de la app, los comentarios del código y los mensajes de commit también van en español.
- **Negocio:** *Team Powerosso*. Asesoría de powerlifting a US$50/mes: planificación mensual en Excel con seguimiento semanal.
- **La app:** *Powerosso App*, una app web privada para sus alumnos. El alumno sigue su planificación día a día y registra lo que hizo (kg, reps, RPE, observaciones). El coach ve todo, compara plan contra realidad y responde observaciones.
- **Identidad visual:** logo de oso en escudo negro y dorado, con "POWER" en rojo. Paleta negro, dorado, rojo carmesí, café y crema. Los temas de color cambian el dorado por otro acento.

## Enlaces

| Qué | Dónde |
|---|---|
| Repo (público, rama `main`) | https://github.com/ossos745/powerosso-app |
| App publicada (GitHub Pages, sirve `main` desde la raíz) | https://ossos745.github.io/powerosso-app/ |
| Backend Supabase | https://cijsqkefjocieytliojb.supabase.co |
| Prototipo original (artifact de claude.ai) | https://claude.ai/artifact/4MaRbmVh4f9RWDxb79btCP |

## Arquitectura

Una sola página HTML sin servidor propio ni framework ni bundler. JavaScript plano, renderizado con template strings sobre `innerHTML`.

```
powerosso-app/
├── index.html                  ← GENERADO. No editar a mano.
├── src/
│   ├── app.src.html            ← fuente real de la app (HTML + CSS + JS, ~1500 líneas)
│   ├── parser.js               ← lector de la planilla Excel (parsePlan, LIFT)
│   └── build.py                ← arma index.html
├── herramientas/
│   └── actualizar-powerosso.bat← plantilla del actualizador (CMD + PowerShell)
├── analizador/index.html       ← COPIA del Analizador IPF (no se genera ni se edita aquí)
├── config.js                   ← URL y anon key de Supabase (públicas)
├── sw.js                       ← service worker (PWA, caché, avisos push)
├── manifest.json               ← PWA instalable
├── assets/                     ← logo.webp, logo.png, íconos 192/512/maskable
└── supabase/
    ├── schema.sql              ← tablas + funciones pw_*
    ├── push.sql                ← avisos push (sin claves)
    └── functions/pw-push/index.ts ← Edge Function que manda los avisos
```

### Build

Después de editar `src/app.src.html`, `src/parser.js`, `assets/logo.webp` o el `.bat`:

```
python3 src/build.py
```

`build.py` reemplaza en `app.src.html`:
- `LOGO_SRC` → el logo en base64 (data URI de `assets/logo.webp`);
- `/*PARSER*/` → el contenido de `parser.js` (sin la línea `module.exports`);
- `/*BAT*/` → el texto del `.bat`, escapado para ir dentro de un template literal (`` const BAT=`/*BAT*/` ``).

**Siempre commitear `index.html` regenerado junto con el cambio en `src/`.** GitHub Pages sirve `index.html` tal cual.

**Excepción: `analizador/index.html`.** Es el Analizador IPF, copiado tal cual desde el `index.html` del repo https://github.com/ossos745/analizador-ipf (su fuente vive allá; ahí está también `PUENTE-TEAM-POWEROSSO.md`, que documenta el puente). No pasa por `build.py` y no se edita aquí: para actualizarlo, copiar de nuevo el archivo del otro repo y subir `IPF_V` en `app.src.html` a la versión nueva. Se publica en https://ossos745.github.io/powerosso-app/analizador/.

La única dependencia externa es SheetJS: `https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js`.

### Modos de almacenamiento (`Store` en app.src.html)

La app decide al arrancar (`Store.init`) dónde guarda:

1. **`supa`** (versión principal): si `config.js` define `window.POWEROSSO_SUPABASE` con `url` y `anonKey`. Todo pasa por funciones RPC `pw_*` (`rpc(fn,args)` hace `POST /rest/v1/rpc/<fn>`).
2. **`db`**: dentro de un artifact de claude.ai (`window.claude.use('db')`). El dueño del artifact es el coach.
3. **`local`**: cualquier otro lugar; todo en `localStorage` (`powerosso.v3`) y quien la abre es coach.

En modo `supa`, `Store.pull()` corre al inicio, cada 20 s y al volver a la pestaña. Trae solo lo cambiado desde `since` (cada 15 tiradas trae todo). `Store.put()` actualiza `DATA` al tiro y encola la escritura por clave para no pisarse.

### Acceso por link (`?k=<token>`)

- No hay correo ni contraseña. Cada persona (coach y alumnos) tiene un link `https://ossos745.github.io/powerosso-app/?k=<token>`. El token está en `athletes.token`.
- La app comparte origen (`https://ossos745.github.io`) y por lo tanto `localStorage` con el Analizador IPF (que usa `ipf.pref`): **toda clave nueva lleva prefijo `powerosso.`**.
- El token se recuerda en `localStorage` (`powerosso.k`, `powerosso.kc`) para que la PWA instalada abra sin `?k=`. Si el teléfono ya tiene el link del coach, abrir el de un alumno no lo reemplaza.
- El coach puede ver la app "como alumno" con `#<aid>` en la URL (banner "Estás viendo la app como…").
- `?ver=obs` abre el panel del coach directo en Observaciones (lo usa el aviso push).

### Supabase

Tablas (todas con RLS y cerradas a `anon`; la app entra solo por funciones `security definer` que revisan el token):

| Tabla | Contenido |
|---|---|
| `athletes` | `id`, `token`, `coach` (bool), `data` jsonb (`name`, `file` = nombre de su Excel, `meso` = mesociclo activo) |
| `files` | planillas Excel crudas en base64 (`name`, `mtime`, `b64`). Cada cliente las parsea. |
| `logs` | registros de entrenamiento, id `<aid>~<MESO>~<semana>-<día>` |
| `notes` | observaciones de los alumnos y respuestas del coach |
| `pw_config` | claves de los avisos push (no visible desde la app) |
| `push_subs` | suscripciones push del coach |

Funciones: `pw_me`, `pw_load(token, since)`, `pw_file`, `pw_put(token, coll, id, data)`, `pw_del` (solo coach), `pw_norm`, `pw_upload` (la usa el .bat), `pw_export`, `pw_import`, `pw_push_sub`. Trigger `notes_push` (con `pg_net`) llama a la Edge Function `pw-push` cuando un alumno deja una observación.

Reglas de permisos importantes:
- Un alumno solo puede escribir `logs` y `notes` cuyo `data.aid` sea el suyo **y** cuyo id empiece con `<su aid>~`.
- Un alumno **no puede** escribir en `athletes` ni borrar nada (`pw_del` es solo para el coach).
- `config.js` lleva la *anon key*, que es pública por diseño. La *service_role key* nunca va en la app ni en el repo.

## Modelo de datos (jsonb)

- **Log de un día** (`logs`, id `<aid>~<MESO>~<w>-<d>`): `{aid, meso, w, d, sets:{<índice ejercicio>:[{kg, reps, rpe, t, pr?}]}, done, startedAt, date, trainedAt, finishedAt, updatedAt, rpe (del día), resetAt?}`.
- **Serie PR**: `pr = {t, file, sheet, row (fila del Excel), kg, reps, rm1, meso, w, d, ex}`.
- **Preferencias del alumno**: registro especial en `logs` con id **`<aid>~PREFS`** y `{aid, prefs:true, warm, aprox, updatedAt}`. Va en `logs` porque el alumno no puede escribir en `athletes`. Al recorrer logs hay que ignorar los que tengan `prefs:true`.
- **Evaluación IPF de una serie**: `ipf = {v (versión del analizador), at, ver (VALIDO | NO_VALIDO | NO_CONCLUYENTE, nunca booleano), mot, mov, reps, vSub, vSubB (banda en %), vBaj, dSub, dBaj, rom, romB, perd, prof:{v,b,u}, cal (calibrado: si es false, rom va en px), vid (si el video quedó en el aparato)}`. Solo el resumen va en el set; el video y el paquete completo van a IndexedDB (`powerosso.ipf`, almacén `ipf`, clave `<id del log>:<índice ejercicio>:<n° serie desde 1>`), nunca a Supabase.
- **Observación** (`notes`): `{aid, meso, w, d, dayLabel, ex, exName, tag, text, at, reviewed, reply, seen}`. Las observaciones del calentamiento usan `ex = -1 - i` (i = índice del ejercicio de movilidad) y `exName = "Calentamiento · …"`.
- **Día reiniciado**: el log se reemplaza por `{sets:{}, done:false, resetAt}`. Un log sin series y sin `done` cuenta como Pendiente. Las observaciones se mantienen.

## La planilla Excel (parser.js)

- Formato del coach (hoja tipo "HIPERTROFIA"): filas `SEMANA n – …`, `DÍA n – LUNES: FOCO`, y cabecera `EJERCICIO | PESO(kg) | SERIES | REPETICIONES | RPE | DESCANSO RECOMENDADO | %RM | RM ESTIMADO | SERIES X REPES REALIZADAS | RPE REAL | RANGO DE PESO`. Título del macrobloque arriba (B2) y detalles (B3).
- La columna del título es donde más se repite "EJERCICIO" (así no la confunde una tabla al lado).
- Acepta texto en las celdas: peso "BANDA"/"LIVIANO", reps "AMRAP" (se cuenta como 10), "8-10", "10 c/pierna", RPE "9-10", descanso "3-4 min", "90 s".
- RPE de la planilla mayor que 10: de 10,5 a 11 se muestra como 9; desde 11,5, como 10.
- Avisa de datos faltantes y de pesos que no cuadran con el nombre del ejercicio.
- **Mesociclos**: solo cuentan las hojas cuyo nombre contiene Hipertrofia, Fuerza Base, Volumen, Peaking o Tapering (sin importar mayúsculas, tildes ni espacios). Con número ("Volumen 2") es un mesociclo aparte. Orden fijo: Hipertrofia → Fuerza base → Volumen → Peaking → Tapering. El coach elige el mesociclo activo de cada alumno (`athletes.data.meso`).

## Funciones implementadas

### Alumno
- **Entrenar**: elige semana y día, o "Vista semana" tipo Excel. La semana por defecto (`currentWeek`) es la del último entrenamiento registrado por fecha en el mesociclo activo; sin registros, la primera.
- Sesión ejercicio por ejercicio: kg, reps y RPE por serie; temporizador de descanso según la planilla con aviso (sonido y notificación) al terminar; paso automático a la siguiente serie/ejercicio; RPE real por serie y por día con ✓ "RPE registrado".
- **Calentamiento recomendado** al abrir un día: 4 ejercicios de movilidad con animación SVG (`FIG`, `figSvg`). Pierna y lumbar si ≥60% de los ejercicios son de tren inferior; brazos y tronco si ≤40%; si no, mixto 2+2. 1 min de descanso. Se puede dejar observación por ejercicio.
- **Aproximaciones** antes de básicos con barra (`LIFT` ≠ Accesorio, sin mancuernas ni máquina; no se repiten si el ejercicio anterior es el mismo levantamiento): barra 20 kg 8–10 reps 1 min, 40% ×5 1:30, 60% ×4 2:00, 75% ×3 2:00, 90% ×2 3:00. Redondeo a 2,5 kg. El peso de trabajo es editable.
- Interruptores de calentamiento y aproximaciones al final de la lista de días (se guardan en `<aid>~PREFS`).
- **Mantener presionado un día** → "Reiniciar día" con confirmación. Tocar un día hecho abre su resumen.
- **Serie Bilbo**: 1RM estimado = peso × reps × 0,03 + peso (`rm1`).
- **Serie PR**: ejercicio cuyo nombre empieza con "PR". Si el alumno anota kg ≥ plan y reps ≥ plan, la serie guarda `pr` (ver modelo de datos) y el .bat lo escribe en el Excel.
- Observaciones por ejercicio (etiquetas `OBS`: Intensidad perfecta, Podría hacer más, Muy pesado, Molestia / dolor, Duda técnica) y pestaña "Mis notas" con las respuestas del coach.
- **Dashboard semanal**, en este orden: foto de la semana, KPIs, torta por grupo muscular, "Kg totales movidos por semana", avance de topsets, RPE por semana, y el resto.
  - Métricas: tonelaje (kg × reps), carga (tonelaje × RPE/10), series efectivas (RPE ≥ 7, `EFF`), RPE medio, peso más alto por levantamiento.
  - **Torta muscular**: usa la tabla `PONDER` (reparto % de cada variante de básico en 8 grupos `PGRP`) vía `basicOf`/`musclesOf`; lo que no es básico va 100% a su grupo (`MUSC`, regex por nombre). En `MUSC` Espalda va antes que Pecho (por "jalón al pecho").
  - **Avance de topsets**: línea por semana del 1RM estimado de la mejor serie de Sentadilla, Banca y Peso muerto, más la variante punteada (`TSVAR` = pausa, búfalo, block, etc.). Filtro por levantamiento y tabla de la semana con Δ.
  - **RPE por semana** (`rpeCards`): promedio semanal y por básico, plan punteado contra real.
- **Foto del entrenamiento** (día en Resumen, semana en Dashboard): cámara o galería, contenido movible y escalable (dedos en celular, barras en PC). Título = nombre del alumno + fecha, subtítulo "TEAM POWEROSSO" en dorado, luego mesociclo/semana/día. Formatos en `PHOTO_FMTS`: diarios `clasico`, `grupos`, `mixto`, `minimal`; semanales `semana` (kg + torta de kg por día + torta de grupos) y `progreso` (kg por semana real/plan + topsets). Muestra "Máx. intensidad / Máx. volumen", RPE promedio y top set @RPE. No muestra el tiempo de entrenamiento. La foto queda solo en el teléfono (no se sube).
- **Evaluar en video (Analizador IPF)**: tarjeta en la sesión, solo en sentadilla, banca y peso muerto de competencia (`liftDe(x)` sobre `tsCat`: fuera variantes `TSVAR`, mancuernas y máquinas; sí cuentan las variantes con pausa y el peso muerto sumo). Un chip por serie hecha abre `analizador/` en otra pestaña con el contexto en el fragmento (`origen=powerosso`, `sesion` = id del log, `token` de un solo uso guardado en `localStorage` `powerosso.ipf`; nunca se pasa el `?k=`). La vuelta llega por `postMessage` (valida origen, `app`, `formato ≤ 2`, token y que la serie coincida; trae el `File` del video en `videoArchivo`) o por `#powerosso=<base64url>` (`ipfLeerHash`, corre antes del ruteo y limpia el fragmento, sin video). Guarda `ipf` en el set con `Store.put` y el video en IndexedDB (pide `navigator.storage.persist()`). "Ver video" reproduce solo el rango analizado, muestra el espacio usado y permite borrar el video (las métricas se quedan). El coach ve el veredicto y las métricas en Plan vs real. Si la versión guardada no es `IPF_V`, se muestra un aviso. **Falta**: gráficos IPF en el Dashboard (carga–velocidad, velocidad por semana, pérdida, tiempos, profundidad, historial de veredictos, con la franja de la banda) y limpieza automática de videos viejos.
- **Tema**: acentos y tonalidades guardados en el teléfono. **Ayuda**. Banner para instalar como app (PWA).

### Coach (panel)
- **Alumnos**: crear y eliminar, asignar planilla, elegir mesociclo activo, copiar link personal, ver la app como el alumno.
- **Observaciones**: responder (borrador en `S.replyDraft`), marcar revisadas, borrar.
- **Plan vs real**: series, kg y RPE planificados contra reales; el coach puede poner el RPE y borrar el registro de un día.
- **Estadísticas**: general y por alumno (Bilbo, filtros, chips de mesociclo con registros `S.statMeso`, gráficos de RPE por semana).
- Exportar Excel, exportar/importar respaldo `.json`, descargar el actualizador `.bat`.
- **Avisos push de observaciones**: botón "Activar avisos de observaciones" (usa `VAPID_PUB` en la app, `pw_push_sub`, el trigger y la Edge Function).

## El actualizador `.bat` y el flujo con Excel

- Benjamín lo descarga desde el panel del coach; la app rellena `__URL__`, `__KEY__`, `__TOKEN__` (el del coach) y `__APP__` en la plantilla `herramientas/actualizar-powerosso.bat`. Es un archivo CMD que se relanza como PowerShell.
- Carpeta por defecto: `C:\Users\benja\OneDrive\Desktop\Alumnos`.
- Pasos al hacer doble clic:
  1. Llama a `pw_load` y junta las series con `pr`.
  2. Abre cada Excel por COM (usa el que esté abierto o abre uno oculto), busca hacia arriba desde la fila del ejercicio la cabecera "SERIES X REPES REALIZADAS" (normalizada sin espacios, puntos ni mayúsculas) y escribe el 1RM en esa columna, en la fila del ejercicio.
  3. Sube todas las `.xlsx`/`.xlsm` de la carpeta con `pw_upload`; asigna cada una al alumno cuyo nombre aparece en el nombre del archivo, o crea uno nuevo.
  4. Guarda un respaldo JSON en `Respaldos Powerosso` dentro de la carpeta.
- Cada vez que cambia la plantilla, Benjamín tiene que **volver a descargar el .bat** desde el panel.
- La parte de PR **no se ha probado en Windows**. Al editar el `.bat`, mantener ASCII sin tildes en los textos de PowerShell y no usar backticks sin escapar (build.py los escapa).

## Convenciones

- **Los datos de alumnos no van al repo** (es público): nada de tokens, nombres con planillas, Excel (`*.xlsx` está en `.gitignore`), respaldos ni la seed.
- **Secretos fuera del repo**: claves VAPID privadas, la clave `hook` de pw_config y la service_role key. `VAPID_PUB` y la anon key sí pueden ir en el código.
- Editar `src/` y regenerar `index.html`; nunca editar `index.html` a mano.
- Todo el código vive en `src/app.src.html` (no hay módulos). Funciones de vista con prefijo `v` (`vDias`, `vSesion`, `vDash`, `vAlumnos`…). Estado global en `S`, datos en `DATA = {athletes, logs, notes}`. Acciones por `data-act`, `data-tab`, `data-ctab`, etc., con delegación de eventos.
- `softRender()` no redibuja si alguien está escribiendo en un input (marca `S.dirty`); al perder el foco se espera a soltar el puntero antes de redibujar, para no comerse el clic de un botón. Respetar esto al agregar campos.
- Formato de números chileno (`es-CL`, coma decimal) con `fmt()`. Escapar todo texto del usuario con `esc()`.
- El service worker es *network first* (`CACHE = 'powerosso-v3'`): no hace falta cambiar la versión en cada cambio de la app.
- Commits en español, descriptivos, directo a `main` (así se ha trabajado hasta ahora). Revisar los cambios visuales en el navegador (por ejemplo con Playwright y un `config.js` vacío, que deja la app en modo local) antes de subir.

## Archivos que viven fuera del repo

En la carpeta compartida del proyecto de claude.ai (`/mnt/project-files/`), no en GitHub:

| Archivo | Para qué |
|---|---|
| `powerosso-app/supabase-schema.sql` | copia de `supabase/schema.sql` para pegar en el SQL Editor |
| `powerosso-app/supabase-seed.sql` | carga inicial con los alumnos y **sus tokens** (privado) |
| `powerosso-app/supabase-avisos.sql` | `push.sql` + las claves de los avisos (privado) |
| `powerosso-app/supabase-avisos-claves.sql` | solo el `insert` de las claves en `pw_config` (privado) |
| `powerosso-app/pw-push-index.ts` | copia de la Edge Function `pw-push` (se despliega con *Verify JWT* apagado) |
| `powerosso-app/ejemplos/*.png` | capturas de referencia de cada función |
| `ponderaciones/ponderacion-muscular-basicos.xlsx` | tabla de ponderación muscular (30 variantes de básicos). La hoja **"Grupos app"** es la que se copió a `PONDER`. Si Benjamín cambia la tabla, regenerar `PONDER` desde esa hoja. |
| `uploads/hearth/…` | Excel originales subidos por Benjamín (datos de alumnos) |

Si Benjamín necesita alguno de estos en local, pídeselo; no los subas al repo.

## Pendiente de Benjamín

- Correr `supabase-avisos-claves.sql` en el SQL Editor de Supabase (las tablas, el trigger y la función `pw-push` ya están; faltan las claves para que lleguen los avisos).
- Volver a descargar el `.bat` desde el panel y probar en Windows la anotación de PR en los Excel.
- Confirmar que el resto de la puesta en marcha quedó hecha (schema, seed, GitHub Pages activado).

## Notas de trabajo

- Los cambios en Supabase (SQL, Edge Functions) los aplica Benjamín: entrégale el SQL listo para pegar en *Supabase → SQL Editor → Run*.
- Los alumnos usan la app en el celular: todo tiene que funcionar bien en pantallas angostas y con dedos (y también en PC).
- Antes de proponer algo grande, explica en una o dos frases qué vas a cambiar.
