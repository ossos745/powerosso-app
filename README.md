# Powerosso App

App privada de **Team Powerosso** para planificar y seguir el entrenamiento de powerlifting.

- **Lector de Excel**: carga la planificación desde el formato de planilla del coach (filas `SEMANA n`, `DÍA n`, cabecera `EJERCICIO | PESO(kg) | SERIES | REPETICIONES | RPE | DESCANSO RECOMENDADO | %RM | … | RANGO DE PESO`). Busca sola la hoja con ese formato y avisa de datos faltantes o pesos que no cuadran con el nombre del ejercicio.
- **Versión alumno** (link personal `…#<id-del-alumno>`): elige semana y día, sigue ejercicio por ejercicio, registra kg, reps y RPE, temporizador de descanso según la planilla, observaciones por ejercicio para el coach, resumen diario y dashboard semanal.
- **Panel del coach**: lista de alumnos, rutina de cada uno con lo realizado, dashboard, observaciones por alumno (responder y marcar revisadas) y carga de nuevas rutinas en Excel.

Métricas del dashboard: tonelaje (kg × reps), carga (tonelaje × RPE/10), series efectivas (RPE ≥ 7), RPE medio y peso más alto por levantamiento y semana.

## Cómo está hecho

Es una sola página (`index.html`) sin servidor propio. Guarda los datos según dónde se abra:

- **GitHub Pages + Supabase** (versión principal): si `config.js` tiene la URL y la anon key del proyecto de Supabase, cada persona entra con su email (link o código por correo, sin contraseña). El coach ve todo; cada alumno ve solo su planificación, sus registros y sus observaciones. Esas reglas viven en la base de datos (`supabase/schema.sql`).
- **Artifact de claude.ai**: usa la base de datos compartida del Artifact y el dueño ve el panel del coach.
- **Cualquier otro lugar**: modo local, todo queda en el navegador de quien la usa.

### Poner en marcha Supabase

1. Crear un proyecto en supabase.com.
2. SQL Editor → pegar y correr `supabase/schema.sql`.
3. Agregar la ficha del coach con su email (`coach = true`) y la de cada alumno. Los alumnos también se pueden crear desde el panel del coach subiendo su Excel e indicando su email.
4. Authentication → URL Configuration: poner la dirección de la app (por ejemplo `https://ossos745.github.io/powerosso-app/`) como Site URL y en Redirect URLs.
5. Copiar la Project URL y la anon public key en `config.js`. La service_role key nunca va en la app.

Para regenerar `index.html` después de editar `src/app.src.html` o `src/parser.js`:

```
python3 src/build.py
```
