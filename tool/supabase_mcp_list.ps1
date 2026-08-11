param(
  [Parameter(Mandatory = $true)]
  [string]$ToolName,

  [string]$ArgumentsJson = '{}'
)

$ErrorActionPreference = 'Stop'

$accessToken = [Environment]::GetEnvironmentVariable(
  'SUPABASE_ACCESS_TOKEN',
  'User'
)
if ([string]::IsNullOrWhiteSpace($accessToken)) {
  throw 'SUPABASE_ACCESS_TOKEN is not configured in the user environment.'
}

$endpoint = 'https://mcp.supabase.com/mcp?project_ref=crhsbpkuteyqbxjpozrp&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching'
$headers = @{
  Authorization = "Bearer $accessToken"
  Accept = 'application/json, text/event-stream'
}

$initializePayload = @{
  jsonrpc = '2.0'
  id = 1
  method = 'initialize'
  params = @{
    protocolVersion = '2025-06-18'
    capabilities = @{}
    clientInfo = @{
      name = 'care-navigator-contract-check'
      version = '1.0'
    }
  }
} | ConvertTo-Json -Depth 8 -Compress

$initializeResponse = Invoke-WebRequest `
  -UseBasicParsing `
  -Method Post `
  -Uri $endpoint `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $initializePayload

$headers['Mcp-Session-Id'] = $initializeResponse.Headers['Mcp-Session-Id']
$initializedPayload = @{
  jsonrpc = '2.0'
  method = 'notifications/initialized'
  params = @{}
} | ConvertTo-Json -Depth 5 -Compress

$null = Invoke-WebRequest `
  -UseBasicParsing `
  -Method Post `
  -Uri $endpoint `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $initializedPayload

$arguments = $ArgumentsJson | ConvertFrom-Json
$toolPayload = @{
  jsonrpc = '2.0'
  id = 2
  method = 'tools/list'
  params = @{
    name = $ToolName
    arguments = $arguments
  }
} | ConvertTo-Json -Depth 30 -Compress

$toolResponse = Invoke-WebRequest `
  -UseBasicParsing `
  -Method Post `
  -Uri $endpoint `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body $toolPayload

$toolResponse.Content

