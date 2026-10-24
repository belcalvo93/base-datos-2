# Bitácora de uso de IA — TP Unidad 5

Registro de cada interacción relevante con la IA (OpenCode, Kiro, Claude Code) del TP de la Unidad 5 (roles, auditoría, incidentes y protección de datos). Cada integrante completa **solo la sección de su parte**, así los cambios de cada uno no se pisan al mezclar las ramas. La Parte E consolida todo al final.

Requisitos del enunciado: un registro por cada parte en la que se usó OpenCode, y señalar al menos un caso en el que la IA propuso algo incorrecto, inseguro o de más, y cómo se detectó y corrigió. Si se usa una herramienta distinta de OpenCode, se declara.

## Parte A — Roles y permisos de mínimo privilegio

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| (Kiro) Prompt con la consigna A.1, el inventario real de la base y 5 puntos a resolver: fn_autenticar INVOKER vs DEFINER, celular en soporte, objetos de rol_reportes, falla del escalamiento en el simulacro y roles de login adicionales. Se le indicó explícitamente no escribir SQL. | Antes de escribir hizo 3 preguntas de diseño. Respondimos: mv_ventas_categoria_mes para reportes, fn_autenticar SECURITY DEFINER, y permiso por columna sobre usuario para soporte en vez de una vista nueva. Generó `requirements.md` y `design.md` en `docs/kiro_roles_spec/`. | **IA de más / incorrecta:** escribió SQL pese a la instrucción. Ese SQL de la vista materializada inventaba columnas (`c.activo`) y filtraba por productos activos, lo que habría borrado del reporte las ventas históricas de productos dados de baja. También le dio a `rol_app_escritura` SELECT sobre una vista inexistente (`vista_productos_videntes`), redundante además. Le faltaba definir quién es dueño de los objetos y su explicación del escalamiento era imprecisa (en PostgreSQL 16+ hace falta ADMIN sobre el rol, no solo CREATEROLE). Se le pidió corregir los 5 puntos. |
| (Kiro) Prompt de corrección de los 5 puntos anteriores. | Reportó todo corregido "en ambos archivos" y agregó R7 (ownership de admin_datos) y la regla de DEFAULT PRIVILEGES para funciones. | **IA reporta algo que no hizo:** el typo `vista_productos_videntes` seguía en `requirements.md`, aunque Kiro dijo haberlo corregido. Se detectó leyendo el archivo línea por línea y se corrigió a mano junto con otros dos detalles menores (un typo y una fila del resumen incompleta). |

### Parte 0 — Reconstrucción previa (roles.sql y funciones de la Clase 2)

Los artefactos de clase no estaban en el repo, así que se reconstruyeron antes de la Parte A, como pide la consigna. Herramienta usada: Claude (chat en el navegador)

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
