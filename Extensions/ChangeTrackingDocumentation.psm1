
<#
.SYNOPSIS
  Documentation generator for Intune Change Tracking exports.
.DESCRIPTION
  Produces Markdown documentation from the files created by the ChangeTracking module:
  - _docs/index.md: Root overview of all object types
  - _docs/by-type/<ObjectType>.md: Overview per object type
  - _docs/objects/<ObjectType>/<Id>.md: Detailed page per object

  Style system:
    - Enterprise  : formal, numbered sections, no collapsible sections, no icons
    - Rich        : readable enhancements, collapsible sections for large blocks, minimal ASCII icons (no emojis)

  All content is generated offline from ExportRoot based on raw.json, meta.json, and flat.json.
#>

# -------------------------------
# Style management
# -------------------------------
$Script:DocumentationStyles = @{
  Enterprise = @{ Collapsible=$false; UseIcons=$false; Numbered=$true;  WarningStyle='blockquote'; Nav='breadcrumb' }
  Rich       = @{ Collapsible=$true;  UseIcons=$true;  Numbered=$false; WarningStyle='admonition'; Nav='breadcrumb' }
}

$Script:DocStyle = 'Enterprise'

function Set-IntuneDocumentationStyle {
  [CmdletBinding()]
  param([Parameter(Mandatory)][ValidateSet('Enterprise','Rich')] [string]$Style)
  $Script:DocStyle = $Style
}

function Get-IntuneDocumentationStyle {
  [CmdletBinding()] param()
  return $Script:DocStyle
}

# -------------------------------
# Public entry points
# -------------------------------
function New-IntuneDocumentation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ExportRoot,
    [ValidateSet('Enterprise','Rich')] [string]$Style,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  if ($PSBoundParameters.ContainsKey('Style')) { Set-IntuneDocumentationStyle -Style $Style }
  $styleProfile = $Script:DocumentationStyles[$Script:DocStyle]

  $docsRoot = Join-Path $ExportRoot '_docs'
  $byType   = Join-Path $docsRoot 'by-type'
  $objects  = Join-Path $docsRoot 'objects'
  foreach ($d in @($docsRoot,$byType,$objects)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

  $types = Get-IntuneObjectTypes -ExportRoot $ExportRoot
  $typeSummaries = @()

  foreach ($t in $types) {
    $list = Get-IntuneObjectList -ExportRoot $ExportRoot -ObjectType $t
    if (-not $list) { continue }

    foreach ($o in $list) {
      New-IntuneDocumentationForObject -ExportRoot $ExportRoot -ObjectType $t -Id $o.id -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat | Out-Null
    }

    $typeDoc = Join-Path $byType ("{0}.md" -f $t)
    Write-IntuneObjectTypeOverview -ExportRoot $ExportRoot -ObjectType $t -List $list -Destination $typeDoc -Style $Script:DocStyle

    $last = ($list | Where-Object { $_.lastModified } | Sort-Object lastModified -Descending | Select-Object -First 1).lastModified
    $typeSummaries += [PSCustomObject]@{ ObjectType=$t; Count=$list.Count; LastModified=$last; Link=(Join-Path 'by-type' ("{0}.md" -f $t)) }
  }

  Write-IntuneRootIndex -ExportRoot $ExportRoot -Summaries $typeSummaries -Destination (Join-Path $docsRoot 'index.md') -Style $Script:DocStyle
}

function New-IntuneDocumentationForObject {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ExportRoot,
    [Parameter(Mandatory)] [string]$ObjectType,
    [Parameter(Mandatory)] [string]$Id,
    [ValidateSet('Enterprise','Rich')] [string]$Style,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  if ($PSBoundParameters.ContainsKey('Style')) { Set-IntuneDocumentationStyle -Style $Style }
  $styleProfile = $Script:DocumentationStyles[$Script:DocStyle]

  $objFolder = Join-Path (Join-Path $ExportRoot $ObjectType) $Id
  if (-not (Test-Path $objFolder)) { throw "Object folder not found: $objFolder" }

  $metaPath = Join-Path $objFolder 'meta.json'
  $rawPath  = Join-Path $objFolder 'raw.json'
  $flatPath = Join-Path $objFolder 'flat.json'

  $meta = if (Test-Path $metaPath) { Get-Content -Raw -Path $metaPath | ConvertFrom-Json } else { $null }
  $raw  = if (Test-Path $rawPath)  { Get-Content -Raw -Path $rawPath  | ConvertFrom-Json } else { $null }
  $flat = if (Test-Path $flatPath) { Get-Content -Raw -Path $flatPath | ConvertFrom-Json } else { $null }

  $docsRoot = Join-Path $ExportRoot '_docs'
  $objDocs  = Join-Path (Join-Path $docsRoot 'objects') $ObjectType
  if (-not (Test-Path $objDocs)) { New-Item -ItemType Directory -Force -Path $objDocs | Out-Null }
  $dest = Join-Path $objDocs ("{0}.md" -f $Id)

  Write-IntuneObjectDetailDocument -ExportRoot $ExportRoot -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Destination $dest -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat

  return $dest
}


# -------------------------------
# Data access helpers
# -------------------------------
function Get-IntuneObjectTypes {
  param([Parameter(Mandatory)][string]$ExportRoot)
  Get-ChildItem -Path $ExportRoot -Directory |
    Where-Object { $_.Name -notmatch '^_' } |
    Select-Object -ExpandProperty Name
}

function Get-IntuneObjectList {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType
  )
  $typePath = Join-Path $ExportRoot $ObjectType
  if (-not (Test-Path $typePath)) { return @() }

  Get-ChildItem -Path $typePath -Directory | ForEach-Object {
    $id = $_.Name
    $metaPath = Join-Path $_.FullName 'meta.json'
    $rawPath  = Join-Path $_.FullName 'raw.json'
    $flatPath = Join-Path $_.FullName 'flat.json'

    $meta = if (Test-Path $metaPath) { Get-Content -Raw -Path $metaPath | ConvertFrom-Json } else { $null }
    $raw  = if (Test-Path $rawPath)  { Get-Content -Raw -Path $rawPath  | ConvertFrom-Json } else { $null }
    $flat = if (Test-Path $flatPath) { Get-Content -Raw -Path $flatPath | ConvertFrom-Json } else { $null }

    [PSCustomObject]@{
      id = $id
      objectType = $ObjectType
      displayName = ($meta.displayName, $raw.name, $raw.displayName | Where-Object { $_ } | Select-Object -First 1)
      lastModified = $meta.lastIntuneModified
      description = $raw.description
      assignments = $meta.assignmentsSummary
      flat = $flat
      meta = $meta
      raw  = $raw
    }
  }
}

# -------------------------------
# Rendering helpers
# -------------------------------
function Out-Md {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Format-MdTable {
  param([array]$Rows,[string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) { return "(no data)" }
  $sb = New-Object System.Text.StringBuilder
  $headerLine = ($Headers -join ' | ')
  $sepLine = (($Headers | ForEach-Object { '---' }) -join ' | ')
  [void]$sb.AppendLine("| $headerLine |")
  [void]$sb.AppendLine("| $sepLine |")
  foreach ($r in $Rows) {
    $line = @()
    foreach ($h in $Headers) { $line += ($r.$h -replace '\r?\n',' ') }
    [void]$sb.AppendLine("| " + ($line -join ' | ') + " |")
  }
  return $sb.ToString()
}

function Render-Breadcrumb {
  param([string]$ExportRoot,[string]$RelPath,[string]$Title)
  return "**Path:** `_docs/$RelPath`  \n**Title:** $Title"
}

function Render-WarningBlock {
  param([string]$Message,[string]$StyleName)
  if ($StyleName -eq 'admonition') {
    return "> **WARNING**: $Message"
  } else {
    return "> WARNING: $Message"
  }
}

function Render-Collapsible {
  param([string]$Summary,[string]$Body,[bool]$Enabled)
  if (-not $Enabled) { return ("### $Summary`n`n" + $Body) }
  $escapedSummary = ($Summary -replace '"','\"')
  return @"
<details>
<summary>$escapedSummary</summary>

$Body

</details>
"@
}

# -------------------------------
# Writers
# -------------------------------
function Write-IntuneRootIndex {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][array]$Summaries,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style
  )
  $styleProfile = $Script:DocumentationStyles[$Style]

  $rows = @()
  foreach ($s in ($Summaries | Sort-Object ObjectType)) {
    $rows += [PSCustomObject]@{
      'Object type'   = $s.ObjectType
      'Count'         = $s.Count
      'Last modified' = if ($s.LastModified) { (Get-Date $s.LastModified).ToString('yyyy-MM-dd') } else { '' }
      'Link'          = "[$($s.ObjectType)](by-type/$($s.ObjectType).md)"
    }
  }
  $table = Format-MdTable -Rows $rows -Headers @('Object type','Count','Last modified','Link')

  $title = if ($styleProfile.Numbered) { '# 1. Intune Export - Overview' } else { '# Intune Export - Overview' }
  $body = @()
  $body += $title
  $body += ""
  $body += "This documentation was generated from ChangeTracking outputs. It summarizes all object types and links to detailed pages."
  $body += ""
  $body += "## Object Types"
  $body += $table

  Out-Md -Path $Destination -Content ($body -join "`n")
}


function Write-IntuneObjectTypeOverview {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][array]$List,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style
  )
  $styleProfile = $Script:DocumentationStyles[$Style]

  $rows = @()
  foreach ($o in ($List | Sort-Object displayName)) {
    $assignCount = if ($o.assignments) { $o.assignments.Count } else { 0 }
    $link = "../objects/$ObjectType/$($o.id).md"
    $desc = if ($o.description) { if ($o.description.Length -gt 120) { $o.description.Substring(0,117) + '...' } else { $o.description } } else { '' }
    $rows += [PSCustomObject]@{
      'Name'          = ($o.displayName)
      'ID'            = $o.id
      'Description'   = $desc
      'Last modified' = if ($o.lastModified) { (Get-Date $o.lastModified).ToString('yyyy-MM-dd') } else { '' }
      'Assignments'   = $assignCount
      'Link'          = "[open]($link)"
    }
  }
  $table = Format-MdTable -Rows $rows -Headers @('Name','ID','Description','Last modified','Assignments','Link')

  $title = if ($styleProfile.Numbered) { "# 2. $ObjectType - Overview" } else { "# $ObjectType - Overview" }
  $body = @()
  $body += $title
  $body += ""
  $body += $table

  Out-Md -Path $Destination -Content ($body -join "`n")
}

function Write-IntuneObjectDetailDocument {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$Id,
    [object]$Raw,
    [object]$Meta,
    [object]$Flat,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $name  = if ($Meta.displayName) { $Meta.displayName } elseif ($Raw.name) { $Raw.name } else { $Id }
  $last  = if ($Meta.lastIntuneModified) { (Get-Date $Meta.lastIntuneModified).ToString('yyyy-MM-dd HH:mm') } else { '' }

  $headerTitle = if ($styleProfile.Numbered) { "# 3. $name" } else { "# $name" }
  $hdr = @()
  $hdr += $headerTitle
  $hdr += "**ID:** $Id  "
  $hdr += "**Type:** $ObjectType  "
  if ($last) { $hdr += "**Last Modified:** $last  " }

  if ($Raw.description) {
    $hdr += ""
    $hdr += "## Description"
    $hdr += ($Raw.description -replace '\r?\n','  \n')
  }

  # Assignments
  $assignRows = @()
  foreach ($a in ($Meta.assignmentsSummary)) {
    $assignRows += [PSCustomObject]@{
      'Target' = 'Group'
      'Name'   = ($a.groupDisplayName)
      'Id'     = ($a.groupId)
      'Filter' = if ($a.filterId) { $a.filterId } else { '' }
      'Type'   = if ($a.filterType) { $a.filterType } else { '' }
    }
  }
  $assignTable = if ($assignRows.Count -gt 0) { Format-MdTable -Rows $assignRows -Headers @('Target','Name','Id','Filter','Type') } else { '(none)' }

  $assignSection = @()
  $assignSection += "## Assignments"
  $assignSection += $assignTable

  # Settings table from flat
  $flatRows = @()
  foreach ($s in ($Flat)) {
    $val = if ($s.value -is [System.Collections.IDictionary]) { ($s.value | ConvertTo-Json -Depth 20) } elseif ($s.value -is [System.Collections.IList]) { ($s.value -join ', ') } else { "$($s.value)" }
    $flatRows += [PSCustomObject]@{
      'Path'        = $s.path
      'Value'       = $val
      'Friendly'    = if ($s.friendlyValue) { $s.friendlyValue } else { '' }
      'CSP'         = if ($s.cspEquivalent) { $s.cspEquivalent } else { '' }
      'Description' = if ($s.scDesc) { $s.scDesc } else { '' }
      'Risk'        = if ($s.risk) { $s.risk } else { '' }
    }
  }
  $flatTable = if ($flatRows.Count -gt 0) { Format-MdTable -Rows $flatRows -Headers @('Path','Value','Friendly','CSP','Description','Risk') } else { '(no flattened settings found)' }

  $flatSection = @()
  $flatSection += "## Settings"
  $flatSection += $flatTable

  # Diagnostics
  $diag = @()
  $diag += "## Diagnostics"
  if ($Meta.diagnostics.assignments.missingGroups.Count -gt 0) { $diag += (Render-WarningBlock -Message ("Missing groups: " + ($Meta.diagnostics.assignments.missingGroups -join ', ')) -StyleName $styleProfile.WarningStyle) }
  if ($Meta.diagnostics.assignments.nonSecurityGroups.Count -gt 0) { $diag += (Render-WarningBlock -Message ("Non-security groups: " + ($Meta.diagnostics.assignments.nonSecurityGroups -join ', ')) -StyleName $styleProfile.WarningStyle) }
  if ($Meta.diagnostics.assignments.filtersPresent) { $diag += "> Note: Assignments include filters." }
  if ($diag.Count -eq 1) { $diag += "(no diagnostics)" }

  # Optional raw/meta/flat dumps (collapsible in Rich style)
  $dumps = @()

  if ($IncludeRaw) {
    if ($Raw) { $json = $Raw | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
    $dumps += (Render-Collapsible -Summary 'raw.json' -Body $body -Enabled:$styleProfile.Collapsible)
  }

  if ($IncludeMeta) {
    if ($Meta) { $json = $Meta | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
    $dumps += (Render-Collapsible -Summary 'meta.json' -Body $body -Enabled:$styleProfile.Collapsible)
  }

  if ($IncludeFlat) {
    if ($Flat) { $json = $Flat | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
    $dumps += (Render-Collapsible -Summary 'flat.json' -Body $body -Enabled:$styleProfile.Collapsible)
  }

  $content = @()
  $content += ($hdr -join "`n")
  $content += ""
  $content += ($assignSection -join "`n")
  $content += ""
  $content += ($flatSection -join "`n")
  $content += ""
  $content += ($diag -join "`n")
  if ($dumps.Count -gt 0) { $content += ""; $content += ($dumps -join "`n") }

  Out-Md -Path $Destination -Content ($content -join "`n")
}


Export-ModuleMember -Function New-IntuneDocumentation,New-IntuneDocumentationForObject,Set-IntuneDocumentationStyle,Get-IntuneDocumentationStyle
