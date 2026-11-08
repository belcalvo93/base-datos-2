# programar_respaldo.ps1 — Registra la tarea "FoodStore_Backup_Diario" (diaria, 21:00)
# Idempotente: si la tarea ya existe, la reemplaza. No guarda ninguna contraseña.
# Uso: powershell -ExecutionPolicy Bypass -File mantenimiento\programar_respaldo.ps1 [-Hora 21:00]

[CmdletBinding()]
param(
    [string]$TaskName = 'FoodStore_Backup_Diario',
    [string]$Hora     = '21:00',
    [string]$BashExe  = ''        # opcional: ruta de bash.exe si no es la estándar
)

$ErrorActionPreference = 'Stop'

# --- Validar la hora ------------------------------------------------------
$horaLimite = [datetime]::MinValue
if (-not [datetime]::TryParse($Hora, [ref]$horaLimite)) {
    throw "Hora inválida: '$Hora'. Usá formato HH:mm, por ejemplo 21:00."
}

# --- Localizar bash.exe de Git for Windows --------------------------------
# El Programador no hereda el PATH de tu terminal, así que la ruta va absoluta.
$candidatos = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe',
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    'C:\Program Files (x86)\Git\bin\bash.exe'
)
if ($BashExe) { $candidatos = @($BashExe) + $candidatos }
$Bash = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Bash) {
    throw "No encontré bash.exe de Git for Windows. Pasá la ruta con -BashExe 'C:\...\bash.exe'."
}

# --- Ruta absoluta del script (desde la ubicación de este .ps1) -----------
$ScriptSh = Join-Path $PSScriptRoot 'backup_foodstore.sh'
$Carpeta  = $PSScriptRoot
if (-not (Test-Path $ScriptSh)) { throw "No existe $ScriptSh" }

# Git Bash entiende rutas estilo Unix; el argumento va entre comillas simples
# para que los espacios ("Program Files", "base datos") no rompan el parseo.
$ScriptUnix = '/' + $ScriptSh.Substring(0,1).ToLower() + $ScriptSh.Substring(2).Replace('\','/')

# --- Aviso (no bloqueante) si falta pgpass.conf ---------------------------
$PgPass = Join-Path $env:APPDATA 'postgresql\pgpass.conf'
if (-not (Test-Path $PgPass)) {
    Write-Warning "No existe $PgPass : la tarea va a fallar con 'no password supplied' (-w)."
}

# --- Acción: bash.exe + script, con ORIGEN=programada y PATH de PostgreSQL -
# bash.exe no hereda el PATH de tu sesión: psql/pg_dump/pg_dumpall viven en
# C:\Program Files\PostgreSQL\17\bin y grep/sed/stat en el usr\bin de Git.
# $Comando va entre comillas simples para que PowerShell no expanda $PATH (lo expande bash).
$Comando   = 'export PATH="$PATH:/c/Program Files/PostgreSQL/17/bin"; export ORIGEN=programada; exec bash "' + $ScriptUnix + '"'
$Argumento = "-c '" + $Comando + "'"
$Accion    = New-ScheduledTaskAction -Execute $Bash -Argument $Argumento -WorkingDirectory $Carpeta
Write-Host "Comando de la tarea: $Argumento"

# --- Disparador diario a las 21:00 ----------------------------------------
$Disparador = New-ScheduledTaskTrigger -Daily -At $horaLimite

# --- Ajustes: corre aunque la PC estaba apagada; una instancia a la vez ----
$Ajustes = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# --- Usuario actual, solo con sesión iniciada, sin contraseña guardada -----
$Principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

# --- Registrar (o reemplazar si ya existe) --------------------------------
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Accion -Trigger $Disparador -Settings $Ajustes -Principal $Principal `
    -Description 'Respaldo diario de foodstore (backup_foodstore.sh). Corre a las 21:00 o al encender la PC.' `
    -Force | Out-String | Write-Host

Write-Host "`nTarea registrada:"
Get-ScheduledTask -TaskName $TaskName | Format-List TaskName, State, @{n='Hora';e={$_.Triggers.StartBoundary}}, @{n='Accion';e={$_.Actions.Execute}} | Out-String | Write-Host
Get-ScheduledTaskInfo -TaskName $TaskName | Format-List LastRunTime, LastTaskResult | Out-String | Write-Host
