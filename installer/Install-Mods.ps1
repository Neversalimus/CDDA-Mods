#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GameRoot='',
    [string]$Mods='',
    [string]$Profile='',
    [string]$UserModRoot='',
    [string]$PackageRoot=$PSScriptRoot,
    [switch]$Update,
    [switch]$Online,
    [switch]$AllowUntested,
    [switch]$PlanOnly,
    [switch]$Yes,
    [string]$Rollback='',
    [int]$ValidationTimeout=240,
    [ValidateSet('auto','supported','broken')][string]$CheckModsInteractions='auto'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ModSuite.psm1') -Force
$lock=$null;$work=$null
try{
    if(-not $GameRoot){
        $candidates=@(Find-GameRoots)
        if($candidates.Count -eq 1){$GameRoot=$candidates[0]}
        elseif($candidates.Count -gt 1){
            if($Yes){throw 'Several game installations found. Specify -GameRoot.'}
            for($i=0;$i -lt $candidates.Count;$i++){Write-Host "[$($i+1)] $($candidates[$i])"}
            $answer=Read-Host 'Choose game number';$number=0
            if(-not[int]::TryParse($answer,[ref]$number) -or $number -lt 1 -or $number -gt $candidates.Count){throw 'Invalid game selection'}
            $GameRoot=$candidates[$number-1]
        }else{if($Yes){throw 'Game not found. Specify -GameRoot.'};$GameRoot=Read-Host 'CDDA game folder'}
    }
    if(-not(Test-GameRoot $GameRoot)){throw "Invalid CDDA game folder: $GameRoot"}
    $GameRoot=(Resolve-Path -LiteralPath $GameRoot).Path
    $identity=Get-GameIdentity $GameRoot
    Write-Host "Game: $GameRoot";Write-Host "Build: $($identity.label) / $($identity.commit)"
    $stateRoot=Join-Path $GameRoot '_CDDA-Mods';$stateFile=Join-Path $stateRoot 'installed.json'
    if(-not $PlanOnly){
        [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
        $lock=[IO.File]::Open((Join-Path $stateRoot 'install.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if($env:OS -eq 'Windows_NT'){
            $running=@(Get-Process -Name 'cataclysm*','ncmm*' -ErrorAction SilentlyContinue)
            if($running.Count){throw 'Close CDDA/NCMM before installing. The installer does not stop game processes.'}
        }
    }
    if($Rollback){
        if($PlanOnly){throw 'Rollback cannot be combined with PlanOnly'}
        Assert-SafeName $Rollback
        Restore-Transaction (Join-Safe (Join-Path $stateRoot 'transactions') $Rollback)
        Write-Host 'Rollback complete. Re-run installer to inspect installed versions.' -ForegroundColor Green
        exit 0
    }
    $pending=@(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'transactions') -Filter journal.json -Recurse -File -ErrorAction SilentlyContinue | Where-Object {(Read-Json $_.FullName).status -eq 'pending'})
    if($pending.Count){throw "Interrupted transaction found: $($pending[0].Directory.Name). Use -Rollback $($pending[0].Directory.Name) before installing."}
    $catalogPath=Join-Path $PackageRoot 'catalog.json'
    if($Online){
        # Fixed project endpoint; package URLs are derived from safe archive basenames.
        $PackageRoot=Join-Path ([IO.Path]::GetTempPath()) ('CDDA-Mods-download-'+[guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($PackageRoot) | Out-Null
        $catalogPath=Join-Path $PackageRoot 'catalog.json'
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Neversalimus/CDDA-Mods/releases/latest/download/catalog.json' -OutFile $catalogPath
    }
    if(-not(Test-Path -LiteralPath $catalogPath)){throw 'catalog.json is missing. Download the full installer release or use -Online after publication.'}
    $catalog=Read-Json $catalogPath
    Assert-SafeName $catalog.release_tag
    if($catalog.repository -ne 'Neversalimus/CDDA-Mods'){throw 'Unexpected catalog repository'}
    if($Update){
        if(-not(Test-Path $stateFile)){throw 'No suite installation receipt. Choose mods for the first installation.'}
        $installed=Read-Json $stateFile
        if(-not $Mods){$Mods=(@($installed.packages | ForEach-Object {$_.id}) -join ',')}
    }
    if($Profile){
        $property=$catalog.profiles.PSObject.Properties[$Profile]
        if(-not $property){throw "Unknown profile: $Profile"};$Mods=(@($property.Value) -join ',')
    }
    if(-not $Mods){
        if($Yes){throw 'Specify -Mods or -Profile when using -Yes'}
        $items=@($catalog.packages | Group-Object id | ForEach-Object {$_.Group[0]})
        Write-Host 'Available components:'
        for($i=0;$i -lt $items.Count;$i++){Write-Host "[$($i+1)] $($items[$i].name) $($items[$i].version) [$($items[$i].validation)]"}
        $choice=Read-Host 'Numbers separated by commas, or profile:all-content / profile:secronom / profile:native'
        if($choice.StartsWith('profile:')){
            $property=$catalog.profiles.PSObject.Properties[$choice.Substring(8)]
            if(-not $property){throw 'Unknown profile'};$Mods=@($property.Value)-join ','
        }else{
            $ids=@();foreach($part in $choice.Split(',')){$n=0;if(-not[int]::TryParse($part.Trim(),[ref]$n) -or $n -lt 1 -or $n -gt $items.Count){throw 'Invalid component selection'};$ids+=$items[$n-1].id};$Mods=$ids -join ','
        }
    }
    $ids=@($Mods.Split(',') | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if(-not $AllowUntested -and -not $Yes){
        $unknown=@($catalog.targets | Where-Object {$_.commit -eq $identity.commit}).Count -eq 0
        $pendingSelected=@($catalog.packages | Where-Object {$ids -contains $_.id -and $_.validation -notin @('load-tested','runtime-tested')}).Count -gt 0
        if($unknown -or $pendingSelected){
            Write-Host 'Some selected content is not certified for this build. Installation will first run the native game validator.' -ForegroundColor Yellow
            if((Read-Host 'Try validation and install only if it passes? Type YES') -ne 'YES'){throw 'Cancelled'}
            $AllowUntested=$true
        }
    }
    $packages=@(Resolve-Packages $catalog $ids $identity.commit -AllowUntested:$AllowUntested)
    $plan=@();$destinations=@{}
    foreach($pkg in $packages){
        $destination=Get-Destination $GameRoot $pkg $UserModRoot
        if($destinations.ContainsKey($destination)){throw 'Two packages target the same directory'};$destinations[$destination]=$true
        $same=Test-PayloadEqual $destination $pkg.files
        $plan+=[pscustomobject]@{package=$pkg;destination=$destination;staged='';unchanged=$same}
        Write-Host "$($pkg.id) $($pkg.version) -> $destination $(if($same){'[unchanged]'})"
    }
    if($PlanOnly){Write-Host 'Plan only: no game files changed.';exit 0}
    if(-not $Yes -and (Read-Host 'Install/update this selection with backup? [Y/N]') -notin @('y','Y')){throw 'Cancelled'}
    $transactionId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $work=Join-Path $stateRoot ('transactions/'+$transactionId);[IO.Directory]::CreateDirectory($work) | Out-Null
    foreach($p in $plan){
        $archive=Join-Safe $PackageRoot $p.package.archive
        if(-not(Test-Path -LiteralPath $archive)){
            if(-not $Online){throw "Missing package: $($p.package.archive)"}
            Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/Neversalimus/CDDA-Mods/releases/download/'+$catalog.release_tag+'/'+$p.package.archive) -OutFile $archive
        }
        $p.staged=Expand-VerifiedPackage $archive (Join-Path $work ('stage/'+$p.package.id)) $p.package
    }
    $changed=@($plan | Where-Object {-not $_.unchanged})
    if(-not $changed.Count){Write-Host 'Selected files already match this release.' -ForegroundColor Green;exit 0}
    Write-Host 'Validating in an isolated copy of game data. Saves are not used.'
    Test-StagedMods $GameRoot $plan $work $ValidationTimeout $CheckModsInteractions
    Install-Plan $changed $work $stateFile
    $records=@{}
    if(Test-Path $stateFile){foreach($p in @((Read-Json $stateFile).packages)){$records[$p.id]=$p}}
    foreach($p in $plan){$records[$p.package.id]=[pscustomobject]@{id=$p.package.id;version=$p.package.version;revision=$p.package.revision;destination=$p.destination;archive_sha256=$p.package.sha256;game_commit=$identity.commit;transaction=$transactionId}}
    Write-Json $stateFile ([pscustomobject]@{schema=1;packages=@($records.Values)})
    # Only generated caches of changed JSON mod folders; never saves or configuration.
    foreach($p in $changed | Where-Object {$_.package.kind -eq 'json'}){
        foreach($cache in @((Join-Path $GameRoot ('data/cache/mods/'+$p.package.folder)),(Join-Path (Split-Path (Split-Path $p.destination -Parent) -Parent) ('cache/mods/'+$p.package.folder)))){
            if(Test-Path -LiteralPath $cache){Remove-Item -LiteralPath $cache -Recurse -Force}
        }
    }
    Write-Host "Installed. Backup/rollback transaction: $transactionId" -ForegroundColor Green
    Write-Host 'Enable new content mods in the world settings. Select the tileset in game options if installed.'
}catch{Write-Host $_.Exception.Message -ForegroundColor Red;if($work){Write-Host "Diagnostics: $work"};exit 1}
finally{if($lock){$lock.Dispose()}}
