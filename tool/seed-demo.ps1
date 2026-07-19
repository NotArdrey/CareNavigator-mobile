$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$seedFile = Join-Path $root 'supabase\seed.sql'

if (-not (Test-Path -LiteralPath $envFile)) {
  throw 'Missing .env file.'
}

$values = @{}
Get-Content -LiteralPath $envFile | ForEach-Object {
  if ($_ -match '^(?<key>[^#=]+)=(?<value>.*)$') {
    $values[$Matches.key.Trim()] = $Matches.value.Trim()
  }
}

$projectId = $values['SUPABASE_PROJECT_ID']
$accessToken = $values['SUPABASE_ACCESS_TOKEN']
if (-not $projectId -or -not $accessToken) {
  throw 'SUPABASE_PROJECT_ID and SUPABASE_ACCESS_TOKEN are required in .env.'
}

$headers = @{
  Authorization = "Bearer $accessToken"
  'Content-Type' = 'application/json'
}
$uri = "https://api.supabase.com/v1/projects/$projectId/database/query"

$demoIds = @(
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005',
  '10000000-0000-4000-8000-000000000006'
)
$quotedIds = ($demoIds | ForEach-Object { "'$_'" }) -join ','
$deleteSql = @"
delete from public.medical_records where id in ('70000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000002');
delete from public.consultations where id in ('60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000003');
delete from public.doctor_patient_assignments where id = '50000000-0000-4000-8000-000000000001';
delete from public.doctors where id in ('30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002');
delete from public.patients where id = '40000000-0000-4000-8000-000000000001';
delete from auth.users where id in ($quotedIds);
"@
$deleteBody = @{ query = $deleteSql } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $deleteBody | Out-Null

$keys = Invoke-RestMethod -Method Get `
  -Uri "https://api.supabase.com/v1/projects/$projectId/api-keys?reveal=true" `
  -Headers @{ Authorization = "Bearer $accessToken" }
$serviceRoleKey = ($keys | Where-Object { $_.name -eq 'service_role' }).api_key
if (-not $serviceRoleKey) {
  throw 'Could not obtain the Supabase service-role key.'
}

$authHeaders = @{
  apikey = $serviceRoleKey
  Authorization = "Bearer $serviceRoleKey"
  'Content-Type' = 'application/json'
}
$authUrl = "$($values['NEXT_PUBLIC_SUPABASE_URL'])/auth/v1/admin/users"
$accounts = @(
  @{ id=$demoIds[0]; email='admin@demo.test'; first_name='Demo'; last_name='Admin' },
  @{ id=$demoIds[1]; email='hospital@demo.test'; first_name='Hospital'; last_name='Admin' },
  @{ id=$demoIds[2]; email='doctor@demo.test'; first_name='Maria'; last_name='Santos' },
  @{ id=$demoIds[3]; email='patient@demo.test'; first_name='Juan'; last_name='Dela Cruz' },
  @{ id=$demoIds[4]; email='guest@demo.test'; first_name='Guest'; last_name='User' }
  @{ id=$demoIds[5]; email='history.doctor@demo.test'; first_name='Elena'; last_name='Reyes' }
)
foreach ($account in $accounts) {
  $accountBody = @{
    id = $account.id
    email = $account.email
    password = 'pass123'
    email_confirm = $true
    user_metadata = @{
      first_name = $account.first_name
      last_name = $account.last_name
    }
  } | ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri $authUrl -Headers $authHeaders -Body $accountBody | Out-Null
}

$sql = [System.IO.File]::ReadAllText($seedFile)
$body = @{ query = $sql } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body | Out-Null
Write-Host 'CareNavigator demo data seeded successfully.'
Write-Host 'All demo accounts use password: pass123'
