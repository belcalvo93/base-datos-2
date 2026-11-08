-- maintenance.sql — Revision semanal de autovacuum/estadisticas y mantenimiento justificado (TP Unidad 6)
-- Uso: psql -U postgres -d foodstore -X -f mantenimiento/maintenance.sql
--      (tambien sobre foodstore_restore_test, recien restaurada y sin estadisticas)
-- NO usa VACUUM FULL (bloquea la tabla con ACCESS EXCLUSIVE).
-- VACUUM y ANALYZE solo se ejecutan si el diagnostico lo justifica.

-- psql: cortar en el primer error
\set ON_ERROR_STOP on

-- Protocolo: confirmar la base antes de ejecutar
SELECT current_database() NOT IN ('foodstore', 'foodstore_restore_test') AS base_no_permitida \gset
\if :base_no_permitida
  \echo 'ABORTADO: este script solo se ejecuta sobre foodstore o foodstore_restore_test'
  \quit
\endif
\echo 'Base:' :DBNAME

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
  \echo '--- Accion: ANALYZE VERBOSE solo de las tablas pendientes ---'
  SELECT format('ANALYZE VERBOSE %I', s.relname)
  FROM pg_stat_user_tables s
  JOIN pg_class c ON c.oid = s.relid
  WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario')
    AND (
      (s.last_analyze IS NULL AND s.last_autoanalyze IS NULL)
      OR s.n_mod_since_analyze > current_setting('autovacuum_analyze_threshold')::numeric
           + current_setting('autovacuum_analyze_scale_factor')::numeric * greatest(c.reltuples, 0)
    )
  ORDER BY s.relname \gexec
\else
  \echo 'Decision: sin accion, estadisticas al dia'
\endif

-- 3b. Diagnostico de VACUUM: tuplas muertas contra el umbral de autovacuum
-- (threshold + scale_factor * filas). Por debajo del umbral, autovacuum alcanza y no hace
-- falta un VACUUM manual. VACUUM FULL nunca: reescribe la tabla y la bloquea por completo.
\echo '=== 3b. Diagnostico: tuplas muertas vs umbral de autovacuum ==='
SELECT s.relname AS tabla,
       s.n_live_tup, s.n_dead_tup,
       current_setting('autovacuum_vacuum_threshold')::numeric
         + current_setting('autovacuum_vacuum_scale_factor')::numeric * greatest(c.reltuples, 0)
         AS umbral_vacuum,
       CASE WHEN s.n_dead_tup > current_setting('autovacuum_vacuum_threshold')::numeric
                 + current_setting('autovacuum_vacuum_scale_factor')::numeric * greatest(c.reltuples, 0)
            THEN 'VACUUM NECESARIO' ELSE 'OK' END AS estado
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario')
ORDER BY s.n_dead_tup DESC;

SELECT count(*) FILTER (WHERE s.n_dead_tup > current_setting('autovacuum_vacuum_threshold')::numeric
         + current_setting('autovacuum_vacuum_scale_factor')::numeric * greatest(c.reltuples, 0)) AS con_vacuum
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario') \gset vac_

SELECT :vac_con_vacuum > 0 AS hay_vacuum \gset vac_
\if :vac_hay_vacuum
  \echo 'Decision VACUUM: se ejecuta VACUUM (no FULL) en' :vac_con_vacuum 'tabla(s) sobre el umbral'
  SELECT format('VACUUM (VERBOSE) %I', s.relname)
  FROM pg_stat_user_tables s JOIN pg_class c ON c.oid = s.relid
  WHERE s.relname IN ('categoria', 'cliente', 'producto', 'pedido', 'detalle_pedido', 'usuario')
    AND s.n_dead_tup > current_setting('autovacuum_vacuum_threshold')::numeric
        + current_setting('autovacuum_vacuum_scale_factor')::numeric * greatest(c.reltuples, 0) \gexec
\else
  \echo 'Decision VACUUM: no se ejecuta. Ninguna tabla supera el umbral de tuplas muertas; autovacuum alcanza.'
\endif
\echo 'VACUUM FULL: no se usa como mantenimiento periodico (bloquea la tabla con ACCESS EXCLUSIVE).'

\echo '=== 4. Estado DESPUES ==='
SELECT pg_stat_clear_snapshot();
SELECT s.relname AS tabla,
       c.reltuples::bigint AS filas_estimadas,
       s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
       s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY c.reltuples DESC;
