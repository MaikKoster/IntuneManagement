
# Export Pipeline Architecture

This document defines the full deterministic export pipeline used by the
ChangeTracking extension module. It outlines each processing stage from initial
staging export through canonicalization, hashing, metadata creation, archival,
and final normalized output.

---

## 1. High-Level Pipeline Overview

The export workflow consists of two major phases:

### **Phase A — Staging Export (Provided by Main Module)**
- Existing IntuneManagement export writes raw objects into a temporary directory.
- Files are named using display names (e.g., `TST-FILTER.json`).
- This acts as the **staging area**.

### **Phase B — Change Tracking Processing (New Module)**
The ChangeTracking module consumes the staging files and produces canonical,
Git-friendly, ID-based exports.

Pipeline:

```
[Staging Export] → [Load] → [Canonical Normalize] → [Hash] →
[Write raw.json] → [Write meta.json] → [Archive or Delete Source]
```

All steps are deterministic, order-independent, and repeatable.

---

## 2. Staging Folder Behavior

The staging folder contains temporary exported files from the upstream module.
Behavior is configurable:

### Default Behavior
- **Delete staging file after processing**
  - Prevents duplication
  - Avoids reprocessing stale files
  - Ensures clean state after each run

### Optional Behavior
- **Archive staging file**, preserving folder type structure:

Example:
```
<ExportRoot>/_archive_original_exports/
    AssignmentFilters/
        TST-FILTER-W-ChangeTrackingTest.json
```

Configuration keys:
```powershell
$ChangeTrackingConfig = @{
    KeepOriginalExport = $false
    ArchiveOriginalExport = $true
    ArchiveRoot = "C:\Exports\_archive_original_exports"
}
```

Only **one archive folder** exists, but the module will recreate subfolders
matching original structure.

---

## 3. Object Processing Pipeline

### Step 1 — Load Staging File
- Read JSON
- Detect object type
- Extract Intune object ID

### Step 2 — Canonical JSON Normalize
Rules:
- Remove all keys starting with `@odata.`
- Remove all keys starting with `#`
- Remove all sibling properties ending with `@odata.type`
- Sort keys lexicographically
- Use 2-space indentation
- Preserve arrays, nulls, and empty objects

### Step 3 — Compute Hash
- SHA-256 over normalized JSON text
- Stored into metadata

### Step 4 — Write Canonical Output
Creates structure:
```
<ExportRoot>/<object-type>/<object-id>/raw.json
<ExportRoot>/<object-type>/<object-id>/meta.json
```

### Step 5 — Cleanup / Archive
- Delete staging file (default)
- OR archive to configured location

---

## 4. Metadata Generation

Fields:
```json
{
  "id": "<guid>",
  "displayName": "<string>",
  "type": "<object-type>",
  "category": "<category>",
  "state": "active | deleted",
  "lastIntuneModified": "<timestamp>",
  "hash": "<sha256>",
  "diagnostics": {}
}
```

---

## 5. Deleted Object Detection
If an object was exported in previous runs but is absent in staging:
- The existing `meta.json` is updated with `state = "deleted"`.
- The previous `raw.json` remains.

---

## 6. Deterministic Behavior Guarantees
- Same input → same output
- No timestamps written except Intune-modified timestamp
- No ordering differences
- Git diffs reflect real configuration changes only

---

## 7. Summary
This pipeline ensures stable Git-based tracking of Intune configuration using a
separate staging model, deterministic normalization, and modular cleanup rules.
