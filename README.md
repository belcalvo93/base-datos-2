# Base de Datos II

**Tecnicatura Universitaria en Programación — UTN**

Proyecto integrador: **Food Store**, un sistema de gestión de pedidos de un negocio de comidas. Un solo trabajo práctico integrado, dividido por unidades; el parcial se rinde entregando todo junto en un ZIP.

---

## Estructura del repositorio

```
├── AGENTS.md
├── README.md
├── .env.example
├── .gitignore
├── protocolo_seguridad.md
├── food-store/
│   ├── schema.sql
│   ├── data.sql
│   ├── restricciones.sql
│   ├── pruebas_restricciones.sql
│   ├── carga_masiva.sql
│   ├── carga_masiva_bloque3_B.sql
│   ├── verificacion_carga_masiva.sql
│   ├── log_carga_produccion.txt
│   ├── queries.sql              (nuevo — TP5 Parte A)
│   ├── indices.sql              (nuevo — TP5 Parte A)
│   ├── medicion_planes.sql      (nuevo — TP5 Parte A)
│   ├── medicion_escritura.sql   (nuevo — TP5 Parte A)
│   ├── planes_tp5_parteA.txt    (nuevo — TP5 Parte A)
│   ├── views.sql                (nuevo — TP5 Parte B)
│   ├── materializadas.sql       (nuevo — TP5 Parte C)
│   ├── informe_mediciones.md    (nuevo — TP5 Partes A, B y C)
│   ├── duia.md                  (nuevo — DUIA consolidada del TP5)
│   ├── README.md                (nuevo — cómo reproducir las pruebas)
│   ├── specs/
│   └── backups/
├── docs/
│   ├── Diagrama ER.png
│   ├── spec_restricciones.md
│   ├── spec_carga_masiva.md
│   ├── informe_concurrencia.md
│   ├── ejercicio_lectura_critica.md
│   ├── informe_parte2_indices.md
│   ├── planes_parte2_antes.txt
│   ├── planes_parte2_despues.txt
│   ├── explicacion_ia_plan_c2.md
│   ├── informe_parte3_lectura_critica.md
│   ├── spec_consultas_parte4.md
│   ├── informe_parte4_consultas.md
│   ├── informe_tp4_semana4.md
│   ├── verificacion_fantasmas_repeatable_read.md
│   └── duia/
│       ├── duia_parte1.md
│       ├── duia_parte2.md
│       ├── duia_parte3.md
│       ├── duia_parte4.md
│       └── duia_parte5.md    (nuevo — TP5 Partes A y B, registro detallado)
└── .kiro/
    └── steering/
        └── database.md
```

| Ruta | Contenido |
|------|-----------|
| `AGENTS.md` | Convenciones SQL, protocolo y gotchas para herramientas de IA |
| `.env.example` | Variables de entorno de ejemplo |
| `.gitignore` | Archivos excluidos del versionado |
| `protocolo_seguridad.md` | Protocolo de respaldo y ejecución segura de scripts |
| `food-store/schema.sql` | Definición de tablas (idempotente) |
| `food-store/data.sql` | Datos iniciales (semillas) |
| `food-store/restricciones.sql` | Triggers de validación sobre `detalle_pedido` (producto activo, stock suficiente) |
| `food-store/pruebas_restricciones.sql` | Tests de las restricciones |
| `food-store/carga_masiva.sql` | Inserción masiva de datos de prueba |
| `food-store/carga_masiva_bloque3_B.sql` | Variante de carga masiva (descartada) |
| `food-store/verificacion_carga_masiva.sql` | Verificación post-carga |
| `food-store/log_carga_produccion.txt` | Log de la ejecución de carga |
| `food-store/queries.sql` | Consultas de TP2 y TP4 consolidadas como fuente de la carga de trabajo del TP5 |
| `food-store/indices.sql` | Índices aceptados del TP5, Parte A (1 aceptado; los descartados quedan comentados con su motivo) |
| `food-store/medicion_planes.sql` | Genera los `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` antes/después de cada índice candidato, en transacción con ROLLBACK |
| `food-store/medicion_escritura.sql` | Mide el costo de escritura de los índices (500 INSERT por tabla y 500 UPDATE de `stock`; tiempo y WAL) |
| `food-store/planes_tp5_parteA.txt` | Salida de `medicion_planes.sql` sobre la base de 499.263 detalles |
| `food-store/views.sql` | Vistas del TP5, Parte B (incluye `vista_usuario_reportes`) |
| `food-store/materializadas.sql` | Vista materializada `mv_facturacion_cat_mes` del TP5, Parte C, con su índice único para `REFRESH CONCURRENTLY` |
| `food-store/informe_mediciones.md` | Informe de mediciones del TP5: Parte A (planes y costo de escritura), Parte B (equivalencia de las vistas) y Parte C (vista materializada) |
| `food-store/duia.md` | DUIA consolidada del TP5 (Partes A, B y C), que es donde la pide la consigna |
| `food-store/README.md` | Pasos para levantar la base y repetir las pruebas del TP5 |
| `food-store/specs/` | Specs de Kiro del TP5: `spec_indice_*.md` (Parte A, con el resultado de la medición al final de cada una), `spec_usuario.md` y `spec_vistas.md` (Parte B) y `spec_vista_materializada_parteC.md` (Parte C) |
| `food-store/backups/` | Respaldos `.dump` de la base de trabajo |
| `docs/Diagrama ER.png` | Diagrama entidad-relación |
| `docs/spec_restricciones.md` | Especificación de restricciones de integridad |
| `docs/spec_carga_masiva.md` | Especificación de la carga masiva |
| `docs/informe_concurrencia.md` | Informe de ejercicios de concurrencia |
| `docs/ejercicio_lectura_critica.md` | Ejercicio de lectura crítica |
| `docs/informe_parte2_indices.md` | Informe de la Parte 2: mediciones de índices antes y después |
| `docs/planes_parte2_antes.txt` | Planes de EXPLAIN ANALYZE sin índices |
| `docs/planes_parte2_despues.txt` | Planes de EXPLAIN ANALYZE con los índices del TP1 |
| `docs/explicacion_ia_plan_c2.md` | Explicación de un plan generada por IA, sin editar (insumo de la Parte 3) |
| `docs/informe_parte3_lectura_critica.md` | Auditoría de esa explicación contra el plan real |
| `docs/spec_consultas_parte4.md` | Specs de las dos consultas de la Parte 4 |
| `docs/informe_parte4_consultas.md` | Informe de la Parte 4 con la verificación de equivalencia |
| `docs/informe_tp4_semana4.md` | Informe TP4: mediciones, lectura crítica, ranking y consultas bajo especificación |
| `docs/verificacion_fantasmas_repeatable_read.md` | Verificación contra el motor de que `REPEATABLE READ` también evita lecturas fantasma |
| `docs/duia/` | Documentación de uso de IA por unidad |
| `docs/duia/duia_parte5.md` | Registro detallado de la DUIA de las Partes A y B del TP5 (19 usos de IA, prompts y verificaciones). La entrega consolidada es `food-store/duia.md` |
| `.kiro/steering/database.md` | Referencia del esquema con diseño justificado |

---

## Equivalencia con la consigna del TP5

| Nombre que usa la consigna | Archivo en el repo |
|---------------------------|--------------------|
| `schema.sql` | `food-store/schema.sql` |
| `data.sql` | `food-store/data.sql` (antes `db/datos.sql`) |
| `indices.sql` | `food-store/indices.sql` |
| `views.sql` | `food-store/views.sql` |
| Vista materializada | `food-store/materializadas.sql` |
| `specs/` | `food-store/specs/` |
| `informe_mediciones.md` | `food-store/informe_mediciones.md` |
| DUIA del TP5 | `food-store/duia.md` (el registro detallado de las Partes A y B queda en `docs/duia/duia_parte5.md`) |

Las specs del TP5 se conservan en `food-store/specs/` junto con sus criterios
de aceptación.

---

## Modelo de datos

| Tabla | Descripción |
|-------|-------------|
| `categoria` | Categorías de productos. Baja lógica (R7). Participación parcial respecto a producto. |
| `cliente` | Datos del cliente. Email como clave candidata (R6). |
| `producto` | Productos del catálogo. Precio ≥ 0, stock ≥ 0. Participación total respecto a categoría. |
| `pedido` | Cabecera de pedido: fecha, forma de pago (ENUM), cliente. |
| `detalle_pedido` | Líneas del pedido (relación N:M). Congela precio histórico (R4). UNIQUE(id_pedido, id_producto). |
| `usuario` | Actores de login y reportes; la contraseña no se expone en `vista_usuario_reportes`. |

Diagrama ER completo en `docs/Diagrama ER.png`.

---

## Entregables por unidad

| Unidad | Semanas | Archivos |
|--------|---------|----------|
| Unidad 1 | Semana 1 | Modelo ER, normalización a 3FN/BCNF, `food-store/schema.sql` |
| Unidad 1 | Semana 2 | `protocolo_seguridad.md`, `docs/spec_restricciones.md`, `food-store/restricciones.sql`, `food-store/pruebas_restricciones.sql`, `docs/informe_concurrencia.md`, `docs/ejercicio_lectura_critica.md`, tres DUIA |
| Unidad 2 | Sem. 3–4 | **Parte 1 (carga masiva):** `food-store/carga_masiva.sql`, `docs/spec_carga_masiva.md`, `food-store/verificacion_carga_masiva.sql`, `food-store/carga_masiva_bloque3_B.sql` (variante descartada), `docs/duia/duia_parte4.md`. **Parte 2 (índices):** `docs/informe_parte2_indices.md`, `docs/planes_parte2_antes.txt`, `docs/planes_parte2_despues.txt`. **Parte 3 (lectura crítica):** `docs/explicacion_ia_plan_c2.md`, `docs/informe_parte3_lectura_critica.md`. **Parte 4 (consultas bajo spec):** `docs/spec_consultas_parte4.md`, `docs/informe_parte4_consultas.md`. **Informe TP4:** `docs/informe_tp4_semana4.md`. |
| Unidad 3 | TP5 | **Parte A:** `food-store/indices.sql`, `food-store/queries.sql`, `food-store/specs/spec_indice_*.md`, `food-store/medicion_planes.sql`, `food-store/medicion_escritura.sql`, `food-store/planes_tp5_parteA.txt`, informe en `food-store/informe_mediciones.md`. **Parte B:** `food-store/specs/spec_vistas.md`, `food-store/specs/spec_usuario.md`, `food-store/views.sql`. **Parte C:** `food-store/specs/spec_vista_materializada_parteC.md`, `food-store/materializadas.sql`. **DUIA:** `food-store/duia.md` (registro detallado de las Partes A y B en `docs/duia/duia_parte5.md`). |

---

## Entorno

- **PostgreSQL 17.11** sobre Windows 11
- Terminal: Git Bash
- Editor: VS Code
- Agentes de IA: OpenCode (Big Pickle / OpenCode Zen), Kiro; Claude Code en la Parte A del TP5

### Bases de datos

| Base | Rol |
|------|-----|
| `bd2_proyecto` | Plantilla. No se modifica. |
| `bd2_trabajo` | Copia de trabajo. Se recrea con `createdb -T bd2_proyecto bd2_trabajo`. |
| `bd2_tp3` | Base poblada de la Unidad 2 (~50.000 productos / 20.000 clientes / 200.000 pedidos / 499.000 detalles). |

---

## Cómo reproducir la Parte A del TP5

Sobre `bd2_tp3` (o una copia `bd2_trabajo` de ella), confirmando antes con `SELECT current_database();`. Todo lo que crea índices de prueba corre dentro de `BEGIN; … ROLLBACK;`, así que no deja nada instalado.

```bash
# 1. Estadísticas y mapa de visibilidad al día (necesario para el Index Only Scan)
psql -U postgres -d bd2_trabajo -X -c "VACUUM ANALYZE"

# 2. EXPLAIN (ANALYZE, BUFFERS, VERBOSE) antes/después de cada índice candidato
psql -U postgres -d bd2_trabajo -X -f food-store/medicion_planes.sql > food-store/planes_tp5_parteA.txt

# 3. Costo de escritura (500 INSERT/UPDATE por tabla; el informe usó 15 rondas y tomó la mediana)
psql -U postgres -d bd2_trabajo -X -A -t -f food-store/medicion_escritura.sql

# 4. Crear el índice aceptado (probar primero dentro de BEGIN; … ROLLBACK;)
psql -U postgres -d bd2_trabajo -f food-store/indices.sql
```

Las decisiones, los planes y las cifras están en `food-store/informe_mediciones.md` (la sección 9 detalla el método y cómo usar `pgbench`).

Para las Partes B y C, con el mismo protocolo (`BEGIN; … ROLLBACK;` primero): `food-store/views.sql` crea las vistas y `food-store/materializadas.sql` crea la vista materializada. Las consultas `EXCEPT` de verificación están en `food-store/specs/spec_vistas.md` y al pie de `materializadas.sql`. Los pasos para levantar la base desde cero están en `food-store/README.md`.

---

## Protocolo de seguridad

Antes de cualquier cambio estructural: **backup** (`pg_dump`), **transacción con ROLLBACK** primero, inspección del resultado, y recién después COMMIT. Aplica a todo script, propio o generado. Detalle completo en `protocolo_seguridad.md`.

---

## Uso de IA

La cátedra establece la IA como motor primario de escritura. La regla es **«se delega la escritura, nunca la decisión»**. Cada uso está documentado en `docs/duia/`.

---

## Equipo

El grupo está conformado por 4 integrantes: Belén Calvo,
Elías Tello, Hernán González y Bruno Fiouchetta.
Bruno se sumó al grupo con autorización del profesor Sergio
Neira, otorgada por WhatsApp: al no tener grupo formal en la materia,
se le consultó al profesor si podía sumarse aunque el grupo ya estuviera
completo, y el profesor autorizó la excepción ("bueno.. metelo en el
grupo"). Captura de la conversación: docs/autorizacion_grupo_4_whatsapp.png.jpeg.
