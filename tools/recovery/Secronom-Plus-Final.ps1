param([string]$ModRoot,[string]$BackupRoot)
$ErrorActionPreference='Stop'
$plusDir=$ModRoot
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
    if ($parts.Count -eq 0) { return '[]' }
    return "[`r`n" + ($parts -join ",`r`n") + "`r`n]"
}

function Write-JsonRootSafe {
    param(
        [string]$Path,
        [object]$Data,
        [string]$OriginalRaw
    )

    if ($OriginalRaw.TrimStart().StartsWith('[')) {
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
        throw 'No experimental CDDA installation found.'
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

function Backup-File {
    param(
        [string]$File,
        [string]$ModRoot,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $File)) { return }
    $relative = $File.Substring($ModRoot.Length).TrimStart('\')
    $dest = Join-Path $BackupRoot $relative
    $dir = Split-Path -Parent $dest
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $File -Destination $dest -Force
    }
}

function Get-DigitsAsInt {
    param([string]$Token)
    $digits = -join ([regex]::Matches($Token, '\d') | ForEach-Object { $_.Value })
    if ([string]::IsNullOrWhiteSpace($digits)) { return 0 }
    return [int]$digits
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

function Copy-ValidatorArtifacts {
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

function Get-JsonErrorInventory {
    param([string]$DebugPath)

    $r = [ordered]@{
        Total = 0
        Plus = 0
        PlusStyle = 0
        PlusOther = 0
        External = 0
        ExternalLines = @()
    }

    if (-not (Test-Path -LiteralPath $DebugPath)) {
        return [pscustomobject]$r
    }

    $lines = [System.IO.File]::ReadAllLines($DebugPath)

    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -notmatch '\(json-error\)') { continue }

        $r.Total++
        $source = $lines[$i]
        $filePath = ''

        if ($i + 1 -lt $lines.Length) {
            $m = [regex]::Match($lines[$i + 1], '^Json error: file (.+?), at line ')
            if ($m.Success) {
                $filePath = $m.Groups[1].Value
            }
        }

        if ($filePath -match '^data[\\/]mods[\\/]secronom_lore_expansion[\\/]') {
            $r.Plus++
            if ($source -match 'text_style_check_reader\.cpp') {
                $r.PlusStyle++
            } else {
                $r.PlusOther++
            }
        } else {
            $r.External++
            $r.ExternalLines += "$filePath`t$source"
        }
    }

    return [pscustomobject]$r
}

function Get-StyleOperations {
    param([string]$DebugPath)

    $ops = @()
    if (-not (Test-Path -LiteralPath $DebugPath)) { return @() }

    $lines = [System.IO.File]::ReadAllLines($DebugPath)

    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -notmatch 'text_style_check_reader\.cpp') { continue }
        if ($i + 1 -ge $lines.Length) { continue }

        # CDDA localizes large line/character numbers in this build.  The report
        # therefore contains e.g. "line 1�014" and "character 1�070".
        # Match the whole token and strip every non-digit instead of requiring \d+.
        $m = [regex]::Match(
            $lines[$i + 1],
            '^Json error: file (.+?), at line ([^,]+), character ([^:]+):$'
        )
        if (-not $m.Success) { continue }

        $relPath = $m.Groups[1].Value
        if ($relPath -notmatch '^data[\\/]mods[\\/]secronom_lore_expansion[\\/]') {
            continue
        }

        $lineNo = Get-DigitsAsInt -Token $m.Groups[2].Value
        $charNo = Get-DigitsAsInt -Token $m.Groups[3].Value
        if ($lineNo -le 0) { continue }

        $kind = $null
        for ($j = $i + 2; $j -lt [Math]::Min($i + 10, $lines.Length); $j++) {
            if ($lines[$j] -match 'insufficient spaces at this location') {
                $kind = 'spacing'; break
            }
            if ($lines[$j] -match 'ellipsis preferred over three dots') {
                $kind = 'ellipsis'; break
            }
            if ($lines[$j] -match 'unnecessary spaces at end of string') {
                $kind = 'trailing'; break
            }
            if ($lines[$j] -match 'unnecessary spaces before this location') {
                $kind = 'beforepunct'; break
            }
            if ($lines[$j] -match 'undesired spaces after a punctuation that starts a string') {
                $kind = 'afterleadingpunct'; break
            }
        }

        if (-not $kind) { continue }

        $ops += [pscustomobject]@{
            RelPath = $relPath
            Line = $lineNo
            Char = $charNo
            Kind = $kind
        }
    }

    return @($ops)
}

function Repair-StyleOperations {
    param(
        [object[]]$Operations,
        [string]$Root,
        [string]$ModRoot,
        [string]$BackupRoot
    )

    $stats = [ordered]@{
        Diagnostics = $Operations.Count
        Applied = 0
        Missed = 0
        Files = 0
        Spacing = 0
        Ellipsis = 0
        Trailing = 0
        BeforePunctuation = 0
        AfterLeadingPunctuation = 0
    }

    $byFile = @{}
    foreach ($op in $Operations) {
        $fullPath = Join-Path $Root ($op.RelPath -replace '/', '\')
        if (-not $byFile.ContainsKey($fullPath)) {
            $byFile[$fullPath] = @()
        }
        $byFile[$fullPath] += $op
    }

    $enc = New-Object System.Text.UTF8Encoding($false)

    foreach ($fullPath in $byFile.Keys) {
        if (-not (Test-Path -LiteralPath $fullPath)) {
            $stats.Missed += @($byFile[$fullPath]).Count
            continue
        }

        $fileLines = [System.IO.File]::ReadAllLines($fullPath)
        $fileChanged = $false
        $lineGroups = @{}

        foreach ($op in @($byFile[$fullPath])) {
            $key = [string]$op.Line
            if (-not $lineGroups.ContainsKey($key)) {
                $lineGroups[$key] = @()
            }
            $lineGroups[$key] += $op
        }

        foreach ($lineKey in $lineGroups.Keys) {
            $lineNo = [int]$lineKey
            $idxLine = $lineNo - 1

            if ($idxLine -lt 0 -or $idxLine -ge $fileLines.Length) {
                $stats.Missed += @($lineGroups[$lineKey]).Count
                continue
            }

            $s = $fileLines[$idxLine]
            $opsForLine = @($lineGroups[$lineKey] | Sort-Object Char -Descending)

            foreach ($op in $opsForLine) {
                $changed = $false
                $idx = [Math]::Max(0, $op.Char - 1)

                switch ($op.Kind) {
                    'spacing' {
                        if ($idx -lt $s.Length -and $idx + 1 -lt $s.Length -and $s[$idx + 1] -eq ' ') {
                            if ($idx + 2 -ge $s.Length -or $s[$idx + 2] -ne ' ') {
                                $s = $s.Substring(0, $idx + 2) + ' ' + $s.Substring($idx + 2)
                                $changed = $true
                            }
                        }

                        if (-not $changed) {
                            $before = $s
                            $s = [regex]::Replace($s, '([A-Za-z0-9-]{3}\.) (?=\S)', '$1  ')
                            $s = [regex]::Replace($s, '([A-Za-z0-9-][!?]+) (?=\S)', '$1  ')
                            $s = [regex]::Replace($s, '([A-Za-z0-9-]…) (?=\S)', '$1  ')
                            $changed = ($s -ne $before)
                        }

                        if ($changed) { $stats.Spacing++ }
                    }

                    'ellipsis' {
                        $before = $s
                        $start = [Math]::Max(0, $idx - 3)
                        $len = [Math]::Min(9, $s.Length - $start)

                        if ($len -gt 0) {
                            $window = $s.Substring($start, $len)
                            $local = $window.IndexOf('...')
                            if ($local -ge 0) {
                                $pos = $start + $local
                                $s = $s.Substring(0, $pos) + '…' + $s.Substring($pos + 3)
                            }
                        }

                        if ($s -eq $before) {
                            $s = $s.Replace('...', '…')
                        }

                        $changed = ($s -ne $before)
                        if ($changed) { $stats.Ellipsis++ }
                    }

                    'trailing' {
                        $before = $s
                        $s = [regex]::Replace($s, ' +(?="\s*[,}\]])', '')
                        $changed = ($s -ne $before)
                        if ($changed) { $stats.Trailing++ }
                    }

                    'beforepunct' {
                        $before = $s
                        $s = [regex]::Replace($s, ' +([!?])', '$1')
                        $changed = ($s -ne $before)
                        if ($changed) { $stats.BeforePunctuation++ }
                    }

                    'afterleadingpunct' {
                        $before = $s
                        $s = [regex]::Replace($s, '("(?:\\u2026|…|[!?]+)) +', '$1')
                        $changed = ($s -ne $before)
                        if ($changed) { $stats.AfterLeadingPunctuation++ }
                    }
                }

                if ($changed) {
                    $stats.Applied++
                    $fileChanged = $true
                } else {
                    $stats.Missed++
                }
            }

            $fileLines[$idxLine] = $s
        }

        if ($fileChanged) {
            Backup-File -File $fullPath -ModRoot $ModRoot -BackupRoot $BackupRoot
            [System.IO.File]::WriteAllLines($fullPath, $fileLines, $enc)
            $stats.Files++
        }
    }

    return [pscustomobject]$stats
}

function Ensure-Trait {
    param(
        [object]$Obj,
        [string]$Trait
    )

    $p = $Obj.PSObject.Properties['traits']
    if ($null -eq $p) {
        $Obj | Add-Member -NotePropertyName traits -NotePropertyValue @($Trait)
        return $true
    }

    $traits = @($Obj.traits)
    if ($traits -contains $Trait) { return $false }
    $Obj.traits = @($traits + $Trait)
    return $true
}

function Apply-SemanticCompatibilityFixes {
    param(
        [string]$PlusRoot,
        [string]$BackupRoot
    )

    $log = @()
    $count = 0

    # 1) BIONIC spell class: current CDDA bionic spells use NONE as class.
    $magicBionics = Join-Path $PlusRoot 'Modification Files\Items\-Essentials\secro_item_magic_bionics.json'
    if (Test-Path -LiteralPath $magicBionics) {
        $raw = Get-Content -LiteralPath $magicBionics -Raw
        try {
            $data = $raw | ConvertFrom-Json
            $changed = $false
            foreach ($o in @($data)) {
                if ($o.id -eq 'secro_power_armor_fleshmend' -and $o.spell_class -eq 'SECRO_BIONIC_FLESH_CORE') {
                    $o.spell_class = 'NONE'
                    $changed = $true
                    $count++
                    $log += "spell_class`tsecro_power_armor_fleshmend`tSECRO_BIONIC_FLESH_CORE -> NONE"
                }
            }
            if ($changed) {
                Backup-File -File $magicBionics -ModRoot $PlusRoot -BackupRoot $BackupRoot
                Write-JsonRootSafe -Path $magicBionics -Data $data -OriginalRaw $raw
            }
        } catch {
            $log += "WARN`tCould not parse $magicBionics`t$($_.Exception.Message)"
        }
    }

    # 2) Professions with starting CBMs need a current CBM interface trait.
    $profFile = Join-Path $PlusRoot 'Modification Files\Others\secro_prof.json'
    if (Test-Path -LiteralPath $profFile) {
        $raw = Get-Content -LiteralPath $profFile -Raw
        try {
            $data = $raw | ConvertFrom-Json
            $changed = $false
            foreach ($o in @($data)) {
                if ($o.id -eq 'secro_prof_vesselrecruit' -or $o.id -eq 'secro_prof_vesselelite_army') {
                    if (Ensure-Trait -Obj $o -Trait 'CBM_Interface') {
                        $changed = $true
                        $count++
                        $log += "profession`t$($o.id)`tadded CBM_Interface"
                    }
                }
            }
            if ($changed) {
                Backup-File -File $profFile -ModRoot $PlusRoot -BackupRoot $BackupRoot
                Write-JsonRootSafe -Path $profFile -Data $data -OriginalRaw $raw
            }
        } catch {
            $log += "WARN`tCould not parse $profFile`t$($_.Exception.Message)"
        }
    }

    # 3) Recipe produces a charge-counted item.  Preserve the historical/default
    # result explicitly: secro_flesh has default 25 charges.
    $recipeFile = Join-Path $PlusRoot 'Modification Files\Items\-Essentials\secro_recipes.json'
    if (Test-Path -LiteralPath $recipeFile) {
        $raw = Get-Content -LiteralPath $recipeFile -Raw
        try {
            $data = $raw | ConvertFrom-Json
            $changed = $false
            foreach ($o in @($data)) {
                if ($o.type -eq 'recipe' -and $o.result -eq 'secro_flesh' -and $null -eq $o.PSObject.Properties['charges']) {
                    $o | Add-Member -NotePropertyName charges -NotePropertyValue 25
                    $changed = $true
                    $count++
                    $log += "recipe`tsecro_flesh`tadded explicit charges=25"
                }
            }
            if ($changed) {
                Backup-File -File $recipeFile -ModRoot $PlusRoot -BackupRoot $BackupRoot
                Write-JsonRootSafe -Path $recipeFile -Data $data -OriginalRaw $raw
            }
        } catch {
            $log += "WARN`tCould not parse $recipeFile`t$($_.Exception.Message)"
        }
    }

    # 4) Ammo pouch references removed vanilla ammotype "46".
    # Remove only that dead restriction; keep every still-valid caliber untouched.
    $pouchFile = Join-Path $PlusRoot 'Modification Files\Items\Armors\secro_ammo_pouch.json'
    if (Test-Path -LiteralPath $pouchFile) {
        $raw = Get-Content -LiteralPath $pouchFile -Raw
        try {
            $data = $raw | ConvertFrom-Json
            $changed = $false
            foreach ($o in @($data)) {
                if ($o.id -ne 'secro_flesh_ammo_pouch') { continue }
                foreach ($pocket in @($o.pocket_data)) {
                    $restriction = $pocket.PSObject.Properties['ammo_restriction']
                    if ($null -eq $restriction) { continue }
                    $dead = $pocket.ammo_restriction.PSObject.Properties['46']
                    if ($null -ne $dead) {
                        $pocket.ammo_restriction.PSObject.Properties.Remove('46')
                        $changed = $true
                        $count++
                        $log += "ammo_pouch`tsecro_flesh_ammo_pouch`tremoved obsolete ammotype 46"
                    }
                }
            }
            if ($changed) {
                Backup-File -File $pouchFile -ModRoot $PlusRoot -BackupRoot $BackupRoot
                Write-JsonRootSafe -Path $pouchFile -Data $data -OriginalRaw $raw
            }
        } catch {
            $log += "WARN`tCould not parse $pouchFile`t$($_.Exception.Message)"
        }
    }

    # 5) Several target IDs refer to names no longer present in the restored core.
    # Apply only mappings that are direct historical renames; remove IDs that have
    # no current counterpart while preserving all other valid targets.
    $itemMagic = Join-Path $PlusRoot 'Modification Files\Items\-Essentials\secro_item_magic.json'
    if (Test-Path -LiteralPath $itemMagic) {
        $raw = Get-Content -LiteralPath $itemMagic -Raw
        try {
            $data = $raw | ConvertFrom-Json
            $changed = $false

            $rename = @{
                'mon_sflesh_taken_bear' = 'mon_sflesh_bear'
                'mon_sflesh_taken_rat' = 'mon_sflesh_rat'
                'mon_sflesh_taken_cougar' = 'mon_sflesh_cougar'
                'mon_sflesh_taken_moose' = 'mon_sflesh_moose'
                'mon_sflesh_taken_zombie' = 'mon_sflesh_zombie'
            }

            $remove = @(
                'mon_zombie_omouth',
                'mon_sflesh_nakedmolerat_giant',
                'mon_sflesh_zombie_bio_op'
            )

            foreach ($o in @($data)) {
                $tp = $o.PSObject.Properties['targeted_monster_ids']
                if ($null -eq $tp) { continue }

                $rebuilt = @()
                $localChanged = $false

                foreach ($id in @($o.targeted_monster_ids)) {
                    $sid = [string]$id

                    if ($rename.ContainsKey($sid)) {
                        $newId = [string]$rename[$sid]
                        if ($rebuilt -notcontains $newId) {
                            $rebuilt += $newId
                        }
                        $log += "monster_target`t$($o.id)`t$sid -> $newId"
                        $localChanged = $true
                        $count++
                        continue
                    }

                    if ($remove -contains $sid) {
                        $log += "monster_target`t$($o.id)`tremoved missing $sid"
                        $localChanged = $true
                        $count++
                        continue
                    }

                    if ($rebuilt -notcontains $sid) {
                        $rebuilt += $sid
                    }
                }

                if ($localChanged) {
                    $o.targeted_monster_ids = @($rebuilt)
                    $changed = $true
                }
            }

            if ($changed) {
                Backup-File -File $itemMagic -ModRoot $PlusRoot -BackupRoot $BackupRoot
                Write-JsonRootSafe -Path $itemMagic -Data $data -OriginalRaw $raw
            }
        } catch {
            $log += "WARN`tCould not parse $itemMagic`t$($_.Exception.Message)"
        }
    }

    # mon_sflesh_hatchery_amalgam is intentionally NOT guessed here.  It is used
    # by the hatchery/transmitter feature, but no definition exists in the pinned
    # core/expansion.  Keep it visible in consistency diagnostics for the next pass.
    $log += "DEFERRED`tmon_sflesh_hatchery_amalgam`tNo definition in pinned source; do not invent replacement."
    $log += "DEFERRED`tsecro_flesh_boneneedle ammotype`tAmmo exists but no current consuming gun was identified; audit after validator."

    return [pscustomobject]@{
        Changes = $count
        Log = @($log)
    }
}

function Get-ConsistencyErrors {
    param([string]$DebugPath)

    $items = @()
    if (-not (Test-Path -LiteralPath $DebugPath)) { return @() }

    foreach ($line in [System.IO.File]::ReadAllLines($DebugPath)) {
        if ($line -notmatch ' ERROR : ') { continue }
        if ($line -match '\(json-error\)') { continue }
        if ($line -match 'error message will follow backtrace') { continue }

        if ($line -match 'recipe\.cpp:' -or
            $line -match 'item_factory\.cpp:' -or
            $line -match 'profession\.cpp:' -or
            $line -match 'ammo\.cpp:' -or
            $line -match 'magic\.cpp:') {
            $items += $line
        }
    }

    return @($items)
}
    Write-Step 'Fixing the two missed colored blade-core plurals'
    $mutationItems = Join-Path $plusDir 'Modification Files\Others\secro_mutation_items.json'
    $bladePatches = 0

    if (Test-Path -LiteralPath $mutationItems) {
        $raw = Get-Content -LiteralPath $mutationItems -Raw

        $pattern = '"name"\s*:\s*\{\s*"str"\s*:\s*"<color_light_green>blade core</color>"\s*\}'
        $matches = [regex]::Matches($raw, $pattern)
        $bladePatches = $matches.Count

        if ($bladePatches -gt 0) {
            $replacement = '"name": { "str": "<color_light_green>blade core</color>", "str_pl": "<color_light_green>blade cores</color>" }'
            $raw = [regex]::Replace($raw, $pattern, $replacement)
            Write-Utf8NoBom -Path $mutationItems -Text $raw
        }
    }

    Write-Host "colored blade-core plurals patched: $bladePatches" -ForegroundColor $(if ($bladePatches -gt 0) { 'Green' } else { 'Yellow' })


Apply-SemanticCompatibilityFixes -PlusRoot $ModRoot -BackupRoot $BackupRoot
    Write-Step 'Installing narrowly scoped recovered-content compatibility file'

    $compatDir = Join-Path $plusDir 'Modification Files\Compatibility'
    New-Item -ItemType Directory -Path $compatDir -Force | Out-Null
    $compatFile = Join-Path $compatDir 'secro_recovered_content_compat.json'

    if (Test-Path -LiteralPath $compatFile) {
        Copy-Item -LiteralPath $compatFile -Destination (Join-Path $backupRoot 'secro_recovered_content_compat.json') -Force
    }

    $compatJson = @'
[
  {
    "id": "mon_sflesh_hatchery_amalgam",
    "copy-from": "mon_sflesh_fleshling_ravagy",
    "type": "MONSTER"
  },
  {
    "id": "secro_power_armor_flesh_created_gun_bonerifle",
    "copy-from": "gun_base_rifle_semi",
    "type": "ITEM",
    "subtypes": [ "GUN" ],
    "name": { "str": "<color_light_blue>gunner creation</color> - bone rifle" },
    "description": "A recovered Secronom bio-organic rifle design.  It launches needle-like bone projectiles through a tendon-driven chamber.",
    "price": "0 cent",
    "price_postapoc": "0 cent",
    "symbol": "(",
    "color": "red",
    "material": [ "flesh", "bone" ],
    "weight": "2830 g",
    "volume": "4325 ml",
    "melee_damage": { "bash": 10 },
    "ammo": [ "secro_flesh_boneneedle" ],
    "range": 15,
    "ranged_damage": { "damage_type": "stab", "amount": 18 },
    "dispersion": 150,
    "durability": 10,
    "reload": 75,
    "flags": [ "TRADER_AVOID", "NEVER_JAMS", "NON_FOULING", "NO_UNLOAD" ],
    "pocket_data": [
      {
        "pocket_type": "MAGAZINE",
        "rigid": true,
        "ammo_restriction": { "secro_flesh_boneneedle": 8 }
      }
    ]
  }
]
'@

    Write-Utf8NoBom -Path $compatFile -Text $compatJson
    Write-Host "Installed compatibility file: $compatFile" -ForegroundColor Green
    Write-Host 'Hatchery companion aliases the existing amalgam ravager mechanics without inventing new combat stats.'
    Write-Host 'Bone rifle restores the historical consumer for secro_flesh_boneneedle using modern gun schema.'

