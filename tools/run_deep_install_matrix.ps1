#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RepositoryRoot,
    [Parameter(Mandatory=$true)][string]$GameRoot,
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [string]$MatrixFile='tests/deep_runtime_matrix.json',
    [string]$Target='',
    [string]$Scenario='all',
    [string]$Out='build/deep-install',
    [int]$ValidationTimeout=900
)
$ErrorActionPreference='Stop'

$RepositoryRoot=(Resolve-Path -LiteralPath $RepositoryRoot).Path
$GameRoot=(Resolve-Path -LiteralPath $GameRoot).Path
$PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path
if(-not [IO.Path]::IsPathRooted($MatrixFile)){$MatrixFile=Join-Path $RepositoryRoot $MatrixFile}
if(-not [IO.Path]::IsPathRooted($Out)){$Out=Join-Path $RepositoryRoot $Out}
[IO.Directory]::CreateDirectory($Out)|Out-Null

Import-Module (Join-Path $RepositoryRoot 'installer/ModSuite.psm1') -Force
$matrix=Read-Json $MatrixFile
if($matrix.schema -ne 1){throw 'Unsupported deep runtime matrix schema.'}
$targetId=if($Target){$Target}else{[string]$matrix.target}
Assert-SafeName $targetId
$targetPath=Join-Path $RepositoryRoot ('catalog/targets/'+$targetId+'.json')
if(-not(Test-Path -LiteralPath $targetPath -PathType Leaf)){throw "Unknown target: $targetId"}
$targetInfo=Read-Json $targetPath
$identity=Get-GameIdentity $GameRoot
if(-not $identity.commit -or $identity.commit -ne $targetInfo.commit){
    throw "Official CDDA identity mismatch. Expected $($targetInfo.commit), got $($identity.commit)."
}
$catalog=Read-Json (Join-Path $PackageRoot 'catalog.json')
$installer=Join-Path $PackageRoot 'Install-Mods.ps1'
if(-not(Test-Path -LiteralPath $installer -PathType Leaf)){throw "Release installer missing: $installer"}

$scenarios=@($matrix.install_scenarios)
if($Scenario -ne 'all'){
    $scenarios=@($scenarios|Where-Object {$_.id -eq $Scenario})
    if($scenarios.Count -ne 1){throw "Unknown deep install scenario: $Scenario"}
}
$summary=[ordered]@{
    schema=1
    target=$targetId
    tag=$targetInfo.tag
    commit=$targetInfo.commit
    game_label=$identity.label
    scenarios=@()
}
$failed=New-Object 'System.Collections.Generic.List[string]'

function Copy-GameTree([string]$Source,[string]$Destination){
    if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Recurse -Force}
    [IO.Directory]::CreateDirectory($Destination)|Out-Null
    & robocopy.exe $Source $Destination /MIR /XD '_CDDA-Mods' /NFL /NDL /NJH /NJS /NP | Out-Null
    $code=$LASTEXITCODE
    if($code -gt 7){throw "robocopy failed with exit $code"}
}

function Invoke-DirectGameCheck([string]$Root,[string[]]$ModIds,[string]$Evidence,[int]$TimeoutSeconds){
    [IO.Directory]::CreateDirectory($Evidence)|Out-Null
    $exe=@('cataclysm-tiles.vanilla.exe','cataclysm-tiles.exe','cataclysm.exe','cataclysm')|
        ForEach-Object {Join-Path $Root $_}|
        Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|
        Select-Object -First 1
    if(-not $exe){throw "CDDA executable missing in $Root"}
    $user=Join-Path $Evidence 'user'
    [IO.Directory]::CreateDirectory($user)|Out-Null
    foreach($p in @($Root,$user)){if($p.Contains('"')){throw 'Quotes in game paths are not supported.'}}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$exe
    $psi.WorkingDirectory=$Root
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.Arguments='--basepath "'+$Root.TrimEnd('\','/')+'/" --userdir "'+$user.TrimEnd('\','/')+'/" --check-mods '+($ModIds -join ' ')
    $proc=New-Object Diagnostics.Process
    $proc.StartInfo=$psi
    try{
        [void]$proc.Start()
        $stdout=$proc.StandardOutput.ReadToEndAsync()
        $stderr=$proc.StandardError.ReadToEndAsync()
        if(-not $proc.WaitForExit($TimeoutSeconds*1000)){
            try{$proc.Kill();$proc.WaitForExit()}catch{}
            throw "Real game check timed out after $TimeoutSeconds seconds."
        }
        $outText=$stdout.Result
        $errText=$stderr.Result
        [IO.File]::WriteAllText((Join-Path $Evidence 'stdout.log'),$outText)
        [IO.File]::WriteAllText((Join-Path $Evidence 'stderr.log'),$errText)
        $logs=$outText+"\n"+$errText
        foreach($f in @(Get-ChildItem -LiteralPath $user -Filter debug.log -File -Recurse -ErrorAction SilentlyContinue)){
            $logs+="\n"+(Get-Content -LiteralPath $f.FullName -Raw)
        }
        $errors=@($logs -split "\n"|Where-Object {
            $_ -match '\(json-error\)|ERROR\s*:|Error loading|Unknown mod:|Missing dependencies:|Fatal:'
        })
        [pscustomobject]@{exit_code=$proc.ExitCode;errors=$errors;mods=$ModIds}
    }finally{$proc.Dispose()}
}

function Invoke-ReleaseInstaller([string]$Root,[string[]]$ExtraArgs){
    $args=@(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,
        '-GameRoot',$Root,'-PackageRoot',$PackageRoot,
        '-AllowUntested','-Yes','-ValidationTimeout',[string]$ValidationTimeout
    )+$ExtraArgs
    & powershell.exe @args
    if($LASTEXITCODE -ne 0){throw "Release installer failed with exit $LASTEXITCODE. Args: $($ExtraArgs -join ' ')"}
}

function Assert-InstalledPayloads([string]$Root,[object[]]$Packages){
    foreach($pkg in $Packages){
        $destination=Get-Destination $Root $pkg ''
        if(-not(Test-PayloadEqual $destination $pkg.files)){
            throw "Installed payload differs from package: $($pkg.id) -> $destination"
        }
    }
}

function Get-GameModIds([object[]]$Packages){
    $result=New-Object 'System.Collections.Generic.List[string]'
    foreach($pkg in $Packages|Where-Object {$_.kind -eq 'json'}){
        foreach($id in @($pkg.game_mod_ids)){
            if(-not $result.Contains([string]$id)){$result.Add([string]$id)}
        }
    }
    return @($result.ToArray())
}

function Get-DefaultDestination([string]$Root,$Package){
    switch([string]$Package.kind){
        'json' { return Join-Path $Root ('data/mods/'+[string]$Package.folder) }
        'tileset' { return Join-Path $Root ('gfx/'+[string]$Package.folder) }
        default { throw "Deep content installation matrix does not accept package kind: $($Package.kind)" }
    }
}

foreach($row in $scenarios){
    $scenarioId=[string]$row.id
    Assert-SafeName $scenarioId
    $scenarioRoot=Join-Path $env:RUNNER_TEMP ('cdda-mods-deep-'+$scenarioId)
    $evidence=Join-Path $Out $scenarioId
    if(Test-Path -LiteralPath $evidence){Remove-Item -LiteralPath $evidence -Recurse -Force}
    [IO.Directory]::CreateDirectory($evidence)|Out-Null
    $record=[ordered]@{id=$scenarioId;mods=@($row.mods);steps=@();status='running';error=$null}
    try{
        Copy-GameTree $GameRoot $scenarioRoot
        $vanilla=Invoke-DirectGameCheck $scenarioRoot @('dda') (Join-Path $evidence '00-vanilla') $ValidationTimeout
        if($vanilla.exit_code -ne 0 -or @($vanilla.errors).Count){throw 'Vanilla baseline failed before installation.'}
        $record.steps+='vanilla-baseline'

        $ids=@($row.mods|ForEach-Object {[string]$_})
        $packages=@(Resolve-Packages $catalog $ids $identity.commit -AllowUntested)
        if(-not $packages.Count){throw 'Scenario resolved to zero packages.'}
        $gameIds=@(Get-GameModIds $packages)

        foreach($pkg in $packages){
            $expected=Get-DefaultDestination $scenarioRoot $pkg
            if(Test-Path -LiteralPath $expected){
                throw "Pristine official CDDA already contains selected destination: $expected"
            }
        }

        Invoke-ReleaseInstaller $scenarioRoot @('-Mods',($ids -join ','))
        Assert-InstalledPayloads $scenarioRoot $packages
        if($gameIds.Count){
            $check=Invoke-DirectGameCheck $scenarioRoot $gameIds (Join-Path $evidence '10-installed') $ValidationTimeout
            if($check.exit_code -ne 0 -or @($check.errors).Count){throw 'Installed game check failed.'}
        }
        $record.steps+='clean-install'

        # Same release on top of itself must be a no-op, not a second divergent install.
        Invoke-ReleaseInstaller $scenarioRoot @('-Mods',($ids -join ','))
        Assert-InstalledPayloads $scenarioRoot $packages
        $record.steps+='idempotent-reinstall'

        # Exercise the player's normal update path using the installation receipt.
        Invoke-ReleaseInstaller $scenarioRoot @('-Update')
        Assert-InstalledPayloads $scenarioRoot $packages
        if($gameIds.Count){
            $check=Invoke-DirectGameCheck $scenarioRoot $gameIds (Join-Path $evidence '20-updated') $ValidationTimeout
            if($check.exit_code -ne 0 -or @($check.errors).Count){throw 'Post-update game check failed.'}
        }
        $record.steps+='receipt-update'

        $statePath=Join-Path $scenarioRoot '_CDDA-Mods/installed.json'
        if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'Installation receipt missing.'}
        $state=Read-Json $statePath
        $packageIds=@($packages|ForEach-Object {$_.id})
        $transactions=@($state.packages|Where-Object {$packageIds -contains $_.id}|ForEach-Object {$_.transaction}|Select-Object -Unique)
        if($transactions.Count -ne 1){throw "Expected one install transaction, found $($transactions.Count)."}
        Invoke-ReleaseInstaller $scenarioRoot @('-Rollback',[string]$transactions[0])
        $record.steps+='rollback'
        if(Test-Path -LiteralPath $statePath -PathType Leaf){
            $rolledState=Read-Json $statePath
            $left=@($rolledState.packages|Where-Object {$packageIds -contains $_.id})
            if($left.Count){throw 'Rollback left selected package records in installed.json.'}
        }
        foreach($pkg in $packages){
            $expected=Get-DefaultDestination $scenarioRoot $pkg
            if(Test-Path -LiteralPath $expected){
                throw "Rollback left selected payload on disk: $($pkg.id) -> $expected"
            }
        }

        # Reinstall after rollback catches stale transaction/receipt/cache state.
        Invoke-ReleaseInstaller $scenarioRoot @('-Mods',($ids -join ','))
        Assert-InstalledPayloads $scenarioRoot $packages
        if($gameIds.Count){
            $check=Invoke-DirectGameCheck $scenarioRoot $gameIds (Join-Path $evidence '30-reinstalled') $ValidationTimeout
            if($check.exit_code -ne 0 -or @($check.errors).Count){throw 'Post-rollback reinstall game check failed.'}
        }
        $record.steps+='reinstall-after-rollback'
        $record.status='passed'
    }catch{
        $record.status='failed'
        $record.error=$_.Exception.Message
        $failed.Add($scenarioId)
        Set-Content -LiteralPath (Join-Path $evidence 'failure.txt') -Value $_.Exception.ToString() -Encoding UTF8
    }finally{
        $summary.scenarios+= [pscustomobject]$record
        $summary|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $Out 'report.json') -Encoding UTF8
        Remove-Item -LiteralPath $scenarioRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ("Deep real-CDDA install matrix: {0} scenario(s), {1} failure(s)." -f $summary.scenarios.Count,$failed.Count)
if($failed.Count){throw ('Failed deep scenarios: '+($failed -join ', '))}
