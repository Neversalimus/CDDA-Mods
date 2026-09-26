param([string]$ModRoot,[string]$BackupRoot)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $BackupRoot | Out-Null
function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function ConvertTo-JsonArraySafe {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,
        [int]$Depth = 100
    )

    $parts = @()
    foreach ($item in $Items) {
        $parts += (ConvertTo-Json -InputObject $item -Depth $Depth)
    }
    if ($parts.Count -eq 0) {
        return '[]'
    }
    return "[`r`n" + ($parts -join ",`r`n") + "`r`n]"
}

function Find-GameRoot {
    param([string]$ExplicitRoot)

    if ($ExplicitRoot) {
        if (-not (Test-Path -LiteralPath (Join-Path $ExplicitRoot 'data\mods'))) {
            throw "GameRoot does not contain data\mods: $ExplicitRoot"
        }
        return (Resolve-Path -LiteralPath $ExplicitRoot).Path
    }

    $base = Join-Path $env:LOCALAPPDATA 'com.munetmo.cat-launcher\Assets\DarkDaysAhead'
    if (-not (Test-Path -LiteralPath $base)) {
        throw "CatLauncher DDA folder not found: $base"
    }

    $preferred = Join-Path $base 'cdda_experimental_2026_09_23_0546'
    if (Test-Path -LiteralPath (Join-Path $preferred 'data\mods')) {
        return $preferred
    }

    $hit = Get-ChildItem -LiteralPath $base -Directory -Filter 'cdda_experimental_*' |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'data\mods') } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $hit) {
        throw 'No experimental CDDA installation found.'
    }
    return $hit.FullName
}

function Get-DurationSecondsApprox {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0.0
    }

    if ($Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal]) {
        return [double]$Value
    }

    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) {
        return 0.0
    }

    # CDDA time_duration strings can contain multiple number+unit pairs.
    # Approximate only enough to identify zero/sub-one-turn durations.
    $matches = [regex]::Matches(
        $s,
        '([+-]?\d+(?:\.\d+)?)\s*(turns?|t|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($matches.Count -eq 0) {
        # Plain numeric string: time_duration's base unit is turns/seconds.
        $n = 0.0
        if ([double]::TryParse(
            $s,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$n
        )) {
            return $n
        }
        return $null
    }

    $total = 0.0
    foreach ($m in $matches) {
        $n = [double]::Parse(
            $m.Groups[1].Value,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $u = $m.Groups[2].Value.ToLowerInvariant()

        if ($u -match '^(turn|turns|t|second|seconds|sec|secs|s)$') {
            $total += $n
        } elseif ($u -match '^(minute|minutes|min|mins|m)$') {
            $total += $n * 60.0
        } elseif ($u -match '^(hour|hours|hr|hrs|h)$') {
            $total += $n * 3600.0
        } elseif ($u -match '^(day|days|d)$') {
            $total += $n * 86400.0
        } elseif ($u -match '^(week|weeks|w)$') {
            $total += $n * 604800.0
        }
    }

    return $total
}

function Clear-GeneratedCache {
    param([string]$Root)

    foreach ($cachePath in @(
        (Join-Path $Root 'data\cache'),
        (Join-Path $Root 'cache')
    ) | Select-Object -Unique) {
        if (Test-Path -LiteralPath $cachePath) {
            Remove-Item -LiteralPath $cachePath -Recurse -Force
            Write-Host "Removed generated cache: $cachePath" -ForegroundColor Green
        }
    }
}

    Write-Step 'Scanning installed Secronom monster definitions'
    Write-Host 'v1.5.1 uses only native PowerShell arrays in the scanner; Generic.List binder paths from v1.5 were removed.' -ForegroundColor DarkGray
    $jsonFiles = Get-ChildItem -LiteralPath $modRoot -Recurse -File -Filter '*.json'
    $patchLog = @()
    $filesChanged = 0
    $entriesChanged = 0
    $emitFieldsSeen = 0
    $positiveEntries = 0
    $parseFailures = 0

    foreach ($file in $jsonFiles) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw

        # Fast pre-filter: most Secronom JSON files do not contain emit_fields.
        if ($raw -notmatch '"emit_fields"\s*:') {
            continue
        }

        $data = $null
        try {
            $data = $raw | ConvertFrom-Json
        } catch {
            $parseFailures++
            $patchLog += "PARSE_FAIL`t$($file.FullName)`t$($_.Exception.Message)"
            continue
        }

        $objects = @($data)
        $changedHere = $false

        foreach ($obj in $objects) {
            if ($null -eq $obj) { continue }
            $prop = $obj.PSObject.Properties['emit_fields']
            if ($null -eq $prop) { continue }

            $monsterId = if ($obj.PSObject.Properties['id']) { [string]$obj.id } else { '<no id>' }
            $emitEntries = @($obj.emit_fields)
            $rebuilt = @()

            foreach ($entry in $emitEntries) {
                $emitFieldsSeen++

                if ($entry -is [string]) {
                    $rebuilt += [pscustomobject][ordered]@{
                        emit_id = [string]$entry
                        delay = '1 s'
                    }

                    $entriesChanged++
                    $changedHere = $true
                    $patchLog += "PATCH`t$($file.FullName)`t$monster=$monsterId`temit=$entry`told=<string shorthand / implicit 0>`tnew=1 s"
                    continue
                }

                if ($entry -is [pscustomobject]) {
                    $emitId = if ($entry.PSObject.Properties['emit_id']) { [string]$entry.emit_id } else { '<missing emit_id>' }
                    $delayProp = $entry.PSObject.Properties['delay']
                    $needsPatch = $false
                    $reason = ''
                    $oldDelay = '<missing>'

                    if ($null -eq $delayProp) {
                        $needsPatch = $true
                        $reason = 'missing delay'
                    } else {
                        $oldDelay = [string]$entry.delay
                        $seconds = Get-DurationSecondsApprox -Value $entry.delay
                        if ($null -ne $seconds -and $seconds -lt 1.0) {
                            $needsPatch = $true
                            $reason = "delay resolves below one turn ($seconds s)"
                        }
                    }

                    if ($needsPatch) {
                        $entry | Add-Member -NotePropertyName delay -NotePropertyValue '1 s' -Force
                        $entriesChanged++
                        $changedHere = $true
                        $patchLog += "PATCH`t$($file.FullName)`t$monster=$monsterId`temit=$emitId`told=$oldDelay`tnew=1 s`treason=$reason"
                    } else {
                        $positiveEntries++
                        $patchLog += "OK`t$($file.FullName)`t$monster=$monsterId`temit=$emitId`tdelay=$oldDelay"
                    }

                    $rebuilt += $entry
                    continue
                }

                # Preserve anything unexpected unchanged and log it.
                $rebuilt += $entry
                $patchLog += "UNKNOWN_FORMAT`t$($file.FullName)`tmonster=$monsterId`tvalue=$entry"
            }

            if ($changedHere) {
                $obj.emit_fields = @($rebuilt)
            }
        }

        if ($changedHere) {
            $relative = $file.FullName.Substring($modRoot.Length).TrimStart('\')
            $backupPath = Join-Path $backupRoot $relative
            $backupDir = Split-Path -Parent $backupPath
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $backupPath -Force

            Write-Utf8NoBom -Path $file.FullName -Text (ConvertTo-JsonArraySafe -Items @($objects) -Depth 100)
            $filesChanged++
        }
    }

    $patchLogPath = Join-Path $BackupRoot 'emit-patch-log.txt'
    $summary = @()
    $summary += "Secronom Revival v1.5 emit_fields runtime hotfix"
    $summary += "Generated: $((Get-Date).ToString('o'))"
    $summary += "GameRoot: $root"
    $summary += "ModRoot: $modRoot"
    $summary += "BackupRoot: $backupRoot"
    $summary += "emit_fields entries seen: $emitFieldsSeen"
    $summary += "entries patched to 1 s: $entriesChanged"
    $summary += "already-positive entries: $positiveEntries"
    $summary += "files changed: $filesChanged"
    $summary += "parse failures: $parseFailures"
    $summary += ""
    $summary += "Reason: captured Windows exception 0xC0000094 resolved to calendar::once_every+0x7."
    $summary += "Current CDDA evaluates once_every as modulo by event_frequency; a zero duration is a hardware integer divide-by-zero."
    $summary += "Current monster runtime feeds emit_fields delay directly to once_every."
    $summary += "Legacy emit_fields string shorthand defaults delay to time_duration() == 0 in named_pair_reader."
    $summary += ""
    $summary += @($patchLog)

    Write-Utf8NoBom -Path $patchLogPath -Text (($summary -join "`r`n") + "`r`n")

