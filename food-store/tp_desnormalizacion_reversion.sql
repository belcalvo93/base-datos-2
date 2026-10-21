-- ============================================================
-- TP U4 — Parte 2: reversión de la desnormalización
-- Deshace todo lo que crea tp_desnormalizacion_top_categorias.sql.
-- Las tablas fuente (pedido, detalle_pedido, producto, categoria) no
-- se tocan: son la fuente de verdad y el resumen se puede reconstruir.
-- Base de ejecución: bd2_tp4u4.
-- ============================================================
-- Primera corrida con ROLLBACK (como está). Para revertir de verdad,
-- cambiar el ROLLBACK de la última línea por COMMIT.
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/tp_desnormalizacion_reversion.sql
-- ============================================================

\set ON_ERROR_STOP on

SELECT current_database();

BEGIN;

SELECT (SELECT count(*) FROM pedido)         AS pedidos_antes,
       (SELECT count(*) FROM detalle_pedido) AS detalles_antes
\gset

DROP TRIGGER IF EXISTS trg_resumen_ventas_detalle ON detalle_pedido;
DROP TRIGGER IF EXISTS trg_resumen_ventas_pedido_borrado ON pedido;
DROP FUNCTION IF EXISTS fn_trg_resumen_ventas_detalle();
DROP FUNCTION IF EXISTS fn_trg_resumen_ventas_pedido_borrado();
DROP FUNCTION IF EXISTS fn_resumen_ventas_aplicar_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
DROP TABLE IF EXISTS resumen_ventas_categoria_dia;

-- Tiene que dar: resumen_existe = f, y los dos conteos en t
SELECT to_regclass('resumen_ventas_categoria_dia') IS NOT NULL AS resumen_existe,
       (SELECT count(*) FROM pedido)         = :pedidos_antes  AS pedidos_iguales,
       (SELECT count(*) FROM detalle_pedido) = :detalles_antes AS detalles_iguales;

-- Primera corrida: ROLLBACK. Para revertir de verdad, cambiar por COMMIT.
ROLLBACK;
