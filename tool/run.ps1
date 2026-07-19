$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'

if (-not (Test-Path -LiteralPath $envFile)) {
  throw 'Missing .env file. Copy .env.example and provide the local values.'
}

$values = @{}
Get-Content -LiteralPath $envFile | ForEach-Object {
  if ($_ -match '^(?<key>[^#=]+)=(?<value>.*)$') {
    $values[$Matches.key.Trim()] = $Matches.value.Trim()
  }
}

$url = $values['NEXT_PUBLIC_SUPABASE_URL']
$key = $values['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']
if (-not $url -or -not $key) {
  throw 'The public Supabase URL and publishable key are required in .env.'
}

Push-Location $root
try {
  flutter run `
    "--dart-define=NEXT_PUBLIC_SUPABASE_URL=$url" `
    "--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$key" `
    @args
}
finally {
  Pop-Location
}
