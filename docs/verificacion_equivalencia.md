# Anonimización y verificación de equivalencia — TP Unidad 5 (Parte D)

**Responsable:** Bruno Fiouchetta  
**Base de prueba:** `bd2_tp5u5` (copia local de `bd2_tp4u4`)  
**Script de anonimización:** `sql/usuario_anon.sql`

---

## 1. Construcción de `usuario_anon` (Parte D, punto 1)

El script `sql/usuario_anon.sql` construye de forma idempotente la tabla `usuario_anon` a partir de `usuario` aplicando el patrón de anonimización determinista visto en la Clase 2:

- **`id`:** se conserva el `id` original como clave primaria (`BIGINT PRIMARY KEY`) para mantener trazabilidad determinista en las verificaciones sin exponer datos personales.
- **`nombre`, `apellido` y `mail`:** se reemplazan por valores sintéticos generados a partir del `id` (`'Usuario ' || id`, `'Apellido ' || id`, `'usuario' || id || '@ejemplo.test'`). A diferencia de usar una constante fija como `'Anónimo'`, este patrón preserva la cardinalidad y la restricción `UNIQUE` sobre `mail`.
- **`celular`:** se reemplaza por `NULL`.
- **`contrasena`:** se reemplaza por el literal `'hash_no_valido'`, que no corresponde a ningún hash válido de `crypt()` ni SHA-256 e impide que las filas de `usuario_anon` puedan utilizarse para autenticarse.
- **`rol`, `eliminado` y `created_at`:** se copian sin alteración porque son los atributos analíticos sobre los que operan las consultas de agregación.
- **Propiedad y mínimo privilegio:** la tabla queda con `OWNER TO admin_datos` (alineada con `sql/roles.sql`) y sin `GRANT` adicionales.

### Salida de control de `sql/usuario_anon.sql` en `bd2_tp5u5`

Primera corrida con `ROLLBACK` y corrida definitiva con `COMMIT`:

```text
 current_database 
------------------
 bd2_tp5u5
(1 row)

BEGIN
DROP TABLE
CREATE TABLE
ALTER TABLE
INSERT 0 3
 filas_usuario | filas_usuario_anon 
---------------+--------------------
             3 |                  3
(1 row)

 filas_con_datos_reales_o_hash_invalido 
----------------------------------------
                                      0
(1 row)

 mails_duplicados 
------------------
                0
(1 row)

COMMIT
```

---

## 2. Consultas de agregación generadas con OpenCode (Parte D, punto 2)

Se especificó a OpenCode en modo Plan una consulta sobre `usuario_anon` que cuenta la cantidad de usuarios activos (`eliminado = FALSE`) agrupados por `rol` y por mes calendario de alta (`created_at`) en la zona horaria explícita del proyecto (`America/Argentina/Mendoza`), y se le pidió la consulta equivalente sobre la tabla real `usuario`.

### Consulta 1 — Sobre la tabla anonimizada (`usuario_anon`)

```sql
SELECT
    rol,
    date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Mendoza')::date AS mes_alta,
    COUNT(*) AS cantidad
FROM usuario_anon
WHERE eliminado = FALSE
GROUP BY
    rol,
    date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY
    mes_alta,
    rol;
```

### Consulta 2 — Equivalente sobre la tabla real (`usuario`)

```sql
SELECT
    rol,
    date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Mendoza')::date AS mes_alta,
    COUNT(*) AS cantidad
FROM usuario
WHERE eliminado = FALSE
GROUP BY
    rol,
    date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY
    mes_alta,
    rol;
```

---

## 3. Ejecución y verificación de equivalencia (Parte D, punto 3)

Como la carga inicial de `data.sql` contiene únicamente 3 filas en `usuario` dadas de alta en el mismo mes (`2026-09`, con 2 activas y 1 con `eliminado = TRUE`), probar la agregación solo sobre esas 3 filas produciría un único mes de alta. Para que la demostración no sea trivial y sin contaminar la base ni recurrir a borrados físicos posteriores, dentro de una transacción controlada (`BEGIN; … ROLLBACK;`) se insertaron 300 usuarios sintéticos de prueba (dominio `@example.test`) distribuidos en 6 meses (`2026-05` a `2026-10`), alternando ambos roles (`USUARIO` y `ADMIN`) y bajas lógicas (`eliminado = TRUE`, 30 filas), se reconstruyó `usuario_anon` (303 filas totales, 272 activas) y se ejecutaron ambas consultas junto con la prueba de conjuntos `EXCEPT` en ambos sentidos.

### Comparación lado a lado (`bd2_tp5u5`, 272 usuarios activos en 6 meses)

| `mes_alta` | `rol` | `cantidad` en `usuario_anon` (Consulta 1) | `cantidad` en `usuario` (Consulta 2) | Coincide |
|---|---|---:|---:|:---:|
| `2026-05-01` | `USUARIO` | 34 | 34 | Sí |
| `2026-05-01` | `ADMIN` | 6 | 6 | Sí |
| `2026-06-01` | `USUARIO` | 43 | 43 | Sí |
| `2026-06-01` | `ADMIN` | 7 | 7 | Sí |
| `2026-07-01` | `USUARIO` | 34 | 34 | Sí |
| `2026-07-01` | `ADMIN` | 6 | 6 | Sí |
| `2026-08-01` | `USUARIO` | 43 | 43 | Sí |
| `2026-08-01` | `ADMIN` | 7 | 7 | Sí |
| `2026-09-01` | `USUARIO` | 36 | 36 | Sí |
| `2026-09-01` | `ADMIN` | 6 | 6 | Sí |
| `2026-10-01` | `USUARIO` | 43 | 43 | Sí |
| `2026-10-01` | `ADMIN` | 7 | 7 | Sí |
| **Total activos** | | **272** | **272** | **12/12 grupos idénticos** |

### Salida literal de `psql` (Consultas 1 y 2 + `EXCEPT` en ambos sentidos)

```text
 total_usuario | total_usuario_anon | activos_usuario | activos_usuario_anon 
---------------+--------------------+-----------------+----------------------
           303 |                303 |             272 |                  272
(1 row)

=== CONSULTA 1: sobre usuario_anon ===
   rol   |  mes_alta  | cantidad 
---------+------------+----------
 USUARIO | 2026-05-01 |       34
 ADMIN   | 2026-05-01 |        6
 USUARIO | 2026-06-01 |       43
 ADMIN   | 2026-06-01 |        7
 USUARIO | 2026-07-01 |       34
 ADMIN   | 2026-07-01 |        6
 USUARIO | 2026-08-01 |       43
 ADMIN   | 2026-08-01 |        7
 USUARIO | 2026-09-01 |       36
 ADMIN   | 2026-09-01 |        6
 USUARIO | 2026-10-01 |       43
 ADMIN   | 2026-10-01 |        7
(12 rows)

=== CONSULTA 2: sobre usuario (tabla real) ===
   rol   |  mes_alta  | cantidad 
---------+------------+----------
 USUARIO | 2026-05-01 |       34
 ADMIN   | 2026-05-01 |        6
 USUARIO | 2026-06-01 |       43
 ADMIN   | 2026-06-01 |        7
 USUARIO | 2026-07-01 |       34
 ADMIN   | 2026-07-01 |        6
 USUARIO | 2026-08-01 |       43
 ADMIN   | 2026-08-01 |        7
 USUARIO | 2026-09-01 |       36
 ADMIN   | 2026-09-01 |        6
 USUARIO | 2026-10-01 |       43
 ADMIN   | 2026-10-01 |        7
(12 rows)

=== EXCEPT 1: usuario_anon EXCEPT usuario (esperado: 0 filas) ===
 rol | mes_alta | cantidad 
-----+----------+----------
(0 rows)

=== EXCEPT 2: usuario EXCEPT usuario_anon (esperado: 0 filas) ===
 rol | mes_alta | cantidad 
-----+----------+----------
(0 rows)

ROLLBACK
```

---

## 4. Frontera de privacidad frente a asistentes de IA (Parte D, punto 4)

Nunca deberían enviarse hacia un asistente de inteligencia artificial sin pasar antes por este proceso de anonimización las filas reales de `usuario` ni de `cliente` que contienen datos personales identificables (`nombre`, `apellido`, `mail`/`email` y `celular`/`telefono`), como tampoco la columna `contrasena` de `usuario` (incluso estando almacenada como hash). Esa misma restricción alcanza a cualquier artefacto derivado que pueda contenerlos de forma directa o indirecta: fragmentos de logs de auditoría sin tokenizar (donde las sentencias SQL o los errores de conexión exponen correos, nombres, direcciones IP o credenciales) y archivos de respaldo (`pg_dump` / backups) de la base de datos. Hacia la IA únicamente deben salir definiciones de esquema (DDL), planes de ejecución sin valores sensibles, consultas de agregación y conjuntos de datos sintéticos o previamente anonimizados como `usuario_anon`.
