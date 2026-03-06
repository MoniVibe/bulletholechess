param(
  [switch]$Online,
  [string]$BackendUrl = 'http://localhost:8080',
  [string]$Name = 'ChessUiBot',
  [int]$Moves = 10,
  [int]$MaxSeconds = 180,
  [int]$IdleSeconds = 45
)

$defs = @(
  "UI_BOT_ONLINE=$([int]$Online.IsPresent)",
  "BOT_BACKEND_URL=$BackendUrl",
  "BOT_NAME=$Name",
  "BOT_MAX_MOVES=$Moves",
  "BOT_MAX_SECONDS=$MaxSeconds",
  "BOT_IDLE_SECONDS=$IdleSeconds"
)

$dartDefineArgs = @()
foreach ($def in $defs) {
  $dartDefineArgs += '--dart-define'
  $dartDefineArgs += $def
}

flutter test integration_test/chess_ui_bot_smoke_test.dart @dartDefineArgs
