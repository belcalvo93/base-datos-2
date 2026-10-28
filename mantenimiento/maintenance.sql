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

-- 3. Accion de mantenimiento
-- Justificacion: el estado ANTES muestra n_live_tup = 0 y sin fechas de analyze/autovacuum
-- en tablas que tienen datos (foodstore se creo con createdb -T y los contadores de
-- actividad no se copian). Sin esos contadores autovacuum no tiene referencia.
-- ANALYZE es seguro: solo toma muestras, no bloquea lecturas ni escrituras.
\echo '=== 3. Accion: ANALYZE de las tablas de Food Store ==='
ANALYZE VERBOSE categoria, cliente, producto, pedido, detalle_pedido;

\echo '=== 4. Estado DESPUES ==='
SELECT pg_stat_clear_snapshot();
SELECT s.relname AS tabla,
       c.reltuples::bigint AS filas_estimadas,
       s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
       s.last_analyze
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY c.reltuples DESC;
