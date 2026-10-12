# Powerosso App

App privada de **Team Powerosso** para planificar y seguir el entrenamiento de powerlifting.

- **Lector de Excel**: carga la planificación desde el formato de planilla del coach (filas `SEMANA n`, `DÍA n`, cabecera `EJERCICIO | PESO(kg) | SERIES | REPETICIONES | RPE | DESCANSO RECOMENDADO | %RM | … | RANGO DE PESO`). Busca sola la hoja con ese formato y avisa de datos faltantes o pesos que no cuadran con el nombre del ejercicio.
- **Versión alumno** (link personal `…#<id-del-alumno>`): elige semana y día, sigue ejercicio por ejercicio, registra kg, reps y RPE, temporizador de descanso según la planilla, observaciones por ejercicio para el coach, resumen diario y dashboard semanal.
- **Panel del coach**: lista de alumnos, rutina de cada uno con lo realizado, dashboard, observaciones por alumno (responder y marcar revisadas) y carga de nuevas rutinas en Excel.

Métricas del dashboard: tonelaje (kg × reps), carga (tonelaje × RPE/10), series efectivas (RPE ≥ 7), RPE medio y peso más alto por levantamiento y semana.

## Mesociclos

La app solo toma las hojas cuyo nombre contiene **Hipertrofia, Fuerza base, Volumen, Peaking o Tapering** (sin importar mayúsculas ni tildes). Una planilla puede traer varios; el coach elige en su panel en qué mesociclo está cada alumno y el alumno ve esa rutina. Los registros y observaciones quedan guardados por mesociclo.

## Cómo está hecho

Es una sola página (`index.html`) sin servidor propio. Guarda los datos según dónde se abra:

- **GitHub Pages + Supabase** (versión principal): si `config.js` tiene la URL y la anon key del proyecto de Supabase, cada persona entra con su link personal (`?k=<clave>`), sin correo ni contraseña. El link del coach abre el panel completo; el de cada alumno, solo lo suyo. Las tablas quedan cerradas y la app entra por las funciones `pw_*` de `supabase/schema.sql`, que revisan la clave.
- **Artifact de claude.ai**: usa la base de datos compartida del Artifact y el dueño ve el panel del coach.
- **Cualquier otro lugar**: modo local, todo queda en el navegador de quien la usa.

### Poner en marcha Supabase

1. Crear un proyecto en supabase.com.
2. SQL Editor → pegar y correr `supabase/schema.sql`.
3. Crear la ficha del coach: `insert into athletes(id, coach, data) values ('coach', true, '{"name":"Tu nombre"}') returning token;` y abrir la app con `?k=<ese token>`.
4. Copiar la Project URL y la anon public key en `config.js`. La service_role key nunca va en la app.

### Actualizador de planillas (.bat)

Desde el panel del coach → *Descargar actualizador (.bat)*. Al abrirlo con doble clic sube todas las planillas de la carpeta de alumnos (por defecto `C:\Users\benja\OneDrive\Desktop\Alumnos`), las asigna al alumno cuyo nombre aparece en el nombre del archivo (o crea uno nuevo) y guarda un respaldo en `Respaldos Powerosso` dentro de esa carpeta. La plantilla está en `herramientas/actualizar-powerosso.bat`.

### Respaldo

*Exportar respaldo* descarga un `.json` con alumnos, links, planillas, mesociclos, registros, observaciones y un resumen de métricas por semana. *Importar respaldo* lo vuelve a cargar.

Para regenerar `index.html` después de editar `src/app.src.html`, `src/parser.js` o el `.bat`:

```
python3 src/build.py
```
