-- maintenance.sql — Revision semanal de autovacuum/estadisticas y mantenimiento justificado (TP Unidad 6)
-- Uso: psql -U postgres -d foodstore -X -f mantenimiento/maintenance.sql
-- NO usa VACUUM FULL (bloquea la tabla con ACCESS EXCLUSIVE).

-- Protocolo: confirmar la base antes de ejecutar
SELECT current_database() <> 'foodstore' AS no_es_foodstore \gset
\if :no_es_foodstore
  \echo 'ABORTADO: este script solo se ejecuta sobre foodstore'
  \quit
\endif

\echo '=== 1. Configuracion de autovacuum ==='
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('autovacuum', 'autovacuum_naptime',
               'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold', 'autovacuum_analyze_scale_factor')
ORDER BY name;

\echo '=== 2. Estado ANTES: tuplas, cambios desde el ultimo analyze y fechas ==='
SELECT s.relname AS tabla,
       c.reltuples::bigint AS filas_estimadas,
       s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
       s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY c.reltuples DESC;

-- 3. Diagnostico por tabla y decision justificada (SPEC U6: la accion solo se ejecuta
-- si hay tuplas muertas o estadisticas desactualizadas). Las 6 tablas de Food Store.
-- Regla: SIN ESTADISTICAS si nunca se analizo (last_analyze y last_autoanalyze NULL);
-- DESACTUALIZADA si n_mod_since_analyze supera el umbral de autoanalyze
-- (threshold + scale_factor * filas); OK en otro caso. reltuples = -1 (nunca analizada)
-- se toma como 0 para no restar al umbral.
\echo '=== 3. Diagnostico: estado de estadisticas por tabla ==='
SELECT s.relname AS tabla,
       c.reltuples::bigint AS filas_estimadas,
       s.n_mod_since_analyze,
       coalesce(s.last_analyze, s.last_autoanalyze) AS ultimo_analyze,
       current_setting('autovacuum_analyze_threshold')::numeric
         + current_setting('autovacuum_analyze_scale_factor')::numeric * greatest(c.reltuples, 0)
         AS umbral_analyze,
       CASE
         WHEN s.last_analyze IS NULL AND s.last_autoanalyze IS NULL THEN 'SIN ESTADISTICAS'
         WHEN s.n_mod_since_analyze > current_setting('autovacuum_analyze_threshold')::numeric
              + current_setting('autovacuum_analyze_scale_factor')::numeric * greatest(c.reltuples, 0)
           THEN 'DESACTUALIZADA'
         ELSE 'OK'
       END AS estado
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario')
ORDER BY c.reltuples DESC;

-- La misma regla del diagnostico, agregada. Si se cambia una, cambiar la otra.
SELECT coalesce(bool_or(estado <> 'OK'), false) AS hay_pendientes,
       count(*) FILTER (WHERE estado <> 'OK') AS pendientes,
       count(*) AS total
FROM (
  SELECT CASE
           WHEN s.last_analyze IS NULL AND s.last_autoanalyze IS NULL THEN 'SIN ESTADISTICAS'
           WHEN s.n_mod_since_analyze > current_setting('autovacuum_analyze_threshold')::numeric
                + current_setting('autovacuum_analyze_scale_factor')::numeric * greatest(c.reltuples, 0)
             THEN 'DESACTUALIZADA'
           ELSE 'OK'
         END AS estado
  FROM pg_stat_user_tables s
  JOIN pg_class c ON c.oid = s.relid
  WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario')
) d \gset dec_

\if :dec_hay_pendientes
  \echo 'Decision: ANALYZE justificado (tablas pendientes:' :dec_pendientes 'de' :dec_total ')'
  \echo 'Motivo: alguna tabla esta SIN ESTADISTICAS o DESACTUALIZADA (ver seccion 3).'
  \echo 'ANALYZE solo toma muestras: no bloquea lecturas ni escrituras.'
  \echo '--- Accion: ANALYZE VERBOSE de las 6 tablas de Food Store ---'
  ANALYZE VERBOSE categoria, cliente, producto, pedido, detalle_pedido, usuario;
\else
  \echo 'Decision: sin accion, estadisticas al dia'
\endif

\echo '=== 4. Estado DESPUES ==='
SELECT pg_stat_clear_snapshot();
SELECT s.relname AS tabla,
       c.reltuples::bigint AS filas_estimadas,
       s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
       s.last_analyze
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY c.reltuples DESC;
