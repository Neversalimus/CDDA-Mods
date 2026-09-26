#requires -Version 5.1
[CmdletBinding()]
param([string]$Repository='Neversalimus/CDDA-Mods',[switch]$Public,[switch]$Release)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if($Repository -ne 'Neversalimus/CDDA-Mods'){throw 'This prepared project is configured for Neversalimus/CDDA-Mods. Update catalog and installer endpoints before choosing another repository.'}
foreach($cmd in @('git','gh')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command missing: $cmd. Install Git for Windows / GitHub CLI and rerun. No token needs to be pasted into this script."}}
Push-Location $root
try{
    & gh auth status
    if($LASTEXITCODE -ne 0){& gh auth login --hostname github.com --git-protocol https --web;if($LASTEXITCODE -ne 0){throw 'GitHub login was not completed'}}
    $login=(& gh api user --jq .login).Trim();if($LASTEXITCODE -ne 0 -or $login -ne 'Neversalimus'){throw "Wrong GitHub account: $login"}
    # Validate file hashes from the delivered reviewed snapshot before first publish.
    $lock=Get-Content (Join-Path $root 'SOURCE_SHA256.json') -Raw | ConvertFrom-Json
    foreach($property in $lock.PSObject.Properties){
        $f=Join-Path $root $property.Name
        if(-not(Test-Path -LiteralPath $f) -or (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value){throw "Snapshot changed: $($property.Name). Review/validate the changes before publishing."}
    }
    if(-not(Test-Path (Join-Path $root '.git'))){
        & git init -b main;if($LASTEXITCODE){throw 'Git init failed'}
        & git add .;if($LASTEXITCODE){throw 'Git add failed'}
        # Command-local identity does not change the user's global Git configuration.
        & git -c user.name=Neversalimus -c user.email=23374190+Neversalimus@users.noreply.github.com commit -m 'Import current CDDA mods and independent update infrastructure'
        if($LASTEXITCODE){throw 'Git commit failed'}
    }
    $ErrorActionPreference='Continue'
    $existing=& gh repo view $Repository --json nameWithOwner 2>$null
    $repoExit=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($repoExit -eq 0){
        $ErrorActionPreference='Continue'
        $remote=& git remote get-url origin 2>$null
        $remoteExit=$LASTEXITCODE
        $ErrorActionPreference='Stop'
        if($remoteExit -ne 0 -or $remote -notin @("https://github.com/$Repository.git","https://github.com/$Repository")){throw 'Repository already exists. Refusing to overwrite it. Review its contents and connect this checkout deliberately.'}
    }else{
        $visibility=if($Public){'--public'}else{'--private'}
        & gh repo create $Repository $visibility --description 'Independently versioned CDDA mods, shared installer and compatibility workflow' --source . --remote origin
        if($LASTEXITCODE){throw 'GitHub repository creation failed'}
    }
    & git push -u origin main;if($LASTEXITCODE){throw 'Push failed; no force-push was attempted'}
    if($Release){
        $catalog=Get-Content catalog/repository.json -Raw | ConvertFrom-Json
        & git tag "v$($catalog.suite_version)";if($LASTEXITCODE){throw 'Tag already exists or could not be created'}
        & git push origin "v$($catalog.suite_version)";if($LASTEXITCODE){throw 'Tag push failed'}
    }
    Write-Host "Repository uploaded: https://github.com/$Repository" -ForegroundColor Green
    Write-Host 'Check Actions. Native DLLs are built as separate candidates; no engine compile runs on player PCs.'
}finally{Pop-Location}
