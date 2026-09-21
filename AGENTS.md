# AGENTS.md — Base de Datos 2

## Project

PostgreSQL course project (TP integrador). Schema + seed data for a bakery/e-commerce domain. Academic context — every SQL statement must be defensible orally.

## Stack

- PostgreSQL 17.11 on Windows 11
- Terminal: Git Bash (`psql`, `createdb`, `pg_dump`)
- No app framework — raw SQL scripts only

## Databases

| Base | Role |
|------|------|
| `bd2_proyecto` | Template. **Never modify.** |
| `bd2_trabajo` | Working copy. All scripts run here. |
| `bd2_tp3` | Populated DB from Unit 2 (~50k products / 20k clients / 200k orders / 499k details). TP5 measurements are done on a copy of it. |

Recreate the working copy when needed:
```bash
dropdb -U postgres bd2_trabajo
createdb -U postgres -T bd2_proyecto bd2_trabajo
```

## Mandatory safety protocol

**Every script** that writes to the DB must follow this order:

1. **Backup** before structural changes: `pg_dump -U postgres -F c -f "food-store/backups/bd2_trabajo_YYYYMMDD.dump" bd2_trabajo`
2. **Transaction with ROLLBACK** first — inspect output, then repeat with COMMIT
3. **Check `SELECT current_database();`** before any execution
4. **Read every line** of generated scripts before running — if you can't explain it, don't run it
5. **Verify in the motor** — don't trust agent reports about what was done

Full protocol: `protocolo_seguridad.md`

## SQL conventions

- Tables/columns: `snake_case` singular (`detalle_pedido`, not `detallePedidos`)
- PKs: `id_<tabla>` (BIGINT GENERATED ALWAYS AS IDENTITY)
- FKs: `id_<tabla_referenciada>`
- Indexes: `idx_<tabla>_<columna(s)>`
- ENUM values: uppercase (`'EFECTIVO'`, not `'efectivo'`)
- Logical delete: `activo BOOLEAN NOT NULL DEFAULT TRUE` — never physical DELETE on `categoria`/`producto`
- `ON DELETE RESTRICT` on most FKs; `CASCADE` only on `detalle_pedido.id_pedido`
- `precio_unitario` in `detalle_pedido` is a frozen historical price (R4), independent of `producto.precio`
- Scripts are idempotent: `DROP … IF EXISTS … CASCADE` before `CREATE`
- **Exception — `usuario` table (TP5 Part B):** PK is `id` (not `id_usuario`), ENUM type is `rol` (not `rol_enum`), soft delete is `eliminado` (FALSE = active). This is the professor's exact DDL; do NOT "fix" it to match the conventions above
- An index is accepted only if `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` before/after justifies it. AI proposals are hypotheses, not decisions

## File layout

```
food-store/schema.sql      — table definitions (idempotent)
food-store/data.sql        — seed data (uses subqueries for FKs, no hardcoded IDs)
food-store/restricciones.sql — triggers for integrity rules (Regla 1, Regla 2)
food-store/queries.sql     — consolidated queries (TP2/TP4), workload source for TP5
food-store/indices.sql     — accepted indexes only (rejected ones stay commented with the reason)
food-store/views.sql       — views (TP5 Parts B/C); CREATE OR REPLACE, idempotent
food-store/medicion_planes.sql / medicion_escritura.sql — measurement scripts (run inside BEGIN…ROLLBACK)
food-store/informe_mediciones.md — TP5 measurement report
food-store/specs/          — one spec per task (spec_indice_*.md, spec_usuario.md, spec_vistas.md)
docs/spec_restricciones.md — integrity constraint specs (read before writing triggers)
docs/duia/                 — AI-use declarations (DUIA), one per unit
protocolo_seguridad.md — safety protocol (MANDATORY reading)
.kiro/steering/database.md — full schema reference with design rationale
```

## Roles of the AI tools

- **Kiro** writes and reviews specs. It never runs SQL.
- **OpenCode** (you, if you are reading this) proposes and generates SQL from a spec. **Start in Plan mode**: describe the plan, wait for approval, then write.
- The author reads every line and runs it against `bd2_trabajo`. Do not run write statements yourself.
- Give each spec a clean session; do not carry over previous solutions.
- Every AI use (accepted or discarded, with the reason) is logged in `docs/duia/`.

## Gotchas

- `EXPLAIN ANALYZE` on INSERT/UPDATE/DELETE **executes the statement**, not just plans it — always wrap in a transaction
- `UPDATE`/`DELETE` without `WHERE` affects all rows — verify WHERE clauses before running
- DBeaver connection must be closed before `createdb -T` (template locking)
- `psql`/`pg_dump` live in `C:\Program Files\PostgreSQL\17\bin`; if the command is not found in Git Bash, that folder is missing from `PATH`
- After a bulk load or restore, run `VACUUM ANALYZE` before measuring, otherwise plans and Index Only Scans are not representative
- `food-store/backups/`, `respuesta/`, and `*.dump`/`*.backup` are gitignored — don't commit them
- SQL scripts live under `food-store/`; `concurrencia/` is an empty placeholder for future work
