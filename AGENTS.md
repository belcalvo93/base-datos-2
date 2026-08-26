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

Recreate the working copy when needed:
```bash
dropdb -U postgres bd2_trabajo
createdb -U postgres -T bd2_proyecto bd2_trabajo
```

## Mandatory safety protocol

**Every script** that writes to the DB must follow this order:

1. **Backup** before structural changes: `pg_dump -U postgres -F c -f "respaldos/bd2_trabajo_YYYYMMDD.dump" bd2_trabajo`
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

## File layout

```
sql/schema.sql     — table definitions (idempotent)
sql/datos.sql      — seed data (uses subqueries for FKs, no hardcoded IDs)
sql/restricciones.sql — triggers for integrity rules (Regla 1, Regla 2)
spec_restricciones.md — integrity constraint specs (read before writing triggers)
protocolo_seguridad.md — safety protocol (MANDATORY reading)
.kiro/steering/database.md — full schema reference with design rationale
```

## Gotchas

- `EXPLAIN ANALYZE` on INSERT/UPDATE/DELETE **executes the statement**, not just plans it — always wrap in a transaction
- `UPDATE`/`DELETE` without `WHERE` affects all rows — verify WHERE clauses before running
- DBeaver connection must be closed before `createdb -T` (template locking)
- `respuesta/` and `*.dump`/`*.backup` are gitignored — don't commit them
- `concurrencia/` and `duia/` directories are empty placeholders for future work
