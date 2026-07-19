param(
  [string]$EnvFile = '.env'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) {
  $EnvFile
} else {
  Join-Path $root $EnvFile
}

if (-not (Test-Path -LiteralPath $envPath)) {
  throw "Environment file not found: $envPath"
}

$config = @{}
Get-Content -LiteralPath $envPath | ForEach-Object {
  if ($_ -match '^[A-Za-z_][A-Za-z0-9_]*=') {
    $pair = $_ -split '=', 2
    $config[$pair[0]] = $pair[1].Trim()
  }
}

foreach ($name in @(
  'SUPABASE_PROJECT_ID',
  'SUPABASE_ACCESS_TOKEN',
  'SMTP_USERNAME',
  'SMTP_PASSWORD',
  'NOTIFICATION_FROM_EMAIL'
)) {
  if ([string]::IsNullOrWhiteSpace($config[$name])) {
    throw "$name is missing from $envPath."
  }
}

$smtpHost = if ($config['SMTP_HOST']) { $config['SMTP_HOST'] } else { 'smtp.gmail.com' }
$smtpPort = if ($config['SMTP_PORT']) { $config['SMTP_PORT'] } else { '465' }
if ($smtpPort -notmatch '^\d+$' -or [int]$smtpPort -lt 1 -or [int]$smtpPort -gt 65535) {
  throw 'SMTP_PORT must be a valid TCP port.'
}

$fromValue = $config['NOTIFICATION_FROM_EMAIL']
$fromEmail = $fromValue
$senderName = 'CareNavigator PH'
if ($fromValue -match '^\s*(.*?)\s*<([^<>\s]+@[^<>\s]+)>\s*$') {
  if (-not [string]::IsNullOrWhiteSpace($Matches[1])) {
    $senderName = $Matches[1].Trim(' ', '"')
  }
  $fromEmail = $Matches[2]
}

if ($fromEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
  throw 'NOTIFICATION_FROM_EMAIL must be an email address or Name <email@example.com>.'
}

$projectRef = $config['SUPABASE_PROJECT_ID']
$headers = @{
  Authorization = "Bearer $($config['SUPABASE_ACCESS_TOKEN'])"
}

$edgeSecrets = @(
  @{ name = 'SMTP_HOST'; value = $smtpHost },
  @{ name = 'SMTP_PORT'; value = $smtpPort },
  @{ name = 'SMTP_USERNAME'; value = $config['SMTP_USERNAME'] },
  @{ name = 'SMTP_PASSWORD'; value = $config['SMTP_PASSWORD'] },
  @{ name = 'NOTIFICATION_FROM_EMAIL'; value = $fromValue }
)
if (-not [string]::IsNullOrWhiteSpace($config['APP_BASE_URL'])) {
  $edgeSecrets += @{ name = 'APP_BASE_URL'; value = $config['APP_BASE_URL'] }
}

Invoke-RestMethod `
  -Method Post `
  -Uri "https://api.supabase.com/v1/projects/$projectRef/secrets" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body ($edgeSecrets | ConvertTo-Json) | Out-Null

$authConfig = @{
  external_email_enabled = $true
  external_phone_enabled = $false
  hook_send_sms_enabled = $false
  sms_autoconfirm = $false
  mfa_phone_enroll_enabled = $false
  mfa_phone_verify_enabled = $false
  smtp_admin_email = $fromEmail
  smtp_host = $smtpHost
  smtp_port = $smtpPort
  smtp_user = $config['SMTP_USERNAME']
  smtp_pass = $config['SMTP_PASSWORD']
  smtp_sender_name = $senderName
  mailer_otp_length = 6
  mailer_otp_exp = 600
  mailer_subjects_magic_link = 'Your CareNavigator verification code'
  mailer_templates_magic_link_content = '<h2>Your CareNavigator verification code</h2><p>Enter this code in the app:</p><p style="font-size:24px;font-weight:700;letter-spacing:4px">{{ .Token }}</p><p>This code expires in 10 minutes.</p>'
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Patch `
  -Uri "https://api.supabase.com/v1/projects/$projectRef/config/auth" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $authConfig | Out-Null

Write-Host 'Gmail SMTP is configured for notification email and Supabase email verification.'
Write-Host 'The app password remained server-side and was not added to the Flutter build.'
