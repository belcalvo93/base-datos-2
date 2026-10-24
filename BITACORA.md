# Bitácora de uso de IA — TP Unidad 5

Registro de cada interacción relevante con la IA (OpenCode, Kiro, Claude Code) del TP de la Unidad 5 (roles, auditoría, incidentes y protección de datos). Cada integrante completa **solo la sección de su parte**, así los cambios de cada uno no se pisan al mezclar las ramas. La Parte E consolida todo al final.

Requisitos del enunciado: un registro por cada parte en la que se usó OpenCode, y señalar al menos un caso en el que la IA propuso algo incorrecto, inseguro o de más, y cómo se detectó y corrigió. Si se usa una herramienta distinta de OpenCode, se declara.

## Parte A — Roles y permisos de mínimo privilegio

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

### Parte 0 — Reconstrucción previa (roles.sql y funciones de la Clase 2)

Los artefactos de clase no estaban en el repo, así que se reconstruyeron antes de la Parte A, como pide la consigna. Se uso Claude chat en el navegador 

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| Se le pasaron a Claude los apuntes de la unidad 5, con el pedido de reconstruir `roles.sql`, `fn_autenticar` y `fn_resetear_password` adaptados a nuestra base. | Script de roles tomado del apunte de la Clase 1 (sección 4.4) y funciones del apunte de la Clase 2 (secciones 1.5 y 2.3), con los nombres de objetos cambiados a los nuestros. | Antes de escribir se hizo un inventario de la base: los nombres del apunte no existen (`v_productos_vigentes` → `vista_productos_vigentes`, `v_usuarios_publico` → `vista_usuario_reportes`, `v_pedidos_resumen` → `vista_pedidos_cliente`, `sp_crear_pedido` → `registrar_pedido`). `mv_ventas_categoria_mes` no existe; `rol_reportes` queda sin GRANT nuevos hasta la Parte A. Se probó todo con `BEGIN`/`ROLLBACK`. |
| — | En la primera prueba, `\du` mostró que `rol_reportes` podía conectarse. | **Hallazgo:** `rol_reportes` ya existía en el servidor desde el TP de vistas, creado con LOGIN, y el script lo salteaba por existir. Se corrigió para que fuerce `NOLOGIN` en todo rol de grupo existente. Se verificó con `\du`: los 4 roles de grupo quedan "No puede conectarse". |

## Parte B — Activación y prueba de la auditoría

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte C — Simulacro de incidente de acceso indebido

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte D — Anonimización y verificación de equivalencia

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte E — Cierre

### Caso más significativo de error o imprecisión de la IA

*Pendiente (Parte E, punto 2).*

### Nota sobre el historial de Git

*Pendiente (Parte E, punto 3).*
