# TP Unidad 6 — Mantenimiento, respaldo y recuperación de Food Store

Plan completo en [`SPEC_U6.md`](SPEC_U6.md). Cada integrante corre las pruebas en su PC
y guarda sus resultados en **su propia carpeta** `evidencias/<nombre>/`.

## Requisitos

- PostgreSQL 16+ (`psql`, `pg_dump`, `pg_restore`, `createdb` en el PATH) y Git Bash
- La base `bd2_tp3` con la carga masiva. Si no la tenés, pedile a Belén el `.dump` y restaurala:
  `createdb -U postgres bd2_tp3 && pg_restore -U postgres -d bd2_tp3 --no-owner ARCHIVO.dump`

## Paso a paso (desde la raíz del repo, en tu rama)

```bash
# 0. Tu nombre y tu carpeta de evidencias
NOMBRE=tunombre          # hernan / elias / bruno
E=mantenimiento/evidencias/$NOMBRE
mkdir -p "$E"

# 1. Contraseña fuera del repo (no se ve al tipear). Se hace una sola vez.
mkdir -p "$APPDATA/postgresql"
read -s -p "Contraseña de postgres: " PW; echo
echo "localhost:5432:*:postgres:$PW" > "$APPDATA/postgresql/pgpass.conf"; unset PW

# 2. Base principal foodstore (copia de bd2_tp3; cerrar pgAdmin/DBeaver antes)
createdb -U postgres -T bd2_tp3 foodstore

# 3. Conteo de referencia ANTES del respaldo
psql -U postgres -d foodstore -X -c "SELECT current_database(), now();" -c "
SELECT 'categoria' AS tabla, COUNT(*) AS filas FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;" > "$E/conteo_antes_respaldo.txt"

# 4. Respaldo (y prueba de error con una base inexistente)
./mantenimiento/backup_foodstore.sh
DB_NAME=base_inexistente ./mantenimiento/backup_foodstore.sh; echo "Código de salida: $?"

# 5. Chequeo de salud y mantenimiento
psql -U postgres -d foodstore -X -f mantenimiento/health_check.sql > "$E/health_check_salida.txt"
psql -U postgres -d foodstore -X -f mantenimiento/maintenance.sql  > "$E/maintenance_salida.txt" 2>&1

# 6. Simulacro de restauración (solo toca foodstore_restore_test)
./mantenimiento/restore_test.sh

# 7. Mover tus resultados a tu carpeta y dejar intactos los de Belén
cp mantenimiento/logs/backup_foodstore.log mantenimiento/logs/restore_test.log \
   mantenimiento/evidencias/restore_test_salida.txt "$E/"
git restore mantenimiento/logs mantenimiento/evidencias/restore_test_salida.txt

# 8. Subir solo tu carpeta
git add "$E"
git commit -m "TP6: evidencias de $NOMBRE"
git push
```

## Para el informe, pasale a Belén

De `"$E/restore_test_salida.txt"`: respaldo usado, **RTO observado**, **antigüedad del respaldo (RPO)**,
resultado de las validaciones y cualquier problema que te haya aparecido.

## Reglas

- Nunca restaurar ni borrar `foodstore`: los scripts solo destruyen `foodstore_restore_test`.
- No subir `.dump` ni contraseñas. No usar `VACUUM FULL`.
