
# Data Model and Files

This document defines the on-disk data model, file layout, and canonical formats
used by the Change Tracking extension module.

---

## 1. Folder Structure

Exports are written under a root export directory following this layout:

```
<export-root>/
  <object-type>/
    <object-id>/
      raw.json
      meta.json
      flat.json   (optional)
```

- **object-type** reflects the Intune category (e.g., ConfigurationProfiles, Apps, CompliancePolicies).
- **object-id** is the stable GUID assigned by Intune.
- **raw.json** contains the canonical JSON representation of the object.
- **meta.json** supplies metadata including diagnostics, hash, timestamps, etc.
- **flat.json** contains a flattened, human-readable structure (future feature).

---

## 2. Canonical JSON Representation

To ensure determinism and stable diff behavior:

- All JSON keys must be **sorted lexicographically**.
- Formatting must use **2-space indentation**.
- All volatile properties (timestamps, etags, runtime states) must be removed.
- Empty arrays/objects should remain for structural stability.

Normalization occurs *before* hashing and writing to disk.

---

## 3. Metadata Schema

Metadata is stored in `meta.json` and follows this structure:

```json
{
  "id": "<guid>",
  "displayName": "<string>",
  "type": "<object type>",
  "category": "<category name>",
  "state": "active | deleted",
  "lastIntuneModified": "<ISO timestamp>",
  "hash": "<sha256 hash>",
  "diagnostics": {
    "missingAssignments": [],
    "missingDefinitions": false
  }
}
```

Fields:
- **state** indicates whether the object currently exists in Intune.
- **diagnostics** contains non-fatal issues detected during export.
- **hash** is derived from the canonical JSON.

---

## 4. Tombstones for Deleted Objects

If an exported object disappears in Intune:

- Its folder and files remain.
- `meta.json` is updated with:
  ```json
  "state": "deleted"
  ```
- The previous raw export is preserved.

This ensures the ability to review or restore the deleted object.

---

## 5. Hashing

The hash is calculated using SHA-256 over the **canonical JSON string**.
This ensures stable change detection even when Graph API response ordering fluctuates.

---

## 6. File Naming Rules

- `raw.json` — canonical object representation
- `meta.json` — metadata + diagnostics
- `flat.json` — flattened, human-readable representation

These filenames are intentionally simple to reduce complexity during Git-based review.

---

## 7. Future Extensions

- Add support for `changes.json` to store long-term human-written change notes
- Add exported dependency maps
- Add symbol tables for unified setting identifiers

