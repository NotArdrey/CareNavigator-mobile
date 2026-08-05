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
  $flutterArgs = @($args)
  $deviceIndex = [Array]::IndexOf([string[]]$flutterArgs, '-d')
  if ($deviceIndex -lt 0) {
    $deviceIndex = [Array]::IndexOf([string[]]$flutterArgs, '--device-id')
  }

  if ($deviceIndex -ge 0 -and $deviceIndex + 1 -lt $flutterArgs.Count -and $flutterArgs[$deviceIndex + 1] -eq 'chrome') {
    $devices = flutter devices 2>$null | Out-String
    if ($devices -notmatch '(?im)^\s*Chrome\s+.*\bchrome\b') {
      if ($devices -match '(?im)^\s*Edge\s+.*\bedge\b') {
        Write-Warning 'Chrome is not available. Using Edge instead.'
        $flutterArgs[$deviceIndex + 1] = 'edge'
      }
    }
  }

  flutter run `
    "--dart-define=NEXT_PUBLIC_SUPABASE_URL=$url" `
    "--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$key" `
    @flutterArgs
}
finally {
  Pop-Location
}
