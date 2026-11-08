# Bitácora y DUIA del TPI — Belén Calvo (Bloque A: respaldo programado y estructura del TPI)

Material para que Bruno lo integre en `docs/tpi_parcial2/bitacora_ia_tpi.md` y `docs/tpi_parcial2/DUIA_tpi.md`.

## Bitácora

Formato: fecha · quién · herramienta · qué se pidió · qué se aceptó · qué se corrigió o descartó y por qué · cómo se comprobó.

---

### Entrada 1 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)

**Qué se pidió:** modificar `backup_foodstore.sh` según la sección "Programación y retención" de `SPEC_U6.md`: retención de 7 días con mínimo de 3 juegos, solo después de un PASS, y respaldo de roles con `pg_dumpall --globals-only --no-role-passwords`.

**Qué se aceptó:** la estructura de `retener()`, las 4 guardas del archivo de roles (falla de `pg_dumpall`, archivo vacío, sin roles, con hashes de contraseña), la retención por fecha del nombre y no por fecha de modificación, y el campo `origen=` en el log.

**Qué se corrigió:**
- Un error de tipeo en una variable (`dumpsuegos`) y, con `set -u`, una variable sin definir cuando no hay juegos completos; se declararon los tres arreglos con `local -a dumps=() juegos=() orden=()`.
- El `.dump` se borraba aunque fallara el borrado de los otros archivos del juego; ahora se borra último y solo si los demás se borraron.
- `ORIGEN` no estaba exportada, así que no llegaba al script lanzado por la tarea.

**Qué se descartó:** las pruebas de retención propuestas daban por hecho el contenido de la carpeta real `backups/`, que tiene respaldos reales. Se descartaron y se probó en una carpeta temporal con `BACKUP_DIR`, para no tocar respaldos verdaderos.

**Cómo se comprobó:** `mantenimiento/evidencias/retencion_pruebas.txt` (6 juegos antes, 3 después; configuración inválida sale con código 2; base inexistente da FAIL y no borra nada) y `globals_pruebas.txt` (9 roles, 0 hashes de contraseña, las 4 guardas fallan como corresponde).

---

### Entrada 2 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)

**Qué se pidió:** `programar_respaldo.ps1` (crea la tarea diaria de las 21:00) y `quitar_respaldo.ps1` (la borra), sin guardar contraseña.

**Qué se aceptó:** tarea idempotente (`-Force`), `StartWhenAvailable`, una sola instancia a la vez, usuario actual con sesión iniciada.

**Qué se corrigió:**
- Usó un bloque de código dentro de `-replace`, que Windows PowerShell 5.1 no soporta; se reemplazó por `Substring` y `Replace`.
- PowerShell expandía `$PATH` al registrar la tarea y no el `bash` al ejecutarla; se escapó. Además la comilla simple se cerraba antes de tiempo y el PATH con espacios (`Program Files`) iba sin comillas.
- En Git Bash, `schtasks /query` convertía `/query` en una ruta de Windows; se usó `MSYS_NO_PATHCONV=1`.

**Qué se descartó:** la secuencia de reproducción del README corría `quitar_respaldo.ps1` justo después de programar y disparar la tarea, y borraba la tarea recién creada. Se descartó: `quitar` queda comentado como paso opcional.

**Cómo se comprobó:** `evidencias/tarea_programada.txt` (estado Listo, diaria, 21:00) y `tarea_programada_prueba_humo.txt` (disparo con `schtasks /run`: PASS con `origen=programada`, resultado 0). Falta la corrida por el horario real.

---

### Entrada 3 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)

**Qué se pidió:** la matriz de los 14 objetivos (`matriz_objetivos.md`), las secciones de U4 y U5 en el README de la raíz y la actualización de `mantenimiento/README.md`.

**Qué se aceptó:** la tabla de 14 filas con enlaces, la reproducción apuntando al README correcto y las dos filas nuevas del README en el formato de la tabla existente.

**Qué se corrigió:** la matriz y el README de mantenimiento estaban redactados de más.

**Qué se descartó:** el README de mantenimiento decía que cubría el simulacro de desastre (objetivo 8), que es de Elías y todavía no está hecho; se reescribió la frase para que cubra solo el respaldo programado y la restauración. También se descartó el procedimiento de retención que remitía a un archivo de evidencia y no se podía repetir; se reemplazó por un bloque con fechas relativas (`date -d "-N days"`) que se reproduce cualquier día.

**Cómo se comprobó:** se leyó cada diff antes de aplicar; las rutas de la matriz se cotejaron con los archivos del repo y los resultados esperados (se eliminan 3 juegos y quedan 3) con `retencion_pruebas.txt`.

---

### Entrada 4 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)

**Qué se pidió:** la plantilla del informe técnico (`informe_tpi.html`) con el estilo del informe del TP8 y los huecos para cada integrante, y la redacción de las secciones U7 y U8 a partir de las evidencias del repo de Mongo.

**Qué se aceptó:** el CSS del TP8, el encabezado, los huecos con clase propia para buscarlos con `grep`, y las cifras de U7 y U8, cada una con su archivo de origen.

**Qué se corrigió:** el índice de objetivos usaba números y archivos sin cotejar con la matriz; se rehízo con los 14 objetivos de la matriz y con el repo (`R:` o `M:`) de cada archivo. Los huecos traían resultados escritos de antemano (por ejemplo un RTO) que no eran los del simulacro de desastre; se sacaron.

**Qué se descartó:** `break-before: page` en cada título, que fuerza una página nueva por sección y supera las 6 páginas aun con las secciones vacías. También se descartó poner autor y extensión en los títulos, porque quedarían en el PDF.

**Cómo se comprobó:** `grep -c 'class="hueco"'` da 7, no hay `break-before` ni `<small>`, y la tabla tiene 14 filas. Las cifras de U7 y U8 se cotejaron contra las salidas de los archivos de evidencia.

---

## DUIA

| Fecha | Herramienta | Propósito | Qué se le dio (Input) | Qué devolvió (Output) | Decisión | Motivo y comprobación |
|---|---|---|---|---|---|---|
| 08/11/2026 | Claude (chat) | Redactar la sección "Programación y retención" de `SPEC_U6.md` (en lugar de Kiro) | Consigna del TPI, estado del TP6 y limitaciones declaradas | Sección con frecuencia, hora, retención, roles, fallas y criterios de aceptación | **Aceptado con corrección** | Se corrigió la afirmación de que toda la carpeta `backups/` estaba ignorada: faltaba `*_globals.sql` en el `.gitignore`. Apartamiento del flujo declarado abajo. |
| 08/11/2026 | OpenCode (Plan y Build) | `backup_foodstore.sh`: retención y roles | La sección de la spec | Retención, `pg_dumpall` y guardas | **Aceptado con 3 correcciones y 1 descarte** | Ver Entrada 1. `retencion_pruebas.txt`, `globals_pruebas.txt`. |
| 08/11/2026 | OpenCode (Plan y Build) | `programar_respaldo.ps1` y `quitar_respaldo.ps1` | La sección de la spec | Scripts de la tarea programada | **Aceptado con correcciones y 1 descarte** | Ver Entrada 2. `tarea_programada*.txt`. |
| 08/11/2026 | OpenCode (Plan y Build) | `maintenance.sql` (guarda con código 3), matriz de objetivos y READMEs | El código existente y la spec | Guarda con `RAISE EXCEPTION`, matriz y secciones nuevas | **Aceptado con correcciones y 1 descarte** | Ver Entrada 3. `maintenance_v5_guarda.txt` (código 3 en base no permitida, normal en `foodstore_restore_test`). |
| 08/11/2026 | OpenCode (Plan y Build) | Plantilla del informe y secciones U7 y U8 | Informe del TP8 y evidencias de Mongo | HTML con huecos y texto con citas | **Aceptado con correcciones y 1 descarte** | Ver Entrada 4. |
| 08/11/2026 | Claude (chat) | Revisión de cada plan y cada diff de OpenCode antes de aplicarlo | Planes y diffs de OpenCode | Lista de errores y correcciones a pedir | **Aceptado** | Cada observación se verificó contra el motor o el archivo antes de decidir. |

### Apartamientos del flujo de la cátedra (declarados)

- La sección "Programación y retención" de `SPEC_U6.md` y un script de referencia las redactó Claude (chat), en lugar de Kiro. Claude explicó el contenido y Belén lo revisó. El script de referencia no se usó: el código del repo salió de OpenCode, y el de Claude se guardó fuera del repo solo para comparar en la bitácora.
- Se ejecutó el respaldo de roles sin contraseñas (`--no-role-passwords`) y no se le pasaron datos personales a ninguna herramienta.
