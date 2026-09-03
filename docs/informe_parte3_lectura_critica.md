# Informe — Parte 3: Lectura Crítica de la Explicación del Plan C2

## 1. Objetivo y método

Se tomó el plan de EXPLAIN ANALYZE de la consulta C2 de la Parte 2, con el índice `idx_pedido_id_cliente` ya aplicado. Se le pidió a OpenCode que lo explicara nodo por nodo, sin darle más contexto que el texto crudo del plan. Esa explicación se contrastó frase por frase contra el plan real.

La explicación completa, sin editar, está en `docs/explicacion_ia_plan_c2.md`. Se conserva intacta a propósito porque es el material sobre el que se hace este análisis.

## 2. Afirmaciones de la IA y veredicto

| Afirmación de la IA | ¿Correcta? | Corrección o evidencia del plan real |
|---|---|---|
| "Index Scan on cliente_pkey (segundo hijo del Nested Loop)" y "para cada fila del cliente ejecuta el Bitmap Heap Scan" | No | La descripción del comportamiento es correcta, pero el orden está invertido. En el plan el Index Scan sobre `cliente_pkey` aparece primero bajo el Nested Loop, o sea que es el hijo externo, y el Bitmap Heap Scan es el interno. Llamarlo "segundo hijo" contradice el texto del plan. |
| "El Recheck Cond indica que PostgreSQL verifica que cada fila leída realmente cumpla la condición, por si hubo cambios concurrentes entre la creación del bitmap y la lectura" | No | El Recheck Cond existe porque el bitmap puede volverse "lossy": cuando no entra en work_mem, PostgreSQL guarda páginas enteras en lugar de punteros a filas individuales, y hay que re-verificar cada fila de esas páginas. No tiene relación con la concurrencia — de eso se ocupa MVCC. Evidencia del plan real: "Heap Blocks: exact=23" dice exact, no lossy, así que en esta ejecución el recheck no llegó a filtrar ninguna fila. |
| "Rendimiento: 0.002 ms para ordenar 24 filas" | No | Ese número no está en el plan. Sale de restar 0.116 - 0.114, pero esos son los tiempos hasta la primera fila y hasta la última del nodo Sort, no la duración del ordenamiento. El costo real del Sort es 0.116 menos el fin de su hijo (0.093), o sea unos 0.023 ms — un orden de magnitud más. |
| "Las estimaciones (rows=10) difieren de la realidad (rows=24) pero no afectan porque el plan elegido es el correcto de todas formas" | No | Que el plan sea correcto para este valor de filtro no permite concluir que la diferencia "no afecta". Una subestimación de 2,4x indica estadísticas o supuestos de distribución desactualizados, y con otro valor de filtro podría llevar al optimizador a elegir un plan distinto. |
| "El acceso a 23 bloques es eficiente porque es random I/O dirigido" | No | El plan no reporta I/O. Sin EXPLAIN (ANALYZE, BUFFERS) no se puede saber si los bloques vinieron de disco o del caché. Con 0.069 ms para 23 bloques, lo más probable es que estuvieran en memoria y no haya habido I/O de disco. |
| "Se ejecuta de abajo hacia arriba (los hijos primero, el padre al final)" | Sí | Coincide con el plan: el árbol de ejecución se lee de las hojas a la raíz. |
| "El Bitmap Index Scan no accede a la tabla, solo recopila los TIDs del índice" | Sí | Un Bitmap Index Scan solo produce el conjunto de TIDs; el acceso a las filas lo hace el Bitmap Heap Scan padre. |
| "Usa quicksort en memoria (26 kB, cabe en work_mem)" | Sí | Es lo que reporta el plan: "Sort Method: quicksort  Memory: 26kB". |
| "Agregar un índice compuesto (id_cliente, fecha DESC) para satisfacer el ORDER BY sin el Sort, pero con 24 filas el Sort es tan barato que no vale la pena" | Sí | Coincide con lo medido en la Parte 2: ese índice compuesto se creó, se midió y se descartó por no aportar mejora. La IA llegó a la misma conclusión sin tener los datos de esa medición. |

## 3. Conclusiones

Los errores no están en la mecánica de los nodos, que la IA describe bien, sino en las causas que le atribuye y en los números que deriva.

Dos de los cinco errores son invenciones de datos que el plan no contiene: el tiempo del Sort y el tipo de I/O no aparecen por ningún lado en el texto.

El error del Recheck Cond es el más relevante porque suena plausible y está expresado con seguridad. Es el tipo de afirmación que se acepta sin verificar, y es el único que confunde un concepto de fondo (MVCC vs. bitmaps lossy).

Tener el plan real al lado es lo que permite detectarlos; la explicación por sí sola es internamente coherente y no se contradice en ningún punto.
