param([string]$InterfaceAlias = 'Wi-Fi')
$ErrorActionPreference = 'Stop'
if ($InterfaceAlias.Contains('"')) { throw 'InterfaceAlias must not contain a double quote.' }
$taplateUv = (Get-Command uv -ErrorAction Stop).Source
$taplateLauncher = Join-Path $PSScriptRoot 'start-mdns.ps1'
$taplateUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$taplateArguments = '-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}" -UvPath "{1}" -InterfaceAlias "{2}"' -f $taplateLauncher, $taplateUv, $InterfaceAlias
$taplateAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taplateArguments -WorkingDirectory (Split-Path $PSScriptRoot)
$taplateTrigger = New-ScheduledTaskTrigger -AtLogOn -User $taplateUser
$taplatePrincipal = New-ScheduledTaskPrincipal -UserId $taplateUser -LogonType Interactive -RunLevel Limited
$taplateSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$taplateExisting = Get-ScheduledTask -TaskName 'tap-late mDNS' -ErrorAction SilentlyContinue
if ($taplateExisting -and ($taplateExisting.Actions.Arguments -notlike '*start-mdns.ps1*')) {
    throw 'An unrelated task already uses the name tap-late mDNS.'
}
Register-ScheduledTask -TaskName 'tap-late mDNS' -Description 'Advertise tap-late.local:8000 on the selected LAN interface.' -Action $taplateAction -Trigger $taplateTrigger -Principal $taplatePrincipal -Settings $taplateSettings -Force | Out-Null
Start-ScheduledTask -TaskName 'tap-late mDNS'
Get-ScheduledTask -TaskName 'tap-late mDNS' | Select-Object TaskName,State
