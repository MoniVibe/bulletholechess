[CmdletBinding()]
param(
  [string]$BackendUrl = 'http://localhost:8080',
  [string]$Name = '',
  [int]$CooldownSeconds = 3,
  [int]$PollMs = 120,
  [int]$Seed = 0,
  [string]$LogDir = 'debug'
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$dartDefault = 'C:\dev\flutter\bin\dart.bat'
$dartExe = if (Test-Path $dartDefault) { $dartDefault } else { 'dart' }

if ([string]::IsNullOrWhiteSpace($Name)) {
  $Name = "ChessAI-$env:COMPUTERNAME"
}
if ($Seed -le 0) {
  $Seed = Get-Random -Minimum 1 -Maximum 2147483647
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDirectoryPath = Join-Path $repoRoot $LogDir
New-Item -ItemType Directory -Path $logDirectoryPath -Force | Out-Null
$safeName = ($Name -replace '[^a-zA-Z0-9_-]', '_').ToLowerInvariant()
$logFilePath = Join-Path $logDirectoryPath "network-ai-chess-$safeName-$timestamp.jsonl"

Write-Host "Backend: $BackendUrl"
Write-Host "Name: $Name"
Write-Host "Seed: $Seed"
Write-Host "Log file: $logFilePath"
Write-Host ''

& $dartExe run tool\network_ai_duel_client.dart `
  --backend-url="$BackendUrl" `
  --name="$Name" `
  --cooldown-seconds=$CooldownSeconds `
  --poll-ms=$PollMs `
  --seed=$Seed `
  --log-file="$logFilePath"

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
  throw "Network AI duel client failed with exit code $exitCode."
}
