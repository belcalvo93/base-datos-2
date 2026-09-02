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
├── db/
│   ├── schema.sql
│   ├── datos.sql
│   ├── restricciones.sql
│   ├── pruebas_restricciones.sql
│   ├── carga_masiva.sql
│   ├── carga_masiva_bloque3_B.sql
│   ├── verificacion_carga_masiva.sql
│   ├── log_carga_produccion.txt
│   └── backups/
├── docs/
│   ├── Diagrama ER.png
│   ├── spec_restricciones.md
│   ├── spec_carga_masiva.md
│   ├── informe_concurrencia.md
│   ├── ejercicio_lectura_critica.md
│   └── duia/
│       ├── duia_parte1.md
│       ├── duia_parte2.md
│       ├── duia_parte3.md
│       └── duia_parte4.md
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
| `db/schema.sql` | Definición de tablas e índices (idempotente) |
| `db/datos.sql` | Datos iniciales (semillas) |
| `db/restricciones.sql` | Triggers de validación sobre `detalle_pedido` (producto activo, stock suficiente) |
| `db/pruebas_restricciones.sql` | Tests de las restricciones |
| `db/carga_masiva.sql` | Inserción masiva de datos de prueba |
| `db/carga_masiva_bloque3_B.sql` | Variante de carga masiva (descartada) |
| `db/verificacion_carga_masiva.sql` | Verificación post-carga |
| `db/log_carga_produccion.txt` | Log de la ejecución de carga |
| `db/backups/` | Respaldos `.dump` de la base de trabajo |
| `docs/Diagrama ER.png` | Diagrama entidad-relación |
| `docs/spec_restricciones.md` | Especificación de restricciones de integridad |
| `docs/spec_carga_masiva.md` | Especificación de la carga masiva |
| `docs/informe_concurrencia.md` | Informe de ejercicios de concurrencia |
| `docs/ejercicio_lectura_critica.md` | Ejercicio de lectura crítica |
| `docs/duia/` | Documentación de uso de IA por unidad |
| `.kiro/steering/database.md` | Referencia del esquema con diseño justificado |

---

## Modelo de datos

| Tabla | Descripción |
|-------|-------------|
| `categoria` | Categorías de productos. Baja lógica (R7). Participación parcial respecto a producto. |
| `cliente` | Datos del cliente. Email como clave candidata (R6). |
| `producto` | Productos del catálogo. Precio ≥ 0, stock ≥ 0. Participación total respecto a categoría. |
| `pedido` | Cabecera de pedido: fecha, forma de pago (ENUM), cliente. |
| `detalle_pedido` | Líneas del pedido (relación N:M). Congela precio histórico (R4). UNIQUE(id_pedido, id_producto). |

Diagrama ER completo en `docs/Diagrama ER.png`.

---

## Entregables por unidad

| Unidad | Semanas | Archivos |
|--------|---------|----------|
| Unidad 1 | Semana 1 | Modelo ER, normalización a 3FN/BCNF, `db/schema.sql` |
| Unidad 1 | Semana 2 | `protocolo_seguridad.md`, `docs/spec_restricciones.md`, `db/restricciones.sql`, `db/pruebas_restricciones.sql`, `docs/informe_concurrencia.md`, `docs/ejercicio_lectura_critica.md`, tres DUIA |
| Unidad 2 | Sem. 3–4 | `db/carga_masiva.sql`, `docs/spec_carga_masiva.md`, `db/verificacion_carga_masiva.sql`, `db/carga_masiva_bloque3_B.sql` (variante descartada), `docs/duia/duia_parte4.md`. Optimización con EXPLAIN/índices en curso. |

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
