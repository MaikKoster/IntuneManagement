
# 05 – Export Pipeline (Updated)

## 1. Overview

The Export Pipeline in IntuneManagement is responsible for retrieving objects
from Microsoft Intune via Graph API and storing them in a temporary, structured
staging export folder. This data forms the input for the Change Tracking module.

The Change Tracking module does **not** replace or modify the existing export
mechanism but extends it by providing deterministic downstream processing,
hashing, metadata generation, and optional archival.

---

## 2. Export Flow

The standard application export works as follows:

1. The user selects object types and/or specific objects.
2. The existing Intune export engine retrieves objects from Graph.
3. The engine writes them into a **staging export folder**:

```
<StagingPath>\<ObjectType>\<FileName>.json
```

4. The Change Tracking module consumes this staging folder.

The export pipeline itself remains untouched and continues to function exactly
as implemented by the original author.

---

## 3. Staging Folder Requirements

The Change Tracking module expects the staging export to follow the exact
folder structure produced by the IntuneManagement application:

```
<StagingPath>
    ├── ConfigurationPolicies
    ├── AppProtectionPolicies
    ├── AssignmentFilters
    └── ...
```

Each JSON file must contain at minimum an `id` property. Files missing an ID
are skipped.

---

## 4. Running Change Tracking After Export

After the export completes, the Change Tracking module is invoked:

```powershell
Invoke-IntuneExportChangeTracking `
    -StagingPath "C:\temp\StagingExport" `
    -ExportRoot  "C:\Git\Intune"
```

### 4.1 Parameter → Setting → Default Precedence

The Change Tracking module resolves behavior using:

1. Explicit parameters
2. Application settings from the **Change Tracking** section
3. Internal fallback defaults

This is consistent with how other modules in the ecosystem load and apply user
settings.

---

## 5. Outputs of the Change Tracking Pipeline

For each exported object, Change Tracking produces:

```
<ExportRoot>\<ObjectType>\<ObjectId>aw.json
<ExportRoot>\<ObjectType>\<ObjectId>\meta.json
```

### 5.1 Canonical JSON (raw.json)
- Deterministic formatting
- Keys cleaned of volatile OData elements
- Sorted keys
- Preserves array order

### 5.2 Metadata File (meta.json)
- Object ID, display name, type
- Canonical hash
- State (“active”, optionally “deleted”)
- Diagnostics block for future analysis

---

## 6. Optional Archival and Deletion Detection

These behaviors are controlled via application settings or optional parameters:

### 6.1 Archive Original Export
When enabled (`CT_ArchiveOriginalExport = $true`), processed staging files are
moved into:

```
<ArchiveRoot>\<ObjectType>\<OriginalFile>.json
```

The structure is preserved using a safe PowerShell 5.1–compatible relative path
resolver.

### 6.2 Deleted Object Marking
If enabled (`CT_UpdateDeletedStates = $true`), any object previously exported
but not encountered in the current run is marked:

```
"state": "deleted"
```

This is disabled by default.

---

## 7. Logging Support

If `CT_EnableLogging` is enabled or the parameter `-EnableLogging` is supplied,
log files are written to:

```
<ExportRoot>/_logs/ChangeTracking-YYYYMMDD-HHMMSS.log
```

Logs use the standard Write-Log format consistent with other modules in the
project.

---

## 8. Summary

The Change Tracking module fully integrates into the existing Export Pipeline
by:

- Consuming the same staging export structure
- Applying deterministic processing rules
- Honoring application settings
- Remaining compatible with CI/CD automation

The Export Pipeline remains the authoritative source of Intune configuration
objects—the Change Tracking module adds structure, stability, and versioning
capabilities on top of it.

