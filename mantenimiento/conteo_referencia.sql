-- conteo_referencia.sql — Huella de la base para validar una restauracion (TP Unidad 6)
-- La usan backup_foodstore.sh (sobre foodstore, antes del respaldo -> archivo .conteo)
-- y restore_test.sh (sobre foodstore_restore_test, despues de restaurar).
-- Si las dos salidas son iguales, la restauracion recupero las mismas filas,
-- los mismos importes y la misma estructura. Solo lectura.
-- Salida: una linea "clave valor" por fila, siempre en el mismo orden.
SELECT clave, valor
FROM (
          SELECT 1 AS orden, 'categoria'        AS clave, count(*)::text AS valor FROM categoria
UNION ALL SELECT 2, 'cliente',         count(*)::text FROM cliente
UNION ALL SELECT 3, 'producto',        count(*)::text FROM producto
UNION ALL SELECT 4, 'pedido',          count(*)::text FROM pedido
UNION ALL SELECT 5, 'detalle_pedido',  count(*)::text FROM detalle_pedido
UNION ALL SELECT 6, 'usuario',         count(*)::text FROM usuario
-- Suma de todos los subtotales (cantidad * precio_unitario): el subtotal no se guarda
-- en el esquema, se calcula. Si coincide, coinciden los importes, no solo las filas.
UNION ALL SELECT 7, 'total_facturado', coalesce(sum(cantidad * precio_unitario), 0)::text FROM detalle_pedido
-- Estructura del esquema public: tablas, vistas, restricciones e indices
UNION ALL SELECT 8, 'tablas',         count(*)::text FROM pg_tables   WHERE schemaname = 'public'
UNION ALL SELECT 9, 'vistas',         ((SELECT count(*) FROM pg_views WHERE schemaname = 'public')
                                    + (SELECT count(*) FROM pg_matviews WHERE schemaname = 'public'))::text
UNION ALL SELECT 10, 'restricciones', count(*)::text FROM pg_constraint c
                                     JOIN pg_namespace n ON n.oid = c.connamespace
                                     WHERE n.nspname = 'public'
UNION ALL SELECT 11, 'indices',       count(*)::text FROM pg_indexes  WHERE schemaname = 'public'
) t
ORDER BY orden;
