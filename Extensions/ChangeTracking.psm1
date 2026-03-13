<# 
.SYNOPSIS
    Change Tracking + Flattening module for IntuneManagement

.DESCRIPTION
    Processes staging exports into deterministic, Git-friendly outputs:
        - Canonical raw.json + meta.json
        - flat.json (flattened settings) with friendly values
        - Assignment summaries + diagnostics
        - Optional archive of original staging files
        - Optional deleted-state marking

    Also includes a Settings Catalog definition cache builder calling Graph via
    the Intune Manager's MSGraph.psm1 -> Invoke-GraphRequest.
    Cache lives under: <ExportRoot>/_metadata/SettingsCatalogDefinitions
    (never inside the app root; keeps exported dataset self-contained.)

.NOTES
    Works both inside the IntuneManagement app and in standalone PowerShell.
    Inside the app, Core.psm1 sets $global:AppRootFolder = $PSScriptRoot.

    Graph access helper used: Invoke-GraphRequest (Extensions/MSGraph.psm1)
    
    Author: Maik Koster
#>


# module configuration (can be overridden with Set-ChangeTrackingConfig)
$Script:ChangeTrackingConfig = @{
    KeepOriginalExport    = $true   # if $true, staging files are never deleted
    ArchiveOriginalExport = $true    # if $true, staging files moved into ArchiveRoot
    ArchiveRoot           = "$PSScriptRoot/../_archive_original_exports"
    UpdateDeletedStates   = $false   # if $true, mark unseen objects as deleted
    EnableLogging         = $false   # if $true, Write-Log is enabled
}


# CONFIG OVERRIDE ENTRY POINT
function Set-ChangeTrackingConfig {
    param([hashtable]$Config)
    if ($null -ne $Config) {
        foreach ($k in $Config.Keys) {
            $Script:ChangeTrackingConfig[$k] = $Config[$k] 
        }
    }
}

function Invoke-InitializeModule {
    <#
        .SYNOPSIS
            Initializes the ChangeTracking module.

        .DESCRIPTION
            Registers the module, configuration, and prepares internal state.
            Called automatically by the host application.
    #>

    Write-Verbose "[ChangeTracking] Module initialized."
    
    # --- Register a settings section for the UI (good neighbor pattern) ---
    # Matches pattern in EndpointManager.psm1 -> adds a titled section in Settings. 
    $global:appSettingSections += (New-Object PSObject -Property @{
            Title    = "Change Tracking"
            Id       = "ChangeTracking"
            Values   = @()
            Priority = 20
        })

    # Add settings controls – use the same typed controls style as other modules. 
    # Toggle: Enable logging
    Add-SettingsObject (New-Object PSObject -Property @{
            Title        = "Enable logging"
            Key          = "CT_EnableLogging"
            Type         = "Boolean"
            DefaultValue = $false
            SubPath      = "ChangeTracking"
            Description  = "Write Change Tracking logs to <ExportRoot>/_logs."
        }) "ChangeTracking"

    # Toggle: Archive processed staging files
    Add-SettingsObject (New-Object PSObject -Property @{
            Title        = "Archive processed staging files"
            Key          = "CT_ArchiveOriginalExport"
            Type         = "Boolean"
            DefaultValue = $true
            SubPath      = "ChangeTracking"
            Description  = "If on, move staging files to a single archive root while preserving subfolders."
        }) "ChangeTracking"

    # Folder picker: Archive root
    Add-SettingsObject (New-Object PSObject -Property @{
            Title        = "Archive root folder"
            Key          = "CT_ArchiveRoot"
            Type         = "Folder"
            DefaultValue = "$PSScriptRoot\..\_archive_original_exports"
            SubPath      = "ChangeTracking"
            Description  = "Root folder where processed staging files are archived into their original subfolder structure."
        }) "ChangeTracking"

    # Toggle: Mark unseen as deleted
    Add-SettingsObject (New-Object PSObject -Property @{
            Title        = "Mark unseen as deleted"
            Key          = "CT_UpdateDeletedStates"
            Type         = "Boolean"
            DefaultValue = $false
            SubPath      = "ChangeTracking"
            Description  = "If on, items not encountered in the current run are marked state='deleted' in meta.json."
        }) "ChangeTracking"
}

function Invoke-IntuneExportChangeTracking {
    param(
        [Parameter(Mandatory)] [string]$StagingPath,
        [Parameter(Mandatory)] [string]$ExportRoot,
        [string]$ArchiveRoot,
        [Nullable[bool]]$EnableLogging,
        [Nullable[bool]]$ArchiveOriginalExport,
        [Nullable[bool]]$UpdateDeletedStates,
        [switch]$SkipFlattening   # allow disabling flattening if needed
    )

    # Resolve settings (param > app-setting > default)
    $hasSettings = (Get-Command Get-Setting -ErrorAction SilentlyContinue) -ne $null

    # ArchiveRoot
    if ($PSBoundParameters.ContainsKey('ArchiveRoot')) { 
    }
    elseif ($hasSettings) {
        $ArchiveRoot = Get-Setting "ChangeTracking" "CT_ArchiveRoot" "$PSScriptRoot\..\_archive_original_exports" 
    }
    else {
        $ArchiveRoot = "$PSScriptRoot\..\_archive_original_exports" 
    }

    # EnableLogging
    if ($PSBoundParameters.ContainsKey('EnableLogging')) {
        $EnableLogging = [bool]$EnableLogging 
    }
    elseif ($hasSettings) {
        $EnableLogging = Get-Setting "ChangeTracking" "CT_EnableLogging" $false 
    }
    else {
        $EnableLogging = $false 
    }

    # ArchiveOriginalExport
    if ($PSBoundParameters.ContainsKey('ArchiveOriginalExport')) {
        $ArchiveOriginalExport = [bool]$ArchiveOriginalExport 
    }
    elseif ($hasSettings) {
        $ArchiveOriginalExport = Get-Setting "ChangeTracking" "CT_ArchiveOriginalExport" $true 
    }
    else {
        $ArchiveOriginalExport = $true 
    }

    # UpdateDeletedStates
    if ($PSBoundParameters.ContainsKey('UpdateDeletedStates')) {
        $UpdateDeletedStates = [bool]$UpdateDeletedStates 
    }
    elseif ($hasSettings) {
        $UpdateDeletedStates = Get-Setting "ChangeTracking" "CT_UpdateDeletedStates" $false 
    }
    else {
        $UpdateDeletedStates = $false 
    }

    # Apply
    $Script:ChangeTrackingConfig.EnableLogging = $EnableLogging
    $Script:ChangeTrackingConfig.ArchiveOriginalExport = $ArchiveOriginalExport
    $Script:ChangeTrackingConfig.UpdateDeletedStates = $UpdateDeletedStates
    $Script:ChangeTrackingConfig.ArchiveRoot = $ArchiveRoot

    if (-not (Test-Path $StagingPath)) {
        throw "StagingPath not found: $StagingPath" 
    }
    if (-not (Test-Path $ExportRoot)) {
        New-Item -ItemType Directory -Force -Path $ExportRoot | Out-Null 
    }

    $Script:CurrentStagingRoot = (Resolve-Path $StagingPath).Path

    # Logging file
    if ($Script:ChangeTrackingConfig.EnableLogging) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logDir = Join-Path $ExportRoot "_logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null 
        }
        $Script:LogPath = Join-Path $logDir "ChangeTracking-$timestamp.log"
        Write-Log -Message "Change Tracking Started" -Severity Info
    }

    # Counters
    $processed = 0; $changed = 0; $unchanged = 0; $archived = 0; $deleted = 0
    $seen = @{}

    $files = Get-ChildItem -Path $StagingPath -Recurse -File -Filter *.json
    foreach ($file in $files) {
        $processed++
        Write-Verbose "[ChangeTracking] Processing $($file.FullName)"
        Write-Log -Message "Processing $($file.FullName)" -Severity Verbose

        $json = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
        $objectId = $json.id
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Warning "Skipping file without id: $($file.FullName)"; Write-Log -Message "Skipping file without id: $($file.FullName)" -Severity Warning
            Handle-StagingFile -File $file -archivedRef ([ref]$archived); continue
        }

        $objectType = Split-Path $file.DirectoryName -Leaf; if ([string]::IsNullOrWhiteSpace($objectType)) {
            $objectType = 'Unknown' 
        }
        if (-not $seen.ContainsKey($objectType)) {
            $seen[$objectType] = New-Object System.Collections.Generic.HashSet[string] 
        }
        [void]$seen[$objectType].Add($objectId)

        $targetDir = Join-Path $ExportRoot (Join-Path $objectType $objectId)
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        $rawPath = Join-Path $targetDir 'raw.json'
        $metaPath = Join-Path $targetDir 'meta.json'

        $canonical = ConvertTo-CanonicalJson -Object $json
        $hash = Get-ObjectHash -CanonicalJson $canonical

        $existingMeta = $null; if (Test-Path $metaPath) {
            try {
                $existingMeta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json 
            }
            catch {
                $existingMeta = $null 
            } 
        }
        $previousHash = if ($existingMeta) {
            $existingMeta.hash 
        }
        else {
            $null 
        }

        # Assignment summary + diagnostics precompute (will be merged into meta)
        $assignmentSummary = @()
        $assignmentDiagnostics = @{ missingGroups = @(); nonSecurityGroups = @(); filtersReferencedButMissing = @(); filtersPresent = $false }
        if ($json.assignments) {
            foreach ($a in $json.assignments) {
                $gid = $a.target.groupId; $fid = $a.target.deviceAndAppManagementAssignmentFilterId
                if ($fid) {
                    $assignmentDiagnostics.filtersPresent = $true 
                }
                $gName = "(unknown)"; $isSec = $null
                if ($gid) {
                    $gFolder = Join-Path $ExportRoot ("Groups/" + $gid); $gRaw = Join-Path $gFolder 'raw.json'
                    if (Test-Path $gRaw) {
                        try {
                            $gJson = Get-Content -Raw -Path $gRaw | ConvertFrom-Json; $gName = $gJson.displayName; $isSec = $gJson.securityEnabled; if ($isSec -eq $false) {
                                $assignmentDiagnostics.nonSecurityGroups += $gid 
                            } 
                        }
                        catch {
                            $assignmentDiagnostics.missingGroups += $gid 
                        } 
                    }
                    else {
                        $assignmentDiagnostics.missingGroups += $gid 
                    }
                }
                $assignmentSummary += [PSCustomObject]@{ targetType = 'group'; groupId = $gid; groupDisplayName = $gName; filterId = $fid; filterType = $a.target.deviceAndAppManagementAssignmentFilterType }
            }
        }

        if ($previousHash -and ($previousHash -eq $hash)) {
            $unchanged++
            Write-Verbose "[ChangeTracking] No change for $objectType/$objectId"; Write-Log -Message "Unchanged: $objectType/$objectId" -Severity Verbose
            if ($existingMeta -and $existingMeta.state -ne 'active') {
                $existingMeta.state = 'active'; ($existingMeta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8 
            }
            # Even if unchanged, still archive/remove staging file
            Handle-StagingFile -File $file -archivedRef ([ref]$archived)
            continue
        }

        # Changed
        $changed++
        Write-Verbose "[ChangeTracking] Changed $objectType/$objectId"; Write-Log -Message "Changed: $objectType/$objectId" -Severity Info
        $canonical | Out-File -FilePath $rawPath -Encoding utf8

        # Build flat.json unless explicitly skipped
        if (-not $SkipFlattening) {
            $flat = Convert-ToFlatObject -JsonObject $json -ObjectType $objectType -ExportRoot $ExportRoot
            ($flat | ConvertTo-Json -Depth 50) | Out-File (Join-Path $targetDir 'flat.json') -Encoding utf8
        }

        # meta.json
        $meta = [ordered]@{
            id                 = $json.id
            displayName        = ($json.displayName, $json.name | Where-Object { $_ } | Select-Object -First 1)
            type               = $objectType
            category           = $null
            state              = 'active'
            lastIntuneModified = $json.lastModifiedDateTime
            hash               = $hash
            roleScopeTagIds    = $json.roleScopeTagIds
            assignmentsSummary = $assignmentSummary
            diagnostics        = @{ assignments = $assignmentDiagnostics }
            flattened          = (-not $SkipFlattening)
        }

        # If Groups, add service provisioning warnings (if present)
        if ($objectType -eq 'Groups' -and $json.serviceProvisioningErrors) {
            $svcErrors = @(); foreach ($e in $json.serviceProvisioningErrors) {
                $svcErrors += [PSCustomObject]@{ serviceInstance = $e.serviceInstance; isResolved = $e.isResolved; note = "See raw.json/serviceProvisioningErrors" } 
            }
            $meta.diagnostics.serviceProvisioningWarnings = $svcErrors
        }

        ($meta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8
        Handle-StagingFile -File $file -archivedRef ([ref]$archived)
    }

    if ($Script:ChangeTrackingConfig.UpdateDeletedStates) {
        $deleted += (Update-DeletedStates -ExportRoot $ExportRoot -Seen $seen) 
    }

    $summary = @(
        "[ChangeTracking] Summary:",
        "  Processed : $processed",
        "  Changed   : $changed",
        "  Unchanged : $unchanged",
        "  Archived  : $archived"
    )
    if ($Script:ChangeTrackingConfig.UpdateDeletedStates) {
        $summary += "  Deleted   : $deleted" 
    }
    $summaryText = $summary -join [Environment]::NewLine
    Write-Verbose $summaryText
    if ($Script:ChangeTrackingConfig.EnableLogging) {
        Write-Log -Message $summaryText -AsPlainText -Severity Info 
    }
}

function ConvertTo-CanonicalJson {
    <#
        .SYNOPSIS
            Normalizes an arbitrary Graph JSON object to a deterministic structure.
        .NOTES
            Rules:
            - Remove keys starting with '@odata.'
            - Remove keys starting with '#'
            - Remove keys that end with '@odata.type'
            - Sort keys lexicographically at each level
            - Preserve arrays (order as provided by API)
            - Preserve nulls, booleans, numbers, strings
            - Use stable formatting (2-space indentation when written to file)
    #>
    param([Parameter(Mandatory)] [object]$Object)

    function Clean-Node([object]$node) {
        if ($node -is [System.Collections.IDictionary]) {
            $new = @{}
            foreach ($key in $node.Keys | Sort-Object) {
                if ($key -like '@odata.*') {
                    continue 
                }
                if ($key -like '#*') {
                    continue 
                }
                if ($key -like '*@odata.type') {
                    continue 
                }
                $new[$key] = Clean-Node $node[$key]
            }
            return $new
        }
        elseif ($node -is [System.Collections.IList]) {
            return @($node | ForEach-Object { Clean-Node $_ })
        }
        return $node
    }

    $clean = Clean-Node $Object

    # Two-pass convert to ensure stable ordering and indentation
    $compressed = $clean | ConvertTo-Json -Depth 50 -Compress
    $rehydrated = $compressed | ConvertFrom-Json
    return ($rehydrated | ConvertTo-Json -Depth 50)
}

function Get-ObjectHash {
    <#
        .SYNOPSIS
            Returns hex lowercase SHA-256 of a canonical JSON string.
    #>
    param([Parameter(Mandatory)] [string]$CanonicalJson)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalJson)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
}

# HANDLE STAGING FILE (delete or archive)
function Handle-StagingFile {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [ref]$archivedRef
    )

    if ($Script:ChangeTrackingConfig.KeepOriginalExport) {
        return 
    }

    if ($Script:ChangeTrackingConfig.ArchiveOriginalExport) {
        if (-not (Test-Path $Script:ChangeTrackingConfig.ArchiveRoot)) {
            New-Item -ItemType Directory -Force -Path $Script:ChangeTrackingConfig.ArchiveRoot | Out-Null
        }

        $relative = Get-RelativePath -BasePath $Script:CurrentStagingRoot -FullPath $File.FullName

        $destination = Join-Path $Script:ChangeTrackingConfig.ArchiveRoot $relative
        $destDir = Split-Path $destination -Parent
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null

        Move-Item -Path $File.FullName -Destination $destination -Force
        $archivedRef.Value++
    }
    else {
        Remove-Item -Path $File.FullName -Force
    }
}

function Update-DeletedStates {
    <#
        .SYNOPSIS
            Marks objects in ExportRoot as deleted if they were not present in this run.
        .WARNING
            Use with care. In selective exports, this could mark unrelated items as deleted.
            Default is disabled. Enable by setting UpdateDeletedStates = $true via Set-ChangeTrackingConfig.
    #>
    param(
        [Parameter(Mandatory)] [string]$ExportRoot,
        [Parameter(Mandatory)] [hashtable]$Seen
    )

    $deletedCount = 0

    foreach ($typeDir in Get-ChildItem -Path $ExportRoot -Directory) {
        $objectType = $typeDir.Name
        $seenSet = if ($Seen.ContainsKey($objectType)) {
            $Seen[$objectType] 
        }
        else {
            New-Object System.Collections.Generic.HashSet[string] 
        }

        foreach ($idDir in Get-ChildItem -Path $typeDir.FullName -Directory) {
            $id = $idDir.Name
            $metaPath = Join-Path $idDir.FullName 'meta.json'
            if (-not (Test-Path $metaPath)) {
                continue 
            }
            if ($seenSet.Contains($id)) {
                continue 
            }

            try {
                $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
            }
            catch {
                continue 
            }

            if ($meta.state -ne 'deleted') {
                $meta.state = 'deleted'
                ($meta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8
                Write-Log -Message "Marked deleted: $objectType/$id" -Severity Warning
                $deletedCount++
            }
        }
    }

    return $deletedCount

}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    # Normalize both paths
    $base = (Resolve-Path $BasePath).Path.TrimEnd('\', '/')
    $full = (Resolve-Path $FullPath).Path

    if ($full.StartsWith($base, [System.StringComparison]::InvariantCultureIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart('\', '/')
    }

    # Fallback: no shared root → return filename
    return (Split-Path $full -Leaf)
}

function Invoke-ChangeTrackingCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StagingPath,
        [Parameter(Mandatory)] [string]$ExportRoot,
        [string]$ArchiveRoot,
        [switch]$EnableLogging,
        [switch]$ArchiveOriginalExport,
        [switch]$UpdateDeletedStates
    )

    $hasSettings = (Get-Command Get-Setting -ErrorAction SilentlyContinue) -ne $null

    if (-not $PSBoundParameters.ContainsKey('ArchiveRoot')) {
        if ($hasSettings) {
            $ArchiveRoot = Get-Setting "ChangeTracking" "CT_ArchiveRoot" "$PSScriptRoot\..\_archive_original_exports" 
        }
        else {
            $ArchiveRoot = "$PSScriptRoot\..\_archive_original_exports" 
        }
    }

    $logPref = if ($PSBoundParameters.ContainsKey('EnableLogging')) {
        $EnableLogging.IsPresent 
    }
    else {
        if ($hasSettings) {
            Get-Setting "ChangeTracking" "CT_EnableLogging" $false 
        }
        else {
            $false 
        } 
    }
    $arcPref = if ($PSBoundParameters.ContainsKey('ArchiveOriginalExport')) {
        $ArchiveOriginalExport.IsPresent 
    }
    else {
        if ($hasSettings) {
            Get-Setting "ChangeTracking" "CT_ArchiveOriginalExport" $true 
        }
        else {
            $true 
        } 
    }
    $delPref = if ($PSBoundParameters.ContainsKey('UpdateDeletedStates')) {
        $UpdateDeletedStates.IsPresent 
    }
    else {
        if ($hasSettings) {
            Get-Setting "ChangeTracking" "CT_UpdateDeletedStates" $false 
        }
        else {
            $false 
        } 
    }

    Invoke-IntuneExportChangeTracking -StagingPath $StagingPath -ExportRoot $ExportRoot -ArchiveRoot $ArchiveRoot -EnableLogging:$logPref -ArchiveOriginalExport:$arcPref -UpdateDeletedStates:$delPref -Verbose
}

function Invoke-IntuneExportWithFlattening {
    <#
      .SYNOPSIS
        Full pipeline: (optional) update Settings Catalog cache, then run ChangeTracking + flattening.
      .PARAMETER StagingPath
        Root folder containing exported JSONs from IntuneManager's export.
      .PARAMETER ExportRoot
        Output root for canonical structure.
      .PARAMETER RefreshSettingsCatalogCache
        If present, refreshes Settings Catalog definitions under <ExportRoot>/_metadata ... before processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StagingPath,
        [Parameter(Mandatory)] [string]$ExportRoot,
        [switch]$RefreshSettingsCatalogCache,
        [string]$ArchiveRoot,
        [Nullable[bool]]$EnableLogging,
        [Nullable[bool]]$ArchiveOriginalExport,
        [Nullable[bool]]$UpdateDeletedStates
    )

    if ($RefreshSettingsCatalogCache) {
        Ensure-MSGraphModule
        Update-IntuneSettingsCatalogCache -ExportRoot $ExportRoot -Force -Verbose
    }

    Invoke-IntuneExportChangeTracking -StagingPath $StagingPath -ExportRoot $ExportRoot -ArchiveRoot $ArchiveRoot -EnableLogging:$EnableLogging -ArchiveOriginalExport:$ArchiveOriginalExport -UpdateDeletedStates:$UpdateDeletedStates -Verbose
}

function Parse-OmaKeyValueString {
    param([string]$val)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($val)) {
        return $result 
    }
    foreach ($pair in ($val -split ',')) {
        $parts = $pair.Trim() -split ':', 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim(); $v = $parts[1].Trim()
            if ($v -as [int]) {
                $v = [int]$v 
            }
            $result[$key] = $v
        }
    }
    return $result
}


function Convert-ToFlatObject {
    param(
        [Parameter(Mandatory)] [object]$JsonObject,
        [Parameter(Mandatory)] [string]$ObjectType,
        [Parameter(Mandatory)] [string]$ExportRoot
    )

    $flat = @()

    # Assignment Filters
    if ($ObjectType -in @('AssignmentFilters', 'AssignmentFilter', 'Filters', 'Filter')) {
        if ($JsonObject.rule) {
            $flat += [PSCustomObject]@{ path = "filter.rule"; type = "string"; value = $JsonObject.rule } 
        }
        if ($JsonObject.platform) {
            $flat += [PSCustomObject]@{ path = "filter.platform"; type = "string"; value = $JsonObject.platform } 
        }
        return $flat
    }

    # Settings Catalog (presence of 'settings')
    if ($JsonObject.settings) {
        function Flatten-SCSettingInner {
            param([object]$s)
            $inst = $s.settingInstance
            $sid = $inst.settingDefinitionId
            $def = Get-SettingsCatalogDefinition -DefinitionId $sid -ExportRoot $ExportRoot
            $out = [ordered]@{
                path          = $sid
                scName        = $def.displayName
                scDesc        = $def.description
                risk          = $def.riskLevel
                keywords      = $def.keywords
                cspEquivalent = if ($def.baseUri -and $def.offsetUri) {
                    $def.baseUri + $def.offsetUri 
                }
                else {
                    $null 
                }
            }

            if ($inst.'@odata.type' -like '*ChoiceSettingInstance') {
                $itemId = $inst.choiceSettingValue.value
                $valueInt = $null
                if ($itemId -match '_(\d+)$') {
                    $valueInt = [int]$Matches[1] 
                }
                $friendly = $null
                if ($def.options) {
                    foreach ($opt in $def.options) {
                        if ($opt.itemId -eq $itemId) {
                            $friendly = $opt.displayName 
                        } 
                    }
                }
                $out.type = 'choice'; $out.value = $valueInt; $out.valueId = $itemId; $out.friendlyValue = $friendly
                if ($inst.choiceSettingValue.children) {
                    $out.children = @()
                    foreach ($child in $inst.choiceSettingValue.children) {
                        $out.children += @{ path = $child.settingDefinitionId; type = 'simple'; value = $child.simpleSettingValue.value }
                    }
                }
                return $out
            }

            if ($inst.'@odata.type' -like '*SimpleSettingInstance') {
                $out.type = 'simple'; $out.value = $inst.simpleSettingValue.value; return $out
            }
            if ($inst.'@odata.type' -like '*SimpleSettingCollectionInstance') {
                $out.type = 'stringCollection'; $out.value = $inst.simpleSettingCollectionValue; return $out
            }
            return $out
        }

        foreach ($s in $JsonObject.settings) {
            $flat += (Flatten-SCSettingInner -s $s) 
        }
        return $flat
    }

    # Device Configuration (CSP / OMA-URI)
    if ($JsonObject.omaSettings) {
        foreach ($oma in $JsonObject.omaSettings) {
            $typeTag = $oma.'@odata.type'
            $omaUri = $oma.omaUri
            $def = Get-SettingsCatalogDefinitionByCspPath -csp $omaUri -ExportRoot $ExportRoot
            $friendly = $null
            if ($def -and $def.options) {
                foreach ($opt in $def.options) {
                    if ($opt.optionValue.value -eq $oma.value) {
                        $friendly = $opt.displayName 
                    } 
                }
            }

            if ($typeTag -like '*omaSettingString*') {
                $flat += @{ path = $omaUri; type = 'omaString'; value = (Parse-OmaKeyValueString $oma.value); friendlyValue = $friendly; scEquivalent = ($def.id) }
            }
            elseif ($typeTag -like '*omaSettingInteger*') {
                $flat += @{ path = $omaUri; type = 'omaInteger'; value = $oma.value; friendlyValue = $friendly; scEquivalent = ($def.id) }
            }
            else {
                $flat += @{ path = $omaUri; type = 'omaRaw'; value = $oma.value; friendlyValue = $friendly; scEquivalent = ($def.id) }
            }
        }
        return $flat
    }

    return $flat
}

function Ensure-MSGraphModule {
    if ((Get-Command Invoke-GraphRequest -ErrorAction SilentlyContinue)) {
        return 
    }
    $msgraphPath = $null
    if ($global:AppRootFolder) {
        $msgraphPath = Join-Path $global:AppRootFolder "Extensions/MSGraph.psm1"
    }
    else {
        $msgraphPath = Join-Path $PSScriptRoot "../MSGraph.psm1"
    }
    if (Test-Path $msgraphPath) {
        Import-Module $msgraphPath -Force -ErrorAction Stop 
    }
}

function Get-SettingsCatalogCacheRoot {
    param([Parameter(Mandatory)] [string]$ExportRoot)
    return (Join-Path $ExportRoot "_metadata/SettingsCatalogDefinitions")
}

function Get-SettingsCatalogDefinition {
    param(
        [Parameter(Mandatory)] [string]$DefinitionId,
        [Parameter(Mandatory)] [string]$ExportRoot
    )

    $cacheRoot = Get-SettingsCatalogCacheRoot -ExportRoot $ExportRoot
    $mapFile = Join-Path $cacheRoot "filemap.json"
    if (-not (Test-Path $mapFile)) { return $null }

    $fileMap = Get-Content -Raw -Path $mapFile | ConvertFrom-Json
    $safe = $fileMap.$DefinitionId
    if (-not $safe) { return $null }

    $fullPath = Join-Path $cacheRoot $safe
    if (-not (Test-Path $fullPath)) { return $null }

    return (Get-Content -Raw -Path $fullPath | ConvertFrom-Json)
}

function Get-SettingsCatalogDefinitionByCspPath {
    param(
        [Parameter(Mandatory)] [string]$csp,
        [Parameter(Mandatory)] [string]$ExportRoot
    )

    $cacheRoot = Get-SettingsCatalogCacheRoot -ExportRoot $ExportRoot
    $indexFile = Join-Path $cacheRoot "definitions-by-cspPath.json"
    $mapFile   = Join-Path $cacheRoot "filemap.json"
    if (-not (Test-Path $indexFile)) { return $null }
    if (-not (Test-Path $mapFile))   { return $null }

    $index   = Get-Content -Raw -Path $indexFile | ConvertFrom-Json
    $fileMap = Get-Content -Raw -Path $mapFile   | ConvertFrom-Json

    $definitionId = $index.$csp
    if (-not $definitionId) { return $null }

    $safe = $fileMap.$definitionId
    if (-not $safe) { return $null }

    $fullPath = Join-Path $cacheRoot $safe
    if (-not (Test-Path $fullPath)) { return $null }

    return (Get-Content -Raw -Path $fullPath | ConvertFrom-Json)
}

function Get-SafeFilename {
    param([string]$input)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    # hex-encode
    return ([BitConverter]::ToString($hash) -replace "-", "").ToLower() + ".json"
}

function Update-IntuneSettingsCatalogCache {
    <#
      .SYNOPSIS
        Downloads the full Settings Catalog metadata corpus and caches it under ExportRoot.
      .PARAMETER ExportRoot
        The export root used by ChangeTracking; the cache will be stored under <ExportRoot>/_metadata/SettingsCatalogDefinitions
      .PARAMETER Force
        Force re-download even if cache exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ExportRoot,
        [switch]$Force
    )

    Ensure-MSGraphModule

    $cacheRoot = Get-SettingsCatalogCacheRoot -ExportRoot $ExportRoot
    if (-not (Test-Path $cacheRoot)) {
        New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    }

    # If cache exists and not forced AND map exists -> return
    $existing = Get-ChildItem -Path $cacheRoot -Filter *.json -File -ErrorAction SilentlyContinue
    if ($existing -and -not $Force -and (Test-Path (Join-Path $cacheRoot "filemap.json"))) {
        Write-Verbose "[SC Cache] Cache already present at $cacheRoot (use -Force to refresh)."
        return
    }

    # Clean the cache folder; recreate to be safe
    if (Test-Path $cacheRoot) {
        Get-ChildItem -Path $cacheRoot -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    }

    $all = @()
    $url = "https://graph.microsoft.com/beta/deviceManagement/configurationSettings"

    do {
        Write-Verbose "[SC Cache] GET $url"
        $resp = Invoke-GraphRequest -Url $url -Method GET

        # PS5-safe assignment (no ternary)
        if ($resp -is [string]) {
            $obj = $resp | ConvertFrom-Json
        } else {
            $obj = $resp
        }

        if ($obj.value) { $all += $obj.value }
        $url = $obj.'@odata.nextLink'
    } while ($url)

    # Safe file name generator (pure SHA256)
    function Get-SafeFilename([string]$id) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($id)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($bytes)
        $hex = ([BitConverter]::ToString($hashBytes) -replace "-", "").ToLower()
        return "$hex.json"
    }

    # Always create a new map and indexes
    $fileMap      = @{}
    $indexRootId  = @{}
    $indexCspPath = @{}

    foreach ($def in $all) {
        $id = $def.id
        if (-not $id) { continue }

        $safe = Get-SafeFilename $id
        $fileMap[$id] = $safe

        $outPath = Join-Path $cacheRoot $safe
        ($def | ConvertTo-Json -Depth 50) | Out-File $outPath -Encoding utf8

        if ($def.rootDefinitionId) { $indexRootId[$def.rootDefinitionId] = $def.id }
        if ($def.baseUri -and $def.offsetUri) {
            $csp = ($def.baseUri + $def.offsetUri)
            $indexCspPath[$csp] = $def.id
        }
    }

    # Persist indexes (even if empty)
    ($fileMap      | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "filemap.json")                -Encoding utf8
    ($indexRootId  | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "definitions-by-rootId.json")  -Encoding utf8
    ($indexCspPath | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "definitions-by-cspPath.json") -Encoding utf8

    Write-Verbose "[SC Cache] Definitions cached: $($all.Count) at $cacheRoot"
}

function Reindex-IntuneSettingsCatalogCache {
    <#
      .SYNOPSIS
        Rebuilds filemap.json and the CSP/rootId indexes from existing hashed files.
      .DESCRIPTION
        No Graph calls. Scans <ExportRoot>/_metadata/SettingsCatalogDefinitions/*.json,
        reads each definition, and regenerates:
          - filemap.json
          - definitions-by-rootId.json
          - definitions-by-cspPath.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ExportRoot
    )

    $cacheRoot = Get-SettingsCatalogCacheRoot -ExportRoot $ExportRoot
    if (-not (Test-Path $cacheRoot)) {
        throw "Cache root not found: $cacheRoot"
    }

    $fileMap      = @{}
    $indexRootId  = @{}
    $indexCspPath = @{}

    $files = Get-ChildItem -Path $cacheRoot -File -Filter *.json -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notin @('filemap.json','definitions-by-rootId.json','definitions-by-cspPath.json') }

    foreach ($f in $files) {
        try {
            $def = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json
        } catch {
            Write-Warning "Skipping unreadable definition: $($f.Name)"
            continue
        }

        if ($def.id) {
            $fileMap[$def.id] = $f.Name
        }

        if ($def.rootDefinitionId) {
            $indexRootId[$def.rootDefinitionId] = $def.id
        }

        if ($def.baseUri -and $def.offsetUri) {
            $csp = ($def.baseUri + $def.offsetUri)
            $indexCspPath[$csp] = $def.id
        }
    }

    ($fileMap      | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "filemap.json")                -Encoding utf8
    ($indexRootId  | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "definitions-by-rootId.json")  -Encoding utf8
    ($indexCspPath | ConvertTo-Json -Depth 50) | Out-File (Join-Path $cacheRoot "definitions-by-cspPath.json") -Encoding utf8

    Write-Verbose "[SC Cache] Reindex complete. Files: $($files.Count)"
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Error', 'Warning', 'Info', 'Verbose')]
        [string]$Severity = 'Info',

        [Switch]$PassThru,

        [Switch] $AsPlainText
    )

    begin {
        if (-not $Script:ChangeTrackingConfig.EnableLogging) {
            return 
        }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = $Script:LogPath
        }

        # Compute caller info
        $Caller = (Get-PSCallStack)[1]
        $Component = $Caller.Command
        $Source = $Caller.Location
    }

    process {
        if (-not $Script:ChangeTrackingConfig.EnableLogging) {
            return 
        }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            Write-Error "Logging enabled but no LogPath set."
            return
        }

        if (-not (Test-Path $Path)) {
            New-Item -ItemType File -Force -Path $Path | Out-Null
        }

        # Skip verbose unless user requested
        if (($Severity -eq 'Verbose') -and ($VerbosePreference -ne 'Continue')) {
            return
        }

        if ($AsPlainText) {
            $FormattedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $LogText = "$FormattedDate [$($Severity.ToUpper())] - $Message"
        }
        else {
            # Standard log format
            switch ($Severity) {
                'Error' {
                    $Sev = 3 
                }
                'Warning' {
                    $Sev = 2 
                }
                'Info' {
                    $Sev = 1 
                }
                'Verbose' {
                    $Sev = 1 
                }
            }

            if ($null -eq $Script:TimezoneBias) {
                $Script:TimezoneBias = (Get-CimInstance Win32_TimeZone).Bias
            }

            $Date = Get-Date -Format 'MM-dd-yyyy'
            $Time = Get-Date -Format 'HH:mm:ss.fff'
            $TimeString = "$Time$($Script:TimezoneBias)"

            $LogText = "<![LOG[$Message]LOG]!><time=`"$TimeString`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Sev`" thread=`"0`" file=`"$Source`">"
        }

        # Write
        $LogText | Out-File -FilePath $Path -Append -Force -Encoding default

        # Optional console output
        if ($PassThru) {
            switch ($Severity) {
                'Error' {
                    Write-Error $Message 
                }
                'Warning' {
                    Write-Warning $Message 
                }
                'Info' {
                    Write-Verbose $Message 
                }
                'Verbose' {
                    Write-Verbose $Message 
                }
            }
        }
    }
}

Export-ModuleMember -Function *