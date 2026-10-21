-- ============================================================
-- TP U4 — Parte 2 (e): auditoría del resumen sobre la base ya migrada
-- Spec: food-store/specs/spec_top_categorias_auditoria.md (spec 6)
-- Base de ejecución: bd2_tp4u4, con tp_desnormalizacion_top_categorias.sql
-- ya confirmado. Solo lectura.
-- ============================================================
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/auditoria_top_categorias.sql
-- Recalcula el resumen desde la fuente, para TODOS los días, y lo compara
-- con lo guardado en los dos sentidos. Tiene que dar 0 filas.
-- Si da filas, no se corrige el valor a mano: se revisa el mecanismo.
-- Las pruebas de que detecta diferencias están en el script principal.
-- ============================================================

\set ON_ERROR_STOP on

SELECT current_database();

-- Contexto: qué se está auditando
SELECT count(*)              AS filas_resumen,
       count(DISTINCT fecha) AS dias,
       max(fecha)            AS ultimo_dia
  FROM resumen_ventas_categoria_dia;

WITH fuente AS (
    SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha,
           c.id_categoria,
           SUM(dp.cantidad * dp.precio_unitario) AS total_vendido,
           COUNT(*)::int AS cantidad_lineas
      FROM categoria c
     INNER JOIN producto pr       ON pr.id_categoria = c.id_categoria
     INNER JOIN detalle_pedido dp ON dp.id_producto  = pr.id_producto
     INNER JOIN pedido ped        ON ped.id_pedido   = dp.id_pedido
     GROUP BY 1, 2
),
guardado AS (
    SELECT fecha, id_categoria, total_vendido, cantidad_lineas
      FROM resumen_ventas_categoria_dia
)
(SELECT 'solo en el resumen' AS lado, * FROM (SELECT * FROM guardado EXCEPT SELECT * FROM fuente) a)
UNION ALL
(SELECT 'solo en la fuente' AS lado, * FROM (SELECT * FROM fuente EXCEPT SELECT * FROM guardado) b)
ORDER BY fecha, id_categoria, lado;
