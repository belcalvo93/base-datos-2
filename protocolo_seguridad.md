# Protocolo de seguridad — Base de Datos II

Motor: PostgreSQL 17.11
Sistema operativo: Windows 11
Terminal: Git Bash (psql, createdb, pg_dump)
Editor: Visual Studio Code
Cliente gráfico: DBeaver (instalado, no utilizado en este TP)
Usuario de base de datos: postgres

Este protocolo se aplica a **todo** script que escriba en la base, propio o
generado por IA, sin excepción.

## Bases del proyecto

| Base | Rol |
|---|---|
| `bd2_proyecto` | Plantilla. Contiene el esquema y la carga inicial del TP1. No se modifica. |
| `bd2_trabajo` | Copia de desarrollo. Es la única sobre la que se ejecutan scripts. |

## Paso 1 — Copia

Nunca se ejecuta un script sobre `bd2_proyecto`. Se trabaja sobre una copia
creada a partir de ella:

```bash
createdb -U postgres -T bd2_proyecto bd2_trabajo
```

Si la copia quedó inservible, se descarta y se rehace:

```bash
dropdb -U postgres bd2_trabajo
createdb -U postgres -T bd2_proyecto bd2_trabajo
```

Requiere que no haya conexiones abiertas contra la base plantilla: antes de
copiar hay que cerrar la conexión de DBeaver.

## Paso 2 — Transacción

Todo script que escribe se ejecuta primero dentro de una transacción que
termina en ROLLBACK, para inspeccionar el efecto real antes de confirmar nada:

```sql
BEGIN;
-- script a evaluar
-- verificar: filas afectadas, mensajes, resultado de los SELECT de control
ROLLBACK;
```

Recién después de leer la salida y confirmar que coincide con lo esperado se
repite la ejecución terminando en COMMIT.

Esto incluye `EXPLAIN ANALYZE` sobre INSERT, UPDATE o DELETE: ese comando
ejecuta la sentencia realmente, no solo la planifica.

## Paso 3 — Respaldo

Antes de cualquier cambio estructural (ALTER, DROP, creación de triggers o
constraints), se respalda la copia de trabajo:

```bash
pg_dump -U postgres -F c -f "respaldos/bd2_trabajo_20260826.dump" bd2_trabajo
```

Los respaldos viven en `respaldos/`, excluida del control de versiones por
`.gitignore` (son archivos binarios y no corresponde versionarlos).

Restauración:

```bash
pg_restore -U postgres -d bd2_trabajo --clean "respaldos/bd2_trabajo_20260826.dump"
```
Verificación realizada: el 26/08/2026 se ejecutó el pg_dump sobre bd2_trabajo y se comprobó que el archivo se generó correctamente en respaldos/ (14 KB).

## Verificación previa a cada ejecución

Antes de ejecutar cualquier script generado por IA:

1. Confirmar contra qué base está apuntando la sesión (`SELECT current_database();`).
2. Leer el script completo, línea por línea. Si una línea no se entiende, no se ejecuta hasta entenderla. Es la condición para poder defender oralmente cualquier línea
3. Verificar que todo UPDATE y DELETE tenga WHERE, y que ese WHERE sea el correcto. Un UPDATE funcion SET activa = FALSE; sin WHERE da de baja todas las filas de la tabla, no solo las que la consigna pedía.
4. No confiar en el reporte del propio agente sobre lo que hizo. Lo que el agente dice que hizo no es evidencia de que efectivamente lo hizo: se verifica en el motor.