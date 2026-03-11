<# 
.SYNOPSIS
Module to support change tracking of Intune objects

.DESCRIPTION
This module adds support for change tracking of Intune objects
This module is designed to consume *staging* exports created by the
existing IntuneManagement export workflow, then produce deterministic,
Git-friendly outputs under an ID-based structure.


.NOTES
  Author: Maik Koster
#>

# Global config (can be overridden by user)
$Script:ChangeTrackingConfig = @{
    KeepOriginalExport     = $false   # if $true, never deletes/moves staging files
    ArchiveOriginalExport  = $true    # if $true, moves processed staging files into a single archive root
    ArchiveRoot            = "$PSScriptRoot/../_archive_original_exports"
    UpdateDeletedStates    = $false   # if $true, mark objects not seen in staging as deleted (use with care)
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
}

function Set-ChangeTrackingConfig {
    <#
        .SYNOPSIS
            Override default Change Tracking configuration at runtime.
    #>
    param(
        [hashtable]$Config
    )
    if ($null -ne $Config) {
        foreach ($k in $Config.Keys) { $Script:ChangeTrackingConfig[$k] = $Config[$k] }
    }
}

function Invoke-IntuneExportChangeTracking {
    <#
        .SYNOPSIS
            Runs the change-tracking pipeline over a staging export folder.

        .DESCRIPTION
            For each JSON file under -StagingPath:
            - Detect object type (from folder name) and Intune object id (from JSON)
            - Canonicalize JSON (deterministic normalization)
            - Compute SHA-256 hash
            - Compare to existing meta.json (if present)
              * If unchanged => skip writing raw/meta
              * If changed    => write raw.json & meta.json
            - Cleanup or archive staging file according to configuration

            Optional deletion detection (opt-in): objects under ExportRoot that
            were not seen in this run are marked as state = "deleted".
    #>
    param(
        [Parameter(Mandatory)] [string]$StagingPath,
        [Parameter(Mandatory)] [string]$ExportRoot
    )

    if (-not (Test-Path $StagingPath)) { throw "StagingPath not found: $StagingPath" }
    if (-not (Test-Path $ExportRoot)) { New-Item -ItemType Directory -Path $ExportRoot -Force | Out-Null }

    $seen = @{}

    $files = Get-ChildItem -Path $StagingPath -Recurse -Filter *.json -File
    foreach ($file in $files) {
        Write-Verbose "[ChangeTracking] Processing $($file.FullName)"

        $json = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json

        # Determine object id
        $objectId = $json.id
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Warning "[ChangeTracking] Skipping file without id: $($file.FullName)"
            Handle-StagingFile -File $file
            continue
        }

        # Determine object type from folder name in staging (e.g., AssignmentFilters)
        $objectType = Split-Path $file.DirectoryName -Leaf
        if ([string]::IsNullOrWhiteSpace($objectType)) { $objectType = 'Unknown' }

        # Track seen ids per type (for optional deletion detection)
        if (-not $seen.ContainsKey($objectType)) { $seen[$objectType] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$seen[$objectType].Add($objectId)

        # Target directory under export root
        $targetDir = Join-Path $ExportRoot (Join-Path $objectType $objectId)
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        $rawPath  = Join-Path $targetDir 'raw.json'
        $metaPath = Join-Path $targetDir 'meta.json'

        # Canonicalize and hash
        $canonical = ConvertTo-CanonicalJson -Object $json
        $hash      = Get-ObjectHash -CanonicalJson $canonical

        # Load previous meta if exists
        $existingMeta = $null
        if (Test-Path $metaPath) {
            try { $existingMeta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json } catch { $existingMeta = $null }
        }
        $previousHash = if ($existingMeta) { $existingMeta.hash } else { $null }

        if ($previousHash -and ($previousHash -eq $hash)) {
            Write-Verbose "[ChangeTracking] No change for $objectType/$objectId"

            # Ensure state is marked active if previously something else
            if ($existingMeta -and $existingMeta.state -ne 'active') {
                $existingMeta.state = 'active'
                ($existingMeta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8
            }

            Handle-StagingFile -File $file
            continue
        }

        # CHANGED → write raw.json & meta.json
        $canonical | Out-File -FilePath $rawPath -Encoding utf8

        $metadata = [ordered]@{
            id                  = $json.id
            displayName         = $json.displayName
            type                = $objectType
            category            = $null
            state               = 'active'
            lastIntuneModified  = $json.lastModifiedDateTime
            hash                = $hash
            diagnostics         = @{}
        }
        ($metadata | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8

        Handle-StagingFile -File $file
    }

    if ($Script:ChangeTrackingConfig.UpdateDeletedStates) {
        Update-DeletedStates -ExportRoot $ExportRoot -Seen $seen
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
                if ($key -like '@odata.*') { continue }
                if ($key -like '#*')       { continue }
                if ($key -like '*@odata.type') { continue }
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

function Handle-StagingFile {
    <#
        .SYNOPSIS
            Applies configured cleanup to a processed staging file.
    #>
    param([Parameter(Mandatory)] [System.IO.FileInfo]$File)

    if ($Script:ChangeTrackingConfig.KeepOriginalExport) { return }

    if ($Script:ChangeTrackingConfig.ArchiveOriginalExport) {
        # Recreate subfolder structure under single archive root
        if (-not (Test-Path $Script:ChangeTrackingConfig.ArchiveRoot)) {
            New-Item -ItemType Directory -Path $Script:ChangeTrackingConfig.ArchiveRoot -Force | Out-Null
        }

        # Compute relative path from staging root drive to preserve structure
        $stagingRoot = (Get-Item $File.Directory.Root.FullName).FullName
        $relative = $File.FullName.Substring($stagingRoot.Length).TrimStart('\\','/')
        $archiveTarget = Join-Path $Script:ChangeTrackingConfig.ArchiveRoot $relative
        $archiveDir = Split-Path $archiveTarget -Parent
        New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
        Move-Item -Path $File.FullName -Destination $archiveTarget -Force
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

    foreach ($typeDir in Get-ChildItem -Path $ExportRoot -Directory) {
        $objectType = $typeDir.Name
        $seenSet = if ($Seen.ContainsKey($objectType)) { $Seen[$objectType] } else { New-Object System.Collections.Generic.HashSet[string] }
        foreach ($idDir in Get-ChildItem -Path $typeDir.FullName -Directory) {
            $id = $idDir.Name
            $metaPath = Join-Path $idDir.FullName 'meta.json'
            if (-not (Test-Path $metaPath)) { continue }
            if ($seenSet.Contains($id)) { continue }

            try {
                $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
            } catch { continue }

            if ($meta.state -ne 'deleted') {
                $meta.state = 'deleted'
                ($meta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8
                Write-Verbose "[ChangeTracking] Marked deleted: $objectType/$id"
            }
        }
    }
}

Export-ModuleMember -Function *