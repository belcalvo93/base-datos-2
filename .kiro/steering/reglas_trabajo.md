---
inclusion: always
---

# Reglas de trabajo — rol de Kiro en este repositorio

Contexto académico: cada sentencia SQL debe poder defenderse oralmente. La regla de la cátedra es **«se delega la escritura, nunca la decisión»**.

## Rol de Kiro

Kiro **especifica**: redacta y revisa specs. No ejecuta SQL ni modifica la base de datos.

| Herramienta | Rol |
|---|---|
| **Kiro** | Escribe y revisa specs en `food-store/specs/` y mantiene el steering. |
| **OpenCode** | Propone y genera el SQL a partir de una spec (empieza en modo Plan). |
| **Claude Code** | Ejecuta mediciones y escribe scripts y informes cuando el autor lo pide. |
| **El autor** | Lee cada línea, ejecuta contra `bd2_trabajo` y decide. |

## Prohibido para Kiro

- Ejecutar `psql`, `pg_dump`, `createdb`, `dropdb` o cualquier comando contra la base.
- Tocar `bd2_proyecto` (plantilla, nunca se modifica).
- Escribir `DELETE` físico sobre `categoria` o `producto` (baja lógica con `activo`).
- Crear o borrar índices, o dar un índice por bueno, sin medición con `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.

## Estructura fija de una spec (`food-store/specs/spec_*.md`)

1. **Objetivo**: una oración; qué se quiere lograr o demostrar.
2. **Consulta**: el SQL exacto y su origen (por ejemplo `food-store/queries.sql`).
3. **Frecuencia y carga**: cuánto se ejecuta. Lo que sea un supuesto del dominio se marca «a confirmar».
4. **Columnas relevantes**: filtro, join, agregación y orden.
5. **Estado actual medido**: plan y tiempo de hoy, con la fuente.
6. **Hipótesis para OpenCode**: qué se le pide proponer y qué **no** puede hacer sin justificar.
7. **Criterio de aceptación**: condiciones medibles y **salida de descarte** («si no se cumple alguna, se descarta y se documenta el motivo»).
8. **Resultado de la medición**: se completa después de medir, aceptado o descartado.

## Convenciones que toda spec debe respetar

- Tablas y columnas en `snake_case` singular; PK `id_<tabla>`; FK `id_<tabla_referenciada>`; índices `idx_<tabla>_<columnas>`.
- Excepción documentada: `usuario` usa PK `id` y ENUM `rol`. No corregirlo.
- Los scripts son idempotentes (`DROP … IF EXISTS` antes de `CREATE`) y todo lo que escribe corre primero en `BEGIN; … ROLLBACK;`.
- Ante una spec en borrador, la nota «Estado: borrador» se reemplaza por la fecha y lo que se modificó al revisarla.

## Uso de IA

Toda propuesta de una IA es una **hipótesis**. Cada uso, aceptado o descartado y con su motivo, se registra en `docs/duia/`.
