# Powerosso App

App privada de **Team Powerosso** para planificar y seguir el entrenamiento de powerlifting.

- **Lector de Excel**: carga la planificación desde el formato de planilla del coach (filas `SEMANA n`, `DÍA n`, cabecera `EJERCICIO | PESO(kg) | SERIES | REPETICIONES | RPE | DESCANSO RECOMENDADO | %RM | … | RANGO DE PESO`). Busca sola la hoja con ese formato y avisa de datos faltantes o pesos que no cuadran con el nombre del ejercicio.
- **Versión alumno** (link personal `…#<id-del-alumno>`): elige semana y día, sigue ejercicio por ejercicio, registra kg, reps y RPE, temporizador de descanso según la planilla, observaciones por ejercicio para el coach, resumen diario y dashboard semanal.
- **Panel del coach**: lista de alumnos, rutina de cada uno con lo realizado, dashboard, observaciones por alumno (responder y marcar revisadas) y carga de nuevas rutinas en Excel.

Métricas del dashboard: tonelaje (kg × reps), carga (tonelaje × RPE/10), series efectivas (RPE ≥ 7), RPE medio y peso más alto por levantamiento y semana.

## Cómo está hecho

Es una sola página (`index.html`) sin servidor propio.

- Publicada como Artifact en claude.ai, guarda alumnos, registros y observaciones en la base de datos compartida del Artifact (`athletes`, `logs`, `notes`), y el dueño ve el panel del coach.
- Abierta en cualquier otro lugar (por ejemplo GitHub Pages), funciona en modo local: todo queda guardado en el navegador de quien la usa.

Para regenerar `index.html` después de editar `src/app.src.html` o `src/parser.js`:

```
python3 src/build.py
```

## Próximo paso

Para que cada alumno entre con su propia cuenta desde el celular, sin depender de claude.ai, el plan es moverla a una app web instalable (Next.js + Supabase + Vercel) reutilizando `src/parser.js` y las mismas métricas.
