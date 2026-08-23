param(
  [ValidateSet('edge', 'windows', 'web-server')]
  [string]$Target = 'edge',
  [switch]$Release
)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $projectRoot 'env'

if (-not (Test-Path -LiteralPath $configPath)) {
  throw "Missing $configPath. Copy env.example to env and fill in the public Supabase values."
}

$config = @{}
foreach ($line in Get-Content -LiteralPath $configPath) {
  if ($line -match '^\s*([^#=][^=]*)=(.*)$') {
    $config[$matches[1].Trim()] = $matches[2].Trim()
  }
}

$supabaseUrl = $config['NEXT_PUBLIC_SUPABASE_URL']
$supabaseKey = $config['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or
    [string]::IsNullOrWhiteSpace($supabaseKey) -or
    $supabaseUrl -match 'your-project-ref' -or
    $supabaseKey -match 'your-publishable-key') {
  throw 'Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in env before running the app.'
}

$flutterArguments = @(
  'run'
)

if ($Release) {
  $flutterArguments += '--release'
}

$flutterArguments += @(
  '-d',
  $Target,
  "--dart-define=NEXT_PUBLIC_SUPABASE_URL=$supabaseUrl",
  "--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$supabaseKey"
)

if ($Target -eq 'web-server') {
  $flutterArguments += @('--web-hostname', '127.0.0.1', '--web-port', '7357')
}

Push-Location $projectRoot
try {
  & flutter @flutterArguments
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
