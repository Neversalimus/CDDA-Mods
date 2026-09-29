Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Write-Json([string]$Path,$Value) {
    $parent=Split-Path $Path -Parent; [IO.Directory]::CreateDirectory($parent) | Out-Null
    $tmp=$Path+'.tmp'; [IO.File]::WriteAllText($tmp,($Value | ConvertTo-Json -Depth 80),(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $Path){ [IO.File]::Replace($tmp,$Path,[NullString]::Value) } else { [IO.File]::Move($tmp,$Path) }
}
function Assert-SafeName([string]$Name) {
    if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' -or $Name -match '\.\.') { throw "Unsafe name: $Name" }
}
function Join-Safe([string]$Root,[string]$Relative) {
    if(-not $Relative -or $Relative -match '[:\\]' -or $Relative.StartsWith('/') -or @($Relative.Split('/') | Where-Object {$_ -in @('','.','..')}).Count) {throw "Unsafe relative path: $Relative"}
    foreach($part in $Relative.Split('/')) {
        if($part -match '[<>"|?*\x00-\x1f]' -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw "Unsafe filename: $part"}
    }
    $base=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $p=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $p.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Path escapes root'}
    # Reject junctions/symlinks in any existing ancestor.
    $cur=$p
    while($cur -and $cur.Length -ge $base.TrimEnd([IO.Path]::DirectorySeparatorChar).Length){
        if(Test-Path -LiteralPath $cur){if((Get-Item -LiteralPath $cur -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point not allowed: $cur"}}
        $cur=Split-Path $cur -Parent
    }
    return $p
}
function Test-GameRoot([string]$Path) {
    if(-not $Path -or -not (Test-Path -LiteralPath (Join-Path $Path 'data/json'))){return $false}
    return @(@('cataclysm-tiles.exe','cataclysm.exe','cataclysm') | Where-Object {Test-Path -LiteralPath (Join-Path $Path $_)}).Count -gt 0
}
function Find-GameRoots {
    $roots=New-Object 'System.Collections.Generic.List[string]'
    foreach($p in @($env:CDDA_HOME,(Get-Location).Path,(Split-Path $PSScriptRoot -Parent))){if($p){$roots.Add($p)}}
    if($env:LOCALAPPDATA){$roots.Add((Join-Path $env:LOCALAPPDATA 'com.munetmo.cat-launcher/Assets/DarkDaysAhead'))}
    if($env:USERPROFILE){foreach($d in @('Downloads','Desktop','Games','Documents/Games')){$roots.Add((Join-Path $env:USERPROFILE $d))}}
    foreach($p in @('C:/Games','D:/Games','C:/CDDA','D:/CDDA')){if(Test-Path $p){$roots.Add($p)}}
    if($env:OS -eq 'Windows_NT'){
        $steam=Get-ItemProperty 'HKCU:/Software/Valve/Steam' -ErrorAction SilentlyContinue
        if($steam -and $steam.PSObject.Properties['SteamPath']){
            $roots.Add((Join-Path $steam.SteamPath 'steamapps/common'))
            $vdf=Join-Path $steam.SteamPath 'steamapps/libraryfolders.vdf'
            if(Test-Path $vdf){foreach($match in [regex]::Matches((Get-Content $vdf -Raw),'"path"\s+"([^"]+)"')){$roots.Add((Join-Path ($match.Groups[1].Value.Replace('\\','\')) 'steamapps/common'))}}
        }
    }
    $found=@{}; $visited=@{}
    function Scan([string]$Path,[int]$Depth){
        if(-not (Test-Path -LiteralPath $Path -PathType Container)){return}
        $item=Get-Item -LiteralPath $Path -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){return}
        $full=$item.FullName
        if($visited.ContainsKey($full)){return};$visited[$full]=$true
        if(Test-GameRoot $full){$found[$full]=$true;return}
        if($Depth -le 0){return}
        foreach($dir in @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue)){Scan $dir.FullName ($Depth-1)}
    }
    foreach($r in $roots){Scan $r 3}
    return @($found.Keys | Sort-Object)
}
function Get-GameIdentity([string]$Root){
    $commit='';$label=Split-Path $Root -Leaf;$v=Join-Path $Root 'VERSION.txt'
    if(Test-Path -LiteralPath $v){$txt=Get-Content -LiteralPath $v -Raw;if($txt -match '(?im)commit sha:\s*([0-9a-f]{40})'){$commit=$Matches[1].ToLowerInvariant()};if($txt -match '(?im)build number:\s*(\S+)'){$label=$Matches[1]}}
    [pscustomobject]@{commit=$commit;label=$label}
}
function Resolve-Packages($Catalog,[string[]]$Ids,[string]$Commit,[switch]$AllowUntested){
    if($Catalog.schema -ne 1){throw 'Unsupported catalog schema'}
    $target=@($Catalog.targets | Where-Object {$_.commit -eq $Commit -and $Commit})
    if($target.Count -gt 1){throw 'Ambiguous target commit'}
    if(-not $target.Count -and -not $AllowUntested){throw 'This game commit has no catalog target. Use a tested build or explicit -AllowUntested.'}
    $chosen=@{};$visiting=@{};$ordered=New-Object 'System.Collections.Generic.List[object]'
    function Visit([string]$Id){
        Assert-SafeName $Id
        if($chosen.ContainsKey($Id)){return};if($visiting.ContainsKey($Id)){throw "Dependency cycle: $Id"};$visiting[$Id]=$true
        $candidates=@($Catalog.packages | Where-Object {$_.id -eq $Id})
        if($target.Count){$exact=@($candidates | Where-Object {$_.targets -contains $target[0].id})}else{$exact=@()}
        if($exact.Count -eq 1){$pkg=$exact[0]}elseif($exact.Count -gt 1){throw "Ambiguous version for $Id"}elseif($AllowUntested -and $candidates.Count -eq 1){$pkg=$candidates[0]}else{throw "No unambiguous package for $Id on this game build"}
        if($pkg.validation -eq 'blocked'){throw "Package blocked: $Id"}
        if(-not $pkg.archive){throw "Source only: $Id $($pkg.version). A compiled release and compatible external host are required."}
        if($pkg.validation -notin @('load-tested','runtime-tested') -and -not $AllowUntested){throw "Package $Id is $($pkg.validation), not yet load-tested. Use -AllowUntested for an explicit validation attempt."}
        Assert-SafeName $pkg.folder;Assert-SafeName $pkg.archive
        if($pkg.sha256 -notmatch '^[0-9a-f]{64}$'){throw 'Invalid package hash'}
        foreach($d in @($pkg.dependencies)){Visit $d}
        $visiting.Remove($Id);$chosen[$Id]=$pkg;$ordered.Add($pkg)
    }
    foreach($id in $Ids){Visit $id}
    return @($ordered.ToArray())
}
function Expand-VerifiedPackage([string]$Archive,[string]$Destination,$Package){
    if((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Package.sha256){throw "Archive SHA256 mismatch: $($Package.id)"}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try{
        $seen=@{};[long]$total=0
        foreach($entry in $zip.Entries){
            $name=$entry.FullName
            if($name.EndsWith('/')){continue}
            $target=Join-Safe $Destination $name
            if($seen.ContainsKey($name)){throw "Duplicate ZIP entry: $name"};$seen[$name]=$true
            if(($entry.ExternalAttributes -shr 16 -band 61440) -eq 40960){throw 'ZIP symlink not allowed'}
            $total+=$entry.Length;if($total -gt 1073741824 -or $zip.Entries.Count -gt 20000){throw 'Package size limit exceeded'}
            if($name -ne 'package.json' -and -not $name.StartsWith('payload/')){throw "Unexpected ZIP entry: $name"}
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    }finally{$zip.Dispose()}
    $inside=Read-Json (Join-Path $Destination 'package.json')
    foreach($key in @('id','version','revision','kind','folder','content_sha256')){if($inside.$key -ne $Package.$key){throw "Descriptor mismatch: $key"}}
    $payload=Join-Path $Destination 'payload';$expected=@{}
    foreach($prop in $Package.files.PSObject.Properties){
        $p=Join-Safe $payload $prop.Name;$expected[$prop.Name]=$true
        if(-not(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $prop.Value){throw "Payload hash mismatch: $($prop.Name)"}
    }
    if(@(Get-ChildItem -LiteralPath $payload -File -Recurse -Force).Count -ne $expected.Count){throw 'Unlisted payload files'}
    return $payload
}
function Get-ModDirectories([string[]]$Roots,[string[]]$Ids){
    $result=@{}
    foreach($root in $Roots){
        if(-not $root -or -not(Test-Path -LiteralPath $root)){continue}
        foreach($f in @(Get-ChildItem -LiteralPath $root -Filter modinfo.json -File -Recurse -ErrorAction Stop)){
            # PS 5.1 preserves a JSON root array as one pipeline object.
            # Assignment works with both that array and PS 7's enumerated output.
            $records=Read-Json $f.FullName
            foreach($m in $records){if($m.PSObject.Properties['type'] -and $m.type -eq 'MOD_INFO' -and $m.PSObject.Properties['id'] -and $Ids -contains $m.id){$result[$f.Directory.FullName]=$true}}
        }
    }
    return @($result.Keys)
}
function Get-UserMods([string]$Root){
    $result=@((Join-Path $Root 'mods'))
    if($env:LOCALAPPDATA){
        $result+=(Join-Path $env:LOCALAPPDATA 'cataclysm-dda/mods')
        if($Root -like '*com.munetmo.cat-launcher*'){$result+=(Join-Path $env:LOCALAPPDATA 'com.munetmo.cat-launcher/UserData/DarkDaysAhead/mods')}
    }
    return $result
}
function Get-Destination([string]$GameRoot,$Package,[string]$UserModRoot=''){
    switch($Package.kind){
        'json' {
            $root=if($UserModRoot){$UserModRoot}else{Join-Path $GameRoot 'data/mods'}
            $existing=@(Get-ModDirectories (@((Join-Path $GameRoot 'data/mods'))+(Get-UserMods $GameRoot)+@($UserModRoot) | Where-Object {$_} | Select-Object -Unique) $Package.game_mod_ids)
            if($existing.Count -gt 1){throw "Duplicate mod IDs for $($Package.id): $($existing -join '; '). Resolve duplicates before installing."}
            if($existing.Count -eq 1){return $existing[0]}
        }
        'tileset' {$root=Join-Path $GameRoot 'gfx'}
        'native' {
            if(-not(Test-Path -LiteralPath (Join-Path $GameRoot 'ncmm/bootstrap.sha256'))){throw 'Install the compatible NCMM host separately before code mods.'}
            $root=Join-Path $GameRoot 'code_mods'
        }
        default {throw 'Unsupported package kind'}
    }
    return Join-Safe $root $Package.folder
}
function Test-PayloadEqual([string]$Path,$Files){
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){return $false}
    $props=@($Files.PSObject.Properties)
    if(@(Get-ChildItem -LiteralPath $Path -File -Force -Recurse).Count -ne $props.Count){return $false}
    foreach($p in $props){$file=Join-Safe $Path $p.Name;if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $p.Value){return $false}}
    return $true
}
function Invoke-GameCheck([string]$Exe,[string]$GameRoot,[string]$DataRoot,[string]$UserRoot,[string[]]$ModIds,[int]$TimeoutSeconds=240){
    [IO.Directory]::CreateDirectory($UserRoot) | Out-Null
    # CDDA opens config/debug.log before its later essential-directory setup.
    # --check-mods may exit before that setup path, so preserve early diagnostics.
    [IO.Directory]::CreateDirectory((Join-Path $UserRoot 'config')) | Out-Null
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$Exe;$psi.WorkingDirectory=$GameRoot;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($p in @($GameRoot,$DataRoot,$UserRoot)){if($p.Contains('"')){throw 'Quotes in game paths are not supported'}}
    $psi.Arguments='--basepath "'+$GameRoot.TrimEnd('\','/')+'/" --datadir "'+$DataRoot.TrimEnd('\','/')+'/" --userdir "'+$UserRoot.TrimEnd('\','/')+'/" --check-mods '+($ModIds -join ' ')
    $proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi
    try{
        [void]$proc.Start();$stdout=$proc.StandardOutput.ReadToEndAsync();$stderr=$proc.StandardError.ReadToEndAsync()
        if(-not $proc.WaitForExit($TimeoutSeconds*1000)){try{$proc.Kill();$proc.WaitForExit()}catch{};throw "Game validator timed out after $TimeoutSeconds seconds"}
        $out=$stdout.Result;$err=$stderr.Result
        [IO.File]::WriteAllText((Join-Path $UserRoot 'stdout.log'),$out);[IO.File]::WriteAllText((Join-Path $UserRoot 'stderr.log'),$err)
        $logs=$out+"`n"+$err
        foreach($f in @(Get-ChildItem -LiteralPath $UserRoot -Filter debug.log -Recurse -File)){$logs+="`n"+(Get-Content $f.FullName -Raw)}
        $lines=@($logs -split "`r?`n")
        # Only source-bearing ERROR records decide severity. CDDA text-style
        # diagnostics are multi-line; their following "Json error: ..." detail
        # must inherit the style classification instead of becoming a false fatal.
        $errorRecords=@($lines | Where-Object {$_ -match '(^|\s)ERROR\s*:'})
        $style=@($errorRecords | Where-Object {$_ -match 'text_style_check_reader\.cpp:63'})
        $bad=@(
            $errorRecords | Where-Object {
                ($_ -notmatch 'text_style_check_reader\.cpp:63') -and
                ($_ -notmatch '^\s*(\(continued from above\)\s+)?ERROR\s*:\s*\(error message will follow backtrace\)\s*$')
            }
        )
        $bad+=@($lines | Where-Object {
            ($_ -match 'Error loading|Unknown mod:|Missing dependencies:|Fatal:') -and
            ($_ -notmatch '(^|\s)ERROR\s*:')
        })
        $rawExit=$proc.ExitCode
        $exit=$rawExit
        # CDDA also returns 1 for advisory cata-text-style diagnostics.
        if($exit -eq 1 -and $style.Count -gt 0 -and $bad.Count -eq 0){$exit=0}
        return [pscustomobject]@{exit_code=$exit;raw_exit_code=$rawExit;errors=$bad;style_warnings=$style;log=$UserRoot}
    }finally{$proc.Dispose()}
}
function Get-CheckModsInteractionHazards([string]$DataRoot,[string[]]$RootIds){
    $modsRoot=Join-Path $DataRoot 'mods'
    if(-not(Test-Path -LiteralPath $modsRoot -PathType Container)){return @()}
    $index=@{}
    foreach($file in @(Get-ChildItem -LiteralPath $modsRoot -Filter modinfo.json -Recurse -File -ErrorAction SilentlyContinue)){
        try{$doc=Read-Json $file.FullName}catch{continue}
        foreach($row in @($doc)){
            if($null -eq $row -or [string]$row.type -ne 'MOD_INFO' -or -not $row.id){continue}
            $deps=@()
            if($row.PSObject.Properties['dependencies']){$deps=@($row.dependencies | ForEach-Object {[string]$_})}
            $index[[string]$row.id]=[pscustomobject]@{root=$file.Directory.FullName;dependencies=$deps}
        }
    }
    $seen=@{}
    $stack=New-Object 'System.Collections.Generic.Stack[string]'
    foreach($id in @($RootIds)){if($id){$stack.Push([string]$id)}}
    $hazards=New-Object 'System.Collections.Generic.List[string]'
    while($stack.Count -gt 0){
        $id=$stack.Pop()
        if($seen.ContainsKey($id)){continue}
        $seen[$id]=$true
        if(-not $index.ContainsKey($id)){continue}
        $meta=$index[$id]
        $interactions=Join-Path $meta.root 'mod_interactions'
        if((Test-Path -LiteralPath $interactions -PathType Container) -and @(Get-ChildItem -LiteralPath $interactions -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue).Count){
            if(-not $hazards.Contains($id)){$hazards.Add($id)}
        }
        foreach($dep in @($meta.dependencies)){if($dep){$stack.Push([string]$dep)}}
    }
    return @($hazards | Sort-Object -Unique)
}
function Test-CheckModsInteractionCapability([string]$Exe,[string]$GameRoot,[string]$DataRoot,[string]$Work,[int]$TimeoutSeconds=120){
    $token='CDDA_MODS_CHECK_MODS_INTERACTION_PROBE_SENTINEL'
    $modsRoot=Join-Path $DataRoot 'mods'
    [IO.Directory]::CreateDirectory($modsRoot) | Out-Null
    $dep=Join-Path $modsRoot '__cdda_mods_probe_interaction_dep'
    $root=Join-Path $modsRoot '__cdda_mods_probe_interaction_root'
    foreach($p in @($dep,$root)){if(Test-Path -LiteralPath $p){throw "Validator capability probe path already exists: $p"}}
    try{
        [IO.Directory]::CreateDirectory($dep) | Out-Null
        [IO.Directory]::CreateDirectory($root) | Out-Null
        Write-Json (Join-Path $dep 'modinfo.json') @{type='MOD_INFO';id='cdda_mods_probe_interaction_dep';name='CDDA-Mods validator capability dependency';authors=@('CDDA-Mods CI');description='Temporary capability probe.';category='content';dependencies=@('dda')}
        Write-Json (Join-Path $root 'modinfo.json') @{type='MOD_INFO';id='cdda_mods_probe_interaction_root';name='CDDA-Mods validator capability root';authors=@('CDDA-Mods CI');description='Temporary capability probe.';category='content';dependencies=@('dda','cdda_mods_probe_interaction_dep')}
        $hidden=Join-Path $dep 'mod_interactions/cdda_mods_probe_never_loaded'
        [IO.Directory]::CreateDirectory($hidden) | Out-Null
        Write-Json (Join-Path $hidden 'sentinel.json') @{
            type='snippet'
            category='cdda_mods_probe_interaction'
            text=($token+'. single-space sentinel')
        }
        $probe=Invoke-GameCheck $Exe $GameRoot $DataRoot $Work @('cdda_mods_probe_interaction_root') ([Math]::Min($TimeoutSeconds,120))
        $evidence=(@($probe.errors) -join "`n")
        foreach($f in @(Get-ChildItem -LiteralPath $Work -File -Recurse -ErrorAction SilentlyContinue)){
            if($f.Name -in @('stdout.log','stderr.log','debug.log')){try{$evidence+="`n"+(Get-Content $f.FullName -Raw)}catch{}}
        }
        if($evidence -match [regex]::Escape($token)){
            return $false
        }
        if($probe.exit_code -eq 124){
            Write-Warning 'Validator capability probe timed out; treating dependency mod_interactions as unsupported and deferring only affected roots.'
            return $false
        }
        if($probe.exit_code -eq 0 -and @($probe.errors).Count -eq 0){
            return $true
        }
        throw "Validator capability probe was inconclusive; report: $Work"
    }finally{
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $dep -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Test-StagedMods([string]$GameRoot,[object[]]$Plan,[string]$Work,[int]$TimeoutSeconds=240,[string]$CheckModsInteractions='auto'){
    $json=@($Plan | Where-Object {$_.package.kind -eq 'json'});if(-not $json.Count){return}
    $exe=@('cataclysm-tiles.vanilla.exe','cataclysm-tiles.exe','cataclysm.exe','cataclysm') | ForEach-Object {Join-Path $GameRoot $_} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
    if(-not $exe){throw 'Game validator not found'}
    $data=Join-Path $Work 'validation/data';[IO.Directory]::CreateDirectory($data) | Out-Null
    foreach($item in Get-ChildItem -LiteralPath (Join-Path $GameRoot 'data') -Force){if($item.Name -notin @('cache','gfx')){Copy-Item -LiteralPath $item.FullName -Destination $data -Recurse -Force}}
    # CDDA set_datadir changes gfxdir to datadir/gfx. Preserve real tiles/portraits here.
    $gfx=Join-Path $GameRoot 'gfx';if(Test-Path $gfx){Copy-Item -LiteralPath $gfx -Destination (Join-Path $data 'gfx') -Recurse -Force}
    $base=Invoke-GameCheck $exe $GameRoot $data (Join-Path $Work 'validation/baseline') @('dda') $TimeoutSeconds
    if($base.exit_code -ne 0 -or @($base.errors).Count){throw "Vanilla baseline validation failed; report: $($base.log)"}
    if($CheckModsInteractions -eq 'supported'){
        $interactionSupported=$true
    }elseif($CheckModsInteractions -eq 'broken'){
        $interactionSupported=$false
    }elseif($CheckModsInteractions -eq 'auto'){
        $interactionSupported=Test-CheckModsInteractionCapability $exe $GameRoot $data (Join-Path $Work 'validation/capability-check-mods-interactions') $TimeoutSeconds
    }else{
        throw "Unknown check-mods interaction capability mode: $CheckModsInteractions"
    }
    Write-Host ("Validator capability: dependency mod_interactions = " + $(if($interactionSupported){'supported'}else{'broken; exact-source defer required'}))
    foreach($entry in $json){
        foreach($old in @(Get-ModDirectories @((Join-Path $data 'mods')) $entry.package.game_mod_ids)){Remove-Item -LiteralPath $old -Recurse -Force}
        Copy-Item -LiteralPath $entry.staged -Destination (Join-Safe (Join-Path $data 'mods') $entry.package.folder) -Recurse
    }
    $ids=@($json | ForEach-Object {$_.package.game_mod_ids})
    # A synthetic dependency-only mod tests the selected stack together, not just separately.
    $stack=Join-Path $data 'mods/suite_validation_stack';[IO.Directory]::CreateDirectory($stack) | Out-Null
    Write-Json (Join-Path $stack 'modinfo.json') @(@{type='MOD_INFO';id='suite_validation_stack';name='Suite validation only';authors=@('Neversalimus');description='Temporary validation stack.';dependencies=@('dda')+$ids})
    # Capability is detected from the exact binary instead of hard-coding a
    # CDDA version. Older --check-mods builds recursively consume dependency
    # mod_interactions; fixed builds can validate the full graph normally.
    $hazards=@(Get-CheckModsInteractionHazards $data @('suite_validation_stack'))
    if($hazards.Count -and -not $interactionSupported){
        # Preserve every safe validator check in this plan. Only roots whose own
        # dependency closure reaches interaction-bearing mods are deferred.
        foreach($id in $ids){
            $idHazards=@(Get-CheckModsInteractionHazards $data @([string]$id))
            if($idHazards.Count){
                Write-Warning ("Deferring broken upstream --check-mods path for $id via: " + ($idHazards -join ', ') + ". Exact-source cata_test remains the runtime authority.")
                continue
            }
            $safe=($id -replace '[^A-Za-z0-9_.-]','_')
            $individual=Invoke-GameCheck $exe $GameRoot $data (Join-Path $Work ('validation/safe-'+$safe)) @([string]$id) $TimeoutSeconds
            if($individual.exit_code -ne 0 -or @($individual.errors).Count){throw "Selected mod validation failed for $id; report: $($individual.log)"}
        }
        return
    }
    # No interaction-bearing dependency is present: validate the whole selected
    # stack together through one synthetic dependency root.
    $result=Invoke-GameCheck $exe $GameRoot $data (Join-Path $Work 'validation/selected') @('suite_validation_stack') $TimeoutSeconds
    if($result.exit_code -ne 0 -or @($result.errors).Count){throw "Selected mod validation failed; report: $($result.log)"}
}
function Restore-Transaction([string]$Transaction,[switch]$Automatic){
    $path=Join-Path $Transaction 'journal.json';$journal=Read-Json $path
    if($journal.status -eq 'rolled-back'){return}
    # Validate the whole rollback before changing a single destination.
    foreach($entry in @($journal.entries)){
        if(-not $Automatic -and $entry.phase -eq 'installed' -and -not(Test-PayloadEqual $entry.destination $entry.files)){throw "Changed since installation: $($entry.destination). Refusing to overwrite newer/local files."}
    }
    $entries=@($journal.entries);[array]::Reverse($entries)
    foreach($entry in $entries){
        $oldExists=Test-Path -LiteralPath $entry.backup
        if($entry.phase -eq 'restored'){continue}
        if($entry.phase -in @('prepared','backing-up') -and -not $oldExists){continue}
        if($entry.phase -eq 'restoring'){
            # Destination was already removed before restoring started. If the
            # backup is gone, the preceding move completed before interruption.
            if($oldExists){
                if(Test-Path -LiteralPath $entry.destination){throw 'Rollback recovery destination occupied'}
                Move-Item -LiteralPath $entry.backup -Destination $entry.destination
            }
            $entry.phase='restored';Write-Json $path $journal;continue
        }
        if($entry.phase -in @('installing','installed') -and (Test-Path -LiteralPath $entry.destination)){Remove-Item -LiteralPath $entry.destination -Recurse -Force}
        $entry.phase='restoring';Write-Json $path $journal
        if($oldExists){
            if(Test-Path -LiteralPath $entry.destination){throw "Rollback destination occupied: $($entry.destination)"}
            Move-Item -LiteralPath $entry.backup -Destination $entry.destination
        }
        $entry.phase='restored';Write-Json $path $journal
    }
    if($journal.PSObject.Properties['state_path'] -and $journal.state_path){
        $records=@{}
        if(Test-Path -LiteralPath $journal.state_path){foreach($record in @((Read-Json $journal.state_path).packages)){$records[$record.id]=$record}}
        foreach($e in $journal.entries){$records.Remove($e.id)}
        foreach($record in @($journal.previous_records)){$records[$record.id]=$record}
        Write-Json $journal.state_path ([pscustomobject]@{schema=1;packages=@($records.Values)})
    }
    $journal.status='rolled-back';Write-Json $path $journal
}
function Install-Plan([object[]]$Plan,[string]$Transaction,[string]$StateFile=""){
    [IO.Directory]::CreateDirectory($Transaction) | Out-Null
    $entries=@();$i=0
    foreach($p in $Plan){
        $entries+= [pscustomobject]@{id=$p.package.id;destination=$p.destination;backup=(Join-Path $Transaction "backup/$i");staged=$p.staged;files=$p.package.files;version=$p.package.version;phase='prepared'};$i++
    }
    $prior=@()
    if($StateFile -and (Test-Path -LiteralPath $StateFile)){$selected=@($entries | ForEach-Object {$_.id});$prior=@((Read-Json $StateFile).packages | Where-Object {$selected -contains $_.id})}
    $journal=[pscustomobject]@{schema=1;status='pending';entries=$entries;state_path=$StateFile;previous_records=$prior};$path=Join-Path $Transaction 'journal.json';Write-Json $path $journal
    try{
        foreach($e in $journal.entries){
            [IO.Directory]::CreateDirectory((Split-Path $e.destination -Parent)) | Out-Null
            [IO.Directory]::CreateDirectory((Split-Path $e.backup -Parent)) | Out-Null
            $e.phase='backing-up';Write-Json $path $journal
            if(Test-Path -LiteralPath $e.destination){Move-Item -LiteralPath $e.destination -Destination $e.backup}
            $e.phase='installing';Write-Json $path $journal
            Copy-Item -LiteralPath $e.staged -Destination $e.destination -Recurse
            if(-not(Test-PayloadEqual $e.destination $e.files)){throw "Post-install verification failed: $($e.id)"}
            $e.phase='installed';Write-Json $path $journal
        }
        $journal.status='committed';Write-Json $path $journal
    }catch{
        $original=$_
        try{Restore-Transaction $Transaction -Automatic}catch{throw "Install failed: $original. Rollback needs recovery: $_. Journal: $path"}
        throw $original
    }
}
Export-ModuleMember -Function *
