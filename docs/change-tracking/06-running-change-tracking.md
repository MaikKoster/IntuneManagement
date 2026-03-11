
# Running Change Tracking

This guide explains how to run the Change Tracking pipeline using the existing
IntuneManagement export as a staging step.

---

## 1. Prerequisites

- IntuneManagement (export) works as usual.
- The ChangeTracking module is available and imported.

---

## 2. Recommended Workflow (Development)

1. **Export** selected objects using the built-in export, targeting a *staging* folder:

   ```powershell
   $staging = 'C:\\temp\\StagingExport'
   $exportRoot = 'C:\\Git\\Intune'
   Invoke-IntuneExport -Path $staging
   ```

2. **Run Change Tracking** to canonicalize, hash, and write ID-based outputs:

   ```powershell
   Import-Module '...\\Extensions\\ChangeTracking\\ChangeTracking.psm1' -Force

   # Optional: set runtime config
   Set-ChangeTrackingConfig @{ 
       KeepOriginalExport    = $false            # default
       ArchiveOriginalExport = $true             # default
       ArchiveRoot           = 'C:\\temp\\Export\\_archive_original_exports'  
       UpdateDeletedStates   = $false            # use with care
   }

   Invoke-IntuneExportChangeTracking -StagingPath $staging -ExportRoot $exportRoot -Verbose
   ```

3. **Review Git changes** under `$exportRoot` and commit if appropriate.

---

## 3. What the Module Does

- Reads **staging** JSON files
- Produces canonical JSON (`raw.json`) and `meta.json` under
  `\<ExportRoot\>/<objectType>/<objectId>/`
- Computes SHA-256 to detect changes and **skips writing** if unchanged
- Deletes or **archives** processed staging files (configurable)

---

## 4. Configuration Keys

```powershell
Set-ChangeTrackingConfig @{
  KeepOriginalExport     = $false   # if $true: never deletes/moves staging files
  ArchiveOriginalExport  = $true    # if $true: moves to a single ArchiveRoot (preserves subfolders)
  ArchiveRoot            = 'C:\\temp\\Export\\_archive_original_exports'
  UpdateDeletedStates    = $false   # if $true: mark not-seen objects as deleted (use with care)
}
```

---

## 5. Notes & Tips

- **Determinism:** If there are no real configuration changes, the module won’t
  rewrite files; Git stays clean.
- **Deleted Objects:** If you enable `UpdateDeletedStates`, any object that
  existed previously in `ExportRoot` but wasn’t seen in the current run will be
  marked `state = "deleted"` in `meta.json`.
- **Archival:** With `ArchiveOriginalExport = $true`, the module moves staging
  files into **one archive root**, recreating the subfolder structure (e.g.,
  `AssignmentFilters/YourFile.json`).
- **Safety:** In selective exports, keep `UpdateDeletedStates = $false` to avoid
  false positives.

---

## 6. Example One-Liner for Scheduled Runs

```powershell
$staging    = 'C:\\temp\\StagingExport'
$exportRoot = 'C:\\Git\\Intune'
Invoke-IntuneExport -Path $staging; Import-Module '...\\Extensions\\ChangeTracking\\ChangeTracking.psm1' -Force; Invoke-IntuneExportChangeTracking -StagingPath $staging -ExportRoot $exportRoot -Verbose
```

---

## 7. Next Steps

- Add diagnostics to `meta.json` (missing groups/definitions)
- Add flattened views for selected object types
- Add a UI button that runs export → change tracking in one flow
