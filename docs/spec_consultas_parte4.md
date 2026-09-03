# Specs de consultas — TP3 Parte 4

**Ejercicio:** TP3 (Unidad 2), Parte 4 — Consultas resumen y subconsultas
bajo especificación precisa.
**Fecha:** 02/09/2026

Estas specs se redactaron antes de pedirle el SQL a la IA, y son el único
insumo que se le dio. La consigna pide fijar explícitamente: tablas
involucradas, filtro de borrado lógico, columnas de salida, orden y
criterio de corte.

---

## Spec A — Consulta de resumen (agregación)

Sobre el esquema Food Store, generar una consulta que devuelva la
facturación total por categoría.

- **Tablas:** `categoria`, `producto`, `detalle_pedido`.
- **Filtro de borrado lógico:** solo categorías con `activo = TRUE` y
  solo productos con `activo = TRUE`.
- **Columnas de salida:** nombre de la categoría, cantidad de líneas de
  venta, y monto total facturado. El monto se calcula como la suma de
  `cantidad * precio_unitario` de `detalle_pedido`; la tabla no almacena
  `subtotal` (decisión del TP1, normalización a 3FN).
- **Inclusión:** incluir las categorías vigentes que no tengan ninguna
  venta, con cantidad 0 y monto 0.
- **Orden:** de mayor a menor monto facturado.
- **Criterio de corte:** ninguno, se devuelven todas las categorías
  vigentes.
- **Restricción:** no usar `SELECT *`.

**Por qué la cláusula de inclusión:** sin ella la spec sería ambigua y
cada implementación podría elegir `INNER JOIN` o `LEFT JOIN`, devolviendo
conjuntos distintos de filas. Fijarla obliga al `LEFT JOIN` y hace que
las dos versiones sean comparables.

---

## Spec B — Consulta con subconsulta

Sobre el esquema Food Store, generar una consulta que devuelva los
productos que nunca se vendieron.

- **Tablas:** `producto`, `detalle_pedido`.
- **Filtro de borrado lógico:** solo productos con `activo = TRUE`.
- **Definición de "nunca vendido":** que no exista ninguna fila en
  `detalle_pedido` que referencie ese `id_producto`.
- **Columnas de salida:** `id_producto`, nombre, precio y stock.
- **Orden:** por nombre de producto, ascendente.
- **Criterio de corte:** ninguno.
- **Restricción:** no usar `SELECT *`. La consulta debe resolverse con
  una subconsulta, no con un `LEFT JOIN`.

**Por qué se fija la estructura:** la consigna pide una segunda versión
con estructura distinta para verificar equivalencia. Al exigir subconsulta
en la versión especificada, la alternativa (`LEFT JOIN ... IS NULL`) es
realmente otra estructura y no la misma consulta reescrita.