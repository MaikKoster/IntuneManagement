<#
ChangeTrackingDocumentation_v3.psm1 (Part 1/3)
Foundation: styles, template loader (TL1), utilities, data access.
Hybrid Style (D) + H2 Aesthetic + TOC-A3 + Breadcrumbs + Timestamp Bottom + Monospace CSP fields
PS5-safe, ASCII-only. No emojis.
#>

# ==============================
# Global style configuration
# ==============================
$Script:DocumentationStyles = @{
  Enterprise = @{ Collapsible = $false; Numbered = $true }
  Rich       = @{ Collapsible = $true; Numbered = $false }
}

# Current style (string key into $Script:DocumentationStyles)
$Script:DocStyle = 'Enterprise'

function Set-IntuneDocumentationStyle {
  [CmdletBinding()]
  param([Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')] [string]$Style)
  $Script:DocStyle = $Style
}

function Get-IntuneDocumentationStyle {
  [CmdletBinding()] param()
  return $Script:DocStyle
}

# ==============================
# Template path resolution (TL1)
# ==============================
function Get-TemplateRoot {
  [CmdletBinding()] param([switch]$ThrowIfMissing)
  # TL1: templates are located at ../docs/Templates relative to this module
  $root = Join-Path (Join-Path $PSScriptRoot '..') 'docs'
  $root = Join-Path $root 'Templates'
  if (-not (Test-Path $root)) {
    if ($ThrowIfMissing) {
      throw "Template root not found: $root" 
    }
  }
  return $root
}

function Get-TemplateFilePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('Html', 'Markdown')] [string]$Format,
    [Parameter(Mandatory)][ValidateSet('Index', 'ObjectTypeOverview', 'ObjectDetail')] [string]$Name
  )
  $root = Get-TemplateRoot
  if ($Format -eq 'Html') {
    $folder = Join-Path $root 'Html'
    $file = "$Name.html"
  }
  else {
    $folder = Join-Path $root 'Markdown'
    $file = "$Name.md"
  }
  return (Join-Path $folder $file)
}

function Load-Template {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('Html', 'Markdown')] [string]$Format,
    [Parameter(Mandatory)][ValidateSet('Index', 'ObjectTypeOverview', 'ObjectDetail')] [string]$Name
  )
  $path = Get-TemplateFilePath -Format $Format -Name $Name
  if (Test-Path $path) {
    return (Get-Content -Raw -Path $path)
  }
  # Fallback minimal templates (very small, just to prevent failures)
  if ($Format -eq 'Html') {
    if ($Name -eq 'Index') {
      return '<h1>Intune Export Documentation</h1>' 
    }
    if ($Name -eq 'ObjectTypeOverview') {
      return '<h1>{ObjectType} - Overview</h1>{Table}' 
    }
    if ($Name -eq 'ObjectDetail') {
      return '<h1>{Title}</h1>{Body}' 
    }
  }
  else {
    if ($Name -eq 'Index') {
      return '# Intune Export Documentation\n\n## Object Types\n{Table}' 
    }
    if ($Name -eq 'ObjectTypeOverview') {
      return '# {ObjectType} - Overview\n\n{Table}' 
    }
    if ($Name -eq 'ObjectDetail') {
      return '# {Title}\n\n{Body}' 
    }
  }
}

# ==============================
# Data access helpers
# ==============================
function Get-IntuneObjectTypes {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$ExportRoot)
  if (-not (Test-Path $ExportRoot)) {
    return @() 
  }
  return (Get-ChildItem -Path $ExportRoot -Directory |
    Where-Object { $_.Name -notmatch '^_' } |
    Select-Object -ExpandProperty Name)
}

function Get-IntuneObjectList {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType
  )
  $typePath = Join-Path $ExportRoot $ObjectType
  if (-not (Test-Path $typePath)) {
    return @() 
  }

  $items = @()
  foreach ($dir in (Get-ChildItem -Path $typePath -Directory)) {
    $id = $dir.Name
    $metaPath = Join-Path $dir.FullName 'meta.json'
    $rawPath = Join-Path $dir.FullName 'raw.json'
    $flatPath = Join-Path $dir.FullName 'flat.json'

    $meta = $null; $raw = $null; $flat = $null
    if (Test-Path $metaPath) {
      try {
        $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json 
      }
      catch {
      } 
    }
    if (Test-Path $rawPath) {
      try {
        $raw = Get-Content -Raw -Path $rawPath  | ConvertFrom-Json 
      }
      catch {
      } 
    }
    if (Test-Path $flatPath) {
      try {
        $flat = Get-Content -Raw -Path $flatPath | ConvertFrom-Json 
      }
      catch {
      } 
    }

    $display = $null
    $candidates = @()
    if ($meta -and $meta.displayName) {
      $candidates += $meta.displayName 
    }
    if ($raw -and $raw.name) {
      $candidates += $raw.name 
    }
    if ($raw -and $raw.displayName) {
      $candidates += $raw.displayName 
    }
    $candidates += $id
    foreach ($c in $candidates) {
      if ($c) {
        $display = $c; break 
      } 
    }

    $obj = [PSCustomObject]@{
      id           = $id
      objectType   = $ObjectType
      displayName  = $display
      lastModified = if ($meta) {
        $meta.lastIntuneModified 
      }
      else {
        $null 
      }
      description  = if ($raw) {
        $raw.description 
      }
      else {
        $null 
      }
      assignments  = if ($meta) {
        $meta.assignmentsSummary 
      }
      else {
        $null 
      }
      flat         = $flat
      meta         = $meta
      raw          = $raw
    }
    $items += $obj
  }
  return $items
}

# ==============================
# Utilities
# ==============================
function Get-SafeFileName {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [int]$MaxLength = 120)
  $safe = $Name
  $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
  $regex = '[' + [Regex]::Escape($invalid) + ']'
  $safe = [Regex]::Replace($safe, $regex, '_')
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) {
    $safe = $safe.Substring(0, $MaxLength) 
  }
  if ([string]::IsNullOrWhiteSpace($safe)) {
    $safe = 'unnamed' 
  }
  return $safe
}

function Html-Encode {
  [CmdletBinding()] param([string]$Text)
  try {
    return [System.Web.HttpUtility]::HtmlEncode($Text)
  }
  catch {
    # Fallback minimal escaping
    $t = $Text
    $t = $t -replace '&', '&amp;'
    $t = $t -replace '<', '&lt;'
    $t = $t -replace '>', '&gt;'
    $t = $t -replace '"', '&quot;'
    $t = $t -replace "'", '&#39;'
    return $t
  }
}

# Note: public entry points, Markdown and HTML writers will arrive in Parts 2 and 3.
<#
ChangeTrackingDocumentation_v3.psm1 (Part 2A/3)
Section: Markdown helpers (Invoke-MarkdownTemplate, New-MdTable)
PS5-safe, ASCII-only.
#>

# ==============================
# Markdown Rendering Helpers
# ==============================
function Invoke-MarkdownTemplate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][hashtable]$Values
  )

  # Simple placeholder replacement: {Key} -> Values[Key]
  $output = $Template
  foreach ($key in $Values.Keys) {
    $placeholder = '{' + $key + '}'
    $value = $Values[$key]
    if ($null -eq $value) {
      $value = '' 
    }
    # Replace all occurrences; escape placeholder for regex safety
    $output = $output -replace [Regex]::Escape($placeholder), [Regex]::Escape([string]$value)
  }
  return $output
}

function New-MdTable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][array]$Rows,
    [Parameter(Mandatory)][string[]]$Headers
  )

  if (-not $Rows -or $Rows.Count -eq 0) {
    return '(no data)' 
  }

  $sb = New-Object System.Text.StringBuilder
  $headerLine = ($Headers -join ' | ')
  $sepLine = (($Headers | ForEach-Object { '---' }) -join ' | ')
  [void]$sb.AppendLine('| ' + $headerLine + ' |')
  [void]$sb.AppendLine('| ' + $sepLine + ' |')

  foreach ($r in $Rows) {
    $cells = @()
    foreach ($h in $Headers) {
      $val = $null
      try {
        $val = $r.$h 
      }
      catch {
        $val = '' 
      }
      if ($null -eq $val) {
        $val = '' 
      }
      $cells += ([string]$val -replace "\r?\n", ' ')
    }
    [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
  }

  return $sb.ToString()
}

function Write-IntuneRootIndexMarkdown {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][array]$Summaries,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $Template = Load-Template -Format 'Markdown' -Name 'Index'

  $rows = @()
  foreach ($s in ($Summaries | Sort-Object ObjectType)) {
    $rows += [PSCustomObject]@{
      'Object type'   = $s.ObjectType
      'Count'         = $s.Count
      'Last modified' = if ($s.LastModified) {
        (Get-Date $s.LastModified).ToString('yyyy-MM-dd') 
      }
      else {
        '' 
      }
      'Link'          = "[$($s.ObjectType)](by-type/$($s.ObjectType).md)"
    }
  }

  $table = New-MdTable -Rows $rows -Headers @('Object type', 'Count', 'Last modified', 'Link')
  $output = Invoke-MarkdownTemplate -Template $Template -Values @{ Table = $table }
  Out-Md -Path $Destination -Content $output
}


function Write-IntuneObjectTypeOverviewMarkdown {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][array]$List,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $Template = Load-Template -Format 'Markdown' -Name 'ObjectTypeOverview'

  # Build table rows
  $rows = @()
  foreach ($o in ($List | Sort-Object displayName)) {
    $safeName = Get-SafeFileName -Name $o.displayName
    $desc = $o.description
    if ($desc) {
      $desc = $desc -replace "\r?\n", ' ' 
    }
    $rows += [PSCustomObject]@{
      'Name'          = $o.displayName
      'ID'            = $o.id
      'Description'   = $desc
      'Last modified' = if ($o.lastModified) {
        (Get-Date $o.lastModified).ToString('yyyy-MM-dd') 
      }
      else {
        '' 
      }
      'Assignments'   = if ($o.assignments) {
        $o.assignments.Count 
      }
      else {
        0 
      }
      'Link'          = "[open](../objects/$ObjectType/$safeName.md)"
    }
  }

  # Convert to markdown table
  $table = New-MdTable -Rows $rows -Headers @('Name', 'ID', 'Description', 'Last modified', 'Assignments', 'Link')

  # Fill template
  $output = Invoke-MarkdownTemplate -Template $Template -Values @{
    ObjectType = $ObjectType
    Table      = $table
  }

  Out-Md -Path $Destination -Content $output
}


function Write-IntuneObjectDetailMarkdown {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$Id,
    [Parameter()][object]$Raw,
    [Parameter()][object]$Meta,
    [Parameter()][object]$Flat,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $Template = Load-Template -Format 'Markdown' -Name 'ObjectDetail'

  # ---------- TITLE ----------
  $title = if ($Meta.displayName) {
    $Meta.displayName 
  }
  elseif ($Raw.name) {
    $Raw.name 
  }
  else {
    $Id 
  }
  $bodyBuilder = New-Object System.Text.StringBuilder

  # ---------- DESCRIPTION ----------
  $desc = ''
  if ($Raw -and $Raw.description) {
    $desc = ($Raw.description -replace "\r?\n", "  \n")
  }

  # ---------- ASSIGNMENTS TABLE ----------
  $assignRows = @()
  if ($Meta -and $Meta.assignmentsSummary) {
    foreach ($a in $Meta.assignmentsSummary) {
      $assignRows += [PSCustomObject]@{
        'Target' = 'Group'
        'Name'   = $a.groupDisplayName
        'Id'     = $a.groupId
        'Filter' = if ($a.filterId) {
          $a.filterId 
        }
        else {
          '' 
        }
        'Type'   = if ($a.filterType) {
          $a.filterType 
        }
        else {
          '' 
        }
      }
    }
  }
  $assignTable = if ($assignRows.Count -gt 0) {
    New-MdTable -Rows $assignRows -Headers @('Target', 'Name', 'Id', 'Filter', 'Type')
  }
  else {
    '(none)'
  }

  # ---------- SETTINGS TABLE ----------
  $flatRows = @()
  if ($Flat) {
    foreach ($s in $Flat) {
      $val = $s.value
      if ($val -is [System.Collections.IDictionary]) {
        $val = ($val | ConvertTo-Json -Depth 20)
      }
      elseif ($val -is [System.Collections.IList]) {
        $val = ($val -join ', ')
      }

      $flatRows += [PSCustomObject]@{
        'Path'        = $s.path
        'Value'       = $val
        'Friendly'    = if ($s.friendlyValue) {
          $s.friendlyValue 
        }
        else {
          '' 
        }
        'CSP'         = if ($s.cspEquivalent) {
          $s.cspEquivalent 
        }
        else {
          '' 
        }
        'Description' = if ($s.scDesc) {
          $s.scDesc 
        }
        else {
          '' 
        }
        'Risk'        = if ($s.risk) {
          $s.risk 
        }
        else {
          '' 
        }
      }
    }
  }

  $settingsTable = if ($flatRows.Count -gt 0) {
    New-MdTable -Rows $flatRows -Headers @('Path', 'Value', 'Friendly', 'CSP', 'Description', 'Risk')
  }
  else {
    '(no flattened settings found)'
  }

  # ---------- DIAGNOSTICS ----------
  $diag = @()
  if ($Meta -and $Meta.diagnostics -and $Meta.diagnostics.assignments) {
    if ($Meta.diagnostics.assignments.missingGroups.Count -gt 0) {
      $diag += ('> WARNING: Missing groups: ' + ($Meta.diagnostics.assignments.missingGroups -join ', '))
    }
    if ($Meta.diagnostics.assignments.nonSecurityGroups.Count -gt 0) {
      $diag += ('> WARNING: Non-security groups: ' + ($Meta.diagnostics.assignments.nonSecurityGroups -join ', '))
    }
    if ($Meta.diagnostics.assignments.filtersPresent) {
      $diag += '> Note: Assignments include filters.'
    }
  }
  if ($diag.Count -eq 0) {
    $diag += '(no diagnostics)' 
  }

  # ---------- DATA SECTIONS ----------
  $dataSections = ''

  if ($IncludeRaw) {
    $json = if ($Raw) {
      ($Raw | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $rawBlock = @"
```json
$json
```
"@
    if ($styleProfile.Collapsible) {
      $rawSection = @"
<details>
<summary>raw.json</summary>

$rawBlock

</details>
"@
      $dataSections += $rawSection + "`n"
    }
    else {
      $dataSections += "## raw.json`n`n$rawBlock`n"
    }
  }

  if ($IncludeMeta) {
    $json = if ($Meta) {
      ($Meta | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $metaBlock = @"
```json
$json
```
"@
    if ($styleProfile.Collapsible) {
      $metaSection = @"
<details>
<summary>meta.json</summary>

$metaBlock

</details>
"@
      $dataSections += $metaSection + "`n"
    }
    else {
      $dataSections += "## meta.json`n`n$metaBlock`n"
    }
  }

  if ($IncludeFlat) {
    $json = if ($Flat) {
      ($Flat | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $flatBlock = @"
```json
$json
```
"@
    if ($styleProfile.Collapsible) {
      $flatSection = @"
<details>
<summary>flat.json</summary>

$flatBlock

</details>
"@
      $dataSections += $flatSection + "`n"
    }
    else {
      $dataSections += "## flat.json`n`n$flatBlock`n"
    }
  }

  # ---------- TEMPLATE MERGE ----------
  $output = Invoke-MarkdownTemplate -Template $Template -Values @{
    Title        = $title
    Description  = $desc
    Assignments  = $assignTable
    Settings     = $settingsTable
    Diagnostics  = ($diag -join "`n")
    DataSections = $dataSections
  }

  Out-Md -Path $Destination -Content $output
}
<#
ChangeTrackingDocumentation_v3.psm1 (Part 3A/3)
Section: HTML helpers, template engine, and Root Index HTML writer
PS5-safe, ASCII-only. Hybrid style (Enterprise/Rich), TOC-A3, breadcrumbs, timestamp bottom.
#>

# ==============================
# Basic output helpers (file writers)
# ==============================
function Out-Md {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null 
  }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Out-Html {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null 
  }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}

# ==============================
# HTML template processing
# ==============================
function Invoke-HtmlTemplate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][hashtable]$Values
  )
  $output = $Template
  foreach ($key in $Values.Keys) {
    $placeholder = '{' + $key + '}'
    $value = $Values[$key]
    if ($null -eq $value) {
      $value = '' 
    }
    $output = $output -replace [Regex]::Escape($placeholder), [Regex]::Escape([string]$value)
  }
  return $output
}

function Format-HtmlTable {
  [CmdletBinding()]
  param([Parameter(Mandatory)][array]$Rows, [Parameter(Mandatory)][string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) {
    return '<div>(no data)</div>' 
  }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<table>')
  [void]$sb.AppendLine('<thead><tr>')
  foreach ($h in $Headers) {
    [void]$sb.AppendLine('<th>' + (Html-Encode $h) + '</th>') 
  }
  [void]$sb.AppendLine('</tr></thead>')
  [void]$sb.AppendLine('<tbody>')
  foreach ($r in $Rows) {
    [void]$sb.AppendLine('<tr>')
    foreach ($h in $Headers) {
      $val = $null
      try {
        $val = $r.$h 
      }
      catch {
        $val = '' 
      }
      if ($null -eq $val) {
        $val = '' 
      }
      [void]$sb.AppendLine('<td>' + (Html-Encode ([string]$val)) + '</td>')
    }
    [void]$sb.AppendLine('</tr>')
  }
  [void]$sb.AppendLine('</tbody></table>')
  return $sb.ToString()
}

function Render-CollapsibleHtml {
  [CmdletBinding()] param([string]$Summary, [string]$Body, [bool]$Enabled)
  if (-not $Enabled) {
    return ('<h3>' + (Html-Encode $Summary) + '</h3>' + "`n" + $Body) 
  }
  return '<details><summary>' + (Html-Encode $Summary) + '</summary>' + "`n" + $Body + '</details>'
}

function Get-BreadcrumbsHtml {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string[]]$Crumbs)
  # Example: Intune Export / SettingsCatalog / Windows Update Policy
  $encoded = @(); foreach ($c in $Crumbs) {
    $encoded += (Html-Encode $c) 
  }
  return '<div class="breadcrumbs">' + ($encoded -join ' / ') + '</div>'
}

function Get-TocHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$Items,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style,
    [switch]$IncludeAnchors
  )
  $list = '<ul>'
  foreach ($i in $Items) {
    $anchor = if ($IncludeAnchors) {
      '#' + ($i -replace ' ', '').ToLower() 
    }
    else {
      '#' 
    }
    $list += '<li><a href="' + $anchor + '">' + (Html-Encode $i) + '</a></li>'
  }
  $list += '</ul>'

  if ($Style -eq 'Rich') {
    return '<div class="toc-card"><details open><summary>Contents</summary>' + $list + '</details></div>'
  }
  else {
    return '<div class="toc-card"><h2>Contents</h2>' + $list + '</div>'
  }
}

# ==============================
# Root Index HTML writer
# ==============================
function Write-IntuneRootIndexHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][array]$Summaries,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $template = Load-Template -Format 'Html' -Name 'Index'

  # Table of object types
  $rows = @()
  foreach ($s in ($Summaries | Sort-Object ObjectType)) {
    $rows += [PSCustomObject]@{
      'Object type'   = $s.ObjectType
      'Count'         = $s.Count
      'Last modified' = if ($s.LastModified) {
        (Get-Date $s.LastModified).ToString('yyyy-MM-dd') 
      }
      else {
        '' 
      }
      'Link'          = '<a href="' + (Html-Encode ($s.LinkBase + '.html')) + '">' + (Html-Encode $s.ObjectType) + '</a>'
    }
  }
  $table = Format-HtmlTable -Rows $rows -Headers @('Object type', 'Count', 'Last modified', 'Link')

  # Title (numbered for Enterprise)
  $title = if ($styleProfile.Numbered) {
    '1. Intune Export Documentation' 
  }
  else {
    'Intune Export Documentation' 
  }

  # Breadcrumbs & TOC
  $breadcrumbs = Get-BreadcrumbsHtml -Crumbs @('Intune Export')
  $toc = Get-TocHtml -Items @('Object Types') -Style $Style -IncludeAnchors

  # Timestamp footer (bottom)
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

  $html = Invoke-HtmlTemplate -Template $template -Values @{
    Title            = $title
    Breadcrumbs      = $breadcrumbs
    TOC              = $toc
    ObjectTypesTable = $table
    Timestamp        = $timestamp
  }

  Out-Html -Path $Destination -Content $html
}
<#
ChangeTrackingDocumentation_v3.psm1 (Part 3B/3)
Section: Object Type Overview HTML writer
PS5-safe, ASCII-only. Hybrid style (Enterprise/Rich), TOC-A3, breadcrumbs, timestamp bottom.
#>

function Write-IntuneObjectTypeOverviewHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][array]$List,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $template = Load-Template -Format 'Html' -Name 'ObjectTypeOverview'

  # Build table rows
  $rows = @()
  foreach ($o in ($List | Sort-Object displayName)) {
    $safe = Get-SafeFileName -Name $o.displayName
    $rows += [PSCustomObject]@{
      'Name'          = $o.displayName
      'ID'            = $o.id
      'Description'   = (if ($o.description) { (Html-Encode ($o.description -replace "\r?\n", ' ')) } else { '' })
      'Last modified' = (if ($o.lastModified) { (Get-Date $o.lastModified).ToString('yyyy-MM-dd') } else { '' })
      'Assignments'   = (if ($o.assignments) { $o.assignments.Count } else { 0 })
      'Link'          = '<a href="../objects/' + (Html-Encode $ObjectType) + '/' + (Html-Encode $safe) + '.html">open</a>'
    }
  }

  $table = Format-HtmlTable -Rows $rows -Headers @('Name', 'ID', 'Description', 'Last modified', 'Assignments', 'Link')

  # Title (numbered for Enterprise)
  $title = if ($styleProfile.Numbered) {
    '2. ' + $ObjectType + ' - Overview' 
  }
  else {
    $ObjectType + ' - Overview' 
  }

  # Breadcrumbs & TOC (A3: Rich collapsible, Enterprise static)
  $breadcrumbs = Get-BreadcrumbsHtml -Crumbs @('Intune Export', $ObjectType)
  $toc = Get-TocHtml -Items @('Objects') -Style $Style -IncludeAnchors

  # Timestamp footer (bottom)
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

  $html = Invoke-HtmlTemplate -Template $template -Values @{
    Title       = $title
    Breadcrumbs = $breadcrumbs
    TOC         = $toc
    ObjectTable = $table
    Timestamp   = $timestamp
  }

  Out-Html -Path $Destination -Content $html
}
<#
ChangeTrackingDocumentation_v3.psm1 (Part 3C/3)
Section: HTML Object Detail writer + public entrypoints (New-IntuneDocumentation, New-IntuneDocumentationForObject)
PS5-safe, ASCII-only. Final module glue.
#>

# ==============================
# HTML Object Detail writer
# ==============================
function Write-IntuneObjectDetailHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$Id,
    [Parameter()][object]$Raw,
    [Parameter()][object]$Meta,
    [Parameter()][object]$Flat,
    [Parameter(Mandatory)][ValidateSet('Enterprise', 'Rich')][string]$Style,
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  $styleProfile = $Script:DocumentationStyles[$Style]
  $template = Load-Template -Format 'Html' -Name 'ObjectDetail'

  # ---------- TITLE ----------
  $title = if ($Meta.displayName) {
    $Meta.displayName 
  }
  elseif ($Raw.name) {
    $Raw.name 
  }
  else {
    $Id 
  }

  # ---------- BREADCRUMBS ----------
  $breadcrumbs = Get-BreadcrumbsHtml -Crumbs @('Intune Export', $ObjectType, $title)

  # ---------- DESCRIPTION ----------
  $descHtml = ''
  if ($Raw -and $Raw.description) {
    $enc = Html-Encode ($Raw.description -replace "\r?\n", '<br/>')
    $descHtml = '<p>' + $enc + '</p>'
  }

  # ---------- ASSIGNMENTS ----------
  $assignRows = @()
  if ($Meta -and $Meta.assignmentsSummary) {
    foreach ($a in $Meta.assignmentsSummary) {
      $assignRows += [PSCustomObject]@{
        'Target' = 'Group'
        'Name'   = $a.groupDisplayName
        'Id'     = $a.groupId
        'Filter' = if ($a.filterId) {
          $a.filterId 
        }
        else {
          '' 
        }
        'Type'   = if ($a.filterType) {
          $a.filterType 
        }
        else {
          '' 
        }
      }
    }
  }

  $assignHtml = if ($assignRows.Count -gt 0) {
    Format-HtmlTable -Rows $assignRows -Headers @('Target', 'Name', 'Id', 'Filter', 'Type')
  }
  else {
    '<div>(none)</div>'
  }

  # ---------- SETTINGS TABLE ----------
  $flatRows = @()
  if ($Flat) {
    foreach ($s in $Flat) {
      $val = $s.value
      if ($val -is [System.Collections.IDictionary]) {
        $val = ($val | ConvertTo-Json -Depth 20)
      }
      elseif ($val -is [System.Collections.IList]) {
        $val = ($val -join ', ')
      }

      $flatRows += [PSCustomObject]@{
        'Path'        = $s.path
        'Value'       = $val
        'Friendly'    = if ($s.friendlyValue) {
          $s.friendlyValue 
        }
        else {
          '' 
        }
        'CSP'         = if ($s.cspEquivalent) {
          '<code>' + (Html-Encode $s.cspEquivalent) + '</code>' 
        }
        else {
          '' 
        }
        'Description' = if ($s.scDesc) {
          $s.scDesc 
        }
        else {
          '' 
        }
        'Risk'        = if ($s.risk) {
          $s.risk 
        }
        else {
          '' 
        }
      }
    }
  }

  $settingsHtml = if ($flatRows.Count -gt 0) {
    Format-HtmlTable -Rows $flatRows -Headers @('Path', 'Value', 'Friendly', 'CSP', 'Description', 'Risk')
  }
  else {
    '<div>(no flattened settings found)</div>'
  }

  # ---------- DIAGNOSTICS ----------
  $diagItems = @()
  if ($Meta -and $Meta.diagnostics -and $Meta.diagnostics.assignments) {
    if ($Meta.diagnostics.assignments.missingGroups.Count -gt 0) {
      $diagItems += '<div class="warn">Missing groups: ' + (Html-Encode ($Meta.diagnostics.assignments.missingGroups -join ', ')) + '</div>'
    }
    if ($Meta.diagnostics.assignments.nonSecurityGroups.Count -gt 0) {
      $diagItems += '<div class="warn">Non-security groups: ' + (Html-Encode ($Meta.diagnostics.assignments.nonSecurityGroups -join ', ')) + '</div>'
    }
    if ($Meta.diagnostics.assignments.filtersPresent) {
      $diagItems += '<div class="note">Assignments include filters.</div>'
    }
  }
  if ($diagItems.Count -eq 0) {
    $diagItems += '<div class="muted">(no diagnostics)</div>' 
  }
  $diagHtml = ($diagItems -join "`n")

  # ---------- DATA SECTIONS ----------
  $dataHtml = ''

  if ($IncludeRaw) {
    $json = if ($Raw) {
      ($Raw | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $pre = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
    $dataHtml += (Render-CollapsibleHtml -Summary 'raw.json' -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
  }

  if ($IncludeMeta) {
    $json = if ($Meta) {
      ($Meta | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $pre = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
    $dataHtml += (Render-CollapsibleHtml -Summary 'meta.json' -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
  }

  if ($IncludeFlat) {
    $json = if ($Flat) {
      ($Flat | ConvertTo-Json -Depth 50) 
    }
    else {
      '(not available)' 
    }
    $pre = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
    $dataHtml += (Render-CollapsibleHtml -Summary 'flat.json' -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
  }

  # ---------- TOC (Hybrid TOC-A3) ----------
  $toc = Get-TocHtml -Items @('Description', 'Assignments', 'Settings', 'Diagnostics', 'Data') -Style $Style -IncludeAnchors

  # ---------- TIMESTAMP ----------
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

  # ---------- MERGE INTO TEMPLATE ----------
  $html = Invoke-HtmlTemplate -Template $template -Values @{
    Title        = $title
    Breadcrumbs  = $breadcrumbs
    TOC          = $toc
    Description  = $descHtml
    Assignments  = $assignHtml
    Settings     = $settingsHtml
    Diagnostics  = $diagHtml
    DataSections = $dataHtml
    Timestamp    = $timestamp
  }

  Out-Html -Path $Destination -Content $html
}

# ==============================
# Public entrypoints
# ==============================
function New-IntuneDocumentationForObject {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$Id,
    [ValidateSet('Enterprise', 'Rich')][string]$Style,
    [ValidateSet('Markdown', 'Html', 'Both')][string]$Output = 'Markdown',
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  Set-IntuneDocumentationStyle -Style $Style
  $styleProfile = $Script:DocumentationStyles[$Script:DocStyle]

  $objFolder = Join-Path (Join-Path $ExportRoot $ObjectType) $Id
  if (-not (Test-Path $objFolder)) {
    throw "Object folder not found: $objFolder" 
  }

  $metaPath = Join-Path $objFolder 'meta.json'
  $rawPath = Join-Path $objFolder 'raw.json'
  $flatPath = Join-Path $objFolder 'flat.json'

  $meta = if (Test-Path $metaPath) {
    Get-Content -Raw -Path $metaPath | ConvertFrom-Json 
  }
  else {
    $null 
  }
  $raw = if (Test-Path $rawPath) {
    Get-Content -Raw -Path $rawPath  | ConvertFrom-Json 
  }
  else {
    $null 
  }
  $flat = if (Test-Path $flatPath) {
    Get-Content -Raw -Path $flatPath | ConvertFrom-Json 
  }
  else {
    $null 
  }

  $docsRoot = Join-Path $ExportRoot '_docs'
  $objDocs = Join-Path (Join-Path $docsRoot 'objects') $ObjectType
  if (-not (Test-Path $objDocs)) {
    New-Item -ItemType Directory -Force -Path $objDocs | Out-Null 
  }

  $displayName = ($meta.displayName, $raw.name, $raw.displayName, $Id | Where-Object { $_ } | Select-Object -First 1)
  $safeName = Get-SafeFileName -Name $displayName
  $destBase = Join-Path $objDocs $safeName

  if ($Output -in @('Markdown', 'Both')) {
    Write-IntuneObjectDetailMarkdown -Destination ("{0}.md" -f $destBase) -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat
  }

  if ($Output -in @('Html', 'Both')) {
    Write-IntuneObjectDetailHtml -Destination ("{0}.html" -f $destBase) -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat
  }

  return $destBase
}

function New-IntuneDocumentation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [ValidateSet('Enterprise', 'Rich')][string]$Style,
    [ValidateSet('Markdown', 'Html', 'Both')][string]$Output = 'Markdown',
    [switch]$IncludeRaw,
    [switch]$IncludeMeta,
    [switch]$IncludeFlat
  )

  Set-IntuneDocumentationStyle -Style $Style
  $docsRoot = Join-Path $ExportRoot '_docs'
  $byType = Join-Path $docsRoot 'by-type'
  $objects = Join-Path $docsRoot 'objects'
  foreach ($d in @($docsRoot, $byType, $objects)) {
    if (-not (Test-Path $d)) {
      New-Item -ItemType Directory -Force -Path $d | Out-Null 
    }
  }

  $types = Get-IntuneObjectTypes -ExportRoot $ExportRoot
  $summaries = @()

  foreach ($t in $types) {
    $list = Get-IntuneObjectList -ExportRoot $ExportRoot -ObjectType $t
    if (-not $list) {
      continue 
    }

    foreach ($o in $list) {
      New-IntuneDocumentationForObject -ExportRoot $ExportRoot -ObjectType $t -Id $o.id -Style $Script:DocStyle -Output $Output -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat | Out-Null
    }

    # Generate type overview for Markdown/HTML
    $typeBase = Join-Path $byType $t

    if ($Output -in '@Both', 'Markdown') {
      Write-IntuneObjectTypeOverviewMarkdown -Destination ("{0}.md" -f $typeBase) -ObjectType $t -List $list -Style $Script:DocStyle
    }

    if ($Output -in '@Both', 'Html') {
      Write-IntuneObjectTypeOverviewHtml -Destination ("{0}.html" -f $typeBase) -ObjectType $t -List $list -Style $Script:DocStyle
    }

    $last = ($list | Where-Object { $_.lastModified } | Sort-Object lastModified -Descending | Select-Object -First 1).lastModified
    $summaries += [PSCustomObject]@{ ObjectType = $t; Count = $list.Count; LastModified = $last; LinkBase = (Join-Path 'by-type'$t) }
  }

  # Root index
  $rootBase = Join-Path $docsRoot 'index'

  if ($Output -in '@Both', 'Markdown') {
    Write-IntuneRootIndexMarkdown -Destination ("{0}.md" -f $rootBase) -Summaries $summaries -Style $Script:DocStyle
  }

  if ($Output -in '@Both', 'Html') {
    Write-IntuneRootIndexHtml -Destination ("{0}.html" -f $rootBase) -Summaries $summaries -Style $Script:DocStyle
  }
}

# ------------------------------
# Export public functions
# ------------------------------
Export-ModuleMember -Function New-IntuneDocumentation, New-IntuneDocumentationForObject, Set-IntuneDocumentationStyle, Get-IntuneDocumentationStyle
