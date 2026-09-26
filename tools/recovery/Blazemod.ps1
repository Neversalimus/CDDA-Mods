param([string]$ModRoot,[string]$GameRoot,[string]$ReportDir)
$ErrorActionPreference='Stop'
$Version='0.5.5'
$TargetBuild='cdda_experimental_2026_09_23_0546'
$TargetCommit='e262adb299a7613b4aedc5f12c08fe0413c56a84'
$dataRoot=Join-Path $GameRoot 'data'
New-Item -ItemType Directory -Force $ReportDir | Out-Null
function Step([string]$Text) {
    Write-Host ("=== {0} ===" -f $Text) -ForegroundColor Cyan
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Read-Json([string]$Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Json([string]$Path, $Value) {
    $json = ConvertTo-Json -InputObject @($Value) -Depth 100
    Write-Utf8NoBom $Path ($json + [Environment]::NewLine)
}

function Has-Prop($Object, [string]$Name) {
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Get-ById($Array, [string]$Id) {
    foreach ($o in @($Array)) {
        if ((Has-Prop $o 'id') -and [string]$o.id -eq $Id) {
            return $o
        }
    }
    return $null
}

function Get-Recipe($Array, [string]$Result) {
    foreach ($o in @($Array)) {
        if ((Has-Prop $o 'type') -and [string]$o.type -eq 'recipe' -and
            (Has-Prop $o 'result') -and [string]$o.result -eq $Result) {
            return $o
        }
    }
    return $null
}

function Set-Prop($Object, [string]$Name, $Value) {
    if (Has-Prop $Object $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Remove-Prop($Object, [string]$Name) {
    if (Has-Prop $Object $Name) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Add-Unique-Recipe($Array, $Recipe) {
    if ($null -ne (Get-Recipe $Array ([string]$Recipe.result))) {
        return @($Array)
    }
    return @($Array) + @($Recipe)
}

function Add-Unique-ObjectById($Array, $Object) {
    foreach ($o in @($Array)) {
        if ((Has-Prop $o 'id') -and (Has-Prop $o 'type') -and
            [string]$o.id -eq [string]$Object.id -and
            [string]$o.type -eq [string]$Object.type) {
            return @($Array)
        }
    }
    return @($Array) + @($Object)
}

function Json-Object([string]$Json) {
    return ($Json | ConvertFrom-Json)
}

function Test-CDDAInstallation([string]$Path) {
    if (-not $Path) { return $false }
    try { $Path = [IO.Path]::GetFullPath($Path) } catch { return $false }
    if (-not (Test-Path $Path -PathType Container)) { return $false }

    $exeA = Join-Path $Path 'cataclysm-tiles.exe'
    $exeB = Join-Path $Path 'cataclysm-tiles.vanilla.exe'
    $json = Join-Path $Path 'data\json'
    $dda = Join-Path $Path 'data\mods\dda\modinfo.json'

    return ((Test-Path $exeA -PathType Leaf) -or (Test-Path $exeB -PathType Leaf)) -and
           (Test-Path $json -PathType Container) -and
           (Test-Path $dda -PathType Leaf)
}

function Get-CDDAInfo([string]$Path, [string]$Source) {
    $full = [IO.Path]::GetFullPath($Path)
    $exe = Join-Path $full 'cataclysm-tiles.vanilla.exe'
    if (-not (Test-Path $exe -PathType Leaf)) {
        $exe = Join-Path $full 'cataclysm-tiles.exe'
    }

    $versionHint = ''
    try {
        $fvi = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        if ($fvi.ProductVersion) { $versionHint = [string]$fvi.ProductVersion }
        elseif ($fvi.FileVersion) { $versionHint = [string]$fvi.FileVersion }
    } catch {}

    return [pscustomobject]@{
        Root = $full
        BuildName = Split-Path $full -Leaf
        ExactTarget = ((Split-Path $full -Leaf) -eq $TargetBuild)
        Exe = $exe
        Source = $Source
        VersionHint = $versionHint
        Modified = (Get-Item $exe).LastWriteTimeUtc
    }
}

function Get-InstallerConfigPath {
    $base = $env:APPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Roaming' }
    $dir = Join-Path $base 'BlazemodRevival'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return (Join-Path $dir 'installer.json')
}

function Read-InstallerConfig {
    $path = Get-InstallerConfigPath
    if (-not (Test-Path $path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Save-InstallerConfig([string]$Root) {
    $path = Get-InstallerConfigPath
    $obj = [pscustomobject]@{
        lastGameRoot = $Root
        targetBuild = $TargetBuild
        updated = (Get-Date).ToString('o')
    }
    Write-Utf8NoBom $path ((ConvertTo-Json $obj -Depth 5) + [Environment]::NewLine)
}

function Get-SteamLibraryRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $defaults = @()
    if (${env:ProgramFiles(x86)}) {
        $defaults += (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }
    if ($env:ProgramFiles) {
        $defaults += (Join-Path $env:ProgramFiles 'Steam')
    }

    foreach ($steam in $defaults) {
        if (Test-Path $steam -PathType Container) {
            $roots.Add($steam)
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf -PathType Leaf) {
                try {
                    $raw = Get-Content -LiteralPath $vdf -Raw -Encoding UTF8
                    foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                        $p = $m.Groups[1].Value -replace '\\\\','\'
                        if ($p) { $roots.Add($p) }
                    }
                } catch {}
            }
        }
    }

    return @($roots | Select-Object -Unique)
}

function Find-CDDAInstallations {
    $found = @{}
    $config = Read-InstallerConfig

    function Add-Candidate([string]$Path, [string]$Source) {
        if (-not $Path) { return }
        try { $full = [IO.Path]::GetFullPath($Path) } catch { return }
        if (-not (Test-CDDAInstallation $full)) { return }
        $key = $full.TrimEnd('\').ToLowerInvariant()
        if (-not $found.ContainsKey($key)) {
            $found[$key] = Get-CDDAInfo $full $Source
        }
    }

    function Scan-One-Level([string]$Base, [string]$Source, [bool]$AllChildren = $false) {
        if (-not $Base -or -not (Test-Path $Base -PathType Container)) { return }
        Add-Candidate $Base $Source
        try {
            foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue)) {
                if ($AllChildren -or $d.Name -match '(?i)(cdda|cataclysm|darkdays|experimental)') {
                    Add-Candidate $d.FullName $Source
                }
            }
        } catch {}
    }

    if ($RequestedGameRoot) { Add-Candidate $RequestedGameRoot 'command line' }
    if ($null -ne $config -and (Has-Prop $config 'lastGameRoot')) {
        Add-Candidate ([string]$config.lastGameRoot) 'saved previous choice'
    }

    $launcherRoots = @(
        (Join-Path $env:LOCALAPPDATA 'com.munetmo.cat-launcher\Assets\DarkDaysAhead'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Catapult\Assets\DarkDaysAhead'),
        (Join-Path $env:LOCALAPPDATA 'Catapult\Assets\DarkDaysAhead')
    )
    foreach ($r in $launcherRoots) { Scan-One-Level $r 'CatLauncher/Catapult' $true }

    # Portable installs close to the installer itself.
    Scan-One-Level $PSScriptRoot 'installer folder' $true
    try { Scan-One-Level (Split-Path $PSScriptRoot -Parent) 'installer parent folder' $true } catch {}

    # Common game folders without recursively scanning whole drives.
    $commonBases = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
        (Join-Path $env:USERPROFILE 'Games'),
        (Join-Path $env:USERPROFILE 'Cataclysm-DDA'),
        'C:\Games',
        'C:\Cataclysm-DDA'
    )) {
        if ($p) { $commonBases.Add($p) }
    }

    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($suffix in @('Games','CDDA','Cataclysm-DDA','SteamLibrary\steamapps\common')) {
            $commonBases.Add((Join-Path $drive.Root $suffix))
        }
    }

    foreach ($steamRoot in @(Get-SteamLibraryRoots)) {
        $commonBases.Add((Join-Path $steamRoot 'steamapps\common'))
    }

    foreach ($b in @($commonBases | Select-Object -Unique)) {
        Scan-One-Level $b 'common game folder' $false
    }

    return @($found.Values)
}

function Select-CDDAInstallation {
    $all = @(Find-CDDAInstallations)
    if ($all.Count -eq 0) {
        Write-Host 'No CDDA installation was detected automatically.' -ForegroundColor Yellow
        $manual = Read-Host 'Paste the folder containing cataclysm-tiles.exe'
        if (-not (Test-CDDAInstallation $manual)) {
            throw "The supplied folder is not a valid CDDA installation: $manual"
        }
        return (Get-CDDAInfo $manual 'manual path')
    }

    # Explicit command-line path always wins.
    if ($RequestedGameRoot) {
        foreach ($x in $all) {
            if ($x.Source -eq 'command line') { return $x }
        }
    }

    # Prefer an exact tested build.  If there is a saved exact choice, use it.
    $exact = @($all | Where-Object { $_.ExactTarget })
    if ($exact.Count -gt 0) {
        $saved = @($exact | Where-Object { $_.Source -eq 'saved previous choice' })
        if ($saved.Count -gt 0) { return $saved[0] }
        if ($exact.Count -eq 1) { return $exact[0] }

        # Multiple copies of the same tested build: newest executable is the
        # least surprising automatic choice.
        return ($exact | Sort-Object Modified -Descending | Select-Object -First 1)
    }

    # Different build(s): never silently patch an untested experimental.
    $candidate = $all | Sort-Object Modified -Descending | Select-Object -First 1
    Write-Host ''
    Write-Host 'No exact tested build was found.' -ForegroundColor Yellow
    Write-Host "Tested: $TargetBuild"
    Write-Host 'Detected installations:'
    $n = 1
    foreach ($x in @($all | Sort-Object BuildName)) {
        Write-Host ("  [{0}] {1}" -f $n, $x.Root)
        if ($x.VersionHint) { Write-Host ("      version: {0}" -f $x.VersionHint) }
        $n++
    }

    if ($AllowDifferentBuild) {
        Write-Host ("Using newest detected build because -AllowDifferentBuild was supplied: {0}" -f $candidate.Root) -ForegroundColor Yellow
        return $candidate
    }

    Write-Host ''
    Write-Host ("Candidate: {0}" -f $candidate.Root) -ForegroundColor Yellow
    $answer = Read-Host 'Type YES to install on this untested build, or anything else to cancel'
    if ($answer -cne 'YES') {
        throw 'Installation cancelled: no exact tested CDDA build was found.'
    }
    return $candidate
}

function Acquire-BaselineMod([string]$DestinationRoot) {
    Step 'Blazemod is not installed; acquiring pinned baseline'

    $localCandidates = @(
        (Join-Path $PSScriptRoot ("blazemod_baseline_" + $BaselineCommit + ".zip")),
        (Join-Path $PSScriptRoot 'blazemod_baseline.zip')
    )

    $archive = $null
    foreach ($p in $localCandidates) {
        if (Test-Path $p -PathType Leaf) {
            $archive = $p
            Write-Host "Using local baseline archive: $archive"
            break
        }
    }

    if (-not $archive) {
        if ($NoDownload) {
            throw 'Blazemod is not installed and -NoDownload was supplied. Put blazemod_baseline.zip next to the installer.'
        }

        $archive = Join-Path $workRoot ("blazemod_baseline_" + $BaselineCommit + ".zip")
        Write-Host "Downloading pinned Blazemod baseline: $BaselineCommit"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $BaselineUrl -OutFile $archive
        } catch {
            throw ("Could not download the pinned Blazemod baseline. " +
                   "Internet is only required for a fresh install. " +
                   "You can also place blazemod_baseline.zip next to the installer.`n" +
                   ($_ | Out-String))
        }
    }

    $extract = Join-Path $workRoot 'baseline_extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

    $modinfo = Get-ChildItem -LiteralPath $extract -Recurse -File -Filter 'modinfo.json' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $j = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($o in @($j)) {
                    if ((Has-Prop $o 'type') -and [string]$o.type -eq 'MOD_INFO' -and
                        (Has-Prop $o 'id') -and [string]$o.id -eq 'blazemod') {
                        return $true
                    }
                }
            } catch {}
            return $false
        } | Select-Object -First 1

    if ($null -eq $modinfo) {
        throw 'Downloaded baseline archive does not contain Blazemod modinfo.json.'
    }

    Copy-Item -LiteralPath $modinfo.Directory.FullName -Destination $DestinationRoot -Recurse -Force
    Write-Host "Fresh baseline staged from: $($modinfo.Directory.FullName)"
}

function Ensure-TilesetCompatibility([string]$Path, [string]$TilesetId) {
    if (-not (Test-Path $Path -PathType Leaf)) { return }
    $data = Read-Json $Path
    foreach ($entry in @($data)) {
        if ((Has-Prop $entry 'type') -and [string]$entry.type -eq 'mod_tileset') {
            $compat = @()
            if (Has-Prop $entry 'compatibility') { $compat = @($entry.compatibility) }
            if ($compat -notcontains $TilesetId) {
                $compat += $TilesetId
                Set-Prop $entry 'compatibility' $compat
            }
        }
    }
    Write-Json $Path $data
}

function Prepare-ActiveBlob($Object, [string]$EocId) {
    if ($null -eq $Object) { throw "Missing active blob object for EOC $EocId" }

    Remove-Prop $Object 'tool_ammo'
    Remove-Prop $Object 'pocket_data'
    Remove-Prop $Object 'charges_per_use'
    Remove-Prop $Object 'use_action'

    Set-Prop $Object 'turns_per_charge' 1
    Set-Prop $Object 'tick_action' ([pscustomobject]@{
        type = 'effect_on_conditions'
        effect_on_conditions = @($EocId)
    })

    $flags = @()
    if (Has-Prop $Object 'flags') { $flags = @($Object.flags) }
    foreach ($flag in @('NO_UNWIELD','UNBREAKABLE_MELEE','SPAWN_ACTIVE')) {
        if ($flags -notcontains $flag) { $flags += $flag }
    }
    Set-Prop $Object 'flags' $flags
}

function Ensure-VehiclePartMigration($Array, [string]$From, [string]$To, [string[]]$Tools) {
    foreach ($o in @($Array)) {
        if ((Has-Prop $o 'type') -and [string]$o.type -eq 'vehicle_part_migration' -and
            (Has-Prop $o 'from') -and [string]$o.from -eq $From) {
            Set-Prop $o 'to' $To
            Set-Prop $o 'add_veh_tools' @($Tools)
            return @($Array)
        }
    }
    return @($Array) + @([pscustomobject]@{
        type = 'vehicle_part_migration'
        from = $From
        to = $To
        add_veh_tools = @($Tools)
    })
}

function Get-DefinitionMap([string[]]$Roots, [string[]]$Types) {
    $map = @{}
    foreach ($root in $Roots) {
        if (-not (Test-Path $root -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
            try {
                $data = Read-Json $f.FullName
            } catch {
                continue
            }
            foreach ($o in @($data)) {
                if (-not (Has-Prop $o 'type') -or -not (Has-Prop $o 'id')) { continue }
                $type = [string]$o.type
                $id = [string]$o.id
                if ($Types -notcontains $type) { continue }
                $key = $type + '|' + $id
                if (-not $map.ContainsKey($key)) {
                    $map[$key] = $f.FullName
                }
            }
        }
    }
    return $map
}

function Get-RecipeResultMap([string[]]$Roots) {
    $map = @{}
    foreach ($root in $Roots) {
        if (-not (Test-Path $root -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
            try { $data = Read-Json $f.FullName } catch { continue }
            foreach ($o in @($data)) {
                if ((Has-Prop $o 'type') -and [string]$o.type -eq 'recipe' -and (Has-Prop $o 'result')) {
                    $result = [string]$o.result
                    if (-not $map.ContainsKey($result)) { $map[$result] = @() }
                    $map[$result] += $f.FullName
                }
            }
        }
    }
    return $map
}

function Invoke-ModCheck([string]$Exe, [string]$GameRoot, [string]$UserDir,
                         [string]$ModId, [string]$Prefix) {
    New-Item -ItemType Directory -Force -Path (Join-Path $UserDir 'config') | Out-Null

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $GameRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Important: normal game data tree only.  The separate datadir path is
    # known to crash this exact Windows tiles build during graphics-option init.
    $psi.Arguments = '--userdir "' + $UserDir + '" --check-mods ' + $ModId

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()

    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $exit = $p.ExitCode

    Write-Utf8NoBom ($Prefix + '_stdout.txt') $stdout
    Write-Utf8NoBom ($Prefix + '_stderr.txt') $stderr
    Write-Utf8NoBom ($Prefix + '_exit.txt') ("Exit code: " + $exit)

    $debug = Join-Path $UserDir 'config\debug.log'
    $crash = Join-Path $UserDir 'config\crash.log'
    if (Test-Path $debug -PathType Leaf) {
        Copy-Item -LiteralPath $debug -Destination ($Prefix + '_debug.log') -Force
    }
    if (Test-Path $crash -PathType Leaf) {
        Copy-Item -LiteralPath $crash -Destination ($Prefix + '_crash.log') -Force
    }

    return [pscustomobject]@{
        Exit = $exit
        Stdout = $stdout
        Stderr = $stderr
        Debug = $debug
        Crash = $crash
    }
}

function Get-ErrorBlocks([string]$Path) {
    if (-not (Test-Path $Path -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $Path)
    $blocks = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\d{2}:\d{2}:\d{2}\.\d{3} ERROR :') {
            $buf = New-Object System.Collections.Generic.List[string]
            $buf.Add([regex]::Replace($lines[$i], '^\d{2}:\d{2}:\d{2}\.\d{3}', '<TS>'))
            $j = $i + 1
            while ($j -lt $lines.Count -and
                   $lines[$j] -notmatch '^\d{2}:\d{2}:\d{2}\.\d{3} (INFO|WARNING|ERROR) :') {
                $buf.Add($lines[$j])
                $j++
            }
            $block = (($buf -join "`n").Trim())
            if ($block) { $blocks.Add($block) }
            $i = $j - 1
        }
    }
    return @($blocks)
}

function Multiset-Difference($Reference, $Target) {
    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($Reference)) { $remaining.Add([string]$x) }

    $delta = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($Target)) {
        $found = -1
        for ($i = 0; $i -lt $remaining.Count; $i++) {
            if ($remaining[$i] -eq [string]$x) { $found = $i; break }
        }
        if ($found -ge 0) { $remaining.RemoveAt($found) }
        else { $delta.Add([string]$x) }
    }
    return @($delta)
}

function Add-SteamRecipe($Array, [string]$Result, [string]$Base, [int]$Difficulty,
                         [int]$Hours, [int]$Chunks, [int]$Lumps, [int]$Pipes, [int]$PowerSupplies) {
    if ($null -ne (Get-Recipe $Array $Result)) { return @($Array) }

    $extra = ''
    if ($PowerSupplies -gt 0) {
        $extra = ', [ [ "power_supply", ' + $PowerSupplies + ' ] ]'
    }

    $json = @"
{
  "type": "recipe",
  "activity_level": "MODERATE_EXERCISE",
  "result": "$Result",
  "category": "CC_OTHER",
  "subcategory": "CSC_OTHER_PARTS",
  "skill_used": "mechanics",
  "skills_required": [ [ "fabrication", $Difficulty ] ],
  "difficulty": $Difficulty,
  "time": "$Hours h",
  "autolearn": true,
  "using": [ [ "welding_standard", 20 ], [ "steel_standard", 2 ] ],
  "components": [
    [ [ "$Base", 1 ] ],
    [ [ "lc_steel_chunk", $Chunks ] ],
    [ [ "lc_steel_lump", $Lumps ] ],
    [ [ "pipe", $Pipes ] ]$extra
  ]
}
"@
    return @($Array) + @((Json-Object $json))
}

    Step 'Compatibility floor'

    # v0.2 style/validator fixes are re-applied so a completely fresh baseline
    # can be installed without first passing through older revival packages.
    $modinfoPath = Join-Path $modRoot 'modinfo.json'
    if (Test-Path $modinfoPath -PathType Leaf) {
        $mi = Read-Json $modinfoPath
        foreach ($entry in @($mi)) {
            if ((Has-Prop $entry 'type') -and [string]$entry.type -eq 'MOD_INFO' -and
                (Has-Prop $entry 'description')) {
                $entry.description = ([string]$entry.description) -replace 'mod\. Adds', 'mod.  Adds'
            }
        }
        Write-Json $modinfoPath $mi
    }

    $diamondToolsPath = Join-Path $modRoot 'items\tools\diamond_tools.json'
    if (Test-Path $diamondToolsPath -PathType Leaf) {
        $diamondTools = Read-Json $diamondToolsPath
        $dcluster = Get-ById $diamondTools 'dcluster'
        if ($null -ne $dcluster -and (Has-Prop $dcluster 'description')) {
            $dcluster.description = ([string]$dcluster.description).TrimEnd()
        }
        Write-Json $diamondToolsPath $diamondTools
    }

    $vortexAmmoPath = Join-Path $modRoot 'items\ammo\vortex_ammo.json'
    if (Test-Path $vortexAmmoPath) {
        $vortexAmmo = Read-Json $vortexAmmoPath
        $vpower = Get-ById $vortexAmmo 'vpower'
        if ($null -ne $vpower) { Set-Prop $vpower 'phase' 'liquid' }
        Write-Json $vortexAmmoPath $vortexAmmo
    }

    Ensure-TilesetCompatibility (Join-Path $modRoot 'mod_tileset.json') $HybridTilesetId
    Ensure-TilesetCompatibility (Join-Path $modRoot 'BlazeIndustries\mod_tileset.json') $HybridTilesetId

    # =========================================================
    # v0.4.0 Core Isolation
    # =========================================================
    Step 'v0.4.0 Core Isolation'

    $weaponsPath = Join-Path $modRoot 'items\guns\blaze_weapons.json'
    $weapons = Read-Json $weaponsPath

    $coil = Get-ById $weapons 'coilgun'
    if ($null -eq $coil) { $coil = Get-ById $weapons 'blaze_coilgun' }
    if ($null -ne $coil) {
        $coil.id = 'blaze_coilgun'
        Write-Host 'Isolated item: coilgun -> blaze_coilgun'
    }

    $nailmag = Get-ById $weapons 'nailmag'
    if ($null -eq $nailmag) { $nailmag = Get-ById $weapons 'blaze_nailmag' }
    if ($null -ne $nailmag) {
        $nailmag.id = 'blaze_nailmag'
        if (Has-Prop $nailmag 'name') {
            if (Has-Prop $nailmag.name 'str') { $nailmag.name.str = 'Blazemod nail rifle magazine' }
        }
        Write-Host 'Isolated item: nailmag -> blaze_nailmag'
    }

    foreach ($o in @($weapons)) {
        if (Has-Prop $o 'pocket_data') {
            foreach ($pocket in @($o.pocket_data)) {
                if (Has-Prop $pocket 'item_restriction') {
                    $newRestriction = @()
                    foreach ($rid in @($pocket.item_restriction)) {
                        if ([string]$rid -eq 'nailmag') { $newRestriction += 'blaze_nailmag' }
                        else { $newRestriction += [string]$rid }
                    }
                    $pocket.item_restriction = $newRestriction
                }
            }
        }

        if ((Has-Prop $o 'items') -and (Has-Prop $o 'type') -and [string]$o.type -eq 'item_group') {
            $newItems = @()
            foreach ($entry in @($o.items)) {
                $e = @($entry)
                if ($e.Count -gt 0 -and [string]$e[0] -eq 'nailmag') { $e[0] = 'blaze_nailmag' }
                $newItems += ,$e
            }
            $o.items = $newItems
        }
    }
    $weapons = @($weapons | Where-Object {
        -not ((Has-Prop $_ 'type') -and [string]$_.type -eq 'item_group' -and
              (Has-Prop $_ 'id') -and @('mags_other_makeshift','blaze_mags_other_makeshift') -contains [string]$_.id)
    })
    Write-Json $weaponsPath $weapons

    $gunRecipesPath = Join-Path $modRoot 'recipes\blaze_gun_recipes.json'
    $gunRecipes = Read-Json $gunRecipesPath
    foreach ($r in @($gunRecipes)) {
        if ((Has-Prop $r 'type') -and [string]$r.type -eq 'recipe' -and
            (Has-Prop $r 'result') -and [string]$r.result -eq 'coilgun') {
            $r.result = 'blaze_coilgun'
        }
    }
    Write-Json $gunRecipesPath $gunRecipes

    $magRecipesPath = Join-Path $modRoot 'recipes\blaze_magazine_recipes.json'
    $magRecipes = Read-Json $magRecipesPath
    $blazeNailmagRecipeJson = @'
{
  "result": "blaze_nailmag",
  "type": "recipe",
  "activity_level": "MODERATE_EXERCISE",
  "category": "CC_WEAPON",
  "subcategory": "CSC_WEAPON_MAGAZINES",
  "skill_used": "fabrication",
  "difficulty": 1,
  "time": "8 m",
  "autolearn": true,
  "tools": [
    [ [ "blaze_coilgun", -1 ] ],
    [ [ "nail", -1 ], [ "combatnail", -1 ] ]
  ],
  "qualities": [
    { "id": "HAMMER", "level": 2 },
    { "id": "SAW_M", "level": 1 }
  ],
  "components": [
    [ [ "sheet_metal_small", 1 ] ],
    [ [ "spring_medium", 1 ] ],
    [ [ "scrap", 1 ] ],
    [ [ "duct_tape", 20 ] ]
  ]
}
'@
    $magRecipes = Add-Unique-Recipe $magRecipes (Json-Object $blazeNailmagRecipeJson)
    Write-Json $magRecipesPath $magRecipes
    Write-Host 'Added dedicated recipe for blaze_nailmag.'

    $weaponRecipesPath = Join-Path $modRoot 'recipes\blaze_weapons_recipes.json'
    $weaponRecipes = Read-Json $weaponRecipesPath
    foreach ($r in @($weaponRecipes)) {
        if (-not (Has-Prop $r 'components')) { continue }
        $newGroups = @()
        foreach ($group in @($r.components)) {
            $newGroup = @()
            foreach ($entry in @($group)) {
                $e = @($entry)
                if ($e.Count -gt 0 -and [string]$e[0] -eq 'coilgun') { $e[0] = 'blaze_coilgun' }
                $newGroup += ,$e
            }
            $newGroups += ,$newGroup
        }
        $r.components = $newGroups
    }
    Write-Json $weaponRecipesPath $weaponRecipes

    $customTurretPath = Join-Path $modRoot 'vehicleparts\blaze_custom_turret.json'
    $customTurrets = Read-Json $customTurretPath
    $mountedCoil = Get-ById $customTurrets 'mounted_coilgun'
    if ($null -ne $mountedCoil) { Set-Prop $mountedCoil 'item' 'blaze_coilgun' }

    $mountedPulse = Get-ById $customTurrets 'mounted_lasgunp'
    if ($null -ne $mountedPulse -and (Has-Prop $mountedPulse 'breaks_into')) {
        foreach ($b in @($mountedPulse.breaks_into)) {
            if ((Has-Prop $b 'item') -and [string]$b.item -eq 'lasgun') { $b.item = 'lasgunp' }
        }
        Write-Host 'Fixed mounted_lasgunp breakage result.'
    }
    Write-Json $customTurretPath $customTurrets

    $ammoPath = Join-Path $modRoot 'items\ammo\blaze_ammo.json'
    $ammo = Read-Json $ammoPath
    $pool = Get-ById $ammo 'pool_ball'
    if ($null -eq $pool) { $pool = Get-ById $ammo 'blaze_pool_ball' }
    if ($null -ne $pool) {
        $pool.id = 'blaze_pool_ball'
        if (Has-Prop $pool 'name') {
            if (Has-Prop $pool.name 'str') { $pool.name.str = 'launcher pool ball' }
        }
        Set-Prop $pool 'description' 'A standard pool ball prepared for use as a heavy projectile in Blazemod launchers.'
        Write-Host 'Isolated item: pool_ball -> blaze_pool_ball'
    }
    Write-Json $ammoPath $ammo

    $ammoRecipesPath = Join-Path $modRoot 'recipes\blaze_ammo_recipes.json'
    $ammoRecipes = Read-Json $ammoRecipesPath
    $poolRecipeJson = @'
{
  "type": "recipe",
  "activity_level": "LIGHT_EXERCISE",
  "result": "blaze_pool_ball",
  "category": "CC_AMMO",
  "subcategory": "CSC_AMMO_OTHER",
  "skill_used": "fabrication",
  "difficulty": 0,
  "time": "10 s",
  "autolearn": true,
  "components": [ [ [ "pool_ball", 1 ] ] ]
}
'@
    $ammoRecipes = Add-Unique-Recipe $ammoRecipes (Json-Object $poolRecipeJson)
    $heavyRecipeJson = @'
{
  "type": "recipe",
  "activity_level": "LIGHT_EXERCISE",
  "result": "h_projectile",
  "category": "CC_AMMO",
  "subcategory": "CSC_AMMO_OTHER",
  "skill_used": "fabrication",
  "skills_required": [ [ "mechanics", 6 ] ],
  "difficulty": 7,
  "time": "45 m",
  "autolearn": true,
  "using": [ [ "welding_standard", 5 ] ],
  "components": [
    [ [ "mininuke", 1 ] ],
    [ [ "sheet_metal_small", 2 ] ],
    [ [ "cable", 10 ] ],
    [ [ "e_scrap", 5 ] ]
  ]
}
'@
    $ammoRecipes = Add-Unique-Recipe $ammoRecipes (Json-Object $heavyRecipeJson)
    Write-Json $ammoRecipesPath $ammoRecipes

    $ammoTypesPath = Join-Path $modRoot 'blaze_ammo_types.json'
    $ammoTypes = Read-Json $ammoTypesPath
    $diamondAmmoTypeJson = @'
{
  "type": "ammunition_type",
  "id": "blaze_diamond_carbon",
  "name": "prepared carbon charge",
  "default": "blaze_diamond_carbon"
}
'@
    $ammoTypes = Add-Unique-ObjectById $ammoTypes (Json-Object $diamondAmmoTypeJson)
    Write-Json $ammoTypesPath $ammoTypes

    $diamondAmmoPath = Join-Path $modRoot 'items\ammo\diamond_ammo.json'
    $diamondAmmo = Read-Json $diamondAmmoPath
    $carbon = Get-ById $diamondAmmo 'charcoal'
    if ($null -eq $carbon) { $carbon = Get-ById $diamondAmmo 'blaze_diamond_carbon' }
    if ($null -ne $carbon) {
        $carbon.id = 'blaze_diamond_carbon'
        $carbon.name = [pscustomobject]@{ str_sp = 'prepared carbon charges' }
        Set-Prop $carbon 'description' 'Charcoal prepared as a feed charge for a diamond matrix weapon.  The matrix converts it into a transient crystalline projectile and leaves a small stable cluster behind.'
        Set-Prop $carbon 'ammo_type' 'blaze_diamond_carbon'
        Set-Prop $carbon 'casing' 'dcluster'
        Write-Host 'Isolated diamond ammo from vanilla charcoal.'
    }
    Write-Json $diamondAmmoPath $diamondAmmo

    $diamondGunsPath = Join-Path $modRoot 'items\guns\diamond_turret.json'
    $diamondGuns = Read-Json $diamondGunsPath
    foreach ($g in @($diamondGuns)) {
        if (Has-Prop $g 'ammo') { $g.ammo = @('blaze_diamond_carbon') }
        if (Has-Prop $g 'pocket_data') {
            foreach ($pocket in @($g.pocket_data)) {
                if (Has-Prop $pocket 'ammo_restriction') {
                    $cap = 50
                    if (Has-Prop $pocket.ammo_restriction 'charcoal') {
                        $cap = [int]$pocket.ammo_restriction.charcoal
                    } elseif (Has-Prop $pocket.ammo_restriction 'blaze_diamond_carbon') {
                        $cap = [int]$pocket.ammo_restriction.blaze_diamond_carbon
                    }
                    $pocket.ammo_restriction = [pscustomobject]@{ blaze_diamond_carbon = $cap }
                }
            }
        }
    }
    Write-Json $diamondGunsPath $diamondGuns

    $diamondRecipesPath = Join-Path $modRoot 'recipes\diamond_recipes.json'
    $diamondRecipes = Read-Json $diamondRecipesPath
    $carbonRecipeJson = @'
{
  "type": "recipe",
  "activity_level": "LIGHT_EXERCISE",
  "result": "blaze_diamond_carbon",
  "category": "CC_AMMO",
  "subcategory": "CSC_AMMO_OTHER",
  "skill_used": "fabrication",
  "difficulty": 1,
  "time": "10 s",
  "autolearn": true,
  "components": [ [ [ "charcoal", 1 ] ] ]
}
'@
    $diamondRecipes = Add-Unique-Recipe $diamondRecipes (Json-Object $carbonRecipeJson)
    Write-Json $diamondRecipesPath $diamondRecipes

    $otherRecipesPath = Join-Path $modRoot 'recipes\blaze_other_recipes.json'
    $otherRecipes = Read-Json $otherRecipesPath
    $newOther = @()
    foreach ($r in @($otherRecipes)) {
        if ((Has-Prop $r 'type') -and [string]$r.type -eq 'recipe' -and
            (Has-Prop $r 'result') -and [string]$r.result -eq 'turret_mount') {
            Write-Host 'Removed legacy alternate turret_mount recipe.'
            continue
        }
        $newOther += $r
    }
    $otherRecipes = $newOther

    # =========================================================
    # v0.4.1 Blob Semantics
    # =========================================================
    Step 'v0.4.1 Blob Semantics'

    $blobToolsPath = Join-Path $modRoot 'items\tools\blob_tools.json'
    $blobTools = Read-Json $blobToolsPath

    Prepare-ActiveBlob (Get-ById $blobTools 'gloople_act') 'EOC_BLAZE_GLOOPLE_SPLIT_TICK'
    Prepare-ActiveBlob (Get-ById $blobTools 'oozle_act') 'EOC_BLAZE_OOZLE_SPLIT_TICK'
    Prepare-ActiveBlob (Get-ById $blobTools 'gray_act') 'EOC_BLAZE_GRAY_SPLIT_TICK'

    Write-Json $blobToolsPath $blobTools

    # effect_on_conditions_actor::use() returns 0 when consume is false.
    # That makes it safe as TOOL tick_action: process_tool already consumes
    # the 7/5/3 internal countdown charge and will not emit
    # "consumes charges via tick_action" debug spam.
    #
    # The original place_monster friendliness formula is reproduced before spawn:
    #   rng(0, INT/2) + chemistry/2 + cooking/2 < rng(0,difficulty) => hostile
    # difficulty was 1.
    #
    # Successful spawns receive a temporary custom monster variable; immediately
    # after spawning, u_run_monster_eocs selects only marked monsters of that
    # exact type and uses the current engine's legacy "friendly" talker setter.
    $blobRuntimeJson = @'
[
  {
    "type": "effect_on_condition",
    "id": "EOC_BLAZE_GLOOPLE_SPLIT_TICK",
    "effect": [
      { "turn_cost": { "math": [ "2.5" ] } },
      {
        "if": {
          "math": [
            "rng(0, floor((u_val('intelligence_base') + u_val('intelligence_bonus')) / 2)) + (u_skill('chemistry') / 2) + (u_skill('cooking') / 2) < rng(0,1)"
          ]
        },
        "then": {
          "u_spawn_monster": "mon_gloople",
          "real_count": 1,
          "min_radius": 1,
          "max_radius": 1,
          "spawn_message": "A blob splits and bounces away!"
        },
        "else": [
          {
            "u_spawn_monster": "mon_gloople",
            "real_count": 1,
            "min_radius": 1,
            "max_radius": 1,
            "mon_variables": { "blaze_split_friendly": "1" },
            "spawn_message": "A blob splits and bounces away!"
          },
          {
            "u_run_monster_eocs": [
              {
                "id": "EOC_BLAZE_GLOOPLE_FRIENDIFY",
                "condition": { "compare_string": [ "1", { "u_val": "blaze_split_friendly" } ] },
                "effect": [ { "math": [ "u_val('friendly') = -1" ] } ]
              }
            ],
            "mtype_ids": [ "mon_gloople" ],
            "monster_range": 1
          }
        ]
      }
    ]
  },
  {
    "type": "effect_on_condition",
    "id": "EOC_BLAZE_OOZLE_SPLIT_TICK",
    "effect": [
      { "turn_cost": { "math": [ "2.5" ] } },
      {
        "if": {
          "math": [
            "rng(0, floor((u_val('intelligence_base') + u_val('intelligence_bonus')) / 2)) + (u_skill('chemistry') / 2) + (u_skill('cooking') / 2) < rng(0,1)"
          ]
        },
        "then": {
          "u_spawn_monster": "mon_oozle",
          "real_count": 1,
          "min_radius": 1,
          "max_radius": 1,
          "spawn_message": "A blob splits and bounces away!"
        },
        "else": [
          {
            "u_spawn_monster": "mon_oozle",
            "real_count": 1,
            "min_radius": 1,
            "max_radius": 1,
            "mon_variables": { "blaze_split_friendly": "1" },
            "spawn_message": "A blob splits and bounces away!"
          },
          {
            "u_run_monster_eocs": [
              {
                "id": "EOC_BLAZE_OOZLE_FRIENDIFY",
                "condition": { "compare_string": [ "1", { "u_val": "blaze_split_friendly" } ] },
                "effect": [ { "math": [ "u_val('friendly') = -1" ] } ]
              }
            ],
            "mtype_ids": [ "mon_oozle" ],
            "monster_range": 1
          }
        ]
      }
    ]
  },
  {
    "type": "effect_on_condition",
    "id": "EOC_BLAZE_GRAY_SPLIT_TICK",
    "effect": [
      { "turn_cost": { "math": [ "1" ] } },
      {
        "if": {
          "math": [
            "rng(0, floor((u_val('intelligence_base') + u_val('intelligence_bonus')) / 2)) + (u_skill('chemistry') / 2) + (u_skill('cooking') / 2) < rng(0,1)"
          ]
        },
        "then": {
          "u_spawn_monster": "mon_gray",
          "real_count": 1,
          "min_radius": 1,
          "max_radius": 1,
          "spawn_message": "A blob splits and bounces away!"
        },
        "else": [
          {
            "u_spawn_monster": "mon_gray",
            "real_count": 1,
            "min_radius": 1,
            "max_radius": 1,
            "mon_variables": { "blaze_split_friendly": "1" },
            "spawn_message": "A blob splits and bounces away!"
          },
          {
            "u_run_monster_eocs": [
              {
                "id": "EOC_BLAZE_GRAY_FRIENDIFY",
                "condition": { "compare_string": [ "1", { "u_val": "blaze_split_friendly" } ] },
                "effect": [ { "math": [ "u_val('friendly') = -1" ] } ]
              }
            ],
            "mtype_ids": [ "mon_gray" ],
            "monster_range": 1
          }
        ]
      }
    ]
  }
]
'@
    $blobRuntime = Json-Object $blobRuntimeJson
    Write-Json (Join-Path $modRoot 'effects_on_condition_blob_runtime.json') $blobRuntime

    Write-Host 'Blob tick_action now returns zero: no double charge-consumption/debug path.'
    Write-Host 'Friendliness roll, split move-cost and 7/5/3 countdown semantics are preserved.'

    # =========================================================
    # v0.4.2 Content Reachability
    # =========================================================
    Step 'v0.4.2 Content Reachability'

    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_triple_large' 'steam_triple_medium' 7 12 20 6 8 0
    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_triple_giant' 'steam_triple_large' 9 24 50 16 16 0
    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_turbine_small' 'steam_triple_small' 7 12 12 4 6 2
    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_turbine_medium' 'steam_triple_medium' 8 16 18 6 8 3
    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_turbine_large' 'steam_triple_medium' 9 24 30 10 12 4
    $otherRecipes = Add-SteamRecipe $otherRecipes 'steam_turbine_giant' 'steam_triple_large' 10 36 45 15 16 6
    Write-Json $otherRecipesPath $otherRecipes
    Write-Host 'Added craft reachability for 6 steam engines/turbines.'

    $blobRecipesPath = Join-Path $modRoot 'recipes\blob_recipes.json'
    $blobRecipes = Read-Json $blobRecipesPath
    $frostHullRecipeJson = @'
{
  "type": "recipe",
  "activity_level": "LIGHT_EXERCISE",
  "result": "frostie_hull",
  "category": "CC_OTHER",
  "subcategory": "CSC_OTHER_MATERIALS",
  "skill_used": "cooking",
  "difficulty": 8,
  "time": "4 h 10 m",
  "reversible": true,
  "autolearn": true,
  "components": [
    [ [ "frostie", 1 ] ],
    [ [ "water", 200 ] ]
  ]
}
'@
    $blobRecipes = Add-Unique-Recipe $blobRecipes (Json-Object $frostHullRecipeJson)

    foreach ($r in @($blobRecipes)) {
        if ((Has-Prop $r 'type') -and [string]$r.type -eq 'recipe' -and
            (Has-Prop $r 'result') -and [string]$r.result -eq 'meltiegrow' -and
            (Has-Prop $r 'components')) {
            $rebuilt = @()
            foreach ($group in @($r.components)) {
                $hasAcid = $false
                $newGroup = @()
                foreach ($entry in @($group)) {
                    $e = @($entry)
                    if ($e.Count -gt 0 -and [string]$e[0] -eq 'chem_sulphuric_acid') {
                        if ($hasAcid) { continue }
                        $hasAcid = $true
                    }
                    $newGroup += ,$e
                }
                $rebuilt += ,$newGroup
            }
            $r.components = $rebuilt
        }
    }
    Write-Json $blobRecipesPath $blobRecipes

    $monsterPath = Join-Path $modRoot 'monsters\blob_monster.json'
    $monsters = Read-Json $monsterPath
    $oozleMon = Get-ById $monsters 'mon_oozle'
    if ($null -ne $oozleMon) { $oozleMon.name = [pscustomobject]@{ str_sp = 'oozing mass' } }
    Write-Json $monsterPath $monsters

    $otherItemsPath = Join-Path $modRoot 'items\vehicle\blaze_other.json'
    $otherItems = Read-Json $otherItemsPath
    $obsoleteRigs = @('afs_metal_rig','afs_kitchen_rig','afs_cooking_rig')
    $keptItems = @()
    foreach ($o in @($otherItems)) {
        if ((Has-Prop $o 'id') -and $obsoleteRigs -contains [string]$o.id) { continue }
        $keptItems += $o
    }
    Write-Json $otherItemsPath $keptItems

    $otherPartsPath = Join-Path $modRoot 'vehicleparts\blaze_other_parts.json'
    $otherParts = Read-Json $otherPartsPath
    $hadWorkshopOverride = $false
    $keptParts = @()
    foreach ($p in @($otherParts)) {
        if ((Has-Prop $p 'type') -and [string]$p.type -eq 'vehicle_part' -and
            (Has-Prop $p 'id') -and [string]$p.id -eq 'veh_tools_workshop') {
            $hadWorkshopOverride = $true
            continue
        }
        $keptParts += $p
    }
    Write-Json $otherPartsPath $keptParts
    if ($hadWorkshopOverride) {
        Write-Host 'Removed global veh_tools_workshop override; vanilla workshop remains untouched.'
    }

    $migrationPath = Join-Path $modRoot 'blaze_migration.json'
    $migrations = Read-Json $migrationPath
    foreach ($pair in @(
        @('afs_metal_rig','veh_tools_workshop'),
        @('afs_kitchen_rig','veh_tools_kitchen'),
        @('afs_cooking_rig','veh_tools_kitchen')
    )) {
        $exists = $false
        foreach ($m in @($migrations)) {
            if ((Has-Prop $m 'type') -and [string]$m.type -eq 'MIGRATION' -and
                (Has-Prop $m 'id') -and [string]$m.id -eq $pair[0]) {
                $exists = $true
            }
        }
        if (-not $exists) {
            $migrations += [pscustomobject]@{
                id = $pair[0]
                type = 'MIGRATION'
                replace = $pair[1]
            }
        }
    }
    $migrations = Ensure-VehiclePartMigration $migrations 'afs_metal_rig' 'veh_tools_workshop' @(
        'welder','soldering_iron','forge','kiln'
    )
    $migrations = Ensure-VehiclePartMigration $migrations 'afs_kitchen_rig' 'veh_tools_kitchen' @(
        'vac_sealer','dehydrator','food_processor','press','puller',
        'pot','pan','chemistry_set','electrolysis_kit','water_purifier'
    )
    $migrations = Ensure-VehiclePartMigration $migrations 'afs_cooking_rig' 'veh_tools_kitchen' @(
        'pot','pan','chemistry_set','electrolysis_kit'
    )
    Write-Json $migrationPath $migrations
    Write-Host 'Added full vehicle_part_migration for legacy AFS rigs.'

    # Keep both custom vehicle flags. TRACKED is actively used by blob wheels/hulls.
    $flagPath = Join-Path $modRoot 'vehicleparts\flags.json'
    if (Test-Path $flagPath -PathType Leaf) {
        $flags = Read-Json $flagPath
        if ($null -eq (Get-ById $flags 'TRACKED')) {
            $flags += [pscustomobject]@{ id='TRACKED'; type='json_flag' }
        }
        if ($null -eq (Get-ById $flags 'FUEL_TANK')) {
            $flags += [pscustomobject]@{ id='FUEL_TANK'; type='json_flag' }
        }
        Write-Json $flagPath $flags
    }

    # =========================================================
    # v0.5 Static integrity gate
    # =========================================================
    Step 'v0.5 Static Integrity Gate'

    $jsonFiles = @(Get-ChildItem -LiteralPath $modRoot -Recurse -File -Filter '*.json')
    foreach ($f in $jsonFiles) {
        try {
            Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        } catch {
            throw "JSON syntax failure in $($f.FullName): $($_.Exception.Message)"
        }
    }
    Write-Host "JSON syntax: OK ($($jsonFiles.Count) files)"

    $forbiddenItems = @('coilgun','nailmag','pool_ball','charcoal')
    $bad = @()
    foreach ($f in $jsonFiles) {
        $data = Read-Json $f.FullName
        foreach ($o in @($data)) {
            if ((Has-Prop $o 'type') -and [string]$o.type -eq 'ITEM' -and
                (Has-Prop $o 'id') -and $forbiddenItems -contains [string]$o.id) {
                $bad += "$($f.FullName): $($o.id)"
            }
            if ((Has-Prop $o 'type') -and [string]$o.type -eq 'item_group' -and
                (Has-Prop $o 'id') -and [string]$o.id -eq 'mags_other_makeshift') {
                $bad += "$($f.FullName): item_group mags_other_makeshift"
            }
            if ((Has-Prop $o 'type') -and [string]$o.type -eq 'recipe' -and
                (Has-Prop $o 'result') -and [string]$o.result -eq 'turret_mount') {
                $bad += "$($f.FullName): recipe turret_mount"
            }
        }
    }
    if ($bad.Count -gt 0) {
        throw ("Core isolation assertion failed:`n" + ($bad -join "`n"))
    }
    Write-Host 'Core isolation assertions: CLEAN'

    $checkOther = Read-Json $otherRecipesPath
    foreach ($id in @(
        'steam_triple_large','steam_triple_giant',
        'steam_turbine_small','steam_turbine_medium',
        'steam_turbine_large','steam_turbine_giant'
    )) {
        if ($null -eq (Get-Recipe $checkOther $id)) { throw "Missing reachability recipe: $id" }
    }
    if ($null -eq (Get-Recipe (Read-Json $blobRecipesPath) 'frostie_hull')) {
        throw 'Missing reachability recipe: frostie_hull'
    }
    if ($null -eq (Get-Recipe (Read-Json $ammoRecipesPath) 'h_projectile')) {
        throw 'Missing reachability recipe: h_projectile'
    }

    $blobCheck = Read-Json $blobToolsPath
    foreach ($id in @('gloople_act','oozle_act','gray_act')) {
        $active = Get-ById $blobCheck $id
        if ($null -eq $active) { throw "Missing active blob: $id" }
        if (Has-Prop $active 'pocket_data') { throw "$id still has ammo pocket" }
        if (Has-Prop $active 'tool_ammo') { throw "$id still has tool_ammo" }
        if (@($active.flags) -notcontains 'SPAWN_ACTIVE') { throw "$id missing SPAWN_ACTIVE" }
        if (-not (Has-Prop $active 'tick_action')) { throw "$id missing tick_action" }
        if (-not (Has-Prop $active.tick_action 'type') -or [string]$active.tick_action.type -ne 'effect_on_conditions') {
            throw "$id tick_action is not zero-return effect_on_conditions"
        }
    }
    $runtimeEocPath = Join-Path $modRoot 'effects_on_condition_blob_runtime.json'
    if (-not (Test-Path $runtimeEocPath -PathType Leaf)) { throw 'Missing blob runtime EOC file' }
    Write-Host 'Blob runtime assertions: CLEAN'

    if ($null -eq (Get-Recipe (Read-Json $magRecipesPath) 'blaze_nailmag')) {
        throw 'Reachability assertion failed: blaze_nailmag has no recipe'
    }

    $checkMigrations = Read-Json $migrationPath
    foreach ($id in @('afs_metal_rig','afs_kitchen_rig','afs_cooking_rig')) {
        $hasVpMigration = $false
        foreach ($m in @($checkMigrations)) {
            if ((Has-Prop $m 'type') -and [string]$m.type -eq 'vehicle_part_migration' -and
                (Has-Prop $m 'from') -and [string]$m.from -eq $id -and
                (Has-Prop $m 'add_veh_tools')) {
                $hasVpMigration = $true
            }
        }
        if (-not $hasVpMigration) { throw "Missing vehicle_part_migration for $id" }
    }

    foreach ($p in @((Read-Json $otherPartsPath))) {
        if ((Has-Prop $p 'type') -and [string]$p.type -eq 'vehicle_part' -and
            (Has-Prop $p 'id') -and [string]$p.id -eq 'veh_tools_workshop') {
            throw 'Global vanilla vehicle-part override still present: veh_tools_workshop'
        }
    }
    Write-Host 'Migration/isolation semantic assertions: CLEAN'

    Step 'Deep vanilla ID collision audit'
    $collisionTypes = @('ITEM','vehicle_part','item_group','ammunition_type','json_flag','SPECIES')
    $coreDefinitionRoots = @((Join-Path $dataRoot 'json'))
    $ddaData = Join-Path $dataRoot 'mods\dda'
    if (Test-Path $ddaData -PathType Container) { $coreDefinitionRoots += $ddaData }

    $coreDefs = Get-DefinitionMap $coreDefinitionRoots $collisionTypes
    $modDefs = Get-DefinitionMap @($modRoot) $collisionTypes

    $collisions = @()
    foreach ($key in @($modDefs.Keys)) {
        if ($coreDefs.ContainsKey($key)) {
            $collisions += [pscustomobject]@{
                key = $key
                mod_file = $modDefs[$key]
                core_file = $coreDefs[$key]
            }
        }
    }

    $collisionLines = @()
    foreach ($c in @($collisions | Sort-Object key)) {
        $collisionLines += ($c.key + "`r`n  MOD : " + $c.mod_file + "`r`n  CORE: " + $c.core_file)
    }
    $collisionReport = Join-Path $reportDir 'core_id_collisions.txt'
    if ($collisionLines.Count -gt 0) {
        Write-Utf8NoBom $collisionReport ($collisionLines -join "`r`n`r`n")
        throw ("Deep core-isolation audit found " + $collisionLines.Count +
               " remaining vanilla definition collision(s). See core_id_collisions.txt.")
    } else {
        Write-Utf8NoBom $collisionReport 'No ITEM/vehicle_part/item_group/ammunition_type/json_flag/SPECIES collisions with vanilla data/json.'
    }
    Write-Host 'Deep vanilla ID collision audit: CLEAN'

    Step 'Recipe overlap audit'
    $coreRecipeMap = Get-RecipeResultMap $coreDefinitionRoots
    $modRecipeMap = Get-RecipeResultMap @($modRoot)
    $recipeOverlapLines = @()
    foreach ($result in @($modRecipeMap.Keys | Sort-Object)) {
        if ($coreRecipeMap.ContainsKey($result)) {
            $recipeOverlapLines += (
                $result + "`r`n  MOD : " + (@($modRecipeMap[$result]) -join '; ') +
                "`r`n  CORE: " + (@($coreRecipeMap[$result]) -join '; ')
            )
        }
    }
    $recipeOverlapReport = Join-Path $reportDir 'recipe_result_overlaps.txt'
    if ($recipeOverlapLines.Count -gt 0) {
        Write-Utf8NoBom $recipeOverlapReport ($recipeOverlapLines -join "`r`n`r`n")
        Write-Host ("Recipe result overlaps with vanilla: {0} (reported, not automatically treated as errors)" -f $recipeOverlapLines.Count) -ForegroundColor Yellow
    } else {
        Write-Utf8NoBom $recipeOverlapReport 'No recipe-result overlaps with vanilla.'
        Write-Host 'Recipe result overlap audit: CLEAN'
    }

    $versionText = @"
Blazemod Revival
Version: $Version
Target CDDA: $TargetBuild
Target commit: $TargetCommit

Cumulative layers:
- v0.4.0 Core Isolation
- v0.4.1 Blob Semantics
- v0.4.2 Content Reachability
- v0.5 Runtime & Save Integrity Gate

Installer / portability layer:
- automatically locates CatLauncher/Catapult, portable and common game-folder installs
- remembers the last successful game root in %APPDATA%\BlazemodRevival\installer.json
- fresh install downloads the pinned baseline commit only when Blazemod is absent
- existing installs are backed up before update
- transactional staging; live working mod is untouched until static checks pass
- previous live mod is moved outside data\mods during validation, preventing duplicate mod IDs
- validator uses the normal game data tree; no alternate datadir is used
- automatic rollback on real validator failure
- blob split uses zero-return EOC tick_action; original friendliness roll is reproduced without tick_action charge warnings
- preserves TRACKED custom flag used by blob wheels/hulls
"@
    Write-Utf8NoBom (Join-Path $modRoot 'REVIVAL_VERSION.txt') $versionText

