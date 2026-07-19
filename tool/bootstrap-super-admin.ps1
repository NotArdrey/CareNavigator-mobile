param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [ValidateLength(12, 200)]
  [string]$Password,

  [Parameter(Mandatory = $true)]
  [ValidateLength(1, 100)]
  [string]$FirstName,

  [Parameter(Mandatory = $true)]
  [ValidateLength(1, 100)]
  [string]$LastName
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $root '.env'

if (-not (Test-Path -LiteralPath $envPath)) {
  throw 'The local .env file is missing.'
}

$config = @{}
Get-Content -LiteralPath $envPath | ForEach-Object {
  if ($_ -match '^[^#][^=]*=') {
    $pair = $_ -split '=', 2
    $config[$pair[0]] = $pair[1]
  }
}

foreach ($name in @(
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
  'ADMIN_BOOTSTRAP_TOKEN'
)) {
  if ([string]::IsNullOrWhiteSpace($config[$name])) {
    throw "$name is missing from .env."
  }
}

$headers = @{
  apikey = $config['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']
  'x-bootstrap-token' = $config['ADMIN_BOOTSTRAP_TOKEN']
}
$body = @{
  action = 'bootstrap_super_admin'
  email = $Email.Trim().ToLowerInvariant()
  password = $Password
  first_name = $FirstName.Trim()
  last_name = $LastName.Trim()
} | ConvertTo-Json

try {
  $result = Invoke-RestMethod `
    -Method Post `
    -Uri "$($config['NEXT_PUBLIC_SUPABASE_URL'])/functions/v1/admin-users" `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body $body
  Write-Host $result.message
  Write-Host 'Sign in through CareNavigator, then rotate or remove ADMIN_BOOTSTRAP_TOKEN.'
} catch {
  $detail = $_.ErrorDetails.Message
  if (-not [string]::IsNullOrWhiteSpace($detail)) {
    try {
      $parsed = $detail | ConvertFrom-Json
      throw $parsed.error
    } catch [System.ArgumentException] {
      throw $detail
    }
  }
  throw
}
