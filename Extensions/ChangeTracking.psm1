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


# module configuration (can be overridden with Set-ChangeTrackingConfig)
$Script:ChangeTrackingConfig = @{
    KeepOriginalExport     = $false   # if $true, staging files are never deleted
    ArchiveOriginalExport  = $true    # if $true, staging files moved into ArchiveRoot
    ArchiveRoot            = "$PSScriptRoot/../_archive_original_exports"
    UpdateDeletedStates    = $false   # if $true, mark unseen objects as deleted
    EnableLogging          = $false   # if $true, Write-Log is enabled
}


# CONFIG OVERRIDE ENTRY POINT
function Set-ChangeTrackingConfig {
    param([hashtable]$Config)
    if ($null -ne $Config) {
        foreach ($k in $Config.Keys) { $Script:ChangeTrackingConfig[$k] = $Config[$k] }
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
    if (-not (Test-Path $ExportRoot)) { New-Item -ItemType Directory -Force -Path $ExportRoot | Out-Null }

    # Set staging root for relative path operations
    $Script:CurrentStagingRoot = (Resolve-Path $StagingPath).Path

    # If logging enabled, create session log
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
    $processed = 0
    $changed   = 0
    $unchanged = 0
    $archived  = 0
    $deleted   = 0

    $seen = @{}

    $files = Get-ChildItem -Path $StagingPath -Recurse -File -Filter *.json
    foreach ($file in $files) {
        $processed++
        Write-Verbose "[ChangeTracking] Processing $($file.FullName)"
        Write-Log -Message "Processing $($file.FullName)" -Severity Verbose

        $json = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json

        # Extract ID
        $objectId = $json.id
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Warning "Skipping file without id: $($file.FullName)"
            Write-Log -Message "Skipping file without id: $($file.FullName)" -Severity Warning
            Handle-StagingFile -File $file -archivedRef ([ref]$archived)
            continue
        }

        # Determine object type from staging structure
        $objectType = Split-Path $file.DirectoryName -Leaf
        if ([string]::IsNullOrWhiteSpace($objectType)) { $objectType = 'Unknown' }

        # Track seen object ids
        if (-not $seen.ContainsKey($objectType)) {
            $seen[$objectType] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$seen[$objectType].Add($objectId)

        # Build export folder
        $targetDir = Join-Path $ExportRoot (Join-Path $objectType $objectId)
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        $rawPath  = Join-Path $targetDir 'raw.json'
        $metaPath = Join-Path $targetDir 'meta.json'

        # Canonicalize + hash
        $canonical = ConvertTo-CanonicalJson -Object $json
        $hash      = Get-ObjectHash -CanonicalJson $canonical

        # Load existing metadata
        $existingMeta = $null
        if (Test-Path $metaPath) {
            try { $existingMeta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json } catch { $existingMeta = $null }
        }
        $previousHash = if ($existingMeta) { $existingMeta.hash } else { $null }

        # CHANGE DETECTION
        if ($previousHash -and ($previousHash -eq $hash)) {
            $unchanged++
            Write-Verbose "[ChangeTracking] No change for $objectType/$objectId"
            Write-Log -Message "Unchanged: $objectType/$objectId" -Severity Verbose

            # Ensure active state
            if ($existingMeta -and $existingMeta.state -ne 'active') {
                $existingMeta.state = 'active'
                ($existingMeta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8
            }

            Handle-StagingFile -File $file -archivedRef ([ref]$archived)
            continue
        }

        # CHANGED → writeraw
        $changed++
        Write-Verbose "[ChangeTracking] Changed $objectType/$objectId"
        Write-Log -Message "Changed: $objectType/$objectId" -Severity Info

        $canonical | Out-File -FilePath $rawPath -Encoding utf8

        # Write meta.json
        $meta = [ordered]@{
            id                 = $json.id
            displayName        = $json.displayName
            type               = $objectType
            category           = $null
            state              = 'active'
            lastIntuneModified = $json.lastModifiedDateTime
            hash               = $hash
            diagnostics        = @{}
        }
        ($meta | ConvertTo-Json -Depth 20) | Out-File -FilePath $metaPath -Encoding utf8

        Handle-StagingFile -File $file -archivedRef ([ref]$archived)
    }

    # Optional deletion detection
    if ($Script:ChangeTrackingConfig.UpdateDeletedStates) {
        $deleted += (Update-DeletedStates -ExportRoot $ExportRoot -Seen $seen)
    }

    # SUMMARY
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

# HANDLE STAGING FILE (delete or archive)
function Handle-StagingFile {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [ref]$archivedRef
    )

    if ($Script:ChangeTrackingConfig.KeepOriginalExport) { return }

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
        $seenSet = if ($Seen.ContainsKey($objectType)) { $Seen[$objectType] } else { New-Object System.Collections.Generic.HashSet[string] }

        foreach ($idDir in Get-ChildItem -Path $typeDir.FullName -Directory) {
            $id = $idDir.Name
            $metaPath = Join-Path $idDir.FullName 'meta.json'
            if (-not (Test-Path $metaPath)) { continue }
            if ($seenSet.Contains($id))      { continue }

            try {
                $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
            } catch { continue }

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
    $base = (Resolve-Path $BasePath).Path.TrimEnd('\','/')
    $full = (Resolve-Path $FullPath).Path

    if ($full.StartsWith($base, [System.StringComparison]::InvariantCultureIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart('\','/')
    }

    # Fallback: no shared root → return filename
    return (Split-Path $full -Leaf)
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Error','Warning','Info', 'Verbose')]
        [string]$Severity='Info',

        [Switch]$PassThru,

        [Switch] $AsPlainText
    )

    begin {
        if (-not $Script:ChangeTrackingConfig.EnableLogging) { return }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = $Script:LogPath
        }

        # Compute caller info
        $Caller   = (Get-PSCallStack)[1]
        $Component = $Caller.Command
        $Source    = $Caller.Location
    }

    process {
        if (-not $Script:ChangeTrackingConfig.EnableLogging) { return }

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
                'Error'   { $Sev = 3 }
                'Warning' { $Sev = 2 }
                'Info'    { $Sev = 1 }
                'Verbose' { $Sev = 1 }
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
                'Error'   { Write-Error $Message }
                'Warning' { Write-Warning $Message }
                'Info'    { Write-Verbose $Message }
                'Verbose' { Write-Verbose $Message }
            }
        }
    }
}

Export-ModuleMember -Function *