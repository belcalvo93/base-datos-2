# quitar_respaldo.ps1 — Borra la tarea "FoodStore_Backup_Diario" si existe.
[CmdletBinding()]
param([string]$TaskName = 'FoodStore_Backup_Diario')

$ErrorActionPreference = 'Stop'

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tarea '$TaskName' eliminada."
} else {
    Write-Host "La tarea '$TaskName' no existía; no hay nada que borrar."
}
