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
│   ├── indices.sql              (nuevo — TP5 Parte A)
│   ├── views.sql                (nuevo — TP5 Partes B y C)
│   ├── informe_mediciones.md    (nuevo — TP5 Partes A y C)
│   ├── specs/
│   └── backups/
├── concurrencia/
│   ├── README.md
│   ├── escenario0_atomicidad.sql
│   ├── escenario1_lectura_no_repetible_sesionA.sql
│   ├── escenario1_lectura_no_repetible_sesionB.sql
│   ├── escenario2_lectura_fantasma_sesionA.sql
│   ├── escenario2_lectura_fantasma_sesionB.sql
│   ├── escenario3_espera_bloqueo_sesionA.sql
│   └── escenario3_espera_bloqueo_sesionB.sql
├── docs/
│   ├── Diagrama ER.png
│   ├── diagrama_er.mmd
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
│   └── duia/
│       ├── duia_parte1.md
│       ├── duia_parte2.md
│       ├── duia_parte3.md
│       ├── duia_parte4.md
│       └── duia_parte5.md    (nuevo — TP5)
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
| `food-store/indices.sql` | Decisiones de índices del TP5, Parte A |
| `food-store/views.sql` | Vistas del TP5, Partes B y C |
| `food-store/informe_mediciones.md` | Informe de mediciones de la Parte A |
| `food-store/specs/` | Specs de Kiro del TP5, incluidas las de Parte A y usuario |
| `food-store/backups/` | Respaldos `.dump` de la base de trabajo |
| `concurrencia/README.md` | Orquestación de los escenarios de concurrencia (TPI, objetivo 8) |
| `concurrencia/escenario*.sql` | Escenarios reproducibles: atomicidad (0), lectura no repetible (1), fantasma (2), espera por bloqueo (3) |
| `docs/Diagrama ER.png` | Diagrama entidad-relación |
| `docs/diagrama_er.mmd` | Diagrama ER en Mermaid (fuente editable del PNG) |
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
| `docs/duia/` | Documentación de uso de IA por unidad |
| `docs/duia/duia_parte5.md` | DUIA de las Partes A y B del TP5 |
| `.kiro/steering/database.md` | Referencia del esquema con diseño justificado |

---

## Equivalencia con la consigna del TP5

| Nombre que usa la consigna | Archivo en el repo |
|---------------------------|--------------------|
| `schema.sql` | `food-store/schema.sql` |
| `data.sql` | `food-store/data.sql` (antes `db/datos.sql`) |
| `indices.sql` | `food-store/indices.sql` |
| `views.sql` | `food-store/views.sql` |
| `specs/` | `food-store/specs/` |
| `informe_mediciones.md` | `food-store/informe_mediciones.md` |
| DUIA del TP5 | `docs/duia/duia_parte5.md` |

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

Diagrama ER completo en `docs/Diagrama ER.png`; fuente editable en `docs/diagrama_er.mmd` (Mermaid).

---

## Entregables por unidad

| Unidad | Semanas | Archivos |
|--------|---------|----------|
| Unidad 1 | Semana 1 | Modelo ER, normalización a 3FN/BCNF, `food-store/schema.sql` |
| Unidad 1 | Semana 2 | `protocolo_seguridad.md`, `docs/spec_restricciones.md`, `food-store/restricciones.sql`, `food-store/pruebas_restricciones.sql`, `docs/informe_concurrencia.md`, `docs/ejercicio_lectura_critica.md`, tres DUIA |
| Unidad 2 | Sem. 3–4 | **Parte 1 (carga masiva):** `food-store/carga_masiva.sql`, `docs/spec_carga_masiva.md`, `food-store/verificacion_carga_masiva.sql`, `food-store/carga_masiva_bloque3_B.sql` (variante descartada), `docs/duia/duia_parte4.md`. **Parte 2 (índices):** `docs/informe_parte2_indices.md`, `docs/planes_parte2_antes.txt`, `docs/planes_parte2_despues.txt`. **Parte 3 (lectura crítica):** `docs/explicacion_ia_plan_c2.md`, `docs/informe_parte3_lectura_critica.md`. **Parte 4 (consultas bajo spec):** `docs/spec_consultas_parte4.md`, `docs/informe_parte4_consultas.md`. **Informe TP4:** `docs/informe_tp4_semana4.md`. |
| Unidad 3 | TP5 | **Parte A:** `food-store/indices.sql`, `food-store/queries.sql`, `food-store/informe_mediciones.md`. **Parte B:** `food-store/specs/spec_vistas.md`, `food-store/specs/spec_usuario.md`, `food-store/views.sql`. **DUIA:** `docs/duia/duia_parte5.md`. |

---

## Entorno

- **PostgreSQL 17.11** sobre Windows 11
- Terminal: Git Bash
- Editor: VS Code
- Agentes de IA: OpenCode (Big Pickle / OpenCode Zen), Kiro

### Bases de datos

| Base | Rol |
|------|-----|
| `bd2_proyecto` | Plantilla. No se modifica. |
| `bd2_trabajo` | Copia de trabajo. Se recrea con `createdb -T bd2_proyecto bd2_trabajo`. |
| `bd2_tp3` | Base poblada de la Unidad 2 (~50.000 productos / 20.000 clientes / 200.000 pedidos / 499.000 detalles). |

---

## Protocolo de seguridad

Antes de cualquier cambio estructural: **backup** (`pg_dump`), **transacción con ROLLBACK** primero, inspección del resultado, y recién después COMMIT. Aplica a todo script, propio o generado. Detalle completo en `protocolo_seguridad.md`.

---

## Uso de IA

La cátedra establece la IA como motor primario de escritura. La regla es **«se delega la escritura, nunca la decisión»**. Cada uso está documentado en `docs/duia/`.
