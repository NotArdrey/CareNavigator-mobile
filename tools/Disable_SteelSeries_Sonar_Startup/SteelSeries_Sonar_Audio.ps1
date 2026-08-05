[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable', 'SetDefault')]
    [string]$Action,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$soundVolumeView = Join-Path $packageDirectory 'SoundVolumeView.exe'

# These are the complete names shown in the Windows sound-device list.
# Do not shorten these strings: exact matching is intentional.
$targetNames = [ordered]@{
    'SteelSeries Sonar - Gaming (SteelSeries Sonar Virtual Audio Device)'    = @('Render')
    'SteelSeries Sonar - Chat (SteelSeries Sonar Virtual Audio Device)'       = @('Render')
}
$microphoneTargetName = 'SteelSeries Sonar - Microphone (SteelSeries Sonar Virtual Audio Device)'
$defaultTargetName = 'XG27ACS (NVIDIA High Definition Audio)'

function Write-Status {
    param([string]$Message)

    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Get-ExportField {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Row.PSObject.Properties[$name]
        if ($null -ne $property) {
            return ([string]$property.Value).Trim()
        }
    }

    return ''
}

function Get-ExactDeviceMatches {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    return @(
        $Rows | Where-Object {
            $type = Get-ExportField -Row $_ -Names @('Type')
            if ($type -ne 'Device') {
                return $false
            }

            $name = Get-ExportField -Row $_ -Names @('Name')
            $deviceName = Get-ExportField -Row $_ -Names @('Device Name', 'DeviceName')
            $combinedName = if ($deviceName) { "$name ($deviceName)" } else { $name }

            # Match the complete exported name, never a substring.
            return (
                [string]::Equals($name, $Target, [StringComparison]::Ordinal) -or
                [string]::Equals($combinedName, $Target, [StringComparison]::Ordinal)
            )
        }
    )
}

if (-not (Test-Path -LiteralPath $soundVolumeView -PathType Leaf)) {
    Write-Error "SoundVolumeView.exe was not found next to this script: $soundVolumeView"
    exit 2
}

$csvPath = Join-Path ([IO.Path]::GetTempPath()) (
    'DisableSteelSeriesSonar-{0}-{1}.csv' -f $PID, ([Guid]::NewGuid().ToString('N'))
)
$problems = 0

try {
    Write-Status "Reading the SoundVolumeView device list..."

    # Export the live list, including disabled devices, so Enable also works.
    $exportArguments = @(
        '/ShowDisabledDevices'
        '1'
        '/SaveFileEncoding'
        '3'
        '/scomma'
        ('"' + $csvPath + '"')
    )
    $exportProcess = Start-Process -FilePath $soundVolumeView -ArgumentList $exportArguments -WindowStyle Hidden -Wait -PassThru

    if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        throw "SoundVolumeView did not create its device-list export. Exit code: $($exportProcess.ExitCode)"
    }

    $rows = @(Import-Csv -LiteralPath $csvPath)

    if ($Action -ne 'SetDefault') {
        foreach ($target in $targetNames.Keys) {
            $matches = @(Get-ExactDeviceMatches -Rows $rows -Target ([string]$target))

            if ($matches.Count -eq 0) {
                Write-Status "Not found; no action taken: $target"
                continue
            }

            # Some Windows audio endpoints expose the same friendly name for
            # both Capture and Render. Use the intended direction when needed.
            $preferredDirections = @($targetNames[$target])
            if ($matches.Count -gt 1 -and $preferredDirections.Count -gt 0) {
                $directionMatches = @(
                    $matches | Where-Object {
                        $candidateId = Get-ExportField -Row $_ -Names @(
                            'Command-Line Friendly ID'
                            'Command-LineFriendlyID'
                        )
                        foreach ($direction in $preferredDirections) {
                            if ($candidateId.EndsWith(('\' + $direction), [StringComparison]::OrdinalIgnoreCase)) {
                                return $true
                            }
                        }
                        return $false
                    }
                )
                if ($directionMatches.Count -gt 0) {
                    $matches = $directionMatches
                }
            }

            $allowMultipleDirections = $preferredDirections.Count -gt 1
            if ($matches.Count -ne 1 -and -not $allowMultipleDirections) {
                Write-Status "Skipped because the exact name was ambiguous ($($matches.Count) matches): $target"
                $problems++
                continue
            }

            Write-Status "$Action`: $target ($($matches.Count) endpoint(s))"
            foreach ($match in $matches) {
                $friendlyId = Get-ExportField -Row $match -Names @(
                    'Command-Line Friendly ID'
                    'Command-LineFriendlyID'
                )
                if ([string]::IsNullOrWhiteSpace($friendlyId)) {
                    Write-Status "Skipped because no Command-Line Friendly ID was exported: $target"
                    $problems++
                    continue
                }

                # Pass the resolved friendly ID to /Disable or /Enable. This avoids
                # SoundVolumeView's normal partial-name lookup behavior.
                $actionArguments = @(
                    ("/{0}" -f $Action)
                    ('"' + $friendlyId + '"')
                )
                $actionProcess = Start-Process -FilePath $soundVolumeView -ArgumentList $actionArguments -WindowStyle Hidden -Wait -PassThru
                if ($actionProcess.ExitCode -ne 0) {
                    Write-Status "  SoundVolumeView returned exit code $($actionProcess.ExitCode)."
                    $problems++
                }
            }
        }
    }

    # Keep the exact Sonar Microphone endpoints enabled and make the Capture
    # endpoint the default input. This is intentionally separate from the
    # Gaming/Chat disable list.
    if ($Action -eq 'Disable' -or $Action -eq 'Enable') {
        $microphoneMatches = @(Get-ExactDeviceMatches -Rows $rows -Target $microphoneTargetName)

        if ($microphoneMatches.Count -eq 0) {
            Write-Status "Microphone not found; no microphone/default-input change taken: $microphoneTargetName"
            $problems++
        }
        else {
            $captureMatches = @(
                $microphoneMatches | Where-Object {
                    $candidateId = Get-ExportField -Row $_ -Names @(
                        'Command-Line Friendly ID'
                        'Command-LineFriendlyID'
                    )
                    $candidateId.EndsWith('\Capture', [StringComparison]::OrdinalIgnoreCase)
                }
            )

            Write-Status "Enable: $microphoneTargetName ($($microphoneMatches.Count) endpoint(s))"
            foreach ($microphoneMatch in $microphoneMatches) {
                $microphoneId = Get-ExportField -Row $microphoneMatch -Names @(
                    'Command-Line Friendly ID'
                    'Command-LineFriendlyID'
                )
                if ([string]::IsNullOrWhiteSpace($microphoneId)) {
                    Write-Status "Skipped microphone endpoint because no Command-Line Friendly ID was exported."
                    $problems++
                    continue
                }

                $enableArguments = @(
                    '/Enable'
                    ('"' + $microphoneId + '"')
                )
                $enableProcess = Start-Process -FilePath $soundVolumeView -ArgumentList $enableArguments -WindowStyle Hidden -Wait -PassThru
                if ($enableProcess.ExitCode -ne 0) {
                    Write-Status "  SoundVolumeView returned exit code $($enableProcess.ExitCode)."
                    $problems++
                }
            }

            if ($captureMatches.Count -eq 1) {
                $captureId = Get-ExportField -Row $captureMatches[0] -Names @(
                    'Command-Line Friendly ID'
                    'Command-LineFriendlyID'
                )
                Write-Status "Set default microphone: $microphoneTargetName"
                $captureDefaultArguments = @(
                    '/SetDefault'
                    ('"' + $captureId + '"')
                    'all'
                )
                $captureDefaultProcess = Start-Process -FilePath $soundVolumeView -ArgumentList $captureDefaultArguments -WindowStyle Hidden -Wait -PassThru
                if ($captureDefaultProcess.ExitCode -ne 0) {
                    Write-Status "  SoundVolumeView returned exit code $($captureDefaultProcess.ExitCode)."
                    $problems++
                }
            }
            elseif ($captureMatches.Count -eq 0) {
                Write-Status "Default microphone skipped because no Capture endpoint was found: $microphoneTargetName"
                $problems++
            }
            else {
                Write-Status "Default microphone skipped because the Capture name was ambiguous ($($captureMatches.Count) matches)."
                $problems++
            }
        }
    }

    # After a disable pass, explicitly make the requested NVIDIA monitor audio
    # endpoint the default render device. SetDefault is never used on Sonar.
    if ($Action -eq 'Disable' -or $Action -eq 'SetDefault') {
        $defaultMatches = @(Get-ExactDeviceMatches -Rows $rows -Target $defaultTargetName)

        if ($defaultMatches.Count -eq 0) {
            Write-Status "Default device not found; no default change taken: $defaultTargetName"
            $problems++
        }
        elseif ($defaultMatches.Count -ne 1) {
            Write-Status "Default device skipped because the exact name was ambiguous ($($defaultMatches.Count) matches): $defaultTargetName"
            $problems++
        }
        else {
            $defaultFriendlyId = Get-ExportField -Row $defaultMatches[0] -Names @(
                'Command-Line Friendly ID'
                'Command-LineFriendlyID'
            )
            if ([string]::IsNullOrWhiteSpace($defaultFriendlyId)) {
                Write-Status "Default device skipped because no Command-Line Friendly ID was exported: $defaultTargetName"
                $problems++
            }
            else {
                Write-Status "Set default playback device: $defaultTargetName"
                $defaultArguments = @(
                    '/SetDefault'
                    ('"' + $defaultFriendlyId + '"')
                    'all'
                )
                $defaultProcess = Start-Process -FilePath $soundVolumeView -ArgumentList $defaultArguments -WindowStyle Hidden -Wait -PassThru
                if ($defaultProcess.ExitCode -ne 0) {
                    Write-Status "  SoundVolumeView returned exit code $($defaultProcess.ExitCode)."
                    $problems++
                }
            }
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if (Test-Path -LiteralPath $csvPath) {
        Remove-Item -LiteralPath $csvPath -Force -ErrorAction SilentlyContinue
    }
}

if ($problems -gt 0) {
    exit 1
}

exit 0
