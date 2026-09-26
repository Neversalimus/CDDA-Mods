$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../installer/ModSuite.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('CDDA-Mods-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$script:passed=0
function Check($ok,[string]$label){if(-not $ok){throw "FAIL: $label"};$script:passed++;Write-Host "PASS: $label"}
function Reject([scriptblock]$code,[string]$label){$failed=$false;try{& $code | Out-Null}catch{$failed=$true;Write-Host ('EXPECTED ERROR: '+$_.Exception.Message)};Check $failed $label}
function FileHash($path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
try{
    foreach($name in @('../evil','/absolute','C:/evil','a\b','a/../b','NUL.txt','a/file.','a//b')){Reject {Join-Safe $root $name} "Path blocked: $name"}
    $safe=Join-Safe $root 'normal/data.json';Check ($safe.StartsWith($root)) 'Normal path accepted'
    $catalog=Read-Json (Join-Path $PSScriptRoot '../dist/catalog.json')
    $plan=@(Resolve-Packages $catalog @('secronom_plus') 'e262adb299a7613b4aedc5f12c08fe0413c56a84' -AllowUntested)
    Check ($plan.Count -eq 2 -and $plan[0].id -eq 'secronom' -and $plan[1].id -eq 'secronom_plus') 'Dependency ordered before expansion'
    Reject {Resolve-Packages $catalog @('axiom_7') 'unknown'} 'Unknown game commit blocked'
    Reject {Resolve-Packages $catalog @('missing') 'e262adb299a7613b4aedc5f12c08fe0413c56a84' -AllowUntested} 'Unknown component blocked'
    Reject {Resolve-Packages $catalog @('survivor_progression') 'e262adb299a7613b4aedc5f12c08fe0413c56a84' -AllowUntested} 'Source-only native mod cannot silently downgrade'
    $pkg=$catalog.packages | Where-Object id -eq 'axiom_7'
    $archive=Join-Path $PSScriptRoot ('../dist/'+$pkg.archive)
    $payload=Expand-VerifiedPackage $archive (Join-Path $root 'unpack') $pkg
    Check (Test-PayloadEqual $payload $pkg.files) 'Archive and every payload hash verified'
    $bad=Join-Path $root 'bad.zip';[IO.File]::WriteAllText($bad,'broken')
    Reject {Expand-VerifiedPackage $bad (Join-Path $root 'bad-out') $pkg} 'Corrupt archive blocked'
    # Crafted zip traversal with matching outer checksum must still fail.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath=Join-Path $root 'traversal.zip';$z=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    $e=$z.CreateEntry('../outside.txt');$w=New-Object IO.StreamWriter($e.Open());$w.Write('no');$w.Dispose();$z.Dispose()
    $attack=[pscustomobject]@{sha256=(FileHash $zipPath);id='attack'}
    Reject {Expand-VerifiedPackage $zipPath (Join-Path $root 'attack') $attack} 'Traversal blocked even with valid ZIP hash'
    Check (-not(Test-Path (Join-Path $root 'outside.txt'))) 'Traversal made no outside file'
    # Transaction: first destination succeeds, second fails; old first is restored.
    $dest=Join-Path $root 'live';[IO.Directory]::CreateDirectory($dest)|Out-Null;[IO.File]::WriteAllText((Join-Path $dest 'old.txt'),'old')
    $one=[pscustomobject]@{package=$pkg;staged=$payload;destination=$dest}
    $two=[pscustomobject]@{package=$pkg;staged=(Join-Path $root 'missing-stage');destination=(Join-Path $root 'live-two')}
    $tx=Join-Path $root 'rollback-test'
    Reject {Install-Plan @($one,$two) $tx} 'Failure triggers group rollback'
    Check ((Get-Content (Join-Path $dest 'old.txt') -Raw) -eq 'old') 'Previous files restored after partial install'
    Check (-not(Test-Path (Join-Path $dest 'modinfo.json'))) 'Failed install left no new files'
    Check ((Read-Json (Join-Path $tx 'journal.json')).status -eq 'rolled-back') 'Rollback journal committed'
    $tx2=Join-Path $root 'success';Install-Plan @($one) $tx2
    Check (Test-PayloadEqual $dest $pkg.files) 'Successful installation matches expected payload'
    [IO.File]::WriteAllText((Join-Path $dest 'local-edit.txt'),'keep')
    Reject {Restore-Transaction $tx2} 'Rollback refuses to overwrite local/newer edits'
    Remove-Item -LiteralPath (Join-Path $dest 'local-edit.txt')
    Restore-Transaction $tx2
    Check ((Get-Content (Join-Path $dest 'old.txt') -Raw) -eq 'old') 'Explicit rollback restores previous installation'
    $state=Join-Path $root 'installed.json'
    Write-Json $state @{schema=1;packages=@(@{id=$pkg.id;version='previous'},@{id='unrelated';version='keep'})}
    $tx3=Join-Path $root 'receipt';Install-Plan @($one) $tx3 $state
    Write-Json $state @{schema=1;packages=@(@{id=$pkg.id;version=$pkg.version},@{id='unrelated';version='newer'})}
    Restore-Transaction $tx3
    $records=@((Read-Json $state).packages)
    Check (($records | Where-Object id -eq $pkg.id).version -eq 'previous') 'Rollback restores previous selected receipt'
    Check (($records | Where-Object id -eq 'unrelated').version -eq 'newer') 'Rollback preserves unrelated newer receipt'
    Restore-Transaction $tx3
    Check (Test-Path (Join-Path $dest 'old.txt')) 'Repeated rollback is harmless'
    # Interrupted after backup move but before the restored phase was saved.
    $tx4=Join-Path $root 'resume';Install-Plan @($one) $tx4
    $j=Read-Json (Join-Path $tx4 'journal.json');$j.status='pending';$j.entries[0].phase='restoring'
    Remove-Item -LiteralPath $dest -Recurse -Force
    Move-Item -LiteralPath $j.entries[0].backup -Destination $dest
    Write-Json (Join-Path $tx4 'journal.json') $j
    Restore-Transaction $tx4
    Check (Test-Path (Join-Path $dest 'old.txt')) 'Interrupted rollback preserves already restored backup'
    $game=Join-Path $root 'game';[IO.Directory]::CreateDirectory((Join-Path $game 'data/json')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $game 'cataclysm.exe'),'fixture')
    Check (Test-GameRoot $game) 'Single executable game detection works under strict mode'
    # Duplicate mod IDs must not be silently selected.
    $dup=Join-Path $root 'duplicate';[IO.Directory]::CreateDirectory($dup)|Out-Null
    foreach($d in @('one','two')){[IO.Directory]::CreateDirectory((Join-Path $dup $d))|Out-Null;Copy-Item (Join-Path $payload 'modinfo.json') (Join-Path $dup "$d/modinfo.json")}
    Check (@(Get-ModDirectories @($dup) @('axiom_7')).Count -eq 2) 'Duplicate installations detected'
    Write-Host "$script:passed installer assertions passed."
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
