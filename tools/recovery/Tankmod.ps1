param([string]$ModRoot)
$ErrorActionPreference='Stop'
$mod=$ModRoot
function Load-JsonArray {
    param([Parameter(Mandatory=$true)][string] $Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $obj = ConvertFrom-Json -InputObject $raw
    if ($obj -is [System.Array]) { return @($obj) }
    return @($obj)
}

function Save-JsonUtf8NoBom {
    param(
        [Parameter(Mandatory=$true)] $Object,
        [Parameter(Mandatory=$true)][string] $Path
    )

    # -InputObject is intentional: preserve the top-level array.
    $json = ConvertTo-Json -InputObject $Object -Depth 100

    [System.IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Remove-PropertyIfPresent {
    param(
        [Parameter(Mandatory=$true)] $Object,
        [Parameter(Mandatory=$true)][string] $Name
    )
    if ($null -ne $Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

# ------------------------------------------------------------------
# 1) modinfo: enable the archived mod for current DDA.
# ------------------------------------------------------------------
$modinfoPath = Join-Path $mod 'modinfo.json'
$modinfo = Load-JsonArray $modinfoPath

$modInfoHits = 0
foreach ($entry in $modinfo) {
    if ($entry.type -eq 'MOD_INFO' -and $entry.id -eq 'Tankmod_Revived') {
        $modInfoHits++
        $entry | Add-Member -NotePropertyName 'obsolete' -NotePropertyValue $false -Force
        $entry | Add-Member -NotePropertyName 'version' -NotePropertyValue 'DDA 2026-09-23 compatibility Fix4' -Force
    }
}
if ($modInfoHits -ne 1) {
    throw "Expected 1 Tankmod MOD_INFO, found $modInfoHits"
}
Save-JsonUtf8NoBom $modinfo $modinfoPath

# ------------------------------------------------------------------
# 2) Remove only the obsolete top-level self-copy of base item group "military".
# IMPORTANT: do NOT recursively rewrite nested item-group arrays.
# ------------------------------------------------------------------
$itemGroupsPath = Join-Path $mod 'item_groups.json'
$itemGroups = Load-JsonArray $itemGroupsPath

$legacyMilitary = @(
    $itemGroups | Where-Object {
        $_.type -eq 'item_group' -and
        $_.id -eq 'military' -and
        $_.'copy-from' -eq 'military'
    }
).Count

$itemGroups = @(
    $itemGroups | Where-Object {
        -not (
            $_.type -eq 'item_group' -and
            $_.id -eq 'military' -and
            $_.'copy-from' -eq 'military'
        )
    }
)

Save-JsonUtf8NoBom $itemGroups $itemGroupsPath
Write-Host "Removed obsolete military item-group patch: $legacyMilitary"

# ------------------------------------------------------------------
# 3) Convert the two Tankmod primers from obsolete AMMO-components
# into ordinary stackable crafting components.
# ------------------------------------------------------------------
$primerIds = @('electric_primer_120mm', 'primer_155mm')
$itemsPath = Join-Path $mod 'items.json'
$items = Load-JsonArray $itemsPath

$primerPatched = 0
foreach ($item in $items) {
    if ($primerIds -contains $item.id) {
        $primerPatched++

        Remove-PropertyIfPresent $item 'subtypes'
        Remove-PropertyIfPresent $item 'ammo_type'
        Remove-PropertyIfPresent $item 'count'
        Remove-PropertyIfPresent $item 'effects'

        $item | Add-Member -NotePropertyName 'stackable' -NotePropertyValue $true -Force
        $item | Add-Member -NotePropertyName 'explode_in_fire' -NotePropertyValue $true -Force
        $item | Add-Member -NotePropertyName 'explosion' -NotePropertyValue ([pscustomobject][ordered]@{
            power = 50
        }) -Force
    }
}

if ($primerPatched -ne 2) {
    throw "Expected 2 Tankmod primer items, patched $primerPatched"
}
Save-JsonUtf8NoBom $items $itemsPath
Write-Host "Modernized primer items: $primerPatched / 2"

# ------------------------------------------------------------------
# 4) Primer recipes produce one discrete item rather than one AMMO charge.
# ------------------------------------------------------------------
$recipesPath = Join-Path $mod 'recipes.json'
$recipes = Load-JsonArray $recipesPath

$primerRecipes = 0
foreach ($recipe in $recipes) {
    if ($primerIds -contains $recipe.result) {
        $primerRecipes++
        Remove-PropertyIfPresent $recipe 'charges'
    }
}

if ($primerRecipes -ne 2) {
    throw "Expected 2 primer recipes, found $primerRecipes"
}
Save-JsonUtf8NoBom $recipes $recipesPath
Write-Host "Modernized primer recipes: $primerRecipes / 2"

# ------------------------------------------------------------------
# 5) ammo_types.json stays pristine. There is NO temporary primer ammotype.
# ------------------------------------------------------------------
$ammoTypesPath = Join-Path $mod 'ammo_types.json'
$ammoTypes = Load-JsonArray $ammoTypesPath
$ammoTypes = @(
    $ammoTypes | Where-Object { $_.id -ne 'tankmod_primer_component' }
)
Save-JsonUtf8NoBom $ammoTypes $ammoTypesPath

# ------------------------------------------------------------------
# 6) Structural checks aimed specifically at the Fix3 failure.
# ------------------------------------------------------------------
$checkGroups = Load-JsonArray $itemGroupsPath
$gunsLauncher = @(
    $checkGroups | Where-Object { $_.id -eq 'guns_launcher_milspec' }
)

if ($gunsLauncher.Count -ne 1) {
    throw "Expected exactly one guns_launcher_milspec item group, found $($gunsLauncher.Count)"
}

$extendItems = $gunsLauncher[0].extend.items
$extendItemsIsArray = ($extendItems -is [System.Array])

$checkItems = Load-JsonArray $itemsPath
$genericPrimerOk = @(
    $checkItems | Where-Object {
        $primerIds -contains $_.id -and
        $null -eq $_.PSObject.Properties['ammo_type'] -and
        $null -eq $_.PSObject.Properties['count'] -and
        $_.stackable -eq $true
    }
).Count

Write-Host ''
Write-Host 'Local verification:'
Write-Host "  guns_launcher_milspec.extend.items is array: $extendItemsIsArray"
Write-Host "  Generic primers:                          $genericPrimerOk / 2"

if (-not $extendItemsIsArray) {
    throw 'item_groups.json still has a collapsed one-element array.'
}
if ($genericPrimerOk -ne 2) {
    throw 'Primer conversion verification failed.'
}

