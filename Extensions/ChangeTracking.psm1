<# 
.SYNOPSIS
Module to support change tracking of Intune objects

.DESCRIPTION
This module adds support for change tracking of Intune objects

.NOTES
  Author: Maik Koster
#>

# Global config (can be overridden by user)
$ChangeTrackingConfig = @{
    KeepOriginalExport     = $false
    ArchiveOriginalExport  = $true
    ArchiveRoot            = "$PSScriptRoot/../_archive_original_exports"
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

function Invoke-IntuneExportChangeTracking {
    param(
        [Parameter(Mandatory)]
        [string]$StagingPath,

        [Parameter(Mandatory)]
        [string]$ExportRoot
    )
    Write-Verbose "[ChangeTracking] Processing staging folder: $StagingPath"

    $files = Get-ChildItem -Path $StagingPath -Recurse -Filter *.json
    foreach ($file in $files) {
        Write-Verbose "[ChangeTracking] Processing $($file.FullName)"

        $json = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json

        # Determine object type and ID
        $objectId = $json.id
        if (-not $objectId) { continue }

        $objectType = Split-Path $file.DirectoryName -Leaf
        $targetDir = Join-Path $ExportRoot "$objectType/$objectId"
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        # Normalize JSON
        $canonical = ConvertTo-CanonicalJson -Object $json

        # Hash
        $hash = Get-ObjectHash -CanonicalJson $canonical

        # Write raw.json
        $rawPath = Join-Path $targetDir "raw.json"
        $canonical | Out-File -FilePath $rawPath -Encoding utf8

        # Write metadata
        $metaPath = Join-Path $targetDir "meta.json"
        $metadata = [ordered]@{
            id = $json.id
            displayName = $json.displayName
            type = $objectType
            category = $null
            state = "active"
            lastIntuneModified = $json.lastModifiedDateTime
            hash = $hash
            diagnostics = @{}
        }
        ($metadata | ConvertTo-Json -Depth 10) | Out-File $metaPath -Encoding utf8

        # Cleanup / archive
        Handle-StagingFile -File $file
    }
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory)] [object]$Object)

    # Remove @odata.* and #* fields recursively
    function Clean-Node([object]$node) {
        if ($node -is [System.Collections.IDictionary]) {
            $new = @{}
            foreach ($key in $node.Keys | Sort-Object) {
                if ($key -like "@odata.*") { continue }
                if ($key -like "#*") { continue }
                if ($key -like "*@odata.type") { continue }
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
    return ($clean | ConvertTo-Json -Depth 50 -Compress | ConvertFrom-Json | ConvertTo-Json -Depth 50)
}

function Get-ObjectHash {
    param([string]$CanonicalJson)
    $bytes = [Text.Encoding]::UTF8.GetBytes($CanonicalJson)
    $sha = [Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
}

function Handle-StagingFile {
    param([Parameter(Mandatory)] [System.IO.FileInfo]$File)

    if (-not $ChangeTrackingConfig.KeepOriginalExport) {
        if ($ChangeTrackingConfig.ArchiveOriginalExport) {
            # Recreate folder structure inside single archive root
            $relative = ($File.FullName).Substring((Split-Path $PSScriptRoot -Parent).Length)
            $archiveTarget = Join-Path $ChangeTrackingConfig.ArchiveRoot $relative
            $archiveDir = Split-Path $archiveTarget
            New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
            Move-Item -Path $File.FullName -Destination $archiveTarget -Force
        }
        else {
            Remove-Item -Path $File.FullName -Force
        }
    }
}

Export-ModuleMember -Function *