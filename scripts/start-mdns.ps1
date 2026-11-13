param(
    [Parameter(Mandatory = $true)][string]$UvPath,
    [string]$InterfaceAlias = 'Wi-Fi'
)
$ErrorActionPreference = 'Stop'
$taplateMdnsScript = Join-Path $PSScriptRoot 'advertise-mdns.py'
$taplateMdnsLog = Join-Path $env:LOCALAPPDATA 'tap-late/mdns.log'
& $UvPath run --script $taplateMdnsScript --interface $InterfaceAlias --log $taplateMdnsLog
exit $LASTEXITCODE
