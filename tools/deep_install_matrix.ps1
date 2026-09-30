#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GameRoot,
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Out,
    [int]$ValidationTimeout=900,
    [ValidateSet('auto','supported','broken')][string]$CheckModsInteractions='auto'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$game=(Resolve-Path -LiteralPath $GameRoot).Path
$packages=(Resolve-Path -LiteralPath $PackageRoot).Path
$outRoot=[IO.Path]::GetFullPath($Out)
[IO.Directory]::CreateDirectory($outRoot) | Out-Null
$installer=Join-Path $packages 'Install-Mods.ps1'
if(-not(Test-Path -LiteralPath $installer)){throw "Shipped installer missing: $installer"}
$ps51=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
if(-not(Test-Path -LiteralPath $ps51)){throw 'Windows PowerShell 5.1 not found'}

$catalog=Get-Content (Join-Path $packages 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$targetInfo=@($catalog.targets | Where-Object {$_.id -eq $Target})
if($targetInfo.Count -ne 1){throw "Target not found or ambiguous: $Target"}

$script:results=New-Object 'System.Collections.Generic.List[object]'
$matrixTimer=[Diagnostics.Stopwatch]::StartNew()

try{
    $repoCommit=(& git -C $repo rev-parse HEAD 2>$null | Select-Object -First 1)
    $catalogHash=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $packages 'catalog.json')).Hash.ToLowerInvariant()
    $installerHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant()
    $environment=[pscustomobject]@{
        schema=1
        kind='deep-install-environment'
        target=$Target
        target_commit=[string]$targetInfo[0].commit
        harness_commit=if($repoCommit){[string]$repoCommit}else{$null}
        powershell=$PSVersionTable.PSVersion.ToString()
        catalog_sha256=$catalogHash
        installer_sha256=$installerHash
    }
    $environment | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $outRoot 'environment.json') -Encoding UTF8
}catch{
    Write-Warning ("Could not write installer environment manifest: " + $_.Exception.Message)
}

# Probe the exact game binary once for the whole lifecycle matrix unless the
# caller already has a capability result from the release-loader pass.
if($CheckModsInteractions -eq 'auto'){
    $capabilityOut=Join-Path $outRoot 'validator-capability'
    & python (Join-Path $repo 'tools/deep_cdda_runtime.py') probe-check-mods --game-root $game --target $Target --out $capabilityOut --timeout ([Math]::Min($ValidationTimeout,120))
    if($LASTEXITCODE -ne 0){throw 'Could not determine validator mod_interactions capability'}
    $validatorCapability=Get-Content (Join-Path $capabilityOut 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:checkModsInteractions=[string]$validatorCapability.status
}else{
    $script:checkModsInteractions=$CheckModsInteractions
}
if($script:checkModsInteractions -notin @('supported','broken')){throw "Unexpected validator capability: $script:checkModsInteractions"}
Write-Host "Exact game validator capability: dependency mod_interactions = $script:checkModsInteractions"

function Safe-Label([string]$Name){
    return ($Name -replace '[^A-Za-z0-9_.-]','_')
}

function Preserve-InstallerDiagnostics([string]$Text,[string]$CaseDir){
    $matches=[regex]::Matches($Text,'(?im)^Diagnostics:\s*(.+?)\s*$')
    if(-not $matches.Count){return $null}
    $source=$matches[$matches.Count-1].Groups[1].Value.Trim()
    if(-not(Test-Path -LiteralPath $source -PathType Container)){
        Write-Warning "Installer diagnostics path was reported but is missing: $source"
        return $null
    }
    $destination=Join-Path $CaseDir 'transaction-diagnostics'
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    $validation=Join-Path $source 'validation'
    if(Test-Path -LiteralPath $validation -PathType Container){
        foreach($file in @(Get-ChildItem -LiteralPath $validation -Recurse -File -ErrorAction SilentlyContinue)){
            if($file.Name -notin @('stdout.log','stderr.log','debug.log')){continue}
            $relative=$file.FullName.Substring($validation.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
            $target=Join-Path $destination ('validation/'+$relative)
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
    }
    $journal=Join-Path $source 'journal.json'
    if(Test-Path -LiteralPath $journal -PathType Leaf){
        Copy-Item -LiteralPath $journal -Destination (Join-Path $destination 'journal.json') -Force
    }
    if(@(Get-ChildItem -LiteralPath $destination -Recurse -File -ErrorAction SilentlyContinue).Count){
        return $destination
    }
    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
    return $null
}
function Invoke-InstallerCase(
    [string]$Label,
    [string[]]$Extra,
    [bool]$ExpectSuccess=$true,
    [string]$UsePackageRoot=$packages
){
    $safe=Safe-Label $Label
    $dir=Join-Path $outRoot $safe
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $log=Join-Path $dir 'installer.log'
    $args=@(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$installer,
        '-GameRoot',$game,
        '-PackageRoot',$UsePackageRoot,
        '-Yes',
        '-ValidationTimeout',([string]$ValidationTimeout),
        '-CheckModsInteractions',$script:checkModsInteractions
    )+$Extra
    $caseTimer=[Diagnostics.Stopwatch]::StartNew()
    $lines=@(& $ps51 @args 2>&1 | ForEach-Object {$_ | Out-String})
    $code=$LASTEXITCODE
    $caseTimer.Stop()
    $text=($lines -join '')
    [IO.File]::WriteAllText($log,$text,(New-Object Text.UTF8Encoding($false)))
    $diagnostics=$null
    if($code -ne 0){
        try{$diagnostics=Preserve-InstallerDiagnostics $text $dir}
        catch{Write-Warning ("Could not preserve installer diagnostics for $($Label): " + $_.Exception.Message)}
    }
    $ok=if($ExpectSuccess){$code -eq 0}else{$code -ne 0}
    $script:results.Add([pscustomobject]@{
        case=$Label
        expected_success=$ExpectSuccess
        exit_code=$code
        passed=$ok
        duration_seconds=[Math]::Round($caseTimer.Elapsed.TotalSeconds,3)
        log=$log
        diagnostics=$diagnostics
    })
    if(-not $ok){
        throw "Installer case '$Label' returned exit $code; expected success=$ExpectSuccess. See $log"
    }
}

function Read-State {
    $path=Join-Path $game '_CDDA-Mods/installed.json'
    if(-not(Test-Path -LiteralPath $path)){return $null}
    return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Installed-Ids {
    $state=Read-State
    if($null -eq $state){return @()}
    return @($state.packages | ForEach-Object {$_.id})
}

function Installed-GameIds {
    $ids=@(Installed-Ids)
    $gameIds=New-Object 'System.Collections.Generic.List[string]'
    foreach($id in $ids){
        $matches=@($catalog.packages | Where-Object {
            $_.id -eq $id -and $_.targets -contains $Target
        })
        if($matches.Count -ne 1){throw "Installed package lookup ambiguous: $id"}
        foreach($gid in @($matches[0].game_mod_ids)){
            if($gid -and -not $gameIds.Contains([string]$gid)){$gameIds.Add([string]$gid)}
        }
    }
    return @($gameIds)
}

function Invoke-LiveCheck([string]$Label){
    $ids=@(Installed-GameIds)
    if(-not $ids.Count){throw "No installed JSON game IDs for live check: $Label"}
    $dest=Join-Path $outRoot ((Safe-Label $Label)+'-live')
    & python (Join-Path $repo 'tools/deep_cdda_runtime.py') run-installed --game-root $game --target $Target --mods ($ids -join ',') --out $dest --timeout $ValidationTimeout --check-mods-interactions $script:checkModsInteractions
    if($LASTEXITCODE -ne 0){throw "Live game check failed: $Label"}
}

function Current-Transaction([string]$Id){
    $state=Read-State
    if($null -eq $state){throw "No receipt after installing $Id"}
    $record=@($state.packages | Where-Object {$_.id -eq $Id})
    if($record.Count -ne 1){throw "Receipt missing/ambiguous for $Id"}
    if(-not $record[0].transaction){throw "Receipt has no transaction for $Id"}
    return [string]$record[0].transaction
}

function Assert-No-SelectedReceipt([string[]]$Ids,[string]$Label){
    $remaining=@(Installed-Ids | Where-Object {$Ids -contains $_})
    if($remaining.Count){throw "$Label left selected receipt(s): $($remaining -join ', ')"}
}

function Rollback-Transaction([string]$Label,[string]$Transaction,[string[]]$Ids){
    $before=Read-State
    $destinations=@()
    if($null -ne $before){
        $destinations=@(
            $before.packages |
                Where-Object {$Ids -contains $_.id} |
                ForEach-Object {$_.destination}
        )
    }
    Invoke-InstallerCase ($Label+'-rollback') @('-Rollback',$Transaction) $true
    Assert-No-SelectedReceipt $Ids $Label
    foreach($destination in $destinations){
        if($destination -and (Test-Path -LiteralPath $destination)){
            throw "$Label rollback left payload on disk: $destination"
        }
    }
}

$jsonPackages=@($catalog.packages | Where-Object {
    $_.kind -eq 'json' -and $_.archive -and $_.targets -contains $Target
})
if(-not $jsonPackages.Count){throw 'No JSON packages available for target'}
$jsonIds=@($jsonPackages | ForEach-Object {$_.id} | Sort-Object -Unique)

# Serialized on one clean official game tree. Every successful install is rolled back,
# so the next scenario starts from the same real game state without mock filesystem logic.
foreach($id in $jsonIds){
    $before=@(Installed-Ids)
    Invoke-InstallerCase ("individual-$id-install") @('-Mods',$id,'-AllowUntested') $true
    Invoke-LiveCheck ("individual-$id")
    $tx=Current-Transaction $id

    Invoke-InstallerCase ("individual-$id-repeat") @('-Mods',$id,'-AllowUntested') $true
    Invoke-LiveCheck ("individual-$id-repeat")

    Invoke-InstallerCase ("individual-$id-update") @('-Update','-AllowUntested') $true
    Invoke-LiveCheck ("individual-$id-update")

    $afterInstall=@(Installed-Ids)
    $added=@($afterInstall | Where-Object {$before -notcontains $_})
    Rollback-Transaction ("individual-$id") $tx $added
}

# Cross-mod transaction and loader interaction.
$beforeCombined=@(Installed-Ids)
Invoke-InstallerCase 'combined-json-install' @('-Mods',($jsonIds -join ','),'-AllowUntested') $true
Invoke-LiveCheck 'combined-json'
$combinedTx=Current-Transaction $jsonIds[0]
Invoke-InstallerCase 'combined-json-repeat' @('-Mods',($jsonIds -join ','),'-AllowUntested') $true
Invoke-LiveCheck 'combined-json-repeat'
$afterCombined=@(Installed-Ids)
$combinedAdded=@($afterCombined | Where-Object {$beforeCombined -notcontains $_})
Rollback-Transaction 'combined-json' $combinedTx $combinedAdded

# Full content profile additionally exercises the real tileset destination/package path.
$profileNames=@($catalog.profiles.PSObject.Properties.Name)
if($profileNames -contains 'all-content'){
    $beforeProfile=@(Installed-Ids)
    Invoke-InstallerCase 'all-content-install' @('-Profile','all-content','-AllowUntested') $true
    Invoke-LiveCheck 'all-content'
    $profileState=Read-State
    $tiles=@($profileState.packages | ForEach-Object {
        $rid=$_.id
        $pkg=@($catalog.packages | Where-Object {
            $_.id -eq $rid -and $_.targets -contains $Target
        })[0]
        if($pkg.kind -eq 'tileset'){$_}
    })
    if(-not $tiles.Count){throw 'all-content profile did not install a tileset receipt'}
    foreach($record in $tiles){
        if(-not(Test-Path -LiteralPath $record.destination -PathType Container)){
            throw "Tileset destination missing after real install: $($record.destination)"
        }
    }
    $profileTx=Current-Transaction (@($profileState.packages)[0].id)
    $afterProfile=@(Installed-Ids)
    $profileAdded=@($afterProfile | Where-Object {$beforeProfile -notcontains $_})
    Rollback-Transaction 'all-content' $profileTx $profileAdded
}

# Negative lifecycle cases on the same real CDDA installation.

# Corrupt archive: must fail before live content changes.
$probe=$jsonPackages | Select-Object -First 1
$badRoot=Join-Path $outRoot 'corrupt-package-root'
[IO.Directory]::CreateDirectory($badRoot) | Out-Null
Copy-Item (Join-Path $packages 'catalog.json') (Join-Path $badRoot 'catalog.json')
$badArchive=Join-Path $badRoot $probe.archive
Copy-Item (Join-Path $packages $probe.archive) $badArchive
[IO.File]::AppendAllText($badArchive,'CORRUPTED-BY-DEEP-CI')
Invoke-InstallerCase 'reject-corrupt-package' @('-Mods',$probe.id,'-AllowUntested') $false $badRoot

# Duplicate live IDs: installer must refuse ambiguity.
$manifest=Get-Content (Join-Path $repo ('mods/'+$probe.id+'/manifest.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
$variant=@($manifest.variants | Where-Object {$_.targets -contains $Target})[0]
$sourceMod=Join-Path $repo ('mods/'+$probe.id+'/'+$variant.path)
$dupA=Join-Path $game 'data/mods/deep_ci_duplicate_a'
$dupB=Join-Path $game 'data/mods/deep_ci_duplicate_b'
try{
    Copy-Item -LiteralPath $sourceMod -Destination $dupA -Recurse
    Copy-Item -LiteralPath $sourceMod -Destination $dupB -Recurse
    Invoke-InstallerCase 'reject-duplicate-mod-id' @('-Mods',$probe.id,'-AllowUntested') $false
}finally{
    Remove-Item -LiteralPath $dupA -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dupB -Recurse -Force -ErrorAction SilentlyContinue
}

# Pending transaction: new writes must stop until recovery.
$pendingDir=Join-Path $game '_CDDA-Mods/transactions/deep-ci-interrupted'
[IO.Directory]::CreateDirectory($pendingDir) | Out-Null
[IO.File]::WriteAllText(
    (Join-Path $pendingDir 'journal.json'),
    '{"schema":1,"status":"pending","entries":[]}',
    (New-Object Text.UTF8Encoding($false))
)
try{
    Invoke-InstallerCase 'reject-pending-transaction' @('-Mods',$probe.id,'-AllowUntested') $false
}finally{
    Remove-Item -LiteralPath $pendingDir -Recurse -Force -ErrorAction SilentlyContinue
}

$failed=@($script:results | Where-Object {-not $_.passed})
$matrixTimer.Stop()
$summary=[pscustomobject]@{
    schema=1
    target=$Target
    game_root=$game
    json_components=$jsonIds
    check_mods_interaction_capability=$script:checkModsInteractions
    duration_seconds=[Math]::Round($matrixTimer.Elapsed.TotalSeconds,3)
    cases=@($script:results)
    passed=($failed.Count -eq 0)
}
$summary | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outRoot 'matrix-summary.json') -Encoding UTF8
if($failed.Count){throw "$($failed.Count) installer matrix case(s) failed"}
Write-Host "Deep installer matrix passed: $($script:results.Count) cases."
