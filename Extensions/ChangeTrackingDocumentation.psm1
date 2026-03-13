# ChangeTrackingDocumentation_v3.psm1
# Unified documentation generator for Intune Change Tracking (Markdown + HTML)
# - Generates per-object pages, per-type overview pages, and a root index
# - Template engine supports both {Key} and {{ key }} placeholders (case-insensitive)
# - HTML and Markdown share the same rendering contract
# - Includes optional Settings Catalog children rendering (for choice instances with children)

# ==============================
# Global style configuration
# ==============================
$Script:DocumentationStyles = @{
  Enterprise = @{ Collapsible = $false; Numbered = $true }
  Rich       = @{ Collapsible = $true;  Numbered = $false }
}
$Script:DocStyle = 'Enterprise'

function Set-IntuneDocumentationStyle {
  [CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style)
  $Script:DocStyle = $Style
}
function Get-IntuneDocumentationStyle { [CmdletBinding()] param() return $Script:DocStyle }

# ==============================
# Template path resolution
# ==============================
function Get-TemplateRoot {
  [CmdletBinding()] param([switch]$ThrowIfMissing)
  $root = Join-Path (Join-Path $PSScriptRoot '..') 'docs'
  $root = Join-Path $root 'Templates'
  if (-not (Test-Path $root)) {
    if ($ThrowIfMissing) { throw "Template root not found: $root" }
  }
  return $root
}
function Get-TemplateFilePath {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][ValidateSet('Html','Markdown')][string]$Format,
    [Parameter(Mandatory)][ValidateSet('Index','ObjectTypeOverview','ObjectDetail')][string]$Name
  )
  $root = Get-TemplateRoot
  if ($Format -eq 'Html') { $folder = Join-Path $root 'Html'; $file = "$Name.html" }
  else                     { $folder = Join-Path $root 'Markdown'; $file = "$Name.md" }
  return (Join-Path $folder $file)
}
function Load-Template {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][ValidateSet('Html','Markdown')][string]$Format,
    [Parameter(Mandatory)][ValidateSet('Index','ObjectTypeOverview','ObjectDetail')][string]$Name
  )
  $path = Get-TemplateFilePath -Format $Format -Name $Name
  if (Test-Path $path) { return (Get-Content -Raw -Path $path) }
  # minimal fallbacks
  if ($Format -eq 'Html') {
    switch ($Name) {
      'Index'              { return '<h1>{Title}</h1>{ObjectTypesTable}' }
      'ObjectTypeOverview' { return '<h1>{Title}</h1>{ObjectTable}' }
      'ObjectDetail'       { return '<h1>{Title}</h1>{Description}{Assignments}{Settings}{Diagnostics}{DataSections}' }
    }
  }
  else {
    switch ($Name) {
      'Index'              { return '# Intune Export - Overview`n`n{Table}' }
      'ObjectTypeOverview' { return '# {ObjectType} - Overview`n`n{Table}' }
      'ObjectDetail'       { return '# {Title}`n`n{Description}`n`n{Assignments}`n`n{Settings}`n`n{Diagnostics}`n`n{DataSections}' }
    }
  }
}

# ==============================
# Data access helpers
# ==============================
function Get-IntuneObjectTypes {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$ExportRoot)
  if (-not (Test-Path $ExportRoot)) { return @() }
  return (Get-ChildItem -Path $ExportRoot -Directory | Where-Object { $_.Name -notmatch '^_' } | Select-Object -ExpandProperty Name)
}
function Get-IntuneObjectList {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType
  )
  $typePath = Join-Path $ExportRoot $ObjectType
  if (-not (Test-Path $typePath)) { return @() }
  $items = @()
  foreach ($dir in (Get-ChildItem -Path $typePath -Directory)) {
    $id = $dir.Name
    $metaPath = Join-Path $dir.FullName 'meta.json'
    $rawPath  = Join-Path $dir.FullName 'raw.json'
    $flatPath = Join-Path $dir.FullName 'flat.json'
    $meta = $null; $raw = $null; $flat = $null
    if (Test-Path $metaPath) { try { $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json } catch { } }
    if (Test-Path $rawPath)  { try { $raw  = Get-Content -Raw -Path $rawPath  | ConvertFrom-Json } catch { } }
    if (Test-Path $flatPath) { try { $flat = Get-Content -Raw -Path $flatPath | ConvertFrom-Json } catch { } }
    $display = $null
    $candidates = @()
    if ($meta -and $meta.displayName) { $candidates += $meta.displayName }
    if ($raw -and $raw.name)         { $candidates += $raw.name }
    if ($raw -and $raw.displayName)  { $candidates += $raw.displayName }
    $candidates += $id
    foreach ($c in $candidates) { if ($c) { $display = $c; break } }
    $items += [PSCustomObject]@{
      id           = $id
      objectType   = $ObjectType
      displayName  = $display
      lastModified = if ($meta) { $meta.lastIntuneModified } else { $null }
      description  = if ($raw)  { $raw.description } else { $null }
      assignments  = if ($meta) { $meta.assignmentsSummary } else { $null }
      flat         = $flat
      meta         = $meta
      raw          = $raw
    }
  }
  return $items
}

# ==============================
# Utilities & IO
# ==============================
function Get-SafeFileName {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Name,[int]$MaxLength=120)
  $safe = $Name
  $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
  $regex = '[' + [Regex]::Escape($invalid) + ']'
  $safe = [Regex]::Replace($safe, $regex, '_')
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { $safe = $safe.Substring(0,$MaxLength) }
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unnamed' }
  return $safe
}
function Html-Encode { [CmdletBinding()] param([string]$Text)
  try { return [System.Web.HttpUtility]::HtmlEncode($Text) }
  catch {
    $t = $Text
    $t = $t -replace '&','&'
    $t = $t -replace '<','<'
    $t = $t -replace '>','>'
    $t = $t -replace '"','"'
    $t = $t -replace "'","'"
    return $t
  }
}
function Out-Md {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}
function Out-Html {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Content | Out-File -FilePath $Path -Encoding UTF8
}

# ==============================
# Template resolver (supports {Key} and {{ key }}, case-insensitive)
# ==============================
function Resolve-Template {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Template,[Parameter(Mandatory)][hashtable]$Values)
  $out = $Template
  foreach ($k in $Values.Keys) {
    $v = [string]$Values[$k]
    $out = $out.Replace('{'+$k+'}', $v)
    $out = $out.Replace('{'+($k.ToLower())+'}', $v)
  }
  foreach ($k in $Values.Keys) {
    $v = [string]$Values[$k]
    $pattern = '\{\{\s*' + [Regex]::Escape($k) + '\s*\}\}'
    $out = [Regex]::Replace($out, $pattern, { param($m) $v }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  }
  return $out
}

# ==============================
# Rendering helpers
# ==============================
function Get-TocHtml {
  [CmdletBinding()] param([Parameter(Mandatory)][string[]]$Items,[Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string]$Style,[switch]$IncludeAnchors)
  $lis = foreach ($i in $Items) { $id = ($i -replace '\s+','').ToLower(); $href = if ($IncludeAnchors) { "#$id" } else { '#' }; "<li><a href=`"$href`">$i</a></li>" }
  return "<div class=`"toc-card`"><h3>Contents</h3><ul>$($lis -join '')</ul></div>"
}
function Format-MdTable {
  [CmdletBinding()] param([array]$Rows,[string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) { return '(no data)' }
  $sb = New-Object System.Text.StringBuilder
  $headerLine = ($Headers -join ' | ')
  $sepLine = (($Headers | ForEach-Object { '---' }) -join ' | ')
  [void]$sb.AppendLine("| $headerLine |")
  [void]$sb.AppendLine("| $sepLine |")
  foreach ($r in $Rows) {
    $line = @()
    foreach ($h in $Headers) { $line += (([string]$r.$h) -replace '\r?\n',' ') }
    [void]$sb.AppendLine('| ' + ($line -join ' | ') + ' |')
  }
  return $sb.ToString()
}
function Format-HtmlTable {
  [CmdletBinding()] param([Parameter(Mandatory)][array]$Rows,[Parameter(Mandatory)][string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) { return '<div class="muted">(no data)</div>' }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<table><thead><tr>')
  foreach ($h in $Headers) { [void]$sb.AppendLine('<th>' + [System.Web.HttpUtility]::HtmlEncode($h) + '</th>') }
  [void]$sb.AppendLine('</tr></thead><tbody>')
  foreach ($r in $Rows) {
    [void]$sb.AppendLine('<tr>')
    foreach ($h in $Headers) {
      $val = $r.$h; if ($null -eq $val) { $val = '' }
      $cell = if ($h -eq 'Link') { [string]$val } else { [System.Web.HttpUtility]::HtmlEncode([string]$val) }
      [void]$sb.AppendLine('<td>' + $cell + '</td>')
    }
    [void]$sb.AppendLine('</tr>')
  }
  [void]$sb.AppendLine('</tbody></table>')
  return $sb.ToString()
}
function Render-CollapsibleMd { [CmdletBinding()] param([string]$Summary,[string]$Body,[bool]$Enabled)
  if (-not $Enabled) { return ("### " + $Summary + "`n`n" + $Body) }
  $block = @"
<details>
<summary>$Summary</summary>
$Body
</details>
"@
  return $block
}
function Render-CollapsibleHtml { [CmdletBinding()] param([string]$Summary,[string]$Body,[bool]$Enabled)
  if (-not $Enabled) { return ('<h3>' + (Html-Encode $Summary) + '</h3>' + "`n" + $Body) }
  return '<details><summary>' + (Html-Encode $Summary) + '</summary>' + "`n" + $Body + "`n" + '</details>'
}

# ==============================
# Writers
# ==============================
function Write-IntuneRootIndexMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][array]  $Summaries,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style
    )

    $template = Load-Template -Format 'Markdown' -Name 'Index'

    $rows = foreach ($s in ($Summaries | Sort-Object ObjectType)) {
        [PSCustomObject]@{
            'Object type'   = $s.ObjectType
            'Count'         = $s.Count
            'Last modified' = $(if ($s.LastModified) { (Get-Date $s.LastModified).ToString('yyyy-MM-dd') } else { '' })
            'Link'          = "$($s.ObjectType).md)"
        }
    }

    $table = Format-MdTable -Rows $rows -Headers @('Object type','Count','Last modified','Link')

    $out = Resolve-Template -Template $template -Values @{
        Table          = $table
        objectTypeList = $table
    }

    Out-Md -Path $Destination -Content $out
}

function Write-IntuneRootIndexHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][array]  $Summaries,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style
    )

    $styleProfile = $Script:DocumentationStyles[$Style]
    $template     = Load-Template -Format 'Html' -Name 'Index'

    $rows = foreach ($s in ($Summaries | Sort-Object ObjectType)) {
        [PSCustomObject]@{
            'Object type'   = $s.ObjectType
            'Count'         = $s.Count
            'Last modified' = $(if ($s.LastModified) { (Get-Date $s.LastModified).ToString('yyyy-MM-dd') } else { '' })
            'Link'          = '<a href="' + ($s.LinkBase + '.html') + '">' + $s.ObjectType + '</a>'
        }
    }

    $table      = Format-HtmlTable -Rows $rows -Headers @('Object type','Count','Last modified','Link')
    $title      = $(if ($styleProfile.Numbered) { '1. Intune Export Documentation' } else { 'Intune Export Documentation' })
    $breadcrumbs = '<div class="breadcrumbs">Intune Export</div>'
    $toc        = Get-TocHtml -Items @('Object Types') -Style $Style -IncludeAnchors
    $timestamp  = (Get-Date).ToString('yyyy-MM-dd HH:mm')

    $html = Resolve-Template -Template $template -Values @{
        Title           = $title
        Breadcrumbs     = $breadcrumbs
        TOC             = $toc
        ObjectTypesTable= $table
        Timestamp       = $timestamp
    }

    Out-Html -Path $Destination -Content $html
}

function Write-IntuneObjectTypeOverviewMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $ObjectType,
        [Parameter(Mandatory)][array]  $List,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style
    )

    $template = Load-Template -Format 'Markdown' -Name 'ObjectTypeOverview'

    $rows = @()
    foreach ($o in ($List | Sort-Object displayName)) {
        $safeName = Get-SafeFileName -Name $o.displayName
        $desc     = $(if ($o.description) { ($o.description -replace '\r?\n',' ') } else { '' })

        $rows += [PSCustomObject]@{
            'Name'          = $o.displayName
            'ID'            = $o.id
            'Description'   = $desc
            'Last modified' = $(if ($o.lastModified) { (Get-Date $o.lastModified).ToString('yyyy-MM-dd') } else { '' })
            'Assignments'   = $(if ($o.assignments) { $o.assignments.Count } else { 0 })
            'Link'          = "[open](../objects/$ObjectType/$safeName.md)"
        }
    }

    $table = Format-MdTable -Rows $rows -Headers @('Name','ID','Description','Last modified','Assignments','Link')

    $out = Resolve-Template -Template $template -Values @{
        ObjectType = $ObjectType
        Table      = $table
        objectList = $table
    }

    Out-Md -Path $Destination -Content $out
}

function Write-IntuneObjectTypeOverviewHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $ObjectType,
        [Parameter(Mandatory)][array]  $List,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style
    )

    $styleProfile = $Script:DocumentationStyles[$Style]
    $template     = Load-Template -Format 'Html' -Name 'ObjectTypeOverview'

    $rows = @()
    foreach ($o in ($List | Sort-Object displayName)) {
        $safeName = Get-SafeFileName -Name $o.displayName

        $rows += [PSCustomObject]@{
            'Name'          = $o.displayName
            'ID'            = $o.id
            'Description'   = $(if ($o.description) { (Html-Encode ($o.description -replace '\r?\n',' ')) } else { '' })
            'Last modified' = $(if ($o.lastModified) { (Get-Date $o.lastModified).ToString('yyyy-MM-dd') } else { '' })
            'Assignments'   = $(if ($o.assignments) { $o.assignments.Count } else { 0 })
            'Link'          = '<a href="../objects/' + (Html-Encode $ObjectType) + '/' + (Html-Encode $safeName) + '.html">open</a>'
        }
    }

    $table       = Format-HtmlTable -Rows $rows -Headers @('Name','ID','Description','Last modified','Assignments','Link')
    $title       = $(if ($styleProfile.Numbered) { "2. $ObjectType - Overview" } else { "$ObjectType - Overview" })
    $breadcrumbs = '<div class="breadcrumbs">Intune Export / ' + (Html-Encode $ObjectType) + '</div>'
    $toc         = Get-TocHtml -Items @('Objects') -Style $Style -IncludeAnchors
    $timestamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm')

    $html = Resolve-Template -Template $template -Values @{
        Title      = $title
        Breadcrumbs= $breadcrumbs
        TOC        = $toc
        ObjectTable= $table
        Timestamp  = $timestamp
    }

    Out-Html -Path $Destination -Content $html
}

function Write-IntuneObjectDetailMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $ObjectType,
        [Parameter(Mandatory)][string] $Id,
        [Parameter()][object] $Raw,
        [Parameter()][object] $Meta,
        [Parameter()][object] $Flat,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style,
        [switch] $IncludeRaw,
        [switch] $IncludeMeta,
        [switch] $IncludeFlat
    )

    $styleProfile = $Script:DocumentationStyles[$Style]
    $template     = Load-Template -Format 'Markdown' -Name 'ObjectDetail'

    # Compact mode for legacy template with {objectJson}
    if ($template -match '\{\s*objectJson\s*\}' -or $template -match '\{\{\s*objectJson\s*\}\}') {
        $rawJson = $(if ($Raw) { $Raw | ConvertTo-Json -Depth 50 } else { '(not available)' })
        $values  = @{
            objectType = $ObjectType
            objectName = $(if ($Meta.displayName) { $Meta.displayName } elseif ($Raw.name) { $Raw.name } else { $Id })
            objectJson = $rawJson
        }
        $out = Resolve-Template -Template $template -Values $values
        Out-Md -Path $Destination -Content $out
        return
    }

    # Rich mode
    $title = $(if ($Meta.displayName) { $Meta.displayName } elseif ($Raw.name) { $Raw.name } else { $Id })
    $desc  = ''
    if ($Raw -and $Raw.description) { $desc = ($Raw.description -replace '\r?\n','  \n') }

    # Assignments
    $assignRows = @()
    if ($Meta -and $Meta.assignmentsSummary) {
        foreach ($a in $Meta.assignmentsSummary) {
            $assignRows += [PSCustomObject]@{
                'Target' = 'Group'
                'Name'   = $a.groupDisplayName
                'Id'     = $a.groupId
                'Filter' = $(if ($a.filterId) { $a.filterId } else { '' })
                'Type'   = $(if ($a.filterType) { $a.filterType } else { '' })
            }
        }
    }
    $assignTable = $(if ($assignRows.Count -gt 0) { Format-MdTable -Rows $assignRows -Headers @('Target','Name','Id','Filter','Type') } else { '(none)' })

    # Settings (with SC-children visibility)
    $flatRows = @()
    if ($Flat) {
        foreach ($s in $Flat) {
            $val = $s.value
            if ($val -is [System.Collections.IDictionary]) { $val = ($val | ConvertTo-Json -Depth 20) }
            elseif ($val -is [System.Collections.IList])   { $val = ($val -join ', ') }

            $flatRows += [PSCustomObject]@{
                'Path'        = $s.path
                'Value'       = $val
                'Friendly'    = $(if ($s.friendlyValue) { $s.friendlyValue } else { '' })
                'CSP'         = $(if ($s.cspEquivalent) { $s.cspEquivalent } else { '' })
                'Description' = $(if ($s.scDesc)       { $s.scDesc } else { '' })
                'Risk'        = $(if ($s.risk)         { $s.risk } else { '' })
            }

            if ($s.PSObject.Properties.Name -contains 'children' -and $s.children) {
                foreach ($c in $s.children) {
                    $cv = $c.value
                    if     ($cv -is [System.Collections.IDictionary]) { $cv = ($cv | ConvertTo-Json -Depth 20) }
                    elseif ($cv -is [System.Collections.IList])       { $cv = ($cv -join ', ') }

                    $flatRows += [PSCustomObject]@{
                        'Path'        = $c.path
                        'Value'       = $cv
                        'Friendly'    = ''
                        'CSP'         = ''
                        'Description' = ''
                        'Risk'        = ''
                    }
                }
            }
        }
    }

    $settingsTable = $(if ($flatRows.Count -gt 0)
        { Format-MdTable -Rows $flatRows -Headers @('Path','Value','Friendly','CSP','Description','Risk') }
        else { '(no flattened settings found)' })

    # Diagnostics
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
    if ($diag.Count -eq 0) { $diag += '(no diagnostics)' }

    # Optional raw/meta/flat data dumps
    $dataSections = ''
    if ($IncludeRaw)  {
        $json  = $(if ($Raw)  { ($Raw  | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $block = "``````json`n$json`n``````"
        $dataSections += (Render-CollapsibleMd -Summary 'raw.json'  -Body $block -Enabled:$styleProfile.Collapsible) + "`n"
    }
    if ($IncludeMeta) {
        $json  = $(if ($Meta) { ($Meta | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $block = "``````json`n$json`n``````"
        $dataSections += (Render-CollapsibleMd -Summary 'meta.json' -Body $block -Enabled:$styleProfile.Collapsible) + "`n"
    }
    if ($IncludeFlat) {
        $json  = $(if ($Flat) { ($Flat | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $block = "``````json`n$json`n``````"
        $dataSections += (Render-CollapsibleMd -Summary 'flat.json' -Body $block -Enabled:$styleProfile.Collapsible) + "`n"
    }

    $out = Resolve-Template -Template $template -Values @{
        Title       = $title
        Description = $(if ($desc) { "## Description`n$desc" } else { '' })
        Assignments = ("## Assignments`n$assignTable")
        Settings    = ("## Settings`n$settingsTable")
        Diagnostics = ("## Diagnostics`n" + ($diag -join "`n"))
        DataSections= $(if ($dataSections) { "## Data`n$dataSections" } else { '' })
    }

    Out-Md -Path $Destination -Content $out
}

function Write-IntuneObjectDetailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $ObjectType,
        [Parameter(Mandatory)][string] $Id,
        [Parameter()][object] $Raw,
        [Parameter()][object] $Meta,
        [Parameter()][object] $Flat,
        [Parameter(Mandatory)][ValidateSet('Enterprise','Rich')][string] $Style,
        [switch] $IncludeRaw,
        [switch] $IncludeMeta,
        [switch] $IncludeFlat
    )

    $styleProfile = $Script:DocumentationStyles[$Style]
    $template     = Load-Template -Format 'Html' -Name 'ObjectDetail'

    $title       = $(if ($Meta.displayName) { $Meta.displayName } elseif ($Raw.name) { $Raw.name } else { $Id })
    $breadcrumbs = '<div class="breadcrumbs">Intune Export / ' + (Html-Encode $ObjectType) + ' / ' + (Html-Encode $title) + '</div>'

    # Description
    $descHtml = ''
    if ($Raw -and $Raw.description) {
        $enc     = Html-Encode ($Raw.description -replace '\r?\n','<br/>')
        $descHtml = '<p>' + $enc + '</p>'
    }

    # Assignments
    $assignRows = @()
    if ($Meta -and $Meta.assignmentsSummary) {
        foreach ($a in $Meta.assignmentsSummary) {
            $assignRows += [PSCustomObject]@{
                'Target' = 'Group'
                'Name'   = $a.groupDisplayName
                'Id'     = $a.groupId
                'Filter' = $(if ($a.filterId) { $a.filterId } else { '' })
                'Type'   = $(if ($a.filterType) { $a.filterType } else { '' })
            }
        }
    }
    $assignHtml = $(if ($assignRows.Count -gt 0)
        { Format-HtmlTable -Rows $assignRows -Headers @('Target','Name','Id','Filter','Type') }
        else { '<div class="muted">(none)</div>' })

    # Settings (with SC-children visibility)
    $flatRows = @()
    if ($Flat) {
        foreach ($s in $Flat) {
            $val = $s.value
            if ($val -is [System.Collections.IDictionary]) { $val = ($val | ConvertTo-Json -Depth 20) }
            elseif ($val -is [System.Collections.IList])   { $val = ($val -join ', ') }

            $flatRows += [PSCustomObject]@{
                'Path'        = $s.path
                'Value'       = $val
                'Friendly'    = $(if ($s.friendlyValue) { $s.friendlyValue } else { '' })
                'CSP'         = $(if ($s.cspEquivalent) { $s.cspEquivalent } else { '' })
                'Description' = $(if ($s.scDesc)       { $s.scDesc } else { '' })
                'Risk'        = $(if ($s.risk)         { $s.risk } else { '' })
            }

            if ($s.PSObject.Properties.Name -contains 'children' -and $s.children) {
                foreach ($c in $s.children) {
                    $cv = $c.value
                    if     ($cv -is [System.Collections.IDictionary]) { $cv = ($cv | ConvertTo-Json -Depth 20) }
                    elseif ($cv -is [System.Collections.IList])       { $cv = ($cv -join ', ') }

                    $flatRows += [PSCustomObject]@{
                        'Path'        = $c.path
                        'Value'       = $cv
                        'Friendly'    = ''
                        'CSP'         = ''
                        'Description' = ''
                        'Risk'        = ''
                    }
                }
            }
        }
    }

    $settingsHtml = $(if ($flatRows.Count -gt 0)
        { Format-HtmlTable -Rows $flatRows -Headers @('Path','Value','Friendly','CSP','Description','Risk') }
        else { '<div class="muted">(no flattened settings found)</div>' })

    # Diagnostics
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
    if ($diagItems.Count -eq 0) { $diagItems += '<div class="muted">(no diagnostics)</div>' }
    $diagHtml = ($diagItems -join "`n")

    # Optional data sections
    $dataHtml = ''
    if ($IncludeRaw)  {
        $json = $(if ($Raw)  { ($Raw  | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $pre  = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
        $dataHtml += (Render-CollapsibleHtml -Summary 'raw.json'  -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
    }
    if ($IncludeMeta) {
        $json = $(if ($Meta) { ($Meta | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $pre  = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
        $dataHtml += (Render-CollapsibleHtml -Summary 'meta.json' -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
    }
    if ($IncludeFlat) {
        $json = $(if ($Flat) { ($Flat | ConvertTo-Json -Depth 50) } else { '(not available)' })
        $pre  = '<pre><code class="language-json">' + (Html-Encode $json) + '</code></pre>'
        $dataHtml += (Render-CollapsibleHtml -Summary 'flat.json' -Body $pre -Enabled:$styleProfile.Collapsible) + "`n"
    }

    $toc       = Get-TocHtml -Items @('Description','Assignments','Settings','Diagnostics','Data') -Style $Style -IncludeAnchors
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

    $html = Resolve-Template -Template $template -Values @{
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
# Public entry points
# ==============================
function New-IntuneDocumentationForObject {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$Id,
    [ValidateSet('Enterprise','Rich')][string]$Style = 'Enterprise',
    [ValidateSet('Markdown','Html','Both')][string]$Output = 'Markdown',
    [switch]$IncludeRaw,[switch]$IncludeMeta,[switch]$IncludeFlat)

  Set-IntuneDocumentationStyle -Style $Style
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

  $displayName = ($meta.displayName, $raw.name, $raw.displayName, $Id | Where-Object { $_ } | Select-Object -First 1)
  $safeName = Get-SafeFileName -Name $displayName
  $destBase = Join-Path $objDocs $safeName

  if ($Output -in @('Markdown','Both')) { Write-IntuneObjectDetailMarkdown -Destination ("{0}.md" -f $destBase) -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat }
  if ($Output -in @('Html','Both'))     { Write-IntuneObjectDetailHtml     -Destination ("{0}.html" -f $destBase) -ObjectType $ObjectType -Id $Id -Raw $raw -Meta $meta -Flat $flat -Style $Script:DocStyle -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat }
  return $destBase
}

function New-IntuneDocumentation {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$ExportRoot,
    [ValidateSet('Enterprise','Rich')][string]$Style = 'Enterprise',
    [ValidateSet('Markdown','Html','Both')][string]$Output = 'Markdown',
    [switch]$IncludeRaw,[switch]$IncludeMeta,[switch]$IncludeFlat)

  Set-IntuneDocumentationStyle -Style $Style
  $docsRoot = Join-Path $ExportRoot '_docs'
  $byType   = Join-Path $docsRoot 'by-type'
  $objects  = Join-Path $docsRoot 'objects'
  foreach ($d in @($docsRoot,$byType,$objects)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

  $types = Get-IntuneObjectTypes -ExportRoot $ExportRoot
  $summaries = @()
  foreach ($t in $types) {
    $list = Get-IntuneObjectList -ExportRoot $ExportRoot -ObjectType $t
    if (-not $list) { continue }

    foreach ($o in $list) {
      New-IntuneDocumentationForObject -ExportRoot $ExportRoot -ObjectType $t -Id $o.id -Style $Script:DocStyle -Output $Output -IncludeRaw:$IncludeRaw -IncludeMeta:$IncludeMeta -IncludeFlat:$IncludeFlat | Out-Null
    }

    $typeBase = Join-Path $byType $t
    if ($Output -in @('Both','Markdown')) { Write-IntuneObjectTypeOverviewMarkdown -Destination ("{0}.md" -f $typeBase)   -ObjectType $t -List $list -Style $Script:DocStyle }
    if ($Output -in @('Both','Html'))     { Write-IntuneObjectTypeOverviewHtml     -Destination ("{0}.html" -f $typeBase) -ObjectType $t -List $list -Style $Script:DocStyle }

    $last = ($list | Where-Object { $_.lastModified } | Sort-Object lastModified -Descending | Select-Object -First 1).lastModified
    $summaries += [PSCustomObject]@{ ObjectType=$t; Count=$list.Count; LastModified=$last; LinkBase=(Join-Path 'by-type' $t) }
  }

  $rootBase = Join-Path $docsRoot 'index'
  if ($Output -in @('Both','Markdown')) { Write-IntuneRootIndexMarkdown -Destination ("{0}.md"   -f $rootBase) -Summaries $summaries -Style $Script:DocStyle }
  if ($Output -in @('Both','Html'))     { Write-IntuneRootIndexHtml     -Destination ("{0}.html" -f $rootBase) -Summaries $summaries -Style $Script:DocStyle }
}

Export-ModuleMember -Function New-IntuneDocumentation, New-IntuneDocumentationForObject, Set-IntuneDocumentationStyle, Get-IntuneDocumentationStyle
