
<#
.SYNOPSIS
  Documentation generator for Intune Change Tracking exports (Markdown and HTML).
.DESCRIPTION
  Produces documentation from ChangeTracking outputs (raw.json, meta.json, flat.json):
  - _docs/index.(md|html): Root overview of all object types
  - _docs/by-type/<ObjectType>.(md|html): Overview per object type
  - _docs/objects/<ObjectType>/<Name>.(md|html): Detailed page per object (uses display name for file name)

  Style system:
    - Enterprise : formal, numbered sections, no collapsible sections, no icons
    - Rich       : readability enhancements, collapsible sections for large blocks

  Output formats: Markdown, Html, or Both.

  Notes:
  - Uses only ASCII hyphens '-' in all titles and text literals.
  - PS5-safe: no ternary operators; here-strings aligned to column 1; no emoji.
#>

# -------------------------------
# Style management
# -------------------------------
$Script:DocumentationStyles = @{
  Enterprise = @{ Collapsible=$false; Numbered=$true }
  Rich       = @{ Collapsible=$true;  Numbered=$false }
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
  <#
    .SYNOPSIS  Generates documentation pages from an ExportRoot in Markdown and/or HTML.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ExportRoot,
    [ValidateSet('Enterprise','Rich')] [string]$Style = 'Enterprise',
    [ValidateSet('Markdown','Html','Both')] [string]$Output = 'Markdown',
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  Set-IntuneDocumentationStyle -Style $Style
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

    # write per-object docs (Markdown and/or HTML)
    foreach ($o in $list) {
      New-IntuneDocumentationForObject -ExportRoot $ExportRoot -ObjectType $t -Id $o.id -Style $Script:DocStyle -Output $Output -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat | Out-Null
    }

    # write type overview
    $typeBase = Join-Path $byType $t
    if ($Output -in @('Markdown','Both')) { Write-IntuneObjectTypeOverview -ExportRoot $ExportRoot -ObjectType $t -List $list -Destination ("{0}.md" -f $typeBase) -Style $Script:DocStyle -Format 'Markdown' }
    if ($Output -in @('Html','Both'))      { Write-IntuneObjectTypeOverview -ExportRoot $ExportRoot -ObjectType $t -List $list -Destination ("{0}.html" -f $typeBase) -Style $Script:DocStyle -Format 'Html' }

    # summary for root
    $last = ($list | Where-Object { $_.lastModified } | Sort-Object lastModified -Descending | Select-Object -First 1).lastModified
    $typeSummaries += [PSCustomObject]@{ ObjectType=$t; Count=$list.Count; LastModified=$last; LinkBase=(Join-Path 'by-type' $t) }
  }

  # write root index
  $rootBase = Join-Path $docsRoot 'index'
  if ($Output -in @('Markdown','Both')) { Write-IntuneRootIndex -ExportRoot $ExportRoot -Summaries $typeSummaries -Destination ("{0}.md" -f $rootBase) -Style $Script:DocStyle -Format 'Markdown' }
  if ($Output -in @('Html','Both'))      { Write-IntuneRootIndex -ExportRoot $ExportRoot -Summaries $typeSummaries -Destination ("{0}.html" -f $rootBase) -Style $Script:DocStyle -Format 'Html' }
}

function New-IntuneDocumentationForObject {
  <# .SYNOPSIS  Generates a detailed documentation page for a single object in Markdown and/or HTML. #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ExportRoot,
    [Parameter(Mandatory)] [string]$ObjectType,
    [Parameter(Mandatory)] [string]$Id,
    [ValidateSet('Enterprise','Rich')] [string]$Style = 'Enterprise',
    [ValidateSet('Markdown','Html','Both')] [string]$Output = 'Markdown',
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  Set-IntuneDocumentationStyle -Style $Style
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

  # Use profile display name for the file name (human friendly)
  $displayName = ($meta.displayName, $raw.name, $raw.displayName, $Id | Where-Object { $_ } | Select-Object -First 1)
  $safeName = Get-SafeFileName -Name $displayName
  $destBase = Join-Path $objDocs $safeName

  if ($Output -in @('Markdown','Both')) { Write-IntuneObjectDetailDocument -ExportRoot $ExportRoot -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Destination ("{0}.md" -f $destBase) -Style $Script:DocStyle -Format 'Markdown' -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat }
  if ($Output -in @('Html','Both'))      { Write-IntuneObjectDetailDocument -ExportRoot $ExportRoot -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Destination ("{0}.html" -f $destBase) -Style $Script:DocStyle -Format 'Html' -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat }

  return $destBase
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
# File name utilities
# -------------------------------
function Get-SafeFileName {
  param([Parameter(Mandatory)][string]$Name,[int]$MaxLength=120)
  $safe = $Name
  $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
  $regex = "[" + [Regex]::Escape($invalid) + "]"
  $safe = [Regex]::Replace($safe, $regex, '_')
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { $safe = $safe.Substring(0,$MaxLength) }
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unnamed' }
  return $safe
}

# -------------------------------
# Rendering helpers (Markdown and HTML)
# -------------------------------
function Out-Md {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Out-Html {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Body,[string]$Title='Intune Documentation')
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$doc = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>$Title</title>
<style>
 body{font-family:Segoe UI,SegoeUI,Arial,sans-serif;line-height:1.4;margin:24px;}
 h1,h2,h3{margin-top:1.2em;}
 table{border-collapse:collapse;width:100%;}
 th,td{border:1px solid #ddd;padding:6px 8px;vertical-align:top;}
 th{background:#f4f4f4;text-align:left;}
 code,pre{font-family:Consolas,Monaco,monospace;font-size:12px;}
 details{margin:8px 0;}
 summary{cursor:pointer;font-weight:600;}
 .note{padding:8px 10px;background:#fffbe6;border:1px solid #ffe58f;}
 .warn{padding:8px 10px;background:#fff1f0;border:1px solid #ffa39e;}
 .muted{color:#666;}
</style>
</head>
<body>
$Body
</body>
</html>
"@
  $doc | Out-File -FilePath $Path -Encoding UTF8
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

function Format-HtmlTable {
  param([array]$Rows,[string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) { return '<div class="muted">(no data)</div>' }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<table>')
  [void]$sb.AppendLine('<thead><tr>')
  foreach ($h in $Headers) { [void]$sb.AppendLine('<th>' + [System.Web.HttpUtility]::HtmlEncode($h) + '</th>') }
  [void]$sb.AppendLine('</tr></thead>')
  [void]$sb.AppendLine('<tbody>')
  foreach ($r in $Rows) {
    [void]$sb.AppendLine('<tr>')
    foreach ($h in $Headers) {
      $val = $r.$h
      if ($null -eq $val) { $val = '' }
      $val = [System.Web.HttpUtility]::HtmlEncode($val)
      [void]$sb.AppendLine('<td>' + $val + '</td>')
    }
    [void]$sb.AppendLine('</tr>')
  }
  [void]$sb.AppendLine('</tbody></table>')
  return $sb.ToString()
}

function Render-CollapsibleMd {
  param([string]$Summary,[string]$Body,[bool]$Enabled)
  if (-not $Enabled) { return ("### " + $Summary + "`n`n" + $Body) }
$block = @"
<details>
<summary>$Summary</summary>

$Body

</details>
"@
  return $block
}

function Render-CollapsibleHtml {
  param([string]$Summary,[string]$Body,[bool]$Enabled)
  if (-not $Enabled) { return ('<h3>' + [System.Web.HttpUtility]::HtmlEncode($Summary) + '</h3>' + "`n" + $Body) }
  return '<details><summary>' + [System.Web.HttpUtility]::HtmlEncode($Summary) + '</summary>' + "`n" + $Body + "`n" + '</details>'
}

# -------------------------------
# Writers
# -------------------------------
function Write-IntuneRootIndex {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][array]$Summaries,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style,
    [Parameter(Mandatory)][ValidateSet('Markdown','Html')][string]$Format
  )
  $styleProfile = $Script:DocumentationStyles[$Style]

  $rows = @()
  foreach ($s in ($Summaries | Sort-Object ObjectType)) {
    $rows += [PSCustomObject]@{
      'Object type'   = $s.ObjectType
      'Count'         = $s.Count
      'Last modified' = if ($s.LastModified) { (Get-Date $s.LastModified).ToString('yyyy-MM-dd') } else { '' }
      'Link'          = if ($Format -eq 'Markdown') { "[$($s.ObjectType)]($($s.LinkBase).md)" } else { '<a href="' + ($s.LinkBase + '.html') + '">'+ $s.ObjectType + '</a>' }
    }
  }

  if ($Format -eq 'Markdown') {
    $table = Format-MdTable -Rows $rows -Headers @('Object type','Count','Last modified','Link')
    $title = if ($styleProfile.Numbered) { '# 1. Intune Export - Overview' } else { '# Intune Export - Overview' }
    $body = @()
    $body += $title
    $body += ''
    $body += 'This documentation was generated from ChangeTracking outputs. It summarizes all object types and links to detailed pages.'
    $body += ''
    $body += '## Object Types'
    $body += $table
    Out-Md -Path $Destination -Content ($body -join "`n")
  } else {
    $table = Format-HtmlTable -Rows $rows -Headers @('Object type','Count','Last modified','Link')
    $title = if ($styleProfile.Numbered) { '1. Intune Export - Overview' } else { 'Intune Export - Overview' }
    $body = '<h1>' + $title + '</h1>' + "`n" + '<p>This documentation was generated from ChangeTracking outputs. It summarizes all object types and links to detailed pages.</p>' + "`n" + '<h2>Object Types</h2>' + "`n" + $table
    Out-Html -Path $Destination -Body $body -Title 'Intune Export - Overview'
  }
}

function Write-IntuneObjectTypeOverview {
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][array]$List,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style,
    [Parameter(Mandatory)][ValidateSet('Markdown','Html')][string]$Format
  )
  $styleProfile = $Script:DocumentationStyles[$Style]

  # Prepare rows
  $rows = @()
  foreach ($o in ($List | Sort-Object displayName)) {
    $assignCount = if ($o.assignments) { $o.assignments.Count } else { 0 }
    $safeName = Get-SafeFileName -Name $o.displayName
    $linkMd   = "../objects/$ObjectType/$safeName.md"
    $linkHtml = "../objects/$ObjectType/$safeName.html"
    $desc = if ($o.description) { if ($o.description.Length -gt 120) { $o.description.Substring(0,117) + '...' } else { $o.description } } else { '' }
    $rows += [PSCustomObject]@{
      'Name'          = $o.displayName
      'ID'            = $o.id
      'Description'   = $desc
      'Last modified' = if ($o.lastModified) { (Get-Date $o.lastModified).ToString('yyyy-MM-dd') } else { '' }
      'Assignments'   = $assignCount
      'Link'          = if ($Format -eq 'Markdown') { "[open]($linkMd)" } else { '<a href="' + $linkHtml + '">open</a>' }
    }
  }

  if ($Format -eq 'Markdown') {
    $table = Format-MdTable -Rows $rows -Headers @('Name','ID','Description','Last modified','Assignments','Link')
    $title = if ($styleProfile.Numbered) { "# 2. $ObjectType - Overview" } else { "# $ObjectType - Overview" }
    $body = @()
    $body += $title
    $body += ''
    $body += $table
    Out-Md -Path $Destination -Content ($body -join "`n")
  } else {
    $table = Format-HtmlTable -Rows $rows -Headers @('Name','ID','Description','Last modified','Assignments','Link')
    $title = if ($styleProfile.Numbered) { "2. $ObjectType - Overview" } else { "$ObjectType - Overview" }
    $body = '<h1>' + $title + '</h1>' + "`n" + $table
    Out-Html -Path $Destination -Body $body -Title ("$ObjectType - Overview")
  }
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
    [Parameter(Mandatory)][ValidateSet('Markdown','Html')][string]$Format,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $name  = if ($Meta.displayName) { $Meta.displayName } elseif ($Raw.name) { $Raw.name } else { $Id }
  $last  = if ($Meta.lastIntuneModified) { (Get-Date $Meta.lastIntuneModified).ToString('yyyy-MM-dd HH:mm') } else { '' }

  if ($Format -eq 'Markdown') {
    $headerTitle = if ($styleProfile.Numbered) { "# 3. $name" } else { "# $name" }
    $hdr = @()
    $hdr += $headerTitle
    $hdr += "**Type:** $ObjectType  "
    if ($last) { $hdr += "**Last Modified:** $last  " }
    $hdr += "**ID:** $Id  "

    if ($Raw.description) {
      $hdr += ''
      $hdr += '## Description'
      $hdr += ($Raw.description -replace '\r?\n','  \n')
    }

    # Assignments table
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
    $assignSection += '## Assignments'
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
    $flatSection += '## Settings'
    $flatSection += $flatTable

    # Diagnostics
    $diag = @()
    $diag += '## Diagnostics'
    if ($Meta.diagnostics.assignments.missingGroups.Count -gt 0) { $diag += ('> WARNING: Missing groups: ' + ($Meta.diagnostics.assignments.missingGroups -join ', ')) }
    if ($Meta.diagnostics.assignments.nonSecurityGroups.Count -gt 0) { $diag += ('> WARNING: Non-security groups: ' + ($Meta.diagnostics.assignments.nonSecurityGroups -join ', ')) }
    if ($Meta.diagnostics.assignments.filtersPresent) { $diag += '> Note: Assignments include filters.' }
    if ($diag.Count -eq 1) { $diag += '(no diagnostics)' }

    # Optional raw/meta/flat dumps (collapsible in Rich style)
    $dumps = @()

    if ($IncludeRaw) {
      if ($Raw) { $json = $Raw | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
      $dumps += (Render-CollapsibleMd -Summary 'raw.json' -Body $body -Enabled:$styleProfile.Collapsible)
    }

    if ($IncludeMeta) {
      if ($Meta) { $json = $Meta | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
      $dumps += (Render-CollapsibleMd -Summary 'meta.json' -Body $body -Enabled:$styleProfile.Collapsible)
    }

    if ($IncludeFlat) {
      if ($Flat) { $json = $Flat | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
$body = @"
``````json
$json
``````
"@
      $dumps += (Render-CollapsibleMd -Summary 'flat.json' -Body $body -Enabled:$styleProfile.Collapsible)
    }

    $content = @()
    $content += ($hdr -join "`n")
    $content += ''
    $content += ($assignSection -join "`n")
    $content += ''
    $content += ($flatSection -join "`n")
    $content += ''
    $content += ($diag -join "`n")
    if ($dumps.Count -gt 0) { $content += ''; $content += ($dumps -join "`n") }

    Out-Md -Path $Destination -Content ($content -join "`n")
  }
  else {
    # HTML version
    $title = if ($styleProfile.Numbered) { "3. $name" } else { "$name" }
    $hdrHtml = '<h1>' + [System.Web.HttpUtility]::HtmlEncode($title) + '</h1>' + "`n" + '<div><strong>Type:</strong> ' + $ObjectType + ' &nbsp; ' + (if ($last) { '<strong>Last Modified:</strong> ' + $last + ' &nbsp; ' } else { '' }) + '<strong>ID:</strong> ' + $Id + '</div>'
    if ($Raw.description) { $hdrHtml += "`n<h2>Description</h2>`n<p>" + ([System.Web.HttpUtility]::HtmlEncode($Raw.description) -replace "\r?\n","<br/>") + '</p>' }

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
    $assignTable = Format-HtmlTable -Rows $assignRows -Headers @('Target','Name','Id','Filter','Type')
    if ($assignRows.Count -eq 0) { $assignTable = '<div class="muted">(none)</div>' }
    $assignHtml = '<h2>Assignments</h2>' + "`n" + $assignTable

    # Settings
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
    $flatTable = if ($flatRows.Count -gt 0) { Format-HtmlTable -Rows $flatRows -Headers @('Path','Value','Friendly','CSP','Description','Risk') } else { '<div class="muted">(no flattened settings found)</div>' }
    $flatHtml = '<h2>Settings</h2>' + "`n" + $flatTable

    # Diagnostics
    $diagItems = @()
    if ($Meta.diagnostics.assignments.missingGroups.Count -gt 0) { $diagItems += ('<div class="warn">Missing groups: ' + ([System.Web.HttpUtility]::HtmlEncode(($Meta.diagnostics.assignments.missingGroups -join ', '))) + '</div>') }
    if ($Meta.diagnostics.assignments.nonSecurityGroups.Count -gt 0) { $diagItems += ('<div class="warn">Non-security groups: ' + ([System.Web.HttpUtility]::HtmlEncode(($Meta.diagnostics.assignments.nonSecurityGroups -join ', '))) + '</div>') }
    if ($Meta.diagnostics.assignments.filtersPresent) { $diagItems += '<div class="note">Assignments include filters.</div>' }
    if ($diagItems.Count -eq 0) { $diagItems += '<div class="muted">(no diagnostics)</div>' }
    $diagHtml = '<h2>Diagnostics</h2>' + "`n" + ($diagItems -join "`n")

    # Optional dumps in HTML (collapsible in Rich)
    $dumpHtml = ''
    if ($IncludeRaw) {
      if ($Raw) { $json = $Raw | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
      $pre = '<pre><code class="language-json">' + [System.Web.HttpUtility]::HtmlEncode($json) + '</code></pre>'
      $dumpHtml += (Render-CollapsibleHtml -Summary 'raw.json' -Body $pre -Enabled:$styleProfile.Collapsible)
    }
    if ($IncludeMeta) {
      if ($Meta) { $json = $Meta | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
      $pre = '<pre><code class="language-json">' + [System.Web.HttpUtility]::HtmlEncode($json) + '</code></pre>'
      $dumpHtml += (Render-CollapsibleHtml -Summary 'meta.json' -Body $pre -Enabled:$styleProfile.Collapsible)
    }
    if ($IncludeFlat) {
      if ($Flat) { $json = $Flat | ConvertTo-Json -Depth 50 } else { $json = '(not available)' }
      $pre = '<pre><code class="language-json">' + [System.Web.HttpUtility]::HtmlEncode($json) + '</code></pre>'
      $dumpHtml += (Render-CollapsibleHtml -Summary 'flat.json' -Body $pre -Enabled:$styleProfile.Collapsible)
    }

    $body = $hdrHtml + "`n" + $assignHtml + "`n" + $flatHtml + "`n" + $diagHtml + (if ($dumpHtml) { "`n<h2>Data</h2>`n" + $dumpHtml } else { '' })
    Out-Html -Path $Destination -Body $body -Title $name
  }
}

Export-ModuleMember -Function New-IntuneDocumentation,New-IntuneDocumentationForObject,Set-IntuneDocumentationStyle,Get-IntuneDocumentationStyle
