param(
    [string]$GameRoot = "",
    [string]$OutputRoot = "",
    [switch]$NoInstall,
    [switch]$SkipCliCheck,
    [switch]$KeepSourceCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProjectName = "Aftershock_Prime"
$ModId = "aftershock_prime"
$CompatProjectName = "Aftershock_Prime_MoM_Compat"
$CompatModId = "aftershock_prime_mom_compat"
$UpstreamCommit = "e262adb299a7613b4aedc5f12c08fe0413c56a84"
$ExpectedBuild = "cdda_experimental_2026_09_23_0546"
$Repo = "CleverRaven/Cataclysm-DDA"
$SourcePrefix = "data/mods/aftershock_exoplanet"

if([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot "build"
}
$BuildRoot = Join-Path $OutputRoot $ProjectName
$CompatBuildRoot = Join-Path $OutputRoot $CompatProjectName
$CacheRoot = Join-Path $env:TEMP "AFSP"
$Archive = Join-Path $CacheRoot ("cdda_" + $UpstreamCommit + ".zip")
$ExtractRoot = Join-Path $CacheRoot "src"

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Normalize-Rel([string]$Path) {
    if($null -eq $Path) { return "" }
    $p = [string]$Path
    $p = $p -replace '\\', '/'
    $p = $p -replace '^/+', ''
    return $p
}

function Get-RelativePathPortable([string]$BasePath, [string]$FullPath) {
    $base = [System.IO.Path]::GetFullPath($BasePath)
    $full = [System.IO.Path]::GetFullPath($FullPath)

    $base = $base.TrimEnd([char[]]@([char]92, [char]47))

    if(-not $full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$full' is not inside base '$base'."
    }

    $rel = $full.Substring($base.Length)
    if($rel.Length -gt 0 -and ($rel[0] -eq [char]92 -or $rel[0] -eq [char]47)) {
        $rel = $rel.Substring(1)
    }

    $rel = $rel -replace '\\', '/'
    return $rel
}

function Get-JsonArray([string]$Path) {
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $obj = $raw | ConvertFrom-Json
    return @($obj)
}

function Set-JsonArray([string]$Path, [object[]]$Objects) {
    $json = @($Objects) | ConvertTo-Json -Depth 100
    Write-Utf8NoBom $Path ($json + "`n")
}

function Get-ObjectId($Obj) {
    if($null -ne $Obj.PSObject.Properties["id"]) { return [string]$Obj.id }
    if($null -ne $Obj.PSObject.Properties["abstract"]) { return "abstract:" + [string]$Obj.abstract }
    return ""
}

function Get-ObjectType($Obj) {
    if($null -ne $Obj.PSObject.Properties["type"]) { return [string]$Obj.type }
    return ""
}

function Find-GameRoot {
    if(-not [string]::IsNullOrWhiteSpace($GameRoot) -and (Test-Path $GameRoot)) {
        return (Resolve-Path $GameRoot).Path
    }

    $launcherBase = Join-Path $env:LOCALAPPDATA "com.munetmo.cat-launcher\Assets\DarkDaysAhead"
    if(Test-Path $launcherBase) {
        $exact = Join-Path $launcherBase $ExpectedBuild
        if(Test-Path $exact) { return (Resolve-Path $exact).Path }

        $newest = Get-ChildItem -LiteralPath $launcherBase -Directory -Filter "cdda_experimental_*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if($newest) { return $newest.FullName }
    }

    $cwd = (Get-Location).Path
    if((Test-Path (Join-Path $cwd "data\mods")) -and
       ((Test-Path (Join-Path $cwd "cataclysm-tiles.exe")) -or (Test-Path (Join-Path $cwd "cataclysm.exe")))) {
        return $cwd
    }
    return ""
}

function Remove-TreeRobust([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)) { return }

    # PowerShell 5.1 Remove-Item can be fragile with very large trees.
    # Try cmd/rmdir first, then fall back to PowerShell.
    try {
        & cmd.exe /d /c "rmdir /s /q `"$Path`"" | Out-Null
    } catch {}
    if(Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    if(Test-Path -LiteralPath $Path) {
        throw "Unable to remove stale cache directory: $Path"
    }
}

function Test-ExtractedAftershock([string]$Path) {
    $modinfo = Join-Path $Path "data\mods\aftershock_exoplanet\modinfo.json"
    $items = Join-Path $Path "data\mods\aftershock_exoplanet\items"
    $monsters = Join-Path $Path "data\mods\aftershock_exoplanet\monsters"
    return (Test-Path -LiteralPath $modinfo) -and
           (Test-Path -LiteralPath $items) -and
           (Test-Path -LiteralPath $monsters)
}

function Expand-AftershockOnly([string]$ZipPath, [string]$Destination) {
    Remove-TreeRobust $Destination
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $top = "Cataclysm-DDA-$UpstreamCommit"
    $wanted = "$top/data/mods/aftershock_exoplanet"

    # Extract ONLY Aftershock. This avoids Windows-incompatible Android archive entries
    # and avoids the enormous/deep full CDDA source tree.
    $tar = Get-Command "tar.exe" -ErrorAction SilentlyContinue
    if(-not $tar) {
        throw "tar.exe is required for selective extraction on Windows 10/11 but was not found."
    }

    Write-Host "Extracting only data/mods/aftershock_exoplanet to short TEMP path ..."
    & $tar.Source -xf $ZipPath -C $Destination "$wanted"
    if($LASTEXITCODE -ne 0) {
        throw "Selective tar extraction failed with exit code $LASTEXITCODE."
    }

    $nested = Join-Path $Destination $top
    if(-not (Test-ExtractedAftershock $nested)) {
        throw "Selective extraction completed but Aftershock source is incomplete."
    }

    return $nested
}

function Download-SourceArchive {
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

    if(Test-ExtractedAftershock (Join-Path $ExtractRoot "Cataclysm-DDA-$UpstreamCommit")) {
        return
    }

    if(-not (Test-Path -LiteralPath $Archive)) {
        $url = "https://codeload.github.com/$Repo/zip/$UpstreamCommit"
        Write-Host "Downloading pinned CDDA source $UpstreamCommit ..."
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Archive
    } else {
        Write-Host "Using cached source archive: $Archive"
    }

    try {
        [void](Expand-AftershockOnly $Archive $ExtractRoot)
    } catch {
        Write-Warning "Selective extraction failed: $($_.Exception.Message)"
        Write-Warning "Discarding cached archive and downloading a clean copy ..."
        if(Test-Path -LiteralPath $Archive) {
            Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
        }
        Remove-TreeRobust $ExtractRoot
        $url = "https://codeload.github.com/$Repo/zip/$UpstreamCommit"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Archive
        [void](Expand-AftershockOnly $Archive $ExtractRoot)
    }
}

function Get-SourceRoot {
    $root = Join-Path $ExtractRoot "Cataclysm-DDA-$UpstreamCommit"
    if(-not (Test-ExtractedAftershock $root)) {
        throw "Unable to locate selectively extracted Aftershock source."
    }
    return $root
}

$RootAllow = @(
    "ascii.json",
    "damage_types.json",
    "effects.json",
    "effects_on_condition.json",
    "emit.json",
    "field.json",
    "flags.json",
    "martialarts.json",
    "requirements.json",
    "skills.json",
    "speech.json",
    "ter_fur_transform.json",
    "ui.json",
    "vitamin.json"
)

$EocAllow = @(
    "EOC/cryosuit_eocs.json",
    "EOC/data_salvage.json",
    "EOC/drug_eoc.json",
    "EOC/game_eoc.json",
    "EOC/hacking_eoc.json",
    "EOC/hacking_results_eoc.json",
    "EOC/monster_weakpoint_eocs.json",
    "EOC/tool_iuse_eoc.json"
)

$PlayerAllow = @(
    "player/activities.json",
    "player/bionic_eocs.json",
    "player/bionics.json",
    "player/techniques.json"
)

$MapAllowPrefixes = @(
    "maps/furniture_and_terrain/"
)
$MapAllowFiles = @(
    "maps/furniture.json",
    "maps/furniture_lab.json",
    "maps/ter_furn_transforms.json"
)

$MapDenyFiles = @(
    "maps/furniture_and_terrain/furniture_spaceship.json",
    "maps/furniture_and_terrain/terrain_spaceship.json"
)

$MutationDeny = @(
    "mutations/esper.json",
    "mutations/origins.json",
    "mutations/vanilla_overrides.json"
)

$ItemDeny = @(
    "items/bionics_mainline_override.json",
    "items/espertech.json",
    "items/obsolete.json"
)

$RecipeDenyPrefixes = @(
    "recipes/esper/",
    "recipes/basecamps/"
)
$RecipeDenyFiles = @(
    "recipes/blacklist.json",
    "recipes/recipe_overrides.json"
)

$SpellDenyPrefixes = @(
    "spells/psionics/"
)

$VehicleDenyFiles = @(
    "vehicles/vehicle_overrides.json"
)

function Should-Include([string]$Rel) {
    $Rel = Normalize-Rel $Rel
    if($RootAllow -contains $Rel) { return $true }
    if($EocAllow -contains $Rel) { return $true }
    if($PlayerAllow -contains $Rel) { return $true }
    if($MapDenyFiles -contains $Rel) { return $false }
    if($MapAllowFiles -contains $Rel) { return $true }
    foreach($p in $MapAllowPrefixes) { if($Rel.StartsWith($p)) { return $true } }

    if($Rel.StartsWith("faults/")) { return $true }

    if($Rel.StartsWith("items/")) {
        if($ItemDeny -contains $Rel) { return $false }
        return $true
    }

    if($Rel.StartsWith("itemgroups/")) { return $true }
    if($Rel.StartsWith("monster_attacks/")) { return $true }
    if($Rel.StartsWith("monsterdrops/")) { return $true }
    if($Rel.StartsWith("monsters/")) { return $true }

    if($Rel.StartsWith("mutations/")) {
        if($MutationDeny -contains $Rel) { return $false }
        return $true
    }

    if($Rel.StartsWith("recipes/")) {
        if($RecipeDenyFiles -contains $Rel) { return $false }
        foreach($p in $RecipeDenyPrefixes) { if($Rel.StartsWith($p)) { return $false } }
        return $true
    }

    if($Rel.StartsWith("snippets/")) { return $true }

    if($Rel.StartsWith("spells/")) {
        foreach($p in $SpellDenyPrefixes) { if($Rel.StartsWith($p)) { return $false } }
        return $true
    }

    if($Rel.StartsWith("vehicles/")) {
        if($VehicleDenyFiles -contains $Rel) { return $false }
        return $true
    }

    return $false
}

function Build-ExternalIndex([string]$InstalledGameRoot) {
    if([string]::IsNullOrWhiteSpace($InstalledGameRoot) -or -not (Test-Path $InstalledGameRoot)) {
        throw "A valid GameRoot is required for collision indexing."
    }

    Write-Host "Building collision index from the installed target game ..."
    $index = @{}
    $roots = @(
        (Join-Path $InstalledGameRoot "data\json"),
        (Join-Path $InstalledGameRoot "data\mods\Xedra_Evolved"),
        (Join-Path $InstalledGameRoot "data\mods\Magiclysm"),
        (Join-Path $InstalledGameRoot "data\mods\MindOverMatter"),
        (Join-Path $InstalledGameRoot "data\mods\No_NPC_Food")
    )

    foreach($r in $roots) {
        if(-not (Test-Path $r)) {
            Write-Warning "Collision-index source not found: $r"
            continue
        }
        foreach($f in Get-ChildItem -LiteralPath $r -Recurse -File -Filter "*.json") {
            try {
                foreach($o in Get-JsonArray $f.FullName) {
                    $t = Get-ObjectType $o
                    $id = Get-ObjectId $o
                    if($t -and $id) {
                        $index[$t + "|" + $id] = $true
                    }
                }
            } catch {
                # The game's own --check-mods pass remains authoritative.
            }
        }
    }

    Write-Host "External collision index keys: $($index.Count)"
    return $index
}

function Copy-Selected([string]$AftershockRoot) {
    if(Test-Path $BuildRoot) { Remove-Item -LiteralPath $BuildRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null

    $resolvedRoot = (Resolve-Path -LiteralPath $AftershockRoot).Path
    Write-Host "Aftershock source root: $resolvedRoot"

    $included = New-Object System.Collections.Generic.List[string]
    $excluded = New-Object System.Collections.Generic.List[string]
    $debugShown = 0

    $jsonFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter "*.json")
    Write-Host "Source JSON discovered: $($jsonFiles.Count)"

    foreach($f in $jsonFiles) {
        $rel = Get-RelativePathPortable $resolvedRoot $f.FullName
        $decision = Should-Include $rel

        if($debugShown -lt 12) {
            Write-Host "PATH PROBE: '$rel' => include=$decision"
            $debugShown++
        }

        if($decision) {
            $dstRel = $rel -replace '/', '\'
            $dst = Join-Path $BuildRoot $dstRel
            $parent = Split-Path -Parent $dst
            if($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            $included.Add($rel)
        } else {
            $excluded.Add($rel)
        }
    }

    Write-Host "Selected JSON copied: $($included.Count); excluded: $($excluded.Count)"

    if($included.Count -eq 0) {
        Write-Host "First excluded paths:" -ForegroundColor Yellow
        foreach($p in @($excluded | Select-Object -First 20)) {
            Write-Host " - $p" -ForegroundColor Yellow
        }
        throw "Copy selection produced zero JSON files. See PATH PROBE above."
    }

    $probeFiles = @(
        "items\armor\exosuit\exosuit_frame.json",
        "items\cbms.json",
        "monsters\robots.json",
        "items\genetech.json",
        "vehicles\vehicles.json"
    )
    foreach($probe in $probeFiles) {
        $probePath = Join-Path $BuildRoot $probe
        if(Test-Path -LiteralPath $probePath) {
            Write-Host "COPY PROBE OK: $probe"
        } else {
            Write-Warning "COPY PROBE MISSING: $probe"
        }
    }

    return @{ included = $included; excluded = $excluded }
}

$ForbiddenIds = @(
    "AFS_ELECTROKINETIC",
    "AFS_PRECOG",
    "AFS_TELEKINETIC",
    "AFS_TELEPATH",
    "ESPER",
    "ESPER_ADVANCEMENT_OKAY",
    "ESPER_STARTER_ADVANCEMENT_OKAY",
    "CANNOT_GAIN_PSIONICS",
    "vitamin_afs_maintained_powers",
    "aftershock_psionics",
    "prof_concentration",
    "prof_concentration_basic",
    "prof_concentration_intermediate",
    "prof_concentration_master",
    "TEEPSHIELD",
    "TELEKIN_SHIELD",
    "TELEKIN_IMMUNE"
)

$KeepFromVanillaOverrides = @(
    "AFS_NIGHTVISION",
    "AFS_UNCARING",
    "AFS_QUICK",
    "AFS_INFIMMUNE",
    "AFS_PAINRESIST",
    "AFS_GOODCARDIO"
)

# These are representative objects from every major imported subsystem.
# If a collision index claims several of these already exist in vanilla/Xedra/Magiclysm/MoM,
# the index is considered contaminated and no broad pruning is allowed.
$ProtectedImportedIds = @(
    "modular_exosuit",
    "modular_exosuit_light",
    "exo_back_battery_rechargable",
    "exo_jetpack",
    "exo_gantry",
    "bio_microgen",
    "afs_bio_missiles",
    "afs_bio_monowhip",
    "afs_bio_translocator",
    "bio_shield_weak",
    "bio_shield_medium",
    "bio_shield_heavy",
    "afs_backpack_shieldgen",
    "afs_v29",
    "laser_cannon_xray",
    "afs_voltaic_pistol",
    "afs_needlegun",
    "afs_marsec_t72",
    "afs_pam-41",
    "mon_utilibot",
    "mon_medibot",
    "mon_wraitheon_imaginifer",
    "mon_scavbot_needle",
    "bot_utilibot_beehive",
    "afs_gene_disp",
    "afs_gene_template_combat_brute",
    "AFS_PHYSICAL_CAPABILITY_GENEMOD",
    "THRESH_COMBAT_BRUTE",
    "compact_atomic",
    "armored_robot_carrier",
    "light_cycle",
    "uica_lynx_ex",
    "afs_jetpack",
    "afs_translocation_device",
    "afs_power_cutter",
    "afs_imager",
    "f_crispr",
    "f_gene_editor",
    "ap_exo_gantry",
    "nano_forge",
    "diamond_press",
    "afs_battery_charger",
    "afs_cRTG",
    "afs_exo_basic_accessories",
    "afs_exosuits_civ",
    "afs_exosuit_military",
    "afs_wintersuit_science_advanced",
    "afs_genetech_commerical_safe",
    "afs_energy_weapon_armory",
    "afs_ballistic_armory",
    "afs_grenade_armory",
    "afs_armor_military_infantry_g",
    "afs_experimental_combat_gear"
)

function Verify-ImportedCore([string]$Stage) {
    $ids = Get-AllObjectIds $BuildRoot
    $missing = @()

    Write-Host "Verifying imported core at stage '$Stage' against $($ProtectedImportedIds.Count) sentinels ..."

    foreach($id in $ProtectedImportedIds) {
        if(-not $ids.ContainsKey($id)) { $missing += $id }
    }

    if($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "IMPORT VERIFICATION FAILED at stage '$Stage':" -ForegroundColor Red
        Write-Host "Indexed unique IDs: $($ids.Count)" -ForegroundColor Yellow
        foreach($id in $missing) { Write-Host " - Missing imported ID: $id" -ForegroundColor Red }
        throw "Imported Aftershock core is incomplete before final integration."
    }

    Write-Host "Imported-core verification passed at stage '$Stage' ($($ProtectedImportedIds.Count) sentinel IDs)." -ForegroundColor Green
}

function Apply-KnownTransforms([string]$AftershockRoot) {
    # 1) Remove dedicated Aftershock psi infrastructure that overlaps Mind Over Matter.
    foreach($rel in @("damage_types.json","skills.json","vitamin.json","flags.json","effects_on_condition.json")) {
        $p = Join-Path $BuildRoot $rel
        if(-not (Test-Path $p)) { continue }
        $arr = Get-JsonArray $p
        $out = @()
        foreach($o in $arr) {
            $id = Get-ObjectId $o
            if($rel -eq "skills.json") {
                if($id -eq "smartgun") { $out += $o }
                continue
            }
            if($ForbiddenIds -contains $id) { continue }
            if($id -like "psi_telekinetic_damage" -or $id -like "psi_telepathic_damage") { continue }
            if($id -like "EOC_TELEKINETIC_DAMAGE_*" -or $id -like "EOC_TELEPATHIC_DAMAGE_*") { continue }
            if($id -eq "afs_night_messages" -or
               $id -eq "EOC_ESCAPE_POD_CHAIR" -or
               $id -eq "EOC_CRASHING_SHIP_SETUP" -or
               $id -eq "EOC_CRASHING_SHIP_U_DIE" -or
               $id -eq "EOC_ESPER_SCENARIO_SETUP") { continue }
            $out += $o
        }
        Set-JsonArray $p $out
    }

    # 2) game_eoc: keep shield UI initialization only.
    $gameEoc = Join-Path $BuildRoot "EOC\game_eoc.json"
    if(Test-Path $gameEoc) {
        $arr = Get-JsonArray $gameEoc
        Set-JsonArray $gameEoc @($arr | Where-Object { (Get-ObjectId $_) -eq "EOC_START_SHIELD_UI" })
    }

    # 3) Vanilla mutation overrides: preserve only AFS-namespaced helper clones.
    $srcVanillaOverrides = Join-Path $AftershockRoot "mutations\vanilla_overrides.json"
    $dstVanillaOverrides = Join-Path $BuildRoot "mutations\vanilla_overrides_prime.json"
    if(Test-Path $srcVanillaOverrides) {
        $arr = Get-JsonArray $srcVanillaOverrides
        $keep = @($arr | Where-Object {
            $id = Get-ObjectId $_
            $isSelfMutationOverlay = (
                (Get-ObjectType $_) -eq "mutation" -and
                $null -ne $_.PSObject.Properties["copy-from"] -and
                [string]$_.'copy-from' -eq $id
            )
            ($KeepFromVanillaOverrides -contains $id) -or $isSelfMutationOverlay
        })
        if($keep.Count -gt 0) { Set-JsonArray $dstVanillaOverrides $keep }
    }

    # 4) Human+ genemods originally cancel Aftershock Esper gate traits.
    # Prime intentionally has no Aftershock Esper system, so remove only those two stale references.
    $humanPlus = Join-Path $BuildRoot "mutations\human_plus.json"
    if(Test-Path $humanPlus) {
        $arr = Get-JsonArray $humanPlus
        foreach($o in $arr) {
            if($null -ne $o.PSObject.Properties["cancels"]) {
                $o.cancels = @($o.cancels | Where-Object {
                    $_ -ne "ESPER_ADVANCEMENT_OKAY" -and $_ -ne "ESPER_STARTER_ADVANCEMENT_OKAY"
                })
            }
        }
        Set-JsonArray $humanPlus $arr
    }

    # 5) Remove the remaining Esper tincture group and its reference from the otherwise useful alien-tech group.
    $alienGroups = Join-Path $BuildRoot "itemgroups\alien_civ_itemgroups.json"
    if(Test-Path $alienGroups) {
        $arr = Get-JsonArray $alienGroups
        $out = @()
        foreach($o in $arr) {
            $id = Get-ObjectId $o
            if($id -eq "afs_espertech_tinctures") { continue }
            if($id -eq "alienciv_artifact_5" -and $null -ne $o.PSObject.Properties["entries"]) {
                $o.entries = @($o.entries | Where-Object {
                    -not ($null -ne $_.PSObject.Properties["group"] -and [string]$_.group -eq "afs_espertech_tinctures")
                })
            }
            $out += $o
        }
        Set-JsonArray $alienGroups $out
    }

    # 6) Runtime-safe hacking closure.
    #
    # Upstream hacking_eoc.json defines three local jmath_function helpers.
    # Static --check-mods accepts them, but real world loading on this target
    # build can resolve EOC expressions before those helpers are callable.
    # Preserve the exact formulas by inlining them and removing the helpers.
    $hackingEoc = Join-Path $BuildRoot "EOC\hacking_eoc.json"
    if(Test-Path -LiteralPath $hackingEoc) {
        $rawHack = Get-Content -LiteralPath $hackingEoc -Raw -Encoding UTF8

        $rawHack = $rawHack.Replace(
            "_t_delay = afs_hack_time_adjust(_t_delay, time('20s'), time('2m'))",
            "_t_delay = _t_delay - time('20s') * (u_skill('computer') + u_val('intelligence') / 3 + u_hack_bonus) < time('2m') ? time('2m') : _t_delay - time('20s') * (u_skill('computer') + u_val('intelligence') / 3 + u_hack_bonus)"
        )
        $rawHack = $rawHack.Replace(
            "u_hack_bonus = afs_hack_bonus( n_quality('HACK'), u_val('focus') )",
            "u_hack_bonus = n_quality('HACK') + trunc( 4 * ( ( u_val('focus') - 100 ) / 100 ) )"
        )
        $rawHack = $rawHack.Replace(
            "afs_hack_skill(1)",
            "(u_skill('computer') + u_val('intelligence') / 3 + u_hack_bonus)"
        )

        Write-Utf8NoBom $hackingEoc $rawHack

        $hackObjects = Get-JsonArray $hackingEoc
        $hackObjects = @($hackObjects | Where-Object {
            $hackId = Get-ObjectId $_
            -not (
                (Get-ObjectType $_) -eq "jmath_function" -and
                $hackId -in @("afs_hack_skill","afs_hack_time_adjust","afs_hack_bonus")
            )
        })
        Set-JsonArray $hackingEoc $hackObjects
    }

    # 7) Salus-only shuttle beacon calls an EOC supplied by excluded planetary travel content.
    $tools = Join-Path $BuildRoot "items\tools.json"
    if(Test-Path $tools) {
        $arr = Get-JsonArray $tools
        Set-JsonArray $tools @($arr | Where-Object { (Get-ObjectId $_) -ne "afs_shuttle_radiobeacon" })
    }

    # 8) The Salus shuttle radio beacon was removed above; remove its dedicated
    # ammo item and ammunition_type as well so no orphaned ammotype survives.
    foreach($rel in @("items\ammo\ammo.json","items\ammo_type.json")) {
        $p = Join-Path $BuildRoot $rel
        if(-not (Test-Path $p)) { continue }
        $arr = Get-JsonArray $p
        Set-JsonArray $p @($arr | Where-Object { (Get-ObjectId $_) -ne "afs_shuttle_beacon" })
    }

    # 9) Current vanilla kelp_sugar volume no longer fits nine units in the old foil bag.
    # Preserve the group but make the overflow behavior explicit, as current item-group schema expects.
    $foodGroups = Join-Path $BuildRoot "itemgroups\food_groups.json"
    if(Test-Path $foodGroups) {
        $arr = Get-JsonArray $foodGroups
        foreach($o in $arr) {
            if((Get-ObjectId $o) -eq "afs_kelp_afs_foil_bag_9") {
                $o | Add-Member -NotePropertyName "on_overflow" -NotePropertyValue "spill" -Force
            }
        }
        Set-JsonArray $foodGroups $arr
    }

    # 10) No original world/scenario/NPC/global/Salus-only files may survive.
    $mustNotExist = @(
        "game_balance.json",
        "options.json",
        "jmath.json",
        "scenarios.json",
        "start_locations.json",
        "weather_type.json",
        "traps.json",
        "items\bionics_mainline_override.json",
        "items\obsolete.json",
        "vehicles\vehicle_overrides.json",
        "recipes\recipe_overrides.json",
        "maps\vanilla_map_weight_eocs.json",
        "maps\furniture_and_terrain\furniture_spaceship.json",
        "maps\furniture_and_terrain\terrain_spaceship.json"
    )
    foreach($rel in $mustNotExist) {
        $p = Join-Path $BuildRoot $rel
        if(Test-Path $p) { Remove-Item -LiteralPath $p -Force }
    }
    foreach($dir in @("region_settings","setting_blacklists","price_overrides","npcs","missions","mod_interactions")) {
        $p = Join-Path $BuildRoot $dir
        if(Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
}

function Remove-ExternalCollisions($ExternalIndex) {
    Write-Host "Auditing object ID collisions with vanilla/Xedra/Magiclysm/MoM ..."
    $report = New-Object System.Collections.Generic.List[object]

    # First pass: count candidate collisions without modifying anything.
    $candidateCount = 0
    $protectedCollisionCount = 0
    foreach($f in Get-ChildItem -LiteralPath $BuildRoot -Recurse -File -Filter "*.json") {
        try { $arr = Get-JsonArray $f.FullName } catch { continue }
        foreach($o in $arr) {
            $t = Get-ObjectType $o
            $id = Get-ObjectId $o
            if(-not $t -or -not $id) { continue }

            $key = $t + "|" + $id
            if($ExternalIndex.ContainsKey($key)) {
                $candidateCount++
                if($ProtectedImportedIds -contains $id) { $protectedCollisionCount++ }
            }
        }
    }

    Write-Host "Collision candidates: $candidateCount; protected-core candidates: $protectedCollisionCount"

    # A healthy external index should not claim that a broad cross-section of unique Aftershock
    # content already exists in vanilla/our other mods. If it does, fail safe: audit only.
    $auditOnly = $protectedCollisionCount -ge 3
    if($auditOnly) {
        Write-Warning "Collision index appears contaminated/unreliable (>=3 protected Aftershock IDs collide)."
        Write-Warning "Switching to AUDIT-ONLY mode. Known dangerous collisions were already removed explicitly."
    }

    foreach($f in Get-ChildItem -LiteralPath $BuildRoot -Recurse -File -Filter "*.json") {
        try {
            $arr = Get-JsonArray $f.FullName
        } catch {
            continue
        }

        $changed = $false
        $out = @()

        foreach($o in $arr) {
            $t = Get-ObjectType $o
            $id = Get-ObjectId $o

            if(-not $t -or -not $id) {
                $out += $o
                continue
            }

            $key = $t + "|" + $id
            if(-not $ExternalIndex.ContainsKey($key)) {
                $out += $o
                continue
            }

            $semanticMutationOverlay = (
                $t -eq "mutation" -and
                $null -ne $o.PSObject.Properties["copy-from"] -and
                [string]$o.'copy-from' -eq $id
            )
            $protected = ($ProtectedImportedIds -contains $id) -or $semanticMutationOverlay
            $action = if($semanticMutationOverlay) {
                "kept_semantic_overlay"
            } elseif($auditOnly -or $protected) {
                "kept_audit"
            } else {
                "pruned"
            }

            $report.Add([pscustomobject]@{
                file = Normalize-Rel ($f.FullName.Substring($BuildRoot.Length))
                type = $t
                id = $id
                action = $action
            })

            if($auditOnly -or $protected) {
                $out += $o
            } else {
                $changed = $true
            }
        }

        if($changed) {
            if($out.Count -eq 0) {
                Remove-Item -LiteralPath $f.FullName -Force
            } else {
                Set-JsonArray $f.FullName $out
            }
        }
    }

    return $report
}

function Write-ModInfo {
    $obj = @(
        [ordered]@{
            type = "MOD_INFO"
            id = $ModId
            name = "Aftershock: Prime Integration"
            authors = @("Aftershock contributors", "Prime integration generated for compatibility")
            maintainers = @("local integration package")
            description = "A compatibility-focused port of portable Aftershock technology into standard Cataclysm: DDA, keeping exosuits, cybernetics, robotics, advanced weapons, genetech and selected vehicles while excluding Salus IV world conversion, Aftershock Esper psionics and global gameplay overrides."
            category = "content"
            dependencies = @("dda")
            conflicts = @("aftershock_exoplanet")
        }
    )
    Set-JsonArray (Join-Path $BuildRoot "modinfo.json") $obj
}

function Write-IntegrationLayer {
    # Write these as literal JSON so nested weighted arrays are never flattened by PowerShell.
    $lootJson = @'
[
  {
    "type": "item_group",
    "id": "science",
    "copy-from": "science",
    "extend": {
      "items": [
        { "group": "afs_exo_basic_accessories", "prob": 1 },
        { "group": "afs_exosuits_civ", "prob": 1 },
        { "group": "afs_wintersuit_science_advanced", "prob": 1 },
        { "group": "afs_genetech_commerical_safe", "prob": 1 },
        { "group": "afs_energy_weapon_armory", "prob": 1 },
        { "item": "bionic_maintenance_toolkit", "prob": 2 },
        { "item": "afs_backpack_shieldgen", "prob": 1 },
        { "item": "afs_translocation_device", "prob": 1 },
        { "item": "afsp_gene_editor_kit", "prob": 1 },
        { "item": "ap_exo_gantry", "prob": 1 },
        { "item": "nano_forge", "prob": 1 },
        { "item": "diamond_press", "prob": 1 },
        { "item": "afs_battery_charger", "prob": 1 },
        { "item": "afs_cRTG", "prob": 1 },
        { "item": "schematics_nano_forge", "prob": 1 },
        { "item": "schematics_diamond_press", "prob": 1 },
        { "item": "exosuit_maintenance", "prob": 2 },
        { "item": "recipe_augs", "prob": 1 },
        { "item": "recipe_unusual_ammos", "prob": 1 },
        { "item": "recipes_cryolab", "prob": 1 },
        { "item": "recipes_resistance", "prob": 1 },
        { "item": "recipe_uplift", "prob": 1 },
        { "item": "millyficents_diary", "prob": 1 },
        { "item": "textbook_atomic", "prob": 1 }
      ]
    }
  },
  {
    "type": "item_group",
    "id": "chem_lab",
    "copy-from": "chem_lab",
    "extend": {
      "items": [
        { "group": "afs_genetech_commerical_safe", "prob": 1 },
        { "item": "afs_gene_disp_low_tier", "prob": 1 }
      ]
    }
  },
  {
    "type": "item_group",
    "id": "guns_milspec",
    "copy-from": "guns_milspec",
    "extend": {
      "items": [
        { "group": "afs_ballistic_armory", "prob": 2 },
        { "group": "afs_energy_weapon_armory", "prob": 1 },
        { "group": "afs_grenade_armory", "prob": 1 }
      ]
    }
  },
  {
    "type": "item_group",
    "id": "mil_armor",
    "copy-from": "mil_armor",
    "extend": {
      "items": [
        { "group": "afs_exosuit_military", "prob": 1 },
        { "group": "afs_armor_military_infantry_g", "prob": 2 },
        { "group": "afs_experimental_combat_gear", "prob": 1 },
        { "item": "afs_backpack_shieldgen", "prob": 1 },
        { "item": "afs_military_cloak", "prob": 2 }
      ]
    }
  },
  {
    "type": "item_group",
    "id": "hardware",
    "copy-from": "hardware",
    "extend": {
      "items": [
        [ "afs_power_cutter", 1 ],
        [ "afs_imager", 1 ],
        [ "afs_plasma_torch", 1 ]
      ]
    }
  },
  {
    "type": "item_group",
    "id": "schematics",
    "copy-from": "schematics",
    "extend": {
      "items": [
        [ "schematics_copbot", 4 ],
        [ "schematics_eyebot", 4 ],
        [ "schematics_hazmatbot", 4 ],
        [ "schematics_riotbot", 3 ],
        [ "schematics_skitterbot", 4 ],
        [ "schematics_chickenbot", 1 ],
        [ "schematics_tankbot", 1 ],
        [ "schematics_tripod", 1 ]
      ]
    }
  },
  {
    "type": "item_group",
    "id": "bionics",
    "copy-from": "bionics",
    "extend": {
      "items": [
        [ "bio_microgen", 1 ],
        [ "afs_bio_missiles", 2 ],
        [ "afs_bio_monowhip", 2 ],
        [ "afs_bio_blood_plus", 1 ],
        [ "afs_bio_deck", 1 ],
        [ "afs_bio_beavy_batteries", 1 ],
        [ "afs_bio_blood_brain", 1 ],
        [ "afs_bio_linguistic_coprocessor", 2 ],
        [ "afs_bio_dopamine_stimulators", 2 ],
        [ "afs_bio_melee_counteraction", 1 ],
        [ "afs_bio_melee_optimization_unit", 1 ],
        [ "afs_bio_neurosoft_aeronautics", 1 ],
        [ "afs_bio_chemical_enhancement_rig", 1 ],
        [ "afs_bio_skullgun", 1 ],
        [ "afs_bio_translocator", 1 ],
        [ "bio_cold_absorber", 2 ],
        [ "bio_shield_weak", 2 ],
        [ "bio_shield_medium", 1 ],
        [ "bio_shield_heavy", 1 ]
      ]
    }
  },
  {
    "type": "item_group",
    "id": "tools_medical",
    "subtype": "collection",
    "copy-from": "tools_medical",
    "extend": {
      "entries": [
        { "item": "bionic_maintenance_toolkit", "prob": 3 }
      ]
    }
  },
  {
    "type": "item_group",
    "id": "nanofab_recipes",
    "subtype": "distribution",
    "copy-from": "nanofab_recipes",
    "extend": {
      "entries": [
        { "item": "afs_archeotech_cartridge", "prob": 2 },
        { "item": "afs_translocation_device", "prob": 1 }
      ]
    }
  }
]
'@
    Write-Utf8NoBom (Join-Path $BuildRoot "prime_integration_loot.json") ($lootJson + "`n")

    # VehicleGroup::load() appends to an existing group. Tiny weights keep these genuinely rare.
    $vehicleJson = @'
[
  {
    "type": "vehicle_group",
    "id": "parkinglot",
    "vehicles": [
      [ "compact_atomic", 1 ],
      [ "car_atomic", 1 ],
      [ "suv_atomic", 1 ],
      [ "car_sports_atomic", 1 ],
      [ "robotic_taxi", 1 ],
      [ "bubble_car", 1 ],
      [ "light_cycle", 1 ]
    ]
  },
  {
    "type": "vehicle_group",
    "id": "city_vehicles",
    "vehicles": [
      [ "robotic_taxi", 1 ],
      [ "compact_atomic", 1 ],
      [ "policecar_atomic", 1 ]
    ]
  },
  {
    "type": "vehicle_group",
    "id": "military_vehicles",
    "vehicles": [
      [ "armored_robot_carrier", 2 ],
      [ "uica_lynx_ex", 1 ]
    ]
  }
]
'@
    Write-Utf8NoBom (Join-Path $BuildRoot "prime_integration_vehicles.json") ($vehicleJson + "`n")

    # MonsterGroupManager appends when the group already exists unless override:true.
    $monsterJson = @'
[
  {
    "type": "monstergroup",
    "id": "GROUP_ROBOT",
    "monsters": [
      { "monster": "mon_utilibot_hostile", "weight": 3, "cost_multiplier": 1 },
      { "monster": "mon_skitterbot_hunter", "weight": 2, "cost_multiplier": 1 },
      { "monster": "mon_bloodhound_drone", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_medibot", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_afs_copbot", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_afs_riotbot", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_wraitheon_imaginifer", "weight": 1, "cost_multiplier": 1, "starts": "180 days" },
      { "monster": "mon_tankbot", "weight": 1, "cost_multiplier": 1, "starts": "270 days" }
    ]
  },
  {
    "type": "monstergroup",
    "id": "GROUP_LAB",
    "monsters": [
      { "monster": "mon_medibot", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_utilibot_hostile", "weight": 1, "cost_multiplier": 1 },
      { "monster": "mon_skitterbot_rat", "weight": 1, "cost_multiplier": 1 }
    ]
  }
]
'@
    Write-Utf8NoBom (Join-Path $BuildRoot "prime_integration_monsters.json") ($monsterJson + "`n")

    # Genetech needs the functional Mercurial resequencer (f_gene_editor / genemill).
    # Prime imports the furniture definition but not Salus mapgen, so this portable kit
    # makes the real gene editor deployable in ordinary New England.
    $supportJson = @'
[
  {
    "type": "ITEM",
    "subtypes": [ "TOOL" ],
    "id": "afsp_gene_editor_kit",
    "name": { "str": "portable gene resequencer kit" },
    "description": "A transport-crated gene resequencer assembled from advanced laboratory hardware.  Activate it to deploy a functional gene editor.  This Prime Integration item exists so Aftershock genetech remains usable without importing Salus IV map generation.",
    "weight": "48 kg",
    "volume": "55 L",
    "price": "25 kUSD",
    "price_postapoc": "250 USD",
    "material": [ "steel", "plastic" ],
    "symbol": ";",
    "color": "light_blue",
    "use_action": { "type": "deploy_furn", "furn_type": "f_gene_editor" }
  },
  {
    "type": "MIGRATION",
    "id": "xray_laser_barrel",
    "replace": "UICA_1d"
  },
  {
    "type": "MIGRATION",
    "id": "damaged_exo_helmet_steel",
    "replace": "exo_helmet_steel"
  },
  {
    "type": "MIGRATION",
    "id": "damaged_exo_torso_steel",
    "replace": "exo_torso_steel"
  },
  {
    "type": "MIGRATION",
    "id": "damaged_exo_arm_steel",
    "replace": "exo_arm_steel"
  },
  {
    "type": "MIGRATION",
    "id": "damaged_exo_leg_steel",
    "replace": "exo_leg_steel"
  },
  {
    "type": "recipe_category",
    "id": "CC_ELECTRONIC",
    "copy-from": "CC_ELECTRONIC",
    "extend": { "recipe_subcategories": [ "CSC_ELECTRONIC_CBMS" ] }
  },
  {
    "type": "recipe",
    "activity_level": "LIGHT_EXERCISE",
    "result": "afsp_gene_editor_kit",
    "category": "CC_ELECTRONIC",
    "subcategory": "CSC_ELECTRONIC_TOOLS",
    "skill_used": "electronics",
    "skills_required": [ [ "fabrication", 8 ], [ "computer", 5 ], [ "firstaid", 5 ] ],
    "difficulty": 8,
    "time": "12 h",
    "autolearn": [ [ "electronics", 8 ], [ "fabrication", 8 ] ],
    "using": [ [ "soldering_standard", 50 ], [ "welding_standard", 20 ] ],
    "components": [
      [ [ "afs_circuitry_3", 4 ] ],
      [ [ "afs_energy_storage_2", 4 ] ],
      [ [ "afs_material_2", 8 ] ],
      [ [ "small_lcd_screen", 2 ] ],
      [ [ "cable", 6 ] ],
      [ [ "plastic_sheet", 10 ] ],
      [ [ "lc_steel_chunk", 8 ] ]
    ]
  }
]
'@
    Write-Utf8NoBom (Join-Path $BuildRoot "prime_support_items.json") ($supportJson + "`n")
}

function Get-AllObjectIds([string]$Root) {
    $index = @{}
    $filesParsed = 0
    $objectsSeen = 0

    foreach($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.json") {
        try {
            $arr = Get-JsonArray $f.FullName
            $filesParsed++
            foreach($o in $arr) {
                $objectsSeen++
                $id = Get-ObjectId $o
                if($id) { $index[$id] = $true }
            }
        } catch {
            Write-Warning "ID index skipped unreadable JSON: $($f.FullName) :: $($_.Exception.Message)"
        }
    }

    Write-Host "ID index: $($index.Count) unique IDs from $filesParsed JSON files / $objectsSeen objects."
    return $index
}


function Write-MoMCompatLayer {
    if(Test-Path -LiteralPath $CompatBuildRoot) {
        Remove-TreeRobust $CompatBuildRoot
    }
    New-Item -ItemType Directory -Path $CompatBuildRoot -Force | Out-Null

    $modInfo = @(
        [ordered]@{
            type = "MOD_INFO"
            id = $CompatModId
            name = "Aftershock Prime - Mind Over Matter Compatibility"
            authors = @("Prime integration generated for compatibility")
            maintainers = @("local integration package")
            description = "Compatibility layer that keeps Aftershock Prime genetech usable alongside Mind Over Matter without permanently blocking later psionic progression."
            category = "content"
            dependencies = @("dda", $ModId, "mindovermatter")
            conflicts = @("aftershock_exoplanet")
        }
    )
    Set-JsonArray (Join-Path $CompatBuildRoot "modinfo.json") $modInfo

    # The stock C++ genemill unconditionally calls set_mutation(CANNOT_GAIN_PSIONICS)
    # after every treatment. In MoM that ID is Headblind and blocks later awakenings.
    # We intentionally DO NOT redefine Headblind globally. Instead the resequencer
    # receives a second explicit action that clears the hardcoded legacy lock when
    # the player wants Aftershock genetech and MoM psionics to coexist.
    $compatJson = @'
[
  {
    "type": "furniture",
    "id": "f_gene_editor",
    "copy-from": "f_gene_editor",
    "description": "A large bio-sarcophagus and accompanying control machinery.  Used in gene editing and for general medical purposes, it can impart or remove traits using genetic templates.  With Mind Over Matter loaded, a compatibility routine can clear the legacy Aftershock psionic lock applied by the gene-editing backend.",
    "examine_action": [
      "genemill",
      {
        "type": "effect_on_condition",
        "name": "Restore psionic compatibility",
        "effect_on_conditions": [ "EOC_AFSP_MOM_CLEAR_GENEMILL_HEADBLIND" ]
      }
    ]
  },
  {
    "type": "effect_on_condition",
    "id": "EOC_AFSP_MOM_CLEAR_GENEMILL_HEADBLIND",
    "condition": { "u_has_trait": "CANNOT_GAIN_PSIONICS" },
    "effect": [
      { "u_lose_trait": "CANNOT_GAIN_PSIONICS" },
      {
        "u_message": "The resequencer clears the legacy psionic exclusion flag.  Mind Over Matter progression is no longer blocked by the genetic treatment.",
        "type": "good"
      }
    ],
    "false_effect": {
      "u_message": "No psionic exclusion flag is currently present.",
      "type": "info"
    }
  }
]
'@
    Write-Utf8NoBom (Join-Path $CompatBuildRoot "mom_genemill_compat.json") ($compatJson + "`n")

    $readme = @"
Aftershock Prime - Mind Over Matter Compatibility
=================================================

This companion mod is intentionally separate from the main Prime mod.

Why it exists
-------------
The CDDA C++ genemill backend unconditionally adds CANNOT_GAIN_PSIONICS after a gene-editing treatment.
Mind Over Matter uses that same trait ID as Headblind and checks it when deciding whether later psionic
awakening / learning is allowed.

Prime does NOT globally redefine or weaken Headblind. Instead, when this compatibility mod is loaded,
the Mercurial Resequencer has two examine actions:

1. Genetic treatment
2. Restore psionic compatibility

After using a genetic treatment, examine the resequencer again and choose the second action if you want
the character to remain eligible for Mind Over Matter progression.

The explicit second action is deliberate: a player who intentionally chose Headblind is not silently
changed by the compatibility layer.

Dependencies: dda, aftershock_prime, mindovermatter
Target build: $ExpectedBuild
"@
    Write-Utf8NoBom (Join-Path $CompatBuildRoot "README_COMPAT.txt") ($readme + "`n")
}

function Static-Verify-MoMCompat {
    $errors = New-Object System.Collections.Generic.List[string]

    if(-not (Test-Path -LiteralPath $CompatBuildRoot)) {
        $errors.Add("MoM compatibility build directory was not generated.")
        return $errors
    }

    $modInfoPath = Join-Path $CompatBuildRoot "modinfo.json"
    $compatPath = Join-Path $CompatBuildRoot "mom_genemill_compat.json"

    if(-not (Test-Path -LiteralPath $modInfoPath)) {
        $errors.Add("MoM compatibility modinfo.json is missing.")
    }
    if(-not (Test-Path -LiteralPath $compatPath)) {
        $errors.Add("MoM compatibility JSON is missing.")
        return $errors
    }

    try {
        $objects = Get-JsonArray $compatPath
        $editor = @($objects | Where-Object { (Get-ObjectType $_) -eq "furniture" -and (Get-ObjectId $_) -eq "f_gene_editor" })
        $eoc = @($objects | Where-Object { (Get-ObjectType $_) -eq "effect_on_condition" -and (Get-ObjectId $_) -eq "EOC_AFSP_MOM_CLEAR_GENEMILL_HEADBLIND" })

        if($editor.Count -ne 1) { $errors.Add("Compat must contain exactly one f_gene_editor override.") }
        if($eoc.Count -ne 1) { $errors.Add("Compat must contain exactly one Headblind-clear EOC.") }

        $raw = Get-Content -LiteralPath $compatPath -Raw -Encoding UTF8
        foreach($needle in @(
            '"copy-from": "f_gene_editor"',
            '"genemill"',
            '"CANNOT_GAIN_PSIONICS"',
            '"u_lose_trait": "CANNOT_GAIN_PSIONICS"',
            '"name": "Restore psionic compatibility"'
        )) {
            if(-not $raw.Contains($needle)) {
                $errors.Add("MoM compatibility layer is missing required content: $needle")
            }
        }
    } catch {
        $errors.Add("MoM compatibility JSON parse failure: $($_.Exception.Message)")
    }

    try {
        $mi = Get-JsonArray $modInfoPath
        $m = @($mi | Where-Object { (Get-ObjectType $_) -eq "MOD_INFO" -and (Get-ObjectId $_) -eq $CompatModId })
        if($m.Count -ne 1) {
            $errors.Add("Compat MOD_INFO '$CompatModId' missing or duplicated.")
        } else {
            $deps = @($m[0].dependencies)
            foreach($dep in @("dda", $ModId, "mindovermatter")) {
                if($deps -notcontains $dep) { $errors.Add("Compat dependency missing: $dep") }
            }
        }
    } catch {
        $errors.Add("MoM compatibility modinfo parse failure: $($_.Exception.Message)")
    }

    return $errors
}

function Static-Verify {
    Write-Host "Running static completeness/safety verification ..."
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $forbiddenPaths = @(
        "region_settings","setting_blacklists","price_overrides","npcs","missions","mod_interactions",
        "game_balance.json","options.json","jmath.json","scenarios.json","start_locations.json",
        "items\bionics_mainline_override.json","items\obsolete.json","vehicles\vehicle_overrides.json","recipes\recipe_overrides.json",
        "traps.json","maps\furniture_and_terrain\furniture_spaceship.json","maps\furniture_and_terrain\terrain_spaceship.json"
    )
    foreach($rel in $forbiddenPaths) {
        if(Test-Path (Join-Path $BuildRoot $rel)) { $errors.Add("Forbidden path survived: $rel") }
    }

    $ids = Get-AllObjectIds $BuildRoot
    $sentinels = @($ProtectedImportedIds + @("afsp_gene_editor_kit"))
    foreach($id in $sentinels) {
        if(-not $ids.ContainsKey($id)) { $errors.Add("Missing critical sentinel ID: $id") }
    }

    foreach($bad in @("AFS_ELECTROKINETIC","AFS_PRECOG","AFS_TELEKINETIC","AFS_TELEPATH","aftershock_psionics","vitamin_afs_maintained_powers")) {
        if($ids.ContainsKey($bad)) { $errors.Add("Aftershock Esper residue survived as object ID: $bad") }
    }

    # Ensure there are no global option/dimension/blacklist objects.
    foreach($f in Get-ChildItem -LiteralPath $BuildRoot -Recurse -File -Filter "*.json") {
        try {
            foreach($o in Get-JsonArray $f.FullName) {
                $t = Get-ObjectType $o
                if($t -in @("EXTERNAL_OPTION","dimension","dimension_region_layout","SCENARIO_BLACKLIST","MONSTER_BLACKLIST","MONSTER_WHITELIST")) {
                    $errors.Add("Forbidden global object type '$t' in $($f.FullName)")
                }
            }
        } catch {
            $errors.Add("JSON parse failure: $($f.FullName) :: $($_.Exception.Message)")
        }
    }

    # Runtime hacking closure: no custom helper call/definition may survive.
    $hackVerify = Join-Path $BuildRoot "EOC\hacking_eoc.json"
    if(Test-Path -LiteralPath $hackVerify) {
        $hackRaw = Get-Content -LiteralPath $hackVerify -Raw -Encoding UTF8

        foreach($needle in @(
            "afs_hack_time_adjust(",
            "afs_hack_skill(",
            "afs_hack_bonus("
        )) {
            if($hackRaw.Contains($needle)) {
                $errors.Add("Runtime-dangerous custom hacking JMath call survived: $needle")
            }
        }

        try {
            foreach($o in Get-JsonArray $hackVerify) {
                if((Get-ObjectType $o) -eq "jmath_function" -and
                   (Get-ObjectId $o) -in @("afs_hack_skill","afs_hack_time_adjust","afs_hack_bonus")) {
                    $errors.Add("Runtime-dangerous hacking jmath_function survived: $(Get-ObjectId $o)")
                }
            }
        } catch {
            $errors.Add("Unable to parse transformed hacking_eoc.json: $($_.Exception.Message)")
        }
    } else {
        $errors.Add("EOC/hacking_eoc.json is missing.")
    }

    # Known closure checks discovered by the real CDDA validator.
    $forbiddenReferenceText = @(
        "ESPER_ADVANCEMENT_OKAY",
        "ESPER_STARTER_ADVANCEMENT_OKAY",
        "afs_espertech_gain_esper_powers_",
        "EOC_ESCAPE_POD_CHAIR",
        "EOC_AFS_CALL_AUGUSTMOON_SHUTTLE",
        "EOC_SHIP_LIGHTS",
        "EOC_THI_CONTROL",
        "EOC_SHIP_RAMP",
        "EOC_SHIP_STAIRS",
        "EOC_AFS_AUGUSTMOON_SHUTTLE_TP",
        "AID_AF_bio_power_storage",
        "afs_shuttle_beacon"
    )
    foreach($f in Get-ChildItem -LiteralPath $BuildRoot -Recurse -File -Filter "*.json") {
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        foreach($needle in $forbiddenReferenceText) {
            if($raw.Contains($needle)) {
                $errors.Add("Forbidden/missing reference '$needle' survived in $($f.FullName)")
            }
        }
    }

    if(-not (Test-Path (Join-Path $BuildRoot "ascii.json"))) {
        $errors.Add("ascii.json missing; Aftershock ammo may reference its ascii_picture IDs.")
    }

    # Verify the CBM recipe category extension generated after broad collision pruning.
    $support = Join-Path $BuildRoot "prime_support_items.json"
    if(Test-Path $support) {
        $rawSupport = Get-Content -LiteralPath $support -Raw -Encoding UTF8
        if(-not $rawSupport.Contains('"furn_type": "f_gene_editor"')) {
            $errors.Add("Portable gene resequencer does not deploy the functional f_gene_editor.")
        }
        if($rawSupport.Contains('"furn_type": "f_crispr"')) {
            $errors.Add("Portable gene resequencer still deploys inert f_crispr.")
        }
        if(-not $rawSupport.Contains("CSC_ELECTRONIC_CBMS")) {
            $errors.Add("Generated CBM recipe subcategory extension is missing.")
        }
        if(-not $rawSupport.Contains('"id": "xray_laser_barrel"')) {
            $errors.Add("Generated xray_laser_barrel migration is missing.")
        }
        foreach($repairId in @(
            "damaged_exo_helmet_steel",
            "damaged_exo_torso_steel",
            "damaged_exo_arm_steel",
            "damaged_exo_leg_steel"
        )) {
            if(-not $rawSupport.Contains('"' + $repairId + '"')) {
                $errors.Add("Generated exosuit repair migration missing: $repairId")
            }
        }
    }

    return @{ errors=$errors; warnings=$warnings; id_count=$ids.Count }
}

function Write-BuildReport($CopyReport, $CollisionReport, $VerifyReport, [string]$DetectedGameRoot, $StackWarnings) {
    $report = [ordered]@{
        project = $ProjectName
        mod_id = $ModId
        upstream_commit = $UpstreamCommit
        target_build = $ExpectedBuild
        generated_utc = [DateTime]::UtcNow.ToString("o")
        game_root = $DetectedGameRoot
        included_upstream_files = @($CopyReport.included).Count
        excluded_upstream_files = @($CopyReport.excluded).Count
        external_collision_records = @($CollisionReport).Count
        external_collisions_pruned = @($CollisionReport | Where-Object { $_.action -eq "pruned" }).Count
        external_collisions_kept_for_audit = @($CollisionReport | Where-Object { $_.action -eq "kept_audit" }).Count
        object_ids_present = $VerifyReport.id_count
        verification_errors = @($VerifyReport.errors)
        verification_warnings = @($VerifyReport.warnings)
        stack_warnings = @($StackWarnings)
        collision_prune_details = @($CollisionReport)
    }
    Write-Utf8NoBom (Join-Path $BuildRoot "BUILD_REPORT.txt") (($report | ConvertTo-Json -Depth 100) + "`n")

    $txt = @"
Aftershock: Prime Integration v0.1 runtime-hacking hotfix 14
=====================================================

Target CDDA build : $ExpectedBuild
Pinned source     : $UpstreamCommit
Mod ID            : $ModId
Hard dependency    : dda only
Compatibility scan: Xedra Evolved + Magiclysm + Mind Over Matter + No NPC Food

Scope
-----
Included:
- modular exosuits and modules
- Aftershock CBMs and bionic support
- energy shields
- laser / electrolaser / flechette / advanced ballistic / plasma / rail weapon definitions
- grenades and high-tech utility devices
- robotics, inactive robots, robot crafting and monster attacks
- genetech / Human+ / Project Sobek
- functional deployable Mercurial Resequencer (f_gene_editor)
- optional separate Mind Over Matter genemill compatibility layer
- validator-safe surrogate CDDA check for the MoM compatibility JSON
- selected advanced vehicles and vehicle parts
- hacking, cryosuit, translocation and non-Esper support EOCs/spells
- conservative integration into science, military, bionic, schematic, hardware and robot pools

Deliberately excluded:
- Salus IV dimensions, climate and world replacement
- scenarios and start locations
- Aftershock NPC factions, planetary economy and missions
- Aftershock Esper system (Mind Over Matter remains authoritative)
- global game options and balance overrides
- vanilla map weight suppression and blacklists
- vanilla APC/vehicle overrides
- vanilla bionic installation-data overrides
- recipe blacklists/overrides
- price overrides

Static verification errors: $(@($VerifyReport.errors).Count)
External collisions pruned: $(@($CollisionReport).Count)

See BUILD_REPORT.txt for the machine-readable JSON audit.
"@
    Write-Utf8NoBom (Join-Path $BuildRoot "README_PRIME.txt") ($txt + "`n")
    Write-Utf8NoBom (Join-Path $BuildRoot "UPSTREAM_COMMIT.txt") ($UpstreamCommit + "`n")
}

function Check-KnownStackIssues([string]$DetectedGameRoot) {
    $warnings = New-Object System.Collections.Generic.List[string]

    $xedraA = Join-Path $DetectedGameRoot "data\mods\Xedra_Evolved\eocs\eoc_mod_overrides.json"
    $xedraB = Join-Path $DetectedGameRoot "data\mods\Xedra_Evolved\mod_interactions\DinoMod\lilin_interactions.json"
    $knownId = "EOC_CONDITIONS_LILIN_DINOMOD_RUACH_DRAIN"

    if((Test-Path -LiteralPath $xedraA) -and (Test-Path -LiteralPath $xedraB)) {
        try {
            $aHas = @((Get-JsonArray $xedraA) | Where-Object { (Get-ObjectId $_) -eq $knownId }).Count -gt 0
            $bHas = @((Get-JsonArray $xedraB) | Where-Object { (Get-ObjectId $_) -eq $knownId }).Count -gt 0
            if($aHas -and $bHas) {
                $msg = "Installed Xedra Evolved contains a known duplicate EOC '$knownId' in eoc_mod_overrides.json and mod_interactions/DinoMod/lilin_interactions.json. Prime will NOT modify Xedra; standalone Prime validation remains authoritative."
                $warnings.Add($msg)
                Write-Warning $msg
            }
        } catch {}
    }

    return $warnings
}

function Clear-PrimeFlexbufferCache([string]$DetectedGameRoot) {
    # data-root JSON uses <GameRoot>\data\cache. Rebuilding either local mod changes source mtimes,
    # so stale .fb entries can force --check-mods to exit 1.
    foreach($cacheName in @($ProjectName, $CompatProjectName)) {
        $cachePath = Join-Path $DetectedGameRoot ("data\cache\mods\" + $cacheName)
        if(Test-Path -LiteralPath $cachePath) {
            Remove-TreeRobust $cachePath
            Write-Host "Cleared stale flexbuffer cache: $cachePath"
        }
    }
}


function Confirm-MoMHeadblindDefinition([string]$DetectedGameRoot) {
    $momTraitPath = Join-Path $DetectedGameRoot "data\mods\MindOverMatter\mutations\traits.json"
    if(-not (Test-Path -LiteralPath $momTraitPath)) {
        throw "Mind Over Matter trait file not found: $momTraitPath"
    }

    $matches = @((Get-JsonArray $momTraitPath) | Where-Object {
        (Get-ObjectType $_) -eq "mutation" -and (Get-ObjectId $_) -eq "CANNOT_GAIN_PSIONICS"
    })

    if($matches.Count -ne 1) {
        throw "Expected exactly one Mind Over Matter CANNOT_GAIN_PSIONICS/Headblind definition, found $($matches.Count)."
    }

    Write-Host "MoM compatibility target verified: CANNOT_GAIN_PSIONICS / Headblind exists exactly once."
}

function Invoke-MoMCompatSurrogateCheck([string]$DetectedGameRoot, [string]$Exe, [string]$ModsDir) {
    # IMPORTANT:
    # CDDA --check-mods recursively loads every JSON file inside dependencies via load_data_from_dir().
    # Mind Over Matter contains conditional mod_interactions; the validator therefore loads interactions
    # for mods that are NOT active and can report duplicate same-source objects (for example mx_alien_grass)
    # or crash while unwinding those errors. Normal world loading uses load_mod_data_from_dir() first and
    # loads only matching mod_interactions afterwards. Therefore a direct
    #   --check-mods aftershock_prime_mom_compat
    # is NOT a faithful test of the real world loader for this stack.
    #
    # We still validate the compatibility JSON with CDDA itself by creating a temporary validation-only
    # mod that depends on Prime but replaces the MoM dependency with a minimal Headblind stub. This tests
    # the real f_gene_editor override, examine actor, EOC syntax, u_has_trait/u_lose_trait handling and
    # finalization without triggering MoM's unrelated interaction tree.

    Confirm-MoMHeadblindDefinition $DetectedGameRoot

    $validationId = "afsp_mom_compat_validation"
    $validationDirName = "_AFSP_MoM_Compat_Validation"
    $validationDir = Join-Path $ModsDir $validationDirName
    $validationCache = Join-Path $DetectedGameRoot ("data\cache\mods\" + $validationDirName)

    if(Test-Path -LiteralPath $validationDir) { Remove-TreeRobust $validationDir }
    if(Test-Path -LiteralPath $validationCache) { Remove-TreeRobust $validationCache }

    try {
        New-Item -ItemType Directory -Path $validationDir -Force | Out-Null

        $validationModInfo = @(
            [ordered]@{
                type = "MOD_INFO"
                id = $validationId
                name = "AFSP MoM compatibility validation harness"
                authors = @("local validation harness")
                description = "Temporary validator-only compatibility harness for Aftershock Prime and Mind Over Matter."
                category = "content"
                dependencies = @("dda", $ModId)
            }
        )
        Set-JsonArray (Join-Path $validationDir "modinfo.json") $validationModInfo

        $stub = @'
[
  {
    "type": "mutation",
    "id": "CANNOT_GAIN_PSIONICS",
    "name": { "str": "Headblind validation stub" },
    "points": -4,
    "description": "Validation-only stand-in for Mind Over Matter Headblind.",
    "valid": false,
    "player_display": false,
    "starting_trait": false,
    "purifiable": false
  }
]
'@
        Write-Utf8NoBom (Join-Path $validationDir "00_headblind_stub.json") ($stub + "`n")

        $compatSource = Join-Path $CompatBuildRoot "mom_genemill_compat.json"
        if(-not (Test-Path -LiteralPath $compatSource)) {
            throw "Generated compatibility JSON is missing: $compatSource"
        }
        Copy-Item -LiteralPath $compatSource -Destination (Join-Path $validationDir "10_mom_genemill_compat.json") -Force

        $diagRoot = Join-Path $env:TEMP "AFSP_checkmods_mom_compat_surrogate"
        if(Test-Path -LiteralPath $diagRoot) { Remove-TreeRobust $diagRoot }
        New-Item -ItemType Directory -Path $diagRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $diagRoot "save") -Force | Out-Null
        $diagConfig = Join-Path $diagRoot "config"
        New-Item -ItemType Directory -Path $diagConfig -Force | Out-Null
        $diagConfigArg = ($diagConfig -replace '\\','/').TrimEnd('/') + '/'

        $stdoutLog = Join-Path $PSScriptRoot "CHECK_MODS_MOM_COMPAT_SURROGATE.stdout.log"
        $stderrLog = Join-Path $PSScriptRoot "CHECK_MODS_MOM_COMPAT_SURROGATE.stderr.log"
        $combinedLog = Join-Path $PSScriptRoot "CHECK_MODS_MOM_COMPAT_SURROGATE.log"
        Remove-Item -LiteralPath $stdoutLog,$stderrLog,$combinedLog -Force -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "Skipping direct --check-mods ${CompatModId}: CDDA's validator recursively loads MoM mod_interactions and is not faithful to normal world loading." -ForegroundColor Yellow
        Write-Host "Running CDDA surrogate compatibility validation instead ..."
        Write-Host "Validation mod: $validationId"
        Write-Host "Diagnostic config: $diagConfigArg"

        $runStarted = Get-Date
        $args = @(
            "--userdir", $diagRoot,
            "--configdir", $diagConfigArg,
            "--check-mods", $validationId
        )

        Push-Location $DetectedGameRoot
        try {
            $proc = Start-Process -FilePath $Exe -ArgumentList $args -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
            $code = $proc.ExitCode
        } finally {
            Pop-Location
        }

        $combined = New-Object System.Collections.Generic.List[string]
        if(Test-Path -LiteralPath $stdoutLog) {
            foreach($line in Get-Content -LiteralPath $stdoutLog -Encoding UTF8) { $combined.Add($line) }
        }
        if(Test-Path -LiteralPath $stderrLog) {
            foreach($line in Get-Content -LiteralPath $stderrLog -Encoding UTF8) { $combined.Add($line) }
        }
        Set-Content -LiteralPath $combinedLog -Value $combined -Encoding UTF8

        Write-Host "===== CHECK_MODS_MOM_COMPAT_SURROGATE.log =====" -ForegroundColor Cyan
        Get-Content -LiteralPath $combinedLog -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        Write-Host "===== END CHECK_MODS_MOM_COMPAT_SURROGATE.log =====" -ForegroundColor Cyan

        $freshLogs = @()
        if(Test-Path -LiteralPath $diagRoot) {
            $freshLogs = @(Get-ChildItem -LiteralPath $diagRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -in @("debug.log","crash.log") -and
                    $_.LastWriteTime -ge $runStarted.AddSeconds(-3)
                })
        }
        foreach($lf in @($freshLogs | Sort-Object LastWriteTime -Descending -Unique)) {
            Write-Host ""
            Write-Host "===== $($lf.FullName) (tail) =====" -ForegroundColor DarkCyan
            Get-Content -LiteralPath $lf.FullName -Encoding UTF8 -Tail 250 | ForEach-Object { Write-Host $_ }
            Write-Host "===== END $($lf.Name) =====" -ForegroundColor DarkCyan
        }

        if($code -ne 0) {
            throw "CDDA surrogate MoM compatibility validation failed with exit code $code. See CHECK_MODS_MOM_COMPAT_SURROGATE.log."
        }

        Write-Host "Prime + MoM compatibility JSON passed the CDDA surrogate validation." -ForegroundColor Green
        Write-Host "The installed companion itself was not passed to --check-mods because that CLI path misloads MoM mod_interactions on this target build." -ForegroundColor Yellow
    } finally {
        if(Test-Path -LiteralPath $validationDir) { Remove-TreeRobust $validationDir }
        if(Test-Path -LiteralPath $validationCache) { Remove-TreeRobust $validationCache }
    }
}

function Install-And-Check([string]$DetectedGameRoot) {
    if($NoInstall) { return }
    if([string]::IsNullOrWhiteSpace($DetectedGameRoot)) {
        Write-Warning "No CDDA game root detected. Build is complete but not installed. Re-run with -GameRoot <path>."
        return
    }

    $modsDir = Join-Path $DetectedGameRoot "data\mods"
    if(-not (Test-Path $modsDir)) { throw "GameRoot does not look valid: no data\mods at $DetectedGameRoot" }

    $backupRoot = Join-Path $DetectedGameRoot "_Aftershock_Prime_Backups"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    # Hotfix 7 migration: older builders incorrectly kept backups INSIDE data\mods.
    # Those copies still contain modinfo.json with the same id and can be discovered by the mod manager.
    $legacyBackups = @(Get-ChildItem -LiteralPath $modsDir -Directory -Filter "Aftershock_Prime.backup_*" -ErrorAction SilentlyContinue)
    foreach($legacy in $legacyBackups) {
        $target = Join-Path $backupRoot $legacy.Name
        if(Test-Path -LiteralPath $target) {
            $target = Join-Path $backupRoot ($legacy.Name + "_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        }
        Move-Item -LiteralPath $legacy.FullName -Destination $target -Force
        Write-Host "Moved legacy in-mods backup out of data\mods: $target"
    }

    $dst = Join-Path $modsDir $ProjectName
    if(Test-Path $dst) {
        $backupName = $ProjectName + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")
        $backup = Join-Path $backupRoot $backupName
        Move-Item -LiteralPath $dst -Destination $backup -Force
        Write-Host "Backed up previous mod OUTSIDE data\mods: $backup"
    }

    Copy-Item -LiteralPath $BuildRoot -Destination $dst -Recurse -Force
    Write-Host "Installed to $dst"

    $compatDst = Join-Path $modsDir $CompatProjectName
    if(Test-Path -LiteralPath $compatDst) {
        $compatBackupName = $CompatProjectName + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")
        $compatBackup = Join-Path $backupRoot $compatBackupName
        Move-Item -LiteralPath $compatDst -Destination $compatBackup -Force
        Write-Host "Backed up previous MoM compatibility mod OUTSIDE data\mods: $compatBackup"
    }
    Copy-Item -LiteralPath $CompatBuildRoot -Destination $compatDst -Recurse -Force
    Write-Host "Installed MoM compatibility layer to $compatDst"

    Clear-PrimeFlexbufferCache $DetectedGameRoot

    # Safety check: there must be exactly one discoverable Prime modinfo under data\mods.
    $primeModinfos = @()
    foreach($mi in Get-ChildItem -LiteralPath $modsDir -Recurse -File -Filter "modinfo.json" -ErrorAction SilentlyContinue) {
        try {
            foreach($o in Get-JsonArray $mi.FullName) {
                if((Get-ObjectType $o) -eq "MOD_INFO" -and (Get-ObjectId $o) -eq $ModId) {
                    $primeModinfos += $mi.FullName
                }
            }
        } catch {}
    }

    Write-Host "Discoverable '$ModId' modinfo count under data\mods: $($primeModinfos.Count)"
    foreach($mi in $primeModinfos) { Write-Host " - $mi" }
    if($primeModinfos.Count -ne 1) {
        throw "Expected exactly one discoverable '$ModId' modinfo under data\mods, found $($primeModinfos.Count)."
    }

    $compatModinfos = @()
    foreach($mi in Get-ChildItem -LiteralPath $modsDir -Recurse -File -Filter "modinfo.json" -ErrorAction SilentlyContinue) {
        try {
            foreach($o in Get-JsonArray $mi.FullName) {
                if((Get-ObjectType $o) -eq "MOD_INFO" -and (Get-ObjectId $o) -eq $CompatModId) {
                    $compatModinfos += $mi.FullName
                }
            }
        } catch {}
    }

    Write-Host "Discoverable '$CompatModId' modinfo count under data\mods: $($compatModinfos.Count)"
    foreach($mi in $compatModinfos) { Write-Host " - $mi" }
    if($compatModinfos.Count -ne 1) {
        throw "Expected exactly one discoverable '$CompatModId' modinfo under data\mods, found $($compatModinfos.Count)."
    }

    if($SkipCliCheck) { return }

    $exeCandidates = @(
        (Join-Path $DetectedGameRoot "cataclysm-tiles.exe"),
        (Join-Path $DetectedGameRoot "cataclysm.exe")
    )
    $exe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if(-not $exe) {
        Write-Warning "No CDDA executable found; skipped --check-mods."
        return
    }

    $log = Join-Path $PSScriptRoot "CHECK_MODS.log"
    $diagRoot = Join-Path $env:TEMP "AFSP_checkmods"
    if(Test-Path -LiteralPath $diagRoot) {
        Remove-TreeRobust $diagRoot
    }
    New-Item -ItemType Directory -Path $diagRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $diagRoot "save") -Force | Out-Null

    $diagConfig = Join-Path $diagRoot "config"
    New-Item -ItemType Directory -Path $diagConfig -Force | Out-Null

    # PATH_INFO::set_config_dir concatenates "options.json" directly, so the
    # argument needs a trailing separator. IMPORTANT: use a FORWARD slash.
    # A trailing backslash immediately before a closing quote is parsed by the
    # Windows CRT as an escaped quote and swallows the following CLI arguments.
    $diagConfigArg = ($diagConfig -replace '\\','/').TrimEnd('/') + '/'
    $runStarted = Get-Date

    Write-Host "Running standalone CDDA --check-mods $ModId (dependency: dda only) ..."
    Write-Host "Diagnostic userdir: $diagRoot"
    Write-Host "Diagnostic configdir: $diagConfigArg"

    $stdoutLog = Join-Path $PSScriptRoot "CHECK_MODS.stdout.log"
    $stderrLog = Join-Path $PSScriptRoot "CHECK_MODS.stderr.log"
    Remove-Item -LiteralPath $stdoutLog,$stderrLog -Force -ErrorAction SilentlyContinue

    $argList = @(
        "--userdir", $diagRoot,
        "--configdir", $diagConfigArg,
        "--check-mods", $ModId
    )

    Push-Location $DetectedGameRoot
    try {
        # Start-Process preserves argument boundaries and avoids cmd.exe quote parsing.
        $proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
        $code = $proc.ExitCode
    } finally {
        Pop-Location
    }

    $combined = New-Object System.Collections.Generic.List[string]
    if(Test-Path -LiteralPath $stdoutLog) {
        foreach($line in Get-Content -LiteralPath $stdoutLog -Encoding UTF8) { $combined.Add($line) }
    }
    if(Test-Path -LiteralPath $stderrLog) {
        foreach($line in Get-Content -LiteralPath $stderrLog -Encoding UTF8) { $combined.Add($line) }
    }
    Set-Content -LiteralPath $log -Value $combined -Encoding UTF8

    Write-Host ""
    if(Test-Path -LiteralPath $log) {
        Write-Host "===== CHECK_MODS.log =====" -ForegroundColor Cyan
        Get-Content -LiteralPath $log -Encoding UTF8 | ForEach-Object { Write-Host $_ }
        Write-Host "===== END CHECK_MODS.log =====" -ForegroundColor Cyan
    } else {
        Write-Warning "CHECK_MODS.log was not created."
    }

    # Search every plausible location because some Windows builds initialize logging
    # before all path CLI overrides have taken effect.
    $logRoots = New-Object System.Collections.Generic.List[string]
    $logRoots.Add($diagRoot)
    $logRoots.Add($DetectedGameRoot)

    $defaultUserDir = Join-Path $env:LOCALAPPDATA "cataclysm-dda"
    if(Test-Path -LiteralPath $defaultUserDir) { $logRoots.Add($defaultUserDir) }

    $candidateLogs = New-Object System.Collections.Generic.List[object]
    foreach($root in @($logRoots | Select-Object -Unique)) {
        if(-not (Test-Path -LiteralPath $root)) { continue }
        foreach($lf in Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in @("debug.log","crash.log") }) {
            if($lf.LastWriteTime -ge $runStarted.AddSeconds(-3)) {
                $candidateLogs.Add($lf)
            }
        }
    }

    if($candidateLogs.Count -eq 0) {
        Write-Warning "No fresh debug.log/crash.log was found after the validator run."
        Write-Host "Expected primary debug path: $(Join-Path $diagConfig 'debug.log')"
    } else {
        foreach($lf in @($candidateLogs | Sort-Object LastWriteTime -Descending -Unique)) {
            Write-Host ""
            Write-Host "===== $($lf.FullName) (tail) =====" -ForegroundColor DarkCyan
            Get-Content -LiteralPath $lf.FullName -Encoding UTF8 -Tail 250 | ForEach-Object { Write-Host $_ }
            Write-Host "===== END $($lf.Name) =====" -ForegroundColor DarkCyan
        }
    }

    if($code -ne 0) {
        throw "CDDA --check-mods failed with exit code $code. Validator stdout/stderr and every fresh debug/crash log found were printed above."
    }

    Write-Host "Standalone CDDA --check-mods passed." -ForegroundColor Green

    Invoke-MoMCompatSurrogateCheck $DetectedGameRoot $exe $modsDir
}

# ----- MAIN -----
$DetectedGameRoot = Find-GameRoot
if($DetectedGameRoot) {
    Write-Host "Game root: $DetectedGameRoot"
} else {
    throw "Game root not auto-detected. Hotfix 2 intentionally uses the installed target game's data for collision auditing. Re-run with -GameRoot <path>."
}

$SourceRoot = $GameRoot
$AftershockRoot = Join-Path $SourceRoot "data\mods\aftershock_exoplanet"
if(-not (Test-Path $AftershockRoot)) { throw "Pinned source does not contain aftershock_exoplanet." }

Write-Host "Copying compatibility-safe Aftershock layers ..."
$copyReport = Copy-Selected $AftershockRoot

Apply-KnownTransforms $AftershockRoot

$frameProbePath = Join-Path $BuildRoot "items\armor\exosuit\exosuit_frame.json"
if(Test-Path -LiteralPath $frameProbePath) {
    $frameProbeObjects = Get-JsonArray $frameProbePath
    $frameProbeIds = @($frameProbeObjects | ForEach-Object { Get-ObjectId $_ } | Where-Object { $_ })
    Write-Host "FRAME PARSE PROBE: objects=$($frameProbeObjects.Count); ids=$($frameProbeIds -join ', ')"
} else {
    Write-Warning "FRAME PARSE PROBE: exosuit_frame.json is physically missing after copy."
}

Verify-ImportedCore "post-copy/post-transform"

$external = Build-ExternalIndex $DetectedGameRoot
$collisionReport = Remove-ExternalCollisions $external
Verify-ImportedCore "post-collision-audit"

Write-ModInfo
Write-IntegrationLayer
Write-MoMCompatLayer

$verifyReport = Static-Verify
$compatVerifyErrors = Static-Verify-MoMCompat
if(@($compatVerifyErrors).Count -gt 0) {
    foreach($e in $compatVerifyErrors) { $verifyReport.errors.Add("MoM compat: $e") }
}
$stackWarnings = Check-KnownStackIssues $DetectedGameRoot
Write-BuildReport $copyReport $collisionReport $verifyReport $DetectedGameRoot $stackWarnings

if(@($verifyReport.errors).Count -gt 0) {
    Write-Host ""
    Write-Host "STATIC VERIFICATION FAILED:" -ForegroundColor Red
    foreach($e in $verifyReport.errors) { Write-Host " - $e" -ForegroundColor Red }
    throw "Build aborted because the static verifier found errors."
}

Write-Host ""
Write-Host "Static verification passed." -ForegroundColor Green
Write-Host "Upstream files included: $(@($copyReport.included).Count)"
Write-Host "Collision records: $(@($collisionReport).Count)"
Write-Host "External collisions actually pruned: $(@($collisionReport | Where-Object { $_.action -eq 'pruned' }).Count)"
Write-Host "Collisions retained for audit/protection: $(@($collisionReport | Where-Object { $_.action -eq 'kept_audit' }).Count)"
Write-Host "Object IDs present: $($verifyReport.id_count)"

