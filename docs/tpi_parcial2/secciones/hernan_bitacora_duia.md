# Bitácora y DUIA del TPI — Hernán González (Bloque B: reversión de FNBC y decisiones de auditoría de roles)

Material para que Bruno lo integre en `docs/tpi_parcial2/bitacora_ia_tpi.md` y `docs/tpi_parcial2/DUIA_tpi.md`.

## Bitácora

Formato: fecha · quién · herramienta · qué se pidió · qué se aceptó · qué se corrigió o descartó y por qué · cómo se comprobó.

---

### Entrada 1 · 08/11/2026 · Hernán González · Kiro / OpenCode (Plan y Build)

**Qué se pidió:** redactar la sección 9 («Plan de reversión») en `food-store/specs/spec_fnbc_descomposicion.md` (qué se deshace, orden de `DROP` por claves foráneas, verificación de equivalencia y cuándo se usa) y generar el script `food-store/tp_fnbc_reversion.sql` para ejecutar sobre `bd2_tp4u4` el ciclo completo `migrar → verificar → revertir → verificar` sin pérdida de datos.

**Qué se aceptó:** la guarda inicial con `DO $$ … RAISE EXCEPTION` si `current_database() <> 'bd2_tp4u4'`, la captura previa en la tabla temporal `temp_pre_reversion`, la reconstrucción de `control_lote_almacen` a partir de `control_lote NATURAL JOIN responsable_deposito`, el orden de borrado `DROP VIEW v_control_lote_almacen` → `DROP TABLE control_lote` (tabla hija $R_2$ con FK a $R_1$) → `DROP TABLE responsable_deposito` (tabla padre $R_1$), y la doble comprobación con `EXCEPT` en ambas direcciones (antes del `DROP` contra la vista y después del `DROP` contra `temp_pre_reversion`).

**Qué se corrigió:**
- En el paso de prueba de reversión, si `control_lote_almacen` conservaba las 3 filas originales de la migración y solo se hacía `INSERT … ON CONFLICT DO NOTHING`, la prueba no demostraba que las filas se estuvieran reconstruyendo realmente desde las tablas en FNBC. Se agregó `TRUNCATE TABLE control_lote_almacen;` inmediatamente después de guardar `temp_pre_reversion` y antes del `INSERT INTO control_lote_almacen SELECT … FROM control_lote NATURAL JOIN responsable_deposito`, probando que las 3 filas vuelven íntegras desde $R_1 \bowtie R_2$.

**Qué se descartó:** la primera propuesta usaba `DROP TABLE IF EXISTS responsable_deposito, control_lote CASCADE;` en una sola sentencia para simplificar el script. Se descartó porque el `CASCADE` oculta el orden de dependencias que exige la consigna (borrar primero la vista, luego la tabla hija `control_lote` que tiene la FK y recién al final la tabla padre `responsable_deposito`) y porque podría arrastrar en silencio objetos dependientes no previstos.

**Cómo se comprobó:** previo respaldo `pg_dump -Fc` de `bd2_tp4u4`, se ejecutó `psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -f food-store/tp_fnbc_reversion.sql` primero con `ROLLBACK` y luego con `COMMIT` vía `-v commit=1` en la copia (sin editar el archivo) (`food-store/tp_fnbc_reversion_salida.txt`): los cuatro `EXCEPT` (dos en la migración y dos en la reversión) dieron `0 filas`, `to_regclass` confirmó `vista_fnbc_existe = f`, `r2_control_lote_existe = f`, `r1_responsable_deposito_existe = f` y `tabla_original_existe = t`, y `control_lote_almacen` quedó con sus 3 tuplas (`(501, 30, 801)`, `(502, 30, 801)`, `(503, 31, 802)`) y sus 4 restricciones (`1 PK + 3 FK`).

---

### Entrada 2 · 08/11/2026 · Hernán González · OpenCode (Plan y Build)

**Qué se pidió:** elaborar `docs/decisiones_auditoria_roles.md` con una fila por cada hallazgo de `docs/auditoria_roles_ia.md` (`H1–H5`, `F1–F4`, `R1–R3` y `M1–M4`), indicando la decisión humana (aceptado, corregido, descartado o pospuesto), su fundamento y las sentencias de comprobación con `SET ROLE …; <intento>; RESET ROLE;` dentro de `BEGIN … ROLLBACK;` para incorporar en `sql/verificacion_roles.sql`.

**Qué se aceptó:** la matriz completa de decisiones documentando los 2 hallazgos aceptados (`H1` y `H4`), los 2 corregidos puntualmente en `sql/roles.sql` (`R1`, `R2`), los 10 descartados con fundamento / riesgos aceptados (`H2`, `H3`, `F1`, `F2`, `F3`, `R3`, `M1–M4` y privilegios de `admin_datos`) y los 2 pospuestos (`H5`, `F4`), junto con el bloque ampliado de pruebas con `SET ROLE` en `sql/verificacion_roles.sql`.

**Qué se corrigió:**
- En la prueba funcional de `H4` dentro de `sql/verificacion_roles.sql`, la consulta propuesta para elegir un usuario no administrador como `rol_soporte` escribía `SELECT fn_resetear_password((SELECT id FROM usuario WHERE rol = 'USUARIO' AND eliminado = FALSE ORDER BY id LIMIT 1), 'corta');`. Al correrla en `bd2_tp5u5` falló con `ERROR: permiso denegado a la tabla usuario` antes de entrar a la función, porque `rol_soporte` solo tiene `GRANT SELECT (id, nombre, apellido, mail, rol) ON usuario` y no puede filtrar por la columna `eliminado` en la subconsulta exterior (justamente lo analizado en `F3`). Se quitó `AND eliminado = FALSE` de la subconsulta del llamador (la función `SECURITY DEFINER` ya lo valida adentro) y la prueba devolvió los resultados esperados: `ERROR: La nueva contraseña debe tener al menos 8 caracteres` con `'corta'` y ejecución exitosa (`1 row`) con `'clave_valida_123'`.

**Qué se descartó:** se descartaron las propuestas de `docs/auditoria_roles_ia.md` de: 1) crear un esquema separado `reportes` para `ALTER DEFAULT PRIVILEGES` (`H2`, rompe las consultas sobre `public` de la unidad); 2) crear el login `soporte_login`, agregar `SELECT (eliminado) ON usuario TO rol_soporte` y crear un rol con `MAINTAIN` para refrescar la vista materializada (`F2` y `F3`, otorgan identidades y permisos no requeridos por la spec, violando mínimo privilegio); 3) editar `food-store/procedimientos.sql` y `food-store/views.sql` o ejecutar `REVOKE` sobre `bd2_tp3` (`H3`, `F1`, `R2`, porque no se tocan `bd2_tp3` ni entregables cerrados de unidades previas); y 4) reemplazar `sql/roles.sql` por loops dinámicos sobre `pg_class`/`pg_proc` y un `REVOKE ALL ON ALL ROUTINES` masivo (`R1`, `M1–M4`, porque dificulta explicar el script línea por línea en la defensa y arriesga quitar `EXECUTE` sobre `pgcrypto`).

**Cómo se comprobó:** sobre la copia `bd2_tp5u5` (con respaldo previo `pg_dump -Fc`), se ejecutó `psql -U postgres -d bd2_tp5u5 -X -f sql/verificacion_roles.sql` y se guardó la salida completa en `docs/verificacion_roles.txt` (160 líneas): todas las pruebas positivas y todos los rechazos esperados (`H1..H5`, `F1..F4`, `R1..R3`, `M1..M4`) se verificaron dentro de `BEGIN … ROLLBACK;`.

---

## DUIA

| Fecha | Herramienta | Propósito | Qué se le dio (Input) | Qué devolvió (Output) | Decisión | Motivo y comprobación |
|---|---|---|---|---|---|---|
| 08/11/2026 | Kiro / asistente en entorno | Redactar la sección 9 «Plan de reversión» en `food-store/specs/spec_fnbc_descomposicion.md` | `spec_fnbc_descomposicion.md`, `tp_fnbc_control_lote.sql` y requisitos del Objetivo 2 del TPI | Sección 9 con escenarios de uso, pasos de reconstrucción sin pérdida, tabla de orden de `DROP` por FK y criterios de aceptación con `EXCEPT` | **Aceptado** | Revisado línea por línea; respeta el esquema real (`BIGINT`, PK `(lote_id, deposito_id)`) y prohíbe `CASCADE` en el `DROP` de reversión. |
| 08/11/2026 | OpenCode (Plan y Build) | Generar `food-store/tp_fnbc_reversion.sql` a partir de la sección 9 de la spec | `spec_fnbc_descomposicion.md` y `tp_desnormalizacion_reversion.sql` como referencia de estilo | Script transaccional con guarda de base, ciclo `migrar → verificar → revertir → verificar`, `DROP` ordenado y `EXCEPT` en ambos sentidos | **Aceptado con 1 corrección y 1 descarte** | Ver Entrada 1. Se descartó `DROP … CASCADE` y se agregó `TRUNCATE control_lote_almacen` antes de reconstruir desde `R1 ⋈ R2`. Verificado con `ROLLBACK` y `COMMIT` en `food-store/tp_fnbc_reversion_salida.txt`. |
| 08/11/2026 | OpenCode (Plan y Build) | Redactar `docs/decisiones_auditoria_roles.md` y ampliar `sql/verificacion_roles.sql` para comprobar todos los hallazgos en `bd2_tp5u5` | `docs/auditoria_roles_ia.md`, `docs/kiro_roles_spec/design.md`, `sql/roles.sql`, `sql/funciones_auth.sql` y `BITACORA.md` | Tabla de decisiones humanas (`H1–H5`, `F1–F4`, `R1–R3`, `M1–M4`) y bloque de pruebas con `SET ROLE` en `ROLLBACK` | **Aceptado con 1 corrección y descartes fundamentados** | Ver Entrada 2. Se corrigió la subconsulta de prueba de `H4` que referenciaba `eliminado` como `rol_soporte`. Evidencia en `docs/verificacion_roles.txt`. |
| 08/11/2026 | Asistente en entorno | Redactar las secciones de Unidad 4 y Unidad 5 del informe técnico (`docs/tpi_parcial2/secciones/hernan_u4_u5.md`) | `docs/informe_tp_u4.md`, `food-store/tp_fnbc_reversion_salida.txt`, `docs/informe_auditoria.md`, `docs/informe_incidente.md`, `docs/decisiones_auditoria_roles.md` y plantilla `informe_tpi.html` | Resumen técnico de U4 y U5 (~¾ pág. c/u) con qué se implementó, cómo se probó, métricas exactas y decisiones de diseño con citas a archivos | **Aceptado** | Todas las cifras (78,077 ms → 0,037 ms, 125 filas MV, 304 usuarios en simulacro, 0 filas en `EXCEPT`) se cotejaron contra las evidencias versionadas en el repositorio. |

### Apartamientos del flujo de la cátedra (declarados)

- La edición de la sección 9 en `food-store/specs/spec_fnbc_descomposicion.md` y la redacción de las secciones del informe se asistieron desde el agente del entorno (siguiendo el formato de Kiro y de la plantilla del equipo) para evitar que la reescritura de Kiro eliminara tildes o formato previo, como ya se había registrado en la DUIA de la Unidad 4 (`docs/duia/duia_tp_u4.md`).
- Todo el código SQL fue leído línea por línea y ejecutado sobre las copias locales `bd2_tp4u4` y `bd2_tp5u5` con respaldo `pg_dump` previo y prueba en `BEGIN … ROLLBACK` antes de confirmar. En ningún paso se enviaron contraseñas reales ni datos personales a herramientas de IA.
