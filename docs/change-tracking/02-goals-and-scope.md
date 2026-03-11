# Goals and Scope

This document describes the functional goals, scope boundaries, and phased
approach for the Intune change-tracking and documentation enhancements.

---

## 1. Primary Goals (Phase 1)

These are the core deliverables for the initial release.

### 1.1 Deterministic Export
Exports must produce identical output when no tenant changes occurred.
This includes canonical JSON and consistent ordering of all data.

### 1.2 Per-Object Storage Using ObjectId
Files and folders are keyed by Intune object IDs to ensure rename stability and
long-term continuity in Git history.

### 1.3 Metadata Generation
Each exported object is accompanied by metadata describing:

- display name  
- object type and category  
- last modified time in Intune  
- current export state (active or deleted)  
- diagnostic information (missing references, warnings)  
- cryptographic hash of canonicalized object  

Metadata improves observability and supports downstream analysis.

### 1.4 Hash-Based Change Detection
A normalized SHA-256 hash determines whether an object has actually changed.
Unchanged objects are not re-exported or re-committed.

### 1.5 Git Integration
Each export cycle should produce:

- stable folder structure
- human-readable diffs
- automatically generated commits (optional)
- version snapshots suitable for review in Git tools

### 1.6 Restore Behavior (Overwrite or Recreate)
The restore module must support:

- **Overwrite** existing objects (preserving IDs)  
- **Recreate** objects that were deleted in Intune  
- Follow metadata state  

This enables rollback or reinstatement of accidentally deleted objects.

---

## 2. Secondary Goals (Phase 2)

These are important but depend on Phase 1 being stable.

### 2.1 Flattened Settings
Generate human-readable flattened views of:

- Settings catalog profiles  
- OMA-URI / CSP profiles  
- Template-based profiles  

Flattened views are critical for meaningful diffs and conflict analysis.

### 2.2 Unified Setting Identifier
Define a canonical identifier schema to unify:

- Catalog definition IDs  
- CSP/OMA-URI paths  
- Template setting IDs  

This enables cross-profile comparison.

### 2.3 Lenient Error Handling
Exports continue even if:

- referenced groups are deleted  
- catalog definitions are missing  
- assignments are inconsistent  

Diagnostics are recorded in metadata.

---

## 3. Advanced Goals (Future)

These are long-term improvements and will be implemented as separate modules.

### 3.1 Conflict & Duplication Detection
Surface situations where multiple policies configure the same underlying setting.

### 3.2 Assignment Overlap Analysis
Detect problematic overlaps such as:

- conflicting assignments  
- redundant or orphaned groups  
- accidental exclusions  

### 3.3 GPResult-like Attribution
Correlate device-side results (e.g., mdmdiagnostics output) with settings and policies.

### 3.4 Comprehensive Documentation Generation
Automated generation of:

- Markdown documentation  
- HTML configuration portals  
- Change logs  
- Human-readable exports  

---

## 4. Out of Scope (Initially)

- GitOps-style deployment  
- Enforcement of naming conventions  
- Cross-tenant comparisons  
- Real-time monitoring  
- Automated remediation  

---

## 5. Summary

This phased scope ensures a stable, deterministic export pipeline before
introducing more advanced analytical features.
