-- ============================================================
-- Variante B del bloque 3 (pedido → cliente)
-- A/B para decidir con mediciones contra la opción A de
-- db/carga_masiva.sql (bloque 3).
-- ============================================================
-- ESTADO: VARIANTE DESCARTADA (medida el 2026-09-01)
--   Medición A vs B a igual volumen (10.000 pedidos / 4.000
--   clientes, bloque 2 cargado): B = 6.778 ms vs A = 9.676 ms →
--   1,4x más rápido, NO la mejora estructural esperada. El EXPLAIN
--   lo explicó: el Hash Join quedó ADENTRO del Nested Loop y el CTE
--   se escanea una vez por pedido (CTE Scan on dominio_clientes:
--   rows=4005 loops=10000) → el barrido por fila no se eliminó,
--   solo se abarató. Se conserva este archivo como evidencia
--   documentada de un diseño probado con su medición, NO como
--   código a ejecutar. El bloque 3 activo es la opción A de
--   db/carga_masiva.sql.
-- ============================================================
-- APARTAMIENTO EXPLÍCITO DEL ESTILO DE LA CÁTEDRA:
--   El Genera_registros.sql original resuelve las FK con un subquery
--   (SELECT ... ORDER BY random() LIMIT 1) evaluado por fila (opción A,
--   vigente en carga_masiva.sql). Esta variante B lo reemplaza por un
--   ROW_NUMBER sobre cliente + Hash Join. Justificación: el costo deja
--   de ser "pedidos × sort de clientes" (un ORDER BY random() sobre
--   toda la tabla por fila) y pasa a ser "1 sort de clientes + hash
--   join". Es la opción pensada para cuando el bloque 3 crezca (20.000
--   clientes, 200.000 pedidos) sin pagar el sort por fila.
-- ============================================================
-- NOTA SOBRE MATERIALIZED — por qué acá es correcto, y es el caso
-- OPUESTO a los tres que rompieron la distribución:
--   Los tres fallos previos cachearon UN VALOR ALEATORIO y lo
--   repitieron en todas las filas:
--     - bloque 1 (producto):         InitPlan loops=1 → 1 sola categoría.
--     - bloque 3 (pedido, opción A): InitPlan loops=1 → 1 solo cliente.
--     - bloque 4 (detalle_pedido):   Materialize loops=1 bajo el
--       subquery de producto → los mismos 4 productos en todos los
--       pedidos.
--   Acá MATERIALIZED materializa el DOMINIO (la lista numerada de
--   clientes), NO un sorteo. El CTE no contiene funciones volátiles
--   (no hay random() adentro) y su contenido es constante durante la
--   carga: el sort de ROW_NUMBER corre una vez y cualquier re-lectura
--   es un rewind del tuplestore sin recomputar nada. El aleatorio vive
--   en jet, del lado de la serie, correlacionado con s.i para no
--   cachearse. No es la misma situación: se fuerza la materialización
--   de lo constante y se impide el cacheo de lo aleatorio.
-- ============================================================
-- MECÁNICA:
--   1) dominio_clientes: numera los clientes una sola vez.
--   2) jet: para cada pedido la variable objetivo es
--      rn = 1 + floor(random() * cant_clientes). La expresión
--      "+ s.i * 0" no altera el valor, pero correlaciona jet con la
--      fila externa e impide que el motor lo materialice/cachee
--      (sorteo nuevo por pedido).
--   3) (SELECT count(*) FROM cliente) SÍ es un InitPlan de una sola
--      evaluación, y acá es deseable: el tamaño del dominio es una
--      constante real del problema.
--   4) La condición del join c.rn = jet.rn tiene cada término
--      dependiendo de una sola relación → hashable → el plan usa
--      Hash Join (en EXPLAIN: "Hash Cond: (c.rn = jet.rn)"), no
--      Nested Loop con Materialize.
-- ============================================================
-- USO (protocolo_seguridad.md — transacción con ROLLBACK primero):
--   BEGIN;
--   \i db/carga_masiva_bloque3_B.sql
--   ROLLBACK;   -- o COMMIT tras inspeccionar
--   Comparar contra la opción A a igual volumen y verificar:
--   SELECT count(DISTINCT id_cliente) FROM
--     (SELECT id_cliente FROM pedido ORDER BY id_pedido DESC LIMIT 10000) t;
-- ============================================================
-- VOLUMEN CONGELADO: el generate_series(1, 10000) de abajo se deja
-- en 10.000 porque es el volumen al que se hizo la medición A vs B.
-- No debe moverse: la variante está descartada y el archivo es
-- evidencia, no código ejecutable.
-- ============================================================

WITH
dominio_clientes AS MATERIALIZED (
    SELECT id_cliente,
           ROW_NUMBER() OVER (ORDER BY id_cliente) AS rn
    FROM cliente
)
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT
    now() - (random() * INTERVAL '2 years'),
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA']::forma_pago_enum[])[floor(random() * 3 + 1)],
    c.id_cliente
FROM generate_series(1, 10000) AS s(i)
CROSS JOIN LATERAL (
    SELECT (1 + floor(random() * (SELECT COUNT(*) FROM cliente)))::INT + s.i * 0 AS rn
) AS jet
JOIN dominio_clientes c ON c.rn = jet.rn;