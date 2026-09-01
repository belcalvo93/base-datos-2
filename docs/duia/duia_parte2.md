# Declaración de Uso de IA (DUIA) — Parte 2

**Ejercicio:** Laboratorio de anomalias con dos sesiones concurrentes (informe_concurrencia.md)

**Fecha:** 26/08/2026

---

## Herramienta
Claude (Antropic), modo conversacional 
La consigna pide explícitamente pedirle a una IA la explicación de cada escenario y verificarla después contra el motor. Esa consulta se hizo con esta herramienta, y las explicaciones quedaron transcriptas en el informe dentro de la sección «Explicación de la IA» de cada escenario.

---

## Spec o prompt utilizado 
El trabajo fue dialogado. La IA propuso la secuencia de comandos de cada escenario indicando qué ejecutar en SESION-A y qué en SESION-B, y en qué orden. Yo ejecuté los comandos y le devolví la salida real de cada sesión para que confirmara si el fenómeno se había reproducido.
Consultas realizadas, en orden:
•	Explicación de qué es un trigger y qué es la concurrencia.
•	Secuencia de comandos para reproducir la lectura no repetible, y qué nivel de aislamiento la evita.
•	Secuencia para reproducir la lectura fantasma.
•	Secuencia para reproducir la espera por bloqueo con FOR UPDATE.
---

## Lo que generó la IA
•	La secuencia exacta de comandos de cada escenario, con el orden entre sesiones.
•	Las explicaciones de por qué ocurre cada anomalía y qué mecanismo la evita (transcriptas en el informe).
•	La sugerencia de activar \timing on en la sesión B para el escenario 3.
---

## Lo que acepté
Las secuencias de comandos, las explicaciones sobre niveles de aislamientos y bloqueos

---

## Lo que se modificó o descarto, y justificación

1. Se corrigió a la IA sobre la reproducción del escenario 3. Al revisar las salidas que le pasé, la IA concluyó dos que el escenario de espera por bloqueo no se había reproducido, porque en el historial de la sesión B el SELECT ... FOR UPDATE y el ROLLBACK aparecían en líneas consecutivas. Le indiqué que la espera sí había ocurrido: lo que pasaba era que el log de texto no registra las pausas, y al pegar cada ventana por separado se pierde el orden real entre sesiones. Por eso se uso \timing on para dejar evidencia medible de la espera.
2. Se agregó \timing on a la reproducción. Surgió de esa discusión: sin una medida de tiempo, la espera no deja ninguna marca en la salida, porque el valor devuelto es idéntico al que se obtendría sin bloqueo. Con el cronómetro activado, la diferencia quedó documentada: 31.170 ms para el SELECT bloqueado frente a 0,316 ms para un BEGIN en la misma sesión.
3. No se confirmó una afirmación no verificada. En el escenario 2, la IA afirmó que en PostgreSQL el nivel Repeatable Read también evita las lecturas fantasma. Esa afirmación no se probó en el motor. Se dejó registrada en el informe como pendiente de verificación en lugar de presentarla como confirmada.
4. Se descartó usar pgAdmin o DBeaver. Se trabajó con dos ventanas de psql. Un cliente gráfico puede administrar las transacciones por su cuenta, lo que impediría controlar con precisión cuándo se abre y se cierra cada una — control indispensable para demostrar que una sesión quedó esperando a la otra.

---

## Verificación realizada

Cada explicación proporcionada por la IA fue contrastada mediante la ejecución real de los escenarios sobre la base de datos `bd2_trabajo`.

En el caso de la **lectura no repetible**, la IA afirmó que con el nivel de aislamiento **Read Committed** una lectura puede cambiar entre dos consultas, mientras que **Repeatable Read** mantiene estable el valor leído. La ejecución confirmó este comportamiento: con Read Committed el valor pasó de **40 a 99**, mientras que con Repeatable Read se mantuvo en **99 → 99**. Por lo tanto, la afirmación fue correcta.

Respecto de la **lectura fantasma**, la IA indicó que con **Read Committed** puede aparecer una fila nueva entre dos lecturas. Esto también fue comprobado en la ejecución, donde el resultado de `COUNT` pasó de **2 a 3**. En consecuencia, la afirmación fue correcta.

La afirmación de que **Repeatable Read evita las lecturas fantasma** no fue comprobada experimentalmente, por lo que se considera **sin verificar** dentro de este trabajo.

Finalmente, en relación con la **espera por bloqueo**, la IA explicó que `FOR UPDATE` bloquea la fila y que una segunda sesión debe esperar hasta que la primera realice `COMMIT`. La ejecución permitió comprobarlo: se registró una espera de aproximadamente **31.170,470 ms** cuando existía el bloqueo, frente a **0,316 ms** sin bloqueo. Por lo tanto, la afirmación fue correcta.

---

## Observación
El error que la IA cometió en el escenario 3, fue util porque obligó a buscar una forma de dejar evidencia objetiva de la espera en lugar de darla por ocurrida. El informe quedo mejor documentado por esa discrepancia.

