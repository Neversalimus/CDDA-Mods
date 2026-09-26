param([string]$ModRoot,[string]$ReportDir,[string]$BackupRoot)
$ErrorActionPreference='Stop'
$targetDir=$ModRoot
$patchBackup=$BackupRoot
New-Item -ItemType Directory -Force $ReportDir,$BackupRoot | Out-Null
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

function Write-JsonRootSafe {
    param(
        [string]$Path,
        [object]$Data,
        [string]$OriginalRaw
    )

    $trimmed = $OriginalRaw.TrimStart()
    if ($trimmed.StartsWith('[')) {
        Write-Utf8NoBom -Path $Path -Text (ConvertTo-JsonArraySafe -Items @($Data) -Depth 100)
    } else {
        Write-Utf8NoBom -Path $Path -Text (ConvertTo-Json -InputObject $Data -Depth 100)
    }
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
        throw 'No CDDA experimental installation found.'
    }

    return $hit.FullName
}

function Clear-GeneratedCache {
    param([string]$Root)

    foreach ($p in @(
        (Join-Path $Root 'data\cache'),
        (Join-Path $Root 'cache')
    ) | Select-Object -Unique) {
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Recurse -Force
            Write-Host "Removed generated cache: $p" -ForegroundColor Green
        }
    }
}

function Get-DurationSecondsApprox {
    param([object]$Value)

    if ($null -eq $Value) { return 0.0 }

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
    if ([string]::IsNullOrWhiteSpace($s)) { return 0.0 }

    $matches = [regex]::Matches(
        $s,
        '([+-]?\d+(?:\.\d+)?)\s*(turns?|t|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($matches.Count -eq 0) {
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
        $n = [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
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

function Repair-EmitFieldsInFile {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw -notmatch '"emit_fields"\s*:') {
        return [pscustomobject]@{ Changed = $false; Seen = 0; Patched = 0 }
    }

    $data = $raw | ConvertFrom-Json
    $objects = @($data)
    $seen = 0
    $patched = 0
    $changed = $false

    foreach ($obj in $objects) {
        if ($null -eq $obj) { continue }
        $prop = $obj.PSObject.Properties['emit_fields']
        if ($null -eq $prop) { continue }

        $rebuilt = @()
        foreach ($entry in @($obj.emit_fields)) {
            $seen++

            if ($entry -is [string]) {
                $rebuilt += [pscustomobject][ordered]@{
                    emit_id = [string]$entry
                    delay = '1 s'
                }
                $patched++
                $changed = $true
                continue
            }

            if ($entry -is [pscustomobject]) {
                $delayProp = $entry.PSObject.Properties['delay']
                $needsPatch = $false

                if ($null -eq $delayProp) {
                    $needsPatch = $true
                } else {
                    $seconds = Get-DurationSecondsApprox -Value $entry.delay
                    if ($null -ne $seconds -and $seconds -lt 1.0) {
                        $needsPatch = $true
                    }
                }

                if ($needsPatch) {
                    $entry | Add-Member -NotePropertyName delay -NotePropertyValue '1 s' -Force
                    $patched++
                    $changed = $true
                }

                $rebuilt += $entry
                continue
            }

            $rebuilt += $entry
        }

        if ($changed) {
            $obj.emit_fields = @($rebuilt)
        }
    }

    if ($changed) {
        Write-JsonRootSafe -Path $Path -Data $data -OriginalRaw $raw
    }

    return [pscustomobject]@{
        Changed = $changed
        Seen = $seen
        Patched = $patched
    }
}

function Add-FlagToItemObject {
    param(
        [Parameter(Mandatory = $true)] [object]$ItemObject,
        [Parameter(Mandatory = $true)] [string]$Flag
    )

    $flagsProp = $ItemObject.PSObject.Properties['flags']
    if ($null -eq $flagsProp) {
        $ItemObject | Add-Member -NotePropertyName flags -NotePropertyValue @($Flag)
        return $true
    }

    $flags = @($ItemObject.flags)
    if ($flags -contains $Flag) {
        return $false
    }

    $ItemObject.flags = @($flags + $Flag)
    return $true
}

function Repair-TransformActive {
    param(
        [string]$ModRoot,
        [string]$BackupRoot
    )

    $docs = @()
    $idIndex = @{}

    foreach ($file in Get-ChildItem -LiteralPath $ModRoot -Recurse -File -Filter '*.json') {
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        try {
            $data = $raw | ConvertFrom-Json
        } catch {
            continue
        }

        $doc = [pscustomobject]@{
            Path = $file.FullName
            Raw = $raw
            Data = $data
            Objects = @($data)
            Changed = $false
        }
        $docs += $doc

        foreach ($obj in $doc.Objects) {
            if ($null -eq $obj) { continue }
            $idProp = $obj.PSObject.Properties['id']
            if ($null -ne $idProp -and -not [string]::IsNullOrWhiteSpace([string]$obj.id)) {
                $idIndex[[string]$obj.id] = [pscustomobject]@{
                    Object = $obj
                    Doc = $doc
                }
            }
        }
    }

    $removed = 0
    $targetsFlagged = 0
    $unresolvedTargets = @()
    $patchLines = @()

    foreach ($doc in $docs) {
        foreach ($obj in $doc.Objects) {
            if ($null -eq $obj) { continue }

            $uaProp = $obj.PSObject.Properties['use_action']
            if ($null -eq $uaProp) { continue }

            foreach ($action in @($obj.use_action)) {
                if ($null -eq $action -or -not ($action -is [pscustomobject])) { continue }

                $typeProp = $action.PSObject.Properties['type']
                $activeProp = $action.PSObject.Properties['active']
                if ($null -eq $typeProp -or $null -eq $activeProp) { continue }

                if ([string]$action.type -ne 'transform' -or $action.active -ne $true) { continue }

                $sourceId = if ($obj.PSObject.Properties['id']) { [string]$obj.id } else { '<no id>' }
                $targetId = if ($action.PSObject.Properties['target']) { [string]$action.target } else { '' }

                $action.PSObject.Properties.Remove('active')
                $doc.Changed = $true
                $removed++

                if (-not [string]::IsNullOrWhiteSpace($targetId) -and $idIndex.ContainsKey($targetId)) {
                    $targetRef = $idIndex[$targetId]
                    if (Add-FlagToItemObject -ItemObject $targetRef.Object -Flag 'SPAWN_ACTIVE') {
                        $targetRef.Doc.Changed = $true
                        $targetsFlagged++
                    }
                    $patchLines += "PATCH`t$sourceId`t$targetId`tactive=true removed; SPAWN_ACTIVE ensured on target"
                } else {
                    $unresolvedTargets += $targetId
                    $patchLines += "UNRESOLVED`t$sourceId`t$targetId`tactive=true removed but target object not found"
                }
            }
        }
    }

    $filesChanged = 0
    foreach ($doc in $docs) {
        if (-not $doc.Changed) { continue }

        $relative = $doc.Path.Substring($ModRoot.Length).TrimStart('\')
        $backupPath = Join-Path $BackupRoot $relative
        $backupDir = Split-Path -Parent $backupPath
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item -LiteralPath $doc.Path -Destination $backupPath -Force

        Write-JsonRootSafe -Path $doc.Path -Data $doc.Data -OriginalRaw $doc.Raw
        $filesChanged++
    }

    return [pscustomobject]@{
        Removed = $removed
        TargetsFlagged = $targetsFlagged
        FilesChanged = $filesChanged
        UnresolvedTargets = @($unresolvedTargets)
        PatchLines = @($patchLines)
    }
}

function Repair-NpcMissionEnums {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Changed = 0; Values = @() }
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $data = $raw | ConvertFrom-Json
    $changed = 0
    $values = @()

    $missionMap = @{
        0 = 'NULL'
        1 = 'LEGACY_1'
        2 = 'SHELTER'
        3 = 'SHOPKEEP'
        4 = 'GUARD_ALLY'
        5 = 'GUARD'
        6 = 'GUARD_PATROL'
        7 = 'ACTIVITY'
        8 = 'TRAVELLING'
        9 = 'CAMP_RESIDENT'
    }

    foreach ($obj in @($data)) {
        if ($null -eq $obj) { continue }
        $p = $obj.PSObject.Properties['mission']
        if ($null -eq $p) { continue }

        $value = $obj.mission
        if ($value -is [byte] -or
            $value -is [sbyte] -or
            $value -is [int16] -or
            $value -is [uint16] -or
            $value -is [int32] -or
            $value -is [uint32] -or
            $value -is [int64] -or
            $value -is [uint64]) {

            $n = [int]$value
            if ($missionMap.ContainsKey($n)) {
                $id = if ($obj.PSObject.Properties['id']) { [string]$obj.id } else { '<no id>' }
                $obj.mission = [string]$missionMap[$n]
                $values += "$id`t$n`t$($missionMap[$n])"
                $changed++
            }
        }
    }

    if ($changed -gt 0) {
        Write-JsonRootSafe -Path $Path -Data $data -OriginalRaw $raw
    }

    return [pscustomobject]@{
        Changed = $changed
        Values = @($values)
    }
}

function Update-TranslationObject {
    param(
        [object]$Node,
        [string]$ContextName,
        [hashtable]$PluralMap,
        [ref]$SamePluralCount,
        [ref]$MappedPluralCount
    )

    if ($null -eq $Node) { return }

    if ($Node -is [System.Collections.IList] -and -not ($Node -is [string])) {
        foreach ($child in $Node) {
            Update-TranslationObject -Node $child -ContextName $ContextName -PluralMap $PluralMap -SamePluralCount $SamePluralCount -MappedPluralCount $MappedPluralCount
        }
        return
    }

    if ($Node -is [pscustomobject]) {
        $strProp = $Node.PSObject.Properties['str']
        $strPlProp = $Node.PSObject.Properties['str_pl']
        $strSpProp = $Node.PSObject.Properties['str_sp']

        if ($null -ne $strProp -and $null -ne $strPlProp -and [string]$strProp.Value -eq [string]$strPlProp.Value) {
            $value = [string]$strProp.Value
            $Node.PSObject.Properties.Remove('str')
            $Node.PSObject.Properties.Remove('str_pl')
            if ($null -eq $strSpProp) {
                $Node | Add-Member -NotePropertyName str_sp -NotePropertyValue $value
            } else {
                $strSpProp.Value = $value
            }
            $SamePluralCount.Value++
        } elseif (
            ($ContextName -eq 'name' -or $ContextName -eq 'name_noun') -and
            $null -ne $strProp -and
            $null -eq $strPlProp -and
            $null -eq $strSpProp
        ) {
            $singular = [string]$strProp.Value
            if ($PluralMap.ContainsKey($singular)) {
                $plural = [string]$PluralMap[$singular]
                if ($plural -eq $singular) {
                    $Node.PSObject.Properties.Remove('str')
                    $Node | Add-Member -NotePropertyName str_sp -NotePropertyValue $singular
                } else {
                    $Node | Add-Member -NotePropertyName str_pl -NotePropertyValue $plural
                }
                $MappedPluralCount.Value++
            }
        }

        $properties = @($Node.PSObject.Properties)
        foreach ($property in $properties) {
            Update-TranslationObject -Node $property.Value -ContextName $property.Name -PluralMap $PluralMap -SamePluralCount $SamePluralCount -MappedPluralCount $MappedPluralCount
        }
    }
}

function Repair-TranslationSchema {
    param([string]$ModRoot)

    $pluralMap = @{
        'overcharged lump of flesh' = 'overcharged lumps of flesh'
        'bio-organic flesh' = 'bio-organic flesh'
        'blade core' = 'blade cores'
        'mutation cores' = 'mutation cores'
        'amalgams' = 'amalgams'
        'amalgam commands' = 'amalgam commands'
        'DNAs' = 'DNAs'
        'cores' = 'cores'
        'bio-organic reconstructors' = 'bio-organic reconstructors'
        'Secronom module implant "Core"' = 'Secronom module implants "Core"'
        'Secronom module implant "Vessel"' = 'Secronom module implants "Vessel"'
        'Secronom module implant "Shock"' = 'Secronom module implants "Shock"'
        'Secronom module implant "Pulsar"' = 'Secronom module implants "Pulsar"'
        'Secronom module implant "Optics"' = 'Secronom module implants "Optics"'
        'Secronom exoskeleton "O"' = 'Secronom exoskeletons "O"'
        'flesh vessel "Warrior"' = 'flesh vessels "Warrior"'
        'flesh vessel "Juggernaut"' = 'flesh vessels "Juggernaut"'
        'flesh vessel "Agile"' = 'flesh vessels "Agile"'
        'flesh vessel "Gunner"' = 'flesh vessels "Gunner"'
        'flesh vessel "Pathogen"' = 'flesh vessels "Pathogen"'
        '<color_red>[FEED]</color> consume flesh' = '<color_red>[FEED]</color> consume flesh'
        'SP Experimental Mech "Flesh"' = 'SP Experimental Mechs "Flesh"'
    }

    $samePlural = 0
    $mappedPlural = 0
    $filesChanged = 0

    foreach ($file in Get-ChildItem -LiteralPath $ModRoot -Recurse -File -Filter '*.json') {
        $raw = Get-Content -LiteralPath $file.FullName -Raw

        try {
            $data = $raw | ConvertFrom-Json
        } catch {
            continue
        }

        $beforeSame = $samePlural
        $beforeMapped = $mappedPlural

        Update-TranslationObject -Node $data -ContextName '' -PluralMap $pluralMap `
            -SamePluralCount ([ref]$samePlural) -MappedPluralCount ([ref]$mappedPlural)

        if ($samePlural -ne $beforeSame -or $mappedPlural -ne $beforeMapped) {
            Write-JsonRootSafe -Path $file.FullName -Data $data -OriginalRaw $raw
            $filesChanged++
        }
    }

    return [pscustomobject]@{
        SamePlural = $samePlural
        MappedPlural = $mappedPlural
        FilesChanged = $filesChanged
    }
}

function Get-DiagnosticLineNumber {
    param([string]$Token)

    $digits = -join ([regex]::Matches($Token, '\d') | ForEach-Object { $_.Value })
    if (-not $digits) { return 0 }
    return [int]$digits
}

function Repair-TextStyleFromDebug {
    param(
        [string]$DebugPath,
        [string]$Root
    )

    $result = [ordered]@{
        Spacing = 0
        Ellipsis = 0
        Trailing = 0
        BeforePunctuation = 0
        AfterLeadingPunctuation = 0
        Files = 0
        DiagnosticLines = 0
    }

    if (-not (Test-Path -LiteralPath $DebugPath)) {
        return [pscustomobject]$result
    }

    $debugLines = [System.IO.File]::ReadAllLines($DebugPath)
    $opsByFile = @{}

    for ($i = 0; $i -lt $debugLines.Length; $i++) {
        if ($debugLines[$i] -notmatch 'text_style_check_reader\.cpp') { continue }
        if ($i + 1 -ge $debugLines.Length) { continue }

        $jsonLine = $debugLines[$i + 1]
        if ($jsonLine -notmatch '^Json error: file (.+?), at line (.+?), character (.+?):$') { continue }

        $relPath = $matches[1]
        if ($relPath -notmatch '^data[\\/]mods[\\/]secronom_lore_expansion[\\/]') { continue }

        $lineNo = Get-DiagnosticLineNumber -Token $matches[2]
        if ($lineNo -le 0) { continue }

        $kind = $null
        for ($j = $i + 2; $j -lt [Math]::Min($i + 10, $debugLines.Length); $j++) {
            if ($debugLines[$j] -match 'insufficient spaces at this location') {
                $kind = 'spacing'
                break
            }
            if ($debugLines[$j] -match 'ellipsis preferred over three dots') {
                $kind = 'ellipsis'
                break
            }
            if ($debugLines[$j] -match 'unnecessary spaces at end of string') {
                $kind = 'trailing'
                break
            }
            if ($debugLines[$j] -match 'unnecessary spaces before this location') {
                $kind = 'beforepunct'
                break
            }
            if ($debugLines[$j] -match 'undesired spaces after a punctuation that starts a string') {
                $kind = 'afterleadingpunct'
                break
            }
        }

        if (-not $kind) { continue }

        $fullPath = Join-Path $Root ($relPath -replace '/', '\')
        if (-not $opsByFile.ContainsKey($fullPath)) {
            $opsByFile[$fullPath] = @{}
        }
        if (-not $opsByFile[$fullPath].ContainsKey($lineNo)) {
            $opsByFile[$fullPath][$lineNo] = @()
        }
        if ($opsByFile[$fullPath][$lineNo] -notcontains $kind) {
            $opsByFile[$fullPath][$lineNo] += $kind
        }

        $result.DiagnosticLines++
    }

    $enc = New-Object System.Text.UTF8Encoding($false)

    foreach ($fullPath in $opsByFile.Keys) {
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }

        $fileLines = [System.IO.File]::ReadAllLines($fullPath)
        $fileChanged = $false

        foreach ($lineNo in $opsByFile[$fullPath].Keys) {
            $idx = [int]$lineNo - 1
            if ($idx -lt 0 -or $idx -ge $fileLines.Length) { continue }

            $before = $fileLines[$idx]
            $after = $before
            $kinds = @($opsByFile[$fullPath][$lineNo])

            if ($kinds -contains 'ellipsis') {
                $next = $after.Replace('...', '…')
                if ($next -ne $after) {
                    $result.Ellipsis++
                    $after = $next
                }
            }

            if ($kinds -contains 'spacing') {
                # Same current CDDA style rule that successfully cleaned core Secronom:
                # periods require a preceding word of at least 3 chars; !/? require one.
                $next = [regex]::Replace($after, '([A-Za-z0-9-]{3}\.) (?=\S)', '$1  ')
                $next = [regex]::Replace($next, '([A-Za-z0-9-][!?]+) (?=\S)', '$1  ')
                $next = [regex]::Replace($next, '([A-Za-z0-9-]…) (?=\S)', '$1  ')
                if ($next -ne $after) {
                    $result.Spacing++
                    $after = $next
                }
            }

            if ($kinds -contains 'beforepunct') {
                $next = [regex]::Replace($after, ' +([!?])', '$1')
                if ($next -ne $after) {
                    $result.BeforePunctuation++
                    $after = $next
                }
            }

            if ($kinds -contains 'afterleadingpunct') {
                # Handles both literal ellipsis and JSON-escaped \u2026 at start of a string.
                $next = [regex]::Replace($after, '("(?:\\u2026|…|[!?]+)) +', '$1')
                if ($next -ne $after) {
                    $result.AfterLeadingPunctuation++
                    $after = $next
                }
            }

            if ($kinds -contains 'trailing') {
                $next = [regex]::Replace($after, ' +(?="\s*[,}\]])', '')
                if ($next -ne $after) {
                    $result.Trailing++
                    $after = $next
                }
            }

            if ($after -ne $before) {
                $fileLines[$idx] = $after
                $fileChanged = $true
            }
        }

        if ($fileChanged) {
            [System.IO.File]::WriteAllLines($fullPath, $fileLines, $enc)
            $result.Files++
        }
    }

    return [pscustomobject]$result
}

function Invoke-ModValidator {
    param(
        [string]$Exe,
        [string]$Root,
        [string]$UserDir,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    New-Item -ItemType Directory -Path (Join-Path $UserDir 'config') -Force | Out-Null
    foreach ($name in @('debug.log','crash.log')) {
        $p = Join-Path $UserDir "config\$name"
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $Root
    $psi.Arguments = "--userdir `"$UserDir`" --check-mods secronom_lore_expansion"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    Write-Utf8NoBom -Path $StdoutPath -Text $stdout
    Write-Utf8NoBom -Path $StderrPath -Text $stderr

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        DebugLog = (Join-Path $UserDir 'config\debug.log')
        CrashLog = (Join-Path $UserDir 'config\crash.log')
    }
}

function Copy-ValidatorLogs {
    param(
        [object]$Validator,
        [string]$ReportDir,
        [string]$Prefix
    )

    if (Test-Path -LiteralPath $Validator.DebugLog) {
        Copy-Item -LiteralPath $Validator.DebugLog -Destination (Join-Path $ReportDir "${Prefix}_debug.log") -Force
    }
    if (Test-Path -LiteralPath $Validator.CrashLog) {
        Copy-Item -LiteralPath $Validator.CrashLog -Destination (Join-Path $ReportDir "${Prefix}_crash.log") -Force
    }
}

function Count-JsonErrors {
    param([string]$DebugPath)

    if (-not (Test-Path -LiteralPath $DebugPath)) { return 0 }
    $raw = Get-Content -LiteralPath $DebugPath -Raw
    return ([regex]::Matches($raw, '\(json-error\)')).Count
}
    Write-Step 'Neutralizing obsolete zero-weight region_overlay'
    $overlay = Join-Path $targetDir 'region_overlay.json'
    $overlayArchived = $false
    if (Test-Path -LiteralPath $overlay) {
        $overlayRaw = Get-Content -LiteralPath $overlay -Raw
        if ($overlayRaw -match '"type"\s*:\s*"region_overlay"' -and
            $overlayRaw -match '"mx_secro_vesselexp_spawn"\s*:\s*0') {
            Move-Item -LiteralPath $overlay -Destination (Join-Path $targetDir 'region_overlay.legacy.txt') -Force
            $overlayArchived = $true
            Write-Host 'Archived known zero-weight legacy overlay.' -ForegroundColor Green
        }
    }

    Write-Step 'Applying proven once_every emit_fields safety'
    $emitSeen = 0
    $emitPatched = 0
    $emitFiles = 0
    foreach ($file in Get-ChildItem -LiteralPath $targetDir -Recurse -File -Filter '*.json') {
        $r = Repair-EmitFieldsInFile -Path $file.FullName
        $emitSeen += $r.Seen
        $emitPatched += $r.Patched
        if ($r.Changed) { $emitFiles++ }
    }
    Write-Host "emit_fields entries seen: $emitSeen"
    Write-Host "emit_fields patched: $emitPatched"

    Write-Step 'Migrating removed transform.active field'
    $transform = Repair-TransformActive -ModRoot $targetDir -BackupRoot $patchBackup
    Write-Host "transform.active=true removed: $($transform.Removed)"
    Write-Host "targets given SPAWN_ACTIVE: $($transform.TargetsFlagged)"
    Write-Host "unresolved transform targets: $($transform.UnresolvedTargets.Count)"
    Write-Utf8NoBom -Path (Join-Path $reportDir 'TRANSFORM_ACTIVE_PATCH.tsv') -Text (($transform.PatchLines -join "`r`n") + "`r`n")

    Write-Step 'Migrating legacy numeric NPC mission enum'
    $npcPath = Join-Path $targetDir 'Modification Files\NPCs\secro_npcs.json'
    $npcMission = Repair-NpcMissionEnums -Path $npcPath
    Write-Host "numeric NPC mission values converted: $($npcMission.Changed)" -ForegroundColor Green
    foreach ($line in $npcMission.Values) {
        Write-Host "  $line"
    }
    Write-Utf8NoBom -Path (Join-Path $reportDir 'NPC_MISSION_PATCH.tsv') -Text (($npcMission.Values -join "`r`n") + "`r`n")

    Write-Step 'Modernizing translation/plural schema'
    $translation = Repair-TranslationSchema -ModRoot $targetDir
    Write-Host "identical str/str_pl -> str_sp: $($translation.SamePlural)" -ForegroundColor Green
    Write-Host "curated explicit plurals: $($translation.MappedPlural)" -ForegroundColor Green
    Write-Host "translation files changed: $($translation.FilesChanged)"

    Write-Step 'Verifying all Secronom+ JSON parses'
    $jsonCount = 0
    $jsonFailures = @()
    foreach ($file in Get-ChildItem -LiteralPath $targetDir -Recurse -File -Filter '*.json') {
        $jsonCount++
        try {
            $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            $jsonFailures += "$($file.FullName)`t$($_.Exception.Message)"
        }
    }
    Write-Host "JSON files checked: $jsonCount"
    Write-Host "JSON parse failures: $($jsonFailures.Count)" -ForegroundColor $(if ($jsonFailures.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Utf8NoBom -Path (Join-Path $reportDir 'JSON_PARSE_AUDIT.tsv') -Text (($jsonFailures -join "`r`n") + "`r`n")
    if ($jsonFailures.Count -gt 0) {
        throw 'JSON parse verification failed before CDDA validator.'
    }

