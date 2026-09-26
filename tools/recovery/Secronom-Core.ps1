param([string]$ModRoot,[string]$GameRoot)
$ErrorActionPreference='Stop'
$targetModDir=$ModRoot
$RevivalVersion='1.1'
$SourceCommit='150a75d1346fbcbf545cb22a4c9d672c0f483e9b'
function Write-Step([string]$Text) {
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
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

    # Windows PowerShell 5.1 may serialize some top-level collections as
    # {"value":[...],"Count":N} when they are passed as one object.
    # CDDA content files here must remain JSON arrays, so serialize each
    # element independently and assemble the outer array ourselves.
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        $parts.Add((ConvertTo-Json -InputObject $item -Depth $Depth)) | Out-Null
    }

    if ($parts.Count -eq 0) {
        return '[]'
    }

    return "[`r`n" + ($parts -join ",`r`n") + "`r`n]"
}

function Find-GameRoot {
    param([string]$Requested)

    if ($Requested) {
        $resolved = (Resolve-Path -LiteralPath $Requested).Path
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'data\mods'))) {
            throw "GameRoot does not look like a CDDA install (data\mods missing): $resolved"
        }
        return $resolved
    }

    $launcherBase = Join-Path $env:LOCALAPPDATA 'com.munetmo.cat-launcher\Assets\DarkDaysAhead'
    if (Test-Path -LiteralPath $launcherBase) {
        $exact = Join-Path $launcherBase $ExpectedBuildHint
        if (Test-Path -LiteralPath (Join-Path $exact 'data\mods')) {
            return $exact
        }

        $found = Get-ChildItem -LiteralPath $launcherBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'cdda_experimental_*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'data\mods')) } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw @"
Could not auto-detect CDDA.
Run again with -GameRoot, for example:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -GameRoot "C:\path\to\cdda_experimental_YYYY_MM_DD_HHMM"
"@
}

function Find-GameExe {
    param([string]$Root)

    $preferred = @(
        'cataclysm-tiles.exe',
        'cataclysm-tiles-sounds-x64-msvc.exe',
        'cataclysm.exe'
    )
    foreach ($name in $preferred) {
        $p = Join-Path $Root $name
        if (Test-Path -LiteralPath $p) { return $p }
    }

    $fallback = Get-ChildItem -LiteralPath $Root -File -Filter 'cataclysm*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'launcher|updater|crash' } |
        Sort-Object Name |
        Select-Object -First 1
    if ($fallback) { return $fallback.FullName }

    throw "Could not find Cataclysm executable in: $Root"
}

function Remove-DirectorySafe {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
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
        } elseif ($ContextName -eq 'name' -and $null -ne $strProp -and $null -eq $strPlProp -and $null -eq $strSpProp) {
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
        $lineNo = Get-DiagnosticLineNumber -Token $matches[2]
        if ($lineNo -le 0) { continue }

        $kind = $null
        for ($j = $i + 2; $j -lt [Math]::Min($i + 10, $debugLines.Length); $j++) {
            if ($debugLines[$j] -match 'insufficient spaces at this location') { $kind = 'spacing'; break }
            if ($debugLines[$j] -match 'ellipsis preferred over three dots') { $kind = 'ellipsis'; break }
            if ($debugLines[$j] -match 'unnecessary spaces at end of string') { $kind = 'trailing'; break }
        }
        if (-not $kind) { continue }

        $fullPath = Join-Path $Root ($relPath -replace '/', '\')
        if (-not $opsByFile.ContainsKey($fullPath)) {
            $opsByFile[$fullPath] = @{}
        }
        if (-not $opsByFile[$fullPath].ContainsKey($lineNo)) {
            $opsByFile[$fullPath][$lineNo] = New-Object 'System.Collections.Generic.HashSet[string]'
        }
        [void]$opsByFile[$fullPath][$lineNo].Add($kind)
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
            $kinds = $opsByFile[$fullPath][$lineNo]

            if ($kinds.Contains('ellipsis')) {
                $next = $after.Replace('...', '…')
                if ($next -ne $after) {
                    $result.Ellipsis++
                    $after = $next
                }
            }

            if ($kinds.Contains('spacing')) {
                # Match the game's current text_style_check rules closely:
                # periods need a preceding word of at least 3 chars, while !/? need 1.
                $next = [regex]::Replace($after, '([A-Za-z0-9-]{3}\.) (?=\S)', '$1  ')
                $next = [regex]::Replace($next, '([A-Za-z0-9-][!?]+) (?=\S)', '$1  ')
                $next = [regex]::Replace($next, '([A-Za-z0-9-]…) (?=\S)', '$1  ')
                if ($next -ne $after) {
                    $result.Spacing++
                    $after = $next
                }
            }

            if ($kinds.Contains('trailing')) {
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

function Clear-GeneratedGameCache {
    param([string]$Root)

    $candidates = @(
        (Join-Path $Root 'data\cache'),
        (Join-Path $Root 'cache')
    ) | Select-Object -Unique

    $removed = 0
    foreach ($cachePath in $candidates) {
        if (Test-Path -LiteralPath $cachePath) {
            Remove-Item -LiteralPath $cachePath -Recurse -Force
            Write-Host "Removed generated cache: $cachePath" -ForegroundColor Green
            $removed++
        }
    }
    if ($removed -eq 0) {
        Write-Host 'No existing game-data cache found.'
    }
    return $removed
}

function Invoke-ModValidator {
    param(
        [string]$Exe,
        [string]$Root,
        [string]$UserDir,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $configDir = Join-Path $UserDir 'config'
    New-Item -ItemType Directory -Path $UserDir, $configDir -Force | Out-Null
    $quotedUserDir = '"' + $UserDir + '"'

    $proc = Start-Process -FilePath $Exe `
        -ArgumentList @('--userdir', $quotedUserDir, '--check-mods', 'secronom') `
        -WorkingDirectory $Root `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath `
        -PassThru -Wait

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        ConfigDir = $configDir
        DebugLog = (Join-Path $configDir 'debug.log')
        CrashLog = (Join-Path $configDir 'crash.log')
    }
}


Write-Host "Secronom Revival v$RevivalVersion - PowerShell 5.1 JSON-array safety pass" -ForegroundColor Green
Write-Host "Source: Erin105/Secronom-Zombies @ $SourceCommit"

    Write-Step 'Migrating obsolete region_overlay'
    $legacyOverlay = Join-Path $targetModDir 'region_overlay.json'
    if (-not (Test-Path -LiteralPath $legacyOverlay)) {
        throw "Expected upstream region_overlay.json was not found: $legacyOverlay"
    }

    # Keep the historical source for reference without a .json extension so CDDA will not load it.
    Copy-Item -LiteralPath $legacyOverlay -Destination (Join-Path $targetModDir 'region_overlay.legacy.txt') -Force

    # Earlier Revival passes used "id": "forest", "copy-from": "forest" style overlays.
    # The target build treats same-id self-copy as a circular dependency. Build complete
    # replacement collections from THIS installation's vanilla regional settings instead.
    # This preserves the exact vanilla chance/weights of the target build and only appends
    # Secronom extras.
    $coreRegionPath = Join-Path $GameRoot 'data\json\region_settings\region_settings\regional_map_settings.json'
    if (-not (Test-Path -LiteralPath $coreRegionPath)) {
        $coreRegionHit = Get-ChildItem -LiteralPath (Join-Path $GameRoot 'data\json') -Recurse -File -Filter 'regional_map_settings.json' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $coreRegionHit) { throw 'Could not locate vanilla regional_map_settings.json.' }
        $coreRegionPath = $coreRegionHit.FullName
    }
    $coreRegionData = Get-Content -LiteralPath $coreRegionPath -Raw | ConvertFrom-Json

    $regionAdditions = @'
{
  "agricultural": [ [ "mx_secro_flesh_random", 45 ] ],
  "forest": [
    [ "mx_secro_saddler_victims_spawn", 7 ],
    [ "mx_secro_carrion_spawn", 10 ],
    [ "mx_secro_flesh_random", 30 ],
    [ "mx_secro_carrion_massacre_spawn", 3 ],
    [ "mx_secro_carrion_massacre_smol_spawn", 10 ]
  ],
  "forest_thick": [
    [ "mx_secro_saddler_victims_spawn", 7 ],
    [ "mx_secro_carrion_spawn", 10 ],
    [ "mx_secro_flesh_random", 40 ],
    [ "mx_secro_carrion_massacre_spawn", 5 ],
    [ "mx_secro_carrion_massacre_smol_spawn", 13 ]
  ],
  "forest_water": [
    [ "mx_secro_saddler_victims_spawn", 12 ],
    [ "mx_secro_carrion_spawn", 15 ],
    [ "mx_secro_flesh_random", 25 ],
    [ "mx_secro_carrion_massacre_spawn", 5 ],
    [ "mx_secro_carrion_massacre_smol_spawn", 12 ]
  ],
  "road": [
    [ "mx_secro_ssf_carrier", 66 ],
    [ "mx_secro_ssb_carrier", 22 ],
    [ "mx_secro_carrion_massacre_spawn", 25 ],
    [ "mx_secro_carrion_massacre_smol_spawn", 45 ]
  ],
  "field": [
    [ "mx_secro_saddler_victims_spawn", 10 ],
    [ "mx_secro_flesh_random", 55 ]
  ],
  "road_nesw_manhole": [ [ "mx_secro_flesh_core", 1 ] ],
  "sewer": [ [ "mx_secro_flesh_random", 100 ] ],
  "subway": [
    [ "mx_secro_flesh_random", 5 ],
    [ "mx_secro_saddler_infest_spawn", 8 ]
  ],
  "build": [
    [ "mx_secro_fleshbuilding_spawn", 15 ],
    [ "mx_secro_saddler_infest_spawn", 5 ]
  ]
}
'@ | ConvertFrom-Json

    $regionIds = @('agricultural','forest','forest_thick','forest_water','road','field','road_nesw_manhole','sewer','subway','build')
    $modernRegionObjects = New-Object System.Collections.ArrayList
    $regionCollectionsPatched = 0
    $regionCollectionsSkipped = 0

    foreach ($regionId in $regionIds) {
        $baseCollection = @($coreRegionData | Where-Object { $_.type -eq 'map_extra_collection' -and $_.id -eq $regionId } | Select-Object -First 1)
        if ($baseCollection.Count -eq 0 -or $null -eq $baseCollection[0]) {
            # "sewer" no longer exists as a vanilla map-extra collection in current builds.
            # Do not invent its old chance: skip it rather than changing spawn balance blindly.
            Write-Host "Region collection absent in this build, skipped: $regionId" -ForegroundColor DarkYellow
            $regionCollectionsSkipped++
            continue
        }

        # Deep clone the vanilla object and append positive-weight Secronom entries.
        $copy = ($baseCollection[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
        $extras = New-Object System.Collections.ArrayList
        foreach ($pair in @($copy.extras)) { [void]$extras.Add($pair) }

        $additionProp = $regionAdditions.PSObject.Properties[$regionId]
        if ($null -ne $additionProp) {
            foreach ($pair in @($additionProp.Value)) {
                if ([int]$pair[1] -gt 0) { [void]$extras.Add($pair) }
            }
        }
        $copy.extras = @($extras)
        [void]$modernRegionObjects.Add($copy)
        $regionCollectionsPatched++
    }

    $secroFleshExtras = [pscustomobject]@{
        type = 'map_extra_collection'
        id = 'secro_flesh_extras'
        chance = 15
        extras = @(
            @('mx_flesh_biome_extra_spawn', 555),
            @('mx_helicopter', 55)
        )
    }
    [void]$modernRegionObjects.Add($secroFleshExtras)

    $baseRegionMapExtras = @($coreRegionData | Where-Object { $_.type -eq 'region_settings_map_extras' -and $_.id -eq 'default' } | Select-Object -First 1)
    if ($baseRegionMapExtras.Count -eq 0 -or $null -eq $baseRegionMapExtras[0]) {
        throw 'Vanilla region_settings_map_extras/default was not found.'
    }
    $mapExtrasCopy = ($baseRegionMapExtras[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
    $mapExtraIds = @($mapExtrasCopy.extras)
    if ($mapExtraIds -notcontains 'secro_flesh_extras') {
        $mapExtraIds += 'secro_flesh_extras'
    }
    $mapExtrasCopy.extras = @($mapExtraIds)
    [void]$modernRegionObjects.Add($mapExtrasCopy)

    $modernRegionJson = ConvertTo-JsonArraySafe -Items @($modernRegionObjects) -Depth 100
    Write-Utf8NoBom -Path $legacyOverlay -Text $modernRegionJson
    Write-Host "Converted region overlay from target-build vanilla data: collections=$regionCollectionsPatched, skipped=$regionCollectionsSkipped" -ForegroundColor Green

    Write-Step 'Migrating ammo_effect field schema'
    $ammoEffectsPath = Join-Path $targetModDir 'Modification_Files\Others\secro_ammo_effects.json'
    if (-not (Test-Path -LiteralPath $ammoEffectsPath)) {
        throw "Expected Secronom ammo effects file was not found: $ammoEffectsPath"
    }

    # In modern CDDA, ammo_effect.aoe and ammo_effect.trail are arrays of effect objects.
    # Upstream Secronom still uses the older single-object form. Wrap those objects in arrays
    # without changing their actual field behavior.
    $ammoData = Get-Content -LiteralPath $ammoEffectsPath -Raw | ConvertFrom-Json
    $aoePatched = 0
    $trailPatched = 0
    foreach ($entry in @($ammoData)) {
        if ($entry.type -ne 'ammo_effect') { continue }
        if ($null -ne $entry.aoe -and -not ($entry.aoe -is [System.Array])) {
            $entry.aoe = @($entry.aoe)
            $aoePatched++
        }
        if ($null -ne $entry.trail -and -not ($entry.trail -is [System.Array])) {
            $entry.trail = @($entry.trail)
            $trailPatched++
        }
    }
    $ammoJson = ConvertTo-JsonArraySafe -Items @($ammoData) -Depth 100
    Write-Utf8NoBom -Path $ammoEffectsPath -Text $ammoJson
    Write-Host "Converted ammo_effect arrays: aoe=$aoePatched, trail=$trailPatched" -ForegroundColor Green

    Write-Step 'Migrating wildlife inheritance changes'
    # Secronom's flesh wildlife was authored when every copied bird kept the old BIRD/ANIMAL
    # inheritance. Modern CDDA changed the mutant crow definitions: mon_crow_mutant_small no
    # longer has ANIMAL, while mon_crow_mutant uses MUTANT rather than BIRD. Generic delete
    # operations now throw if the requested value is absent. Preserve Secronom's intended
    # result by replacing wildlife species with SFLESH directly, then only deleting ANIMAL
    # where the modern parent is known to contain it.
    $wildlifeFiles = @(
        (Join-Path $targetModDir 'Modification_Files\Monsters\Crimson Horrors\Wildlife\Flesh_bird.json'),
        (Join-Path $targetModDir 'Modification_Files\Monsters\Crimson Horrors\Wildlife\Flesh_insect_spider.json'),
        (Join-Path $targetModDir 'Modification_Files\Monsters\Crimson Horrors\Wildlife\Flesh_mammal.json')
    )
    $wildlifeSpeciesPatched = 0
    $wildlifeDeletePatched = 0
    foreach ($wildlifePath in $wildlifeFiles) {
        if (-not (Test-Path -LiteralPath $wildlifePath)) { continue }
        $wildlifeData = Get-Content -LiteralPath $wildlifePath -Raw | ConvertFrom-Json
        foreach ($entry in @($wildlifeData)) {
            if ($entry.type -ne 'MONSTER' -or -not $entry.'copy-from') { continue }
            $hasSfleshExtend = $false
            if ($null -ne $entry.extend -and $null -ne $entry.extend.species) {
                $hasSfleshExtend = @($entry.extend.species) -contains 'SFLESH'
            }
            if (-not $hasSfleshExtend) { continue }

            # Direct assignment safely replaces BIRD/MAMMAL/INSECT/MUTANT etc. with SFLESH.
            $entry | Add-Member -NotePropertyName species -NotePropertyValue @('SFLESH') -Force
            $wildlifeSpeciesPatched++

            # Species is no longer extended/deleted after the direct replacement.
            if ($null -ne $entry.extend -and $null -ne $entry.extend.species) {
                $entry.extend.PSObject.Properties.Remove('species')
            }
            if ($null -ne $entry.delete -and $null -ne $entry.delete.species) {
                $entry.delete.PSObject.Properties.Remove('species')
                $wildlifeDeletePatched++
            }

            # Modern CDDA removed ANIMAL from the insect/spider/worm mutant lineage entirely.
            # The old Secronom conversion still tries to delete ANIMAL from every entry in
            # Flesh_insect_spider.json, which now throws "no value to delete".  Birds and
            # mammals still commonly carry ANIMAL, so keep the old delete there except for
            # the two mutant-crow parents which also no longer have it.
            $isInsectSpiderFile = ((Split-Path -Leaf $wildlifePath) -eq 'Flesh_insect_spider.json')
            $staleAnimalDelete = $isInsectSpiderFile -or ($entry.'copy-from' -in @('mon_crow_mutant_small', 'mon_crow_mutant'))
            if ($staleAnimalDelete -and $null -ne $entry.delete -and $null -ne $entry.delete.flags) {
                $beforeFlags = @($entry.delete.flags)
                $remainingFlags = @($beforeFlags | Where-Object { $_ -ne 'ANIMAL' })
                if ($remainingFlags.Count -ne $beforeFlags.Count) {
                    if ($remainingFlags.Count -gt 0) {
                        $entry.delete.flags = $remainingFlags
                    } else {
                        $entry.delete.PSObject.Properties.Remove('flags')
                    }
                    $wildlifeDeletePatched++
                }
            }

            # Remove now-empty extend/delete objects to avoid skipped-member noise.
            if ($null -ne $entry.extend -and $entry.extend.PSObject.Properties.Count -eq 0) {
                $entry.PSObject.Properties.Remove('extend')
            }
            if ($null -ne $entry.delete -and $entry.delete.PSObject.Properties.Count -eq 0) {
                $entry.PSObject.Properties.Remove('delete')
            }
        }
        $wildlifeJson = ConvertTo-JsonArraySafe -Items @($wildlifeData) -Depth 100
        Write-Utf8NoBom -Path $wildlifePath -Text $wildlifeJson
    }
    Write-Host "Modernized flesh wildlife inheritance: species=$wildlifeSpeciesPatched, delete adjustments=$wildlifeDeletePatched" -ForegroundColor Green

    Write-Step 'Migrating obsolete mapgen item groups'
    # Modern food/item-group reorganizations removed several vanilla ids still used by
    # Secronom mapgen. Patch both "group" and mapgen "item" references under Maps only.
    $groupReplacements = [ordered]@{
        'pasta' = 'groce_pasta'
        'pet_food' = 'pet_food_in_container'
        'groce_cereal' = 'cereal_in_container_full'
    }
    $itemGroupFilesPatched = 0
    $itemGroupRefsPatched = 0
    $mapRoot = Join-Path $targetModDir 'Modification_Files\Maps'
    $mapJsonFiles = Get-ChildItem -LiteralPath $mapRoot -Recurse -File -Filter '*.json'
    foreach ($jsonFile in $mapJsonFiles) {
        $raw = Get-Content -LiteralPath $jsonFile.FullName -Raw
        $patched = $raw
        $changedHere = 0
        foreach ($oldId in $groupReplacements.Keys) {
            $newId = $groupReplacements[$oldId]
            $pattern = '(?m)("(?:group|item)"\s*:\s*)"' + [regex]::Escape($oldId) + '"'
            $matches = [regex]::Matches($patched, $pattern)
            if ($matches.Count -gt 0) {
                $patched = [regex]::Replace($patched, $pattern, ('$1"' + $newId + '"'))
                $changedHere += $matches.Count
            }
        }
        if ($changedHere -gt 0) {
            Write-Utf8NoBom -Path $jsonFile.FullName -Text $patched
            $itemGroupFilesPatched++
            $itemGroupRefsPatched += $changedHere
        }
    }
    Write-Host "Modernized removed mapgen item groups: refs=$itemGroupRefsPatched files=$itemGroupFilesPatched" -ForegroundColor Green

    Write-Step 'Migrating removed firearm base classes'
    $gunsPath = Join-Path $targetModDir 'Modification_Files\Items\secro_guns.json'
    $gunBasePatched = 0
    $gunModesPatched = 0
    if (Test-Path -LiteralPath $gunsPath) {
        $gunsData = Get-Content -LiteralPath $gunsPath -Raw | ConvertFrom-Json
        foreach ($entry in @($gunsData)) {
            if (-not $entry.'copy-from') { continue }
            $newBase = $null
            switch ($entry.id) {
                'cheytac'     { $newBase = 'gun_base_rifle_manual' }
                'hecate'      { $newBase = 'gun_base_rifle_manual' }
                'zx1sniper'   { $newBase = 'gun_base_rifle_manual' }
                'walther2000' { $newBase = 'gun_base_rifle_semi' }
                'psg1'        { $newBase = 'gun_base_rifle_semi' }
                'kacc'        { $newBase = 'gun_base_rifle_semi' }
                'xm556'       { $newBase = 'gun_base_rifle_semi' }
                'xm8'         { $newBase = 'gun_base_rifle_semi' }
            }
            if ($newBase) {
                $entry.'copy-from' = $newBase
                $gunBasePatched++
            }

            # rifle_auto used to provide automatic fire behavior through inheritance.
            # xm8 did not override modes itself, so preserve that intent explicitly.
            if ($entry.id -eq 'xm8' -and $null -eq $entry.modes) {
                $entry | Add-Member -NotePropertyName modes -NotePropertyValue @(
                    @('DEFAULT','semi-auto',1),
                    @('AUTO','auto',5)
                ) -Force
                $gunModesPatched++
            }
        }
        Write-Utf8NoBom -Path $gunsPath -Text (ConvertTo-JsonArraySafe -Items @($gunsData) -Depth 100)
    }
    Write-Host "Modernized firearm bases: bases=$gunBasePatched, explicit modes=$gunModesPatched" -ForegroundColor Green

    Write-Step 'Migrating monster attack body-part targeting'
    $attacksPath = Join-Path $targetModDir 'Modification_Files\Monsters\-Essentials\secro_attacks.json'
    $bodyPartTargetsPatched = 0
    if (Test-Path -LiteralPath $attacksPath) {
        $attackData = Get-Content -LiteralPath $attacksPath -Raw | ConvertFrom-Json
        foreach ($entry in @($attackData)) {
            if ($null -ne $entry.body_parts) {
                $entry | Add-Member -NotePropertyName body_part_types -NotePropertyValue @($entry.body_parts) -Force
                $entry.PSObject.Properties.Remove('body_parts')
                $bodyPartTargetsPatched++
            }
        }
        Write-Utf8NoBom -Path $attacksPath -Text (ConvertTo-JsonArraySafe -Items @($attackData) -Depth 100)
    }
    Write-Host "Renamed body_parts -> body_part_types: $bodyPartTargetsPatched" -ForegroundColor Green

    Write-Step 'Migrating map-extra autonotes'
    $mapExtrasPath = Join-Path $targetModDir 'Modification_Files\Maps\-Essentials\map_extras.json'
    $autonotePatched = 0
    if (Test-Path -LiteralPath $mapExtrasPath) {
        $mapExtraData = Get-Content -LiteralPath $mapExtrasPath -Raw | ConvertFrom-Json
        foreach ($entry in @($mapExtraData)) {
            if ($null -ne $entry.autonote) {
                if ([bool]$entry.autonote) {
                    $entry | Add-Member -NotePropertyName autonote_visibility -NotePropertyValue 'same_tile' -Force
                }
                $entry.PSObject.Properties.Remove('autonote')
                $autonotePatched++
            }
        }
        Write-Utf8NoBom -Path $mapExtrasPath -Text (ConvertTo-JsonArraySafe -Items @($mapExtraData) -Depth 100)
    }
    Write-Host "Modernized map-extra autonotes: $autonotePatched" -ForegroundColor Green

    Write-Step 'Migrating active grenade transforms'
    $ammoZombiePath = Join-Path $targetModDir 'Modification_Files\Monsters\-Essentials\secro_ammo_zombie.json'
    $activeTransformPatched = 0
    $spawnActivePatched = 0
    if (Test-Path -LiteralPath $ammoZombiePath) {
        $ammoZombieData = Get-Content -LiteralPath $ammoZombiePath -Raw | ConvertFrom-Json
        $activeTargets = @('SSxgrenadeact','SSygrenadeact','SSzgrenadeact')
        foreach ($entry in @($ammoZombieData)) {
            if ($null -ne $entry.use_action -and $null -ne $entry.use_action.active) {
                $entry.use_action.PSObject.Properties.Remove('active')
                $activeTransformPatched++
            }
            if ($entry.id -in $activeTargets) {
                $flags = @()
                if ($null -ne $entry.flags) { $flags = @($entry.flags) }
                if ($flags -notcontains 'SPAWN_ACTIVE') {
                    $flags += 'SPAWN_ACTIVE'
                    $entry | Add-Member -NotePropertyName flags -NotePropertyValue @($flags) -Force
                    $spawnActivePatched++
                }
            }
        }
        Write-Utf8NoBom -Path $ammoZombiePath -Text (ConvertTo-JsonArraySafe -Items @($ammoZombieData) -Depth 100)
    }
    Write-Host "Modernized grenade activation: transform.active removed=$activeTransformPatched, SPAWN_ACTIVE targets=$spawnActivePatched" -ForegroundColor Green

    Write-Step 'Removing obsolete undefined item flags'
    $obsoleteFlagRefs = 0
    $obsoleteFlagFiles = 0
    $allModJson = Get-ChildItem -LiteralPath $targetModDir -Recurse -File -Filter '*.json'
    foreach ($jsonFile in $allModJson) {
        $raw = Get-Content -LiteralPath $jsonFile.FullName -Raw
        $matches = [regex]::Matches($raw, '(?<![A-Za-z0-9_])"SMOKABLE"(?![A-Za-z0-9_])')
        if ($matches.Count -gt 0) {
            # Modern CDDA determines smokability from COMESTIBLE smoking_result rather than
            # the removed SMOKABLE json flag. Remove only this undefined flag token.
            $patched = $raw
            $patched = [regex]::Replace($patched, '"SMOKABLE"\s*,\s*', '')
            $patched = [regex]::Replace($patched, ',\s*"SMOKABLE"', '')
            $patched = [regex]::Replace($patched, '"SMOKABLE"', '')
            Write-Utf8NoBom -Path $jsonFile.FullName -Text $patched
            $obsoleteFlagRefs += $matches.Count
            $obsoleteFlagFiles++
        }
    }
    Write-Host "Removed undefined SMOKABLE flag refs=$obsoleteFlagRefs files=$obsoleteFlagFiles" -ForegroundColor Green


    Write-Step 'Modernizing translation/plural schema'
    $pluralMap = @{
        'relinquished zombie''s body' = 'relinquished zombies'' bodies'
        'shapeshifter''s shadows' = 'shapeshifter''s shadows'
        'flesilisk''s bone needles (shower)' = 'flesilisk''s bone needles (shower)'
        'secronom dragon (armed)' = 'secronom dragons (armed)'
        'flesh' = 'flesh'
        'jawed flesh' = 'jawed flesh'
        'wall of flesh' = 'walls of flesh'
        'kaxix' = 'kaxix'
        'axxuros' = 'axxuros'
        'exios' = 'exios'
        'drexx' = 'drexx'
        'nautilus' = 'nautiluses'
        'ichorus' = 'ichorus'
        'psyrus' = 'psyrus'
        'uruxis' = 'uruxis'
        'nix' = 'nix'
        'equinox' = 'equinox'
        'necros' = 'necros'
        'flesh heap (blade)' = 'flesh heaps (blade)'
        'flesh heap (tendril)' = 'flesh heaps (tendril)'
        'flesh heap (mouthswell)' = 'flesh heaps (mouthswell)'
        'flesh heap (unifier)' = 'flesh heaps (unifier)'
        'lying body' = 'lying bodies'
    }

    $translationRelFiles = @(
        'Modification_Files\Items\secro_guns.json',
        'Modification_Files\Monsters\-Essentials\secro_ammo_zombie.json',
        'Modification_Files\Monsters\-Essentials\secro_gun_zombie.json',
        'Modification_Files\Monsters\Bots\SecronomDragon.json',
        'Modification_Files\Monsters\Crimson Horrors\Flesh.json',
        'Modification_Files\Monsters\Crimson Horrors\Flesh_biome.json',
        'Modification_Files\Monsters\Crimson Horrors\Flesh_spawns.json',
        'Modification_Files\Monsters\Unknown\___.json',
        'Modification_Files\Monsters\Zombies\+BOWs.json',
        'Modification_Files\Monsters\Zombies\+Misc.json',
        'Modification_Files\Monsters\Zombies\BO Turrets.json',
        'Modification_Files\Monsters\Zombies\Lying.json',
        'Modification_Files\Others\secro_event_trans_stats.json'
    )

    $samePluralCount = 0
    $mappedPluralCount = 0
    $translationFilesPatched = 0
    foreach ($relFile in $translationRelFiles) {
        $translationPath = Join-Path $targetModDir $relFile
        if (-not (Test-Path -LiteralPath $translationPath)) { continue }

        $beforeSame = $samePluralCount
        $beforeMapped = $mappedPluralCount
        $translationData = Get-Content -LiteralPath $translationPath -Raw | ConvertFrom-Json
        Update-TranslationObject -Node $translationData -ContextName '' -PluralMap $pluralMap -SamePluralCount ([ref]$samePluralCount) -MappedPluralCount ([ref]$mappedPluralCount)

        if ($samePluralCount -ne $beforeSame -or $mappedPluralCount -ne $beforeMapped) {
            Write-Utf8NoBom -Path $translationPath -Text (ConvertTo-JsonArraySafe -Items @($translationData) -Depth 100)
            $translationFilesPatched++
        }
    }
    Write-Host "Modernized translation objects: identical plural=$samePluralCount, mapped plural=$mappedPluralCount, files=$translationFilesPatched" -ForegroundColor Green

    Write-Step 'Verifying patched JSON root shapes'
    $rootShapeFiles = @(
        $legacyOverlay,
        $ammoEffectsPath,
        $gunsPath,
        $attacksPath,
        $mapExtrasPath,
        $ammoZombiePath
    )
    foreach ($wildlifePath in $wildlifeFiles) {
        $rootShapeFiles += $wildlifePath
    }
    foreach ($relFile in $translationRelFiles) {
        $rootShapeFiles += (Join-Path $targetModDir $relFile)
    }
    $rootShapeFiles = @(
        $rootShapeFiles |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -Unique
    )

    $rootShapeVerified = 0
    foreach ($jsonPath in $rootShapeFiles) {
        $rawCheck = Get-Content -LiteralPath $jsonPath -Raw
        $trimmedCheck = $rawCheck.TrimStart()

        if (-not $trimmedCheck.StartsWith('[')) {
            throw "Patched JSON root is not an array: $jsonPath"
        }

        # Reject the exact PowerShell 5.1 collection-wrapper signature from v1.0.
        if ($trimmedCheck -match '^\{\s*"value"\s*:') {
            throw "Detected PowerShell collection wrapper instead of JSON array: $jsonPath"
        }

        # Syntax validation.
        $null = $rawCheck | ConvertFrom-Json
        $rootShapeVerified++
    }
    Write-Host "Verified patched JSON array roots: $rootShapeVerified" -ForegroundColor Green

    $manifest = @"
Secronom Revival compatibility pass v$RevivalVersion
Upstream: https://github.com/Erin105/Secronom-Zombies
Pinned commit: $SourceCommit
Installed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Target build hint: $ExpectedBuildHint
Lore Expansion: NOT installed
Patch 001: Rebuilt obsolete region_overlay from the target build's vanilla map-extra collections (no self-copy circular dependencies).
Patch 002: Dropped legacy zero-weight map-extra entries (vector/fleshweaver).
Patch 003: Converted legacy ammo_effect aoe/trail single objects to modern arrays.
Patch 004: Replaced flesh-wildlife inherited species with SFLESH directly and removed stale flag deletes.
Patch 005: Replaced removed vanilla mapgen item groups pasta/pet_food/groce_cereal with modern ids.
Patch 006: Replaced removed firearm bases rifle_base/rifle_auto/rifle_semi with modern gun_base_rifle_* classes.
Patch 007: Renamed monster melee body_parts targeting to body_part_types.
Patch 008: Converted legacy map-extra autonote=true to autonote_visibility=same_tile.
Patch 009: Converted legacy transform active=true behavior to SPAWN_ACTIVE on the target grenade items.
Patch 010: Removed obsolete undefined SMOKABLE flag (modern CDDA uses smoking_result).
Patch 011: Moved all Revival backups outside data\mods so CDDA no longer loads duplicate modinfo.json files.
Patch 012: Cleared generated game-data cache before validation so patched JSON is never reported as stale.
Patch 013: Modernized translation objects: identical str/str_pl -> str_sp and explicit plurals for names CDDA cannot autogenerate.
Patch 014: Run an isolated preflight validator, use its exact text-style diagnostics to patch only flagged source lines, then validate again.
Patch 015: Clear generated game-data cache between preflight and final validation.
Patch 016: Run final --check-mods with an isolated user directory and capture fresh debug.log/crash.log.
Patch 017: Use a PowerShell 5.1-safe top-level JSON-array serializer and verify array roots before validation.
Legacy region overlay preserved as region_overlay.legacy.txt (not loaded by CDDA).
"@
    Write-Utf8NoBom -Path (Join-Path $targetModDir 'REVIVAL_SOURCE.txt') -Text $manifest

