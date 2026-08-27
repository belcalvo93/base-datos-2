# Declaración de Uso de IA (DUIA) — Parte 3
---
**Ejercicio:** 6.3 Ejercicio de lectura crítica

**Fecha:** 26/08/2026

## Herramienta

Claude (Anthropic), utilizado como apoyo para la comprensión y análisis de conceptos de SQL.
Uso realizado
La herramienta se utilizó para comprender el comportamiento de NOT IN frente a valores NULL, la lógica de tres valores de SQL y la diferencia conceptual entre NOT IN y NOT EXISTS.
También se utilizó como instancia de contraste: primero planteé mis propias interpretaciones sobre los scripts y luego comparé esas interpretaciones con las explicaciones proporcionadas por la herramienta.

---

## Aporte  de la IA
•	Explicaciones sobre el comportamiento de NULL en comparaciones SQL. 
•	Explicación de por qué NOT IN puede producir un resultado desconocido cuando la subconsulta contiene NULL. 
•	Explicación de la alternativa NOT EXISTS. 
•	Orientación sobre la sintaxis de las consultas corregidas. 

---

## Realizado por mí

•	Identifiqué que el Script 1 no posee WHERE y, por lo tanto, afecta todas las filas. 
•	Identifiqué el problema del NULL en el Script 2. 
•	Propuse inicialmente evitar el NULL y
•	Elegí NOT EXISTS como alternativa. 
•	Comparé el DELETE del Script 2 con el diseño de mi propio proyecto y detecté que contradice el mecanismo de baja lógica utilizado en éste. 
•	Las conclusiones sobre qué comportamiento era correcto para el proyecto fueron tomadas a partir de mi análisis del modelo. 

---

## Realizado por mí

El análisis de los scripts genéricos se realizó mediante lectura del código, ya que ese esquema no se encontraba instalado en mi entorno. La observación sobre ON DELETE RESTRICT y la baja lógica sí fue contrastada con el esquema de mi proyecto.
