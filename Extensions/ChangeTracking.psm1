<# 
.SYNOPSIS
Module to support change tracking of Intune objects

.DESCRIPTION
This module adds support for change tracking of Intune objects

.NOTES
  Author: Maik Koster
#>

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
    <#
        .SYNOPSIS
            Entry point for deterministic export + change tracking.

        .DESCRIPTION
            Coordinates the export pipeline:
            - Fetch object
            - Normalize JSON
            - Compute hash
            - Write files
            - Update metadata
    #>

    param(
        [string]$ExportPath
    )

    Write-Verbose "[ChangeTracking] Export pipeline invoked for: $ExportPath"
}

function ConvertTo-CanonicalJson {
    <#
        .SYNOPSIS
            Normalizes JSON for deterministic behavior.
    #>

    param(
        [Parameter(Mandatory)]
        [object]$Object
    )

    # Placeholder: actual normalization logic will be added later.
    return ($Object | ConvertTo-Json -Depth 20)
}

function Get-ObjectHash {
    <#
        .SYNOPSIS
            Computes SHA-256 hash of canonical JSON.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$CanonicalJson
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalJson)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
}

Export-ModuleMember -Function *
