-- health_check.sql — Chequeo de salud diario de Food Store (TP Unidad 6)
-- Uso: psql -U postgres -d foodstore -X -f mantenimiento/health_check.sql
-- Solo lectura: no modifica datos.

\echo '=== 0. Base y momento del chequeo ==='
SELECT current_database() AS base, now() AS fecha_chequeo, current_setting('server_version') AS version;

\echo '=== 1. Tamano de la base y de las tablas principales ==='
SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano_base;

SELECT relname AS tabla,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamano_total
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

\echo '=== 2. Actividad de conexiones ==='
SELECT numbackends AS conexiones, xact_commit, xact_rollback,
       round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = current_database();

SELECT coalesce(state, 'sin estado') AS estado, count(*) AS cantidad
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

\echo '=== 3. Estado de las tablas (tuplas vivas/muertas, autovacuum) ==='
SELECT relname AS tabla, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS pct_muertas,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

\echo '=== 4. Consultas activas (excluye esta sesion) ==='
SELECT pid, usename, state, now() - query_start AS duracion, left(query, 80) AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
  AND pid <> pg_backend_pid();
