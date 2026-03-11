# Intune Change Tracking & Documentation – Architectural Overview

This document provides a high-level architectural summary of the extended
Intune export, change-tracking, and documentation subsystem built on top of the
existing IntuneManagement project. It describes the purpose, guiding concepts,
and long-term direction of the module in a concise, developer-focused way.

---

## 1. Purpose

The goal of this enhancement is to extend the existing IntuneManagement
export/backup tooling into a deterministic, Git-friendly system that enables:

- Reliable tracking of configuration changes over time  
- Human-readable diffs for code-review-like auditing  
- Long-term documentation of configuration intent  
- Consistent restore behavior (overwrite or recreate)  
- Future analytical capabilities such as conflict detection  

This module treats **Intune configuration as code**, using Git as the storage,
versioning, and audit mechanism.

---

## 2. Architectural Approach

The solution is implemented as a **separate extension module**
(e.g., `ChangeTracking.psm1`), integrated using the existing
`Invoke-InitializeModule` extensibility model.

Key architectural concepts:

### 2.1 Deterministic Export Pipeline
Exports must behave identically regardless of whether they run:

- manually  
- on schedule  
- after an event  

Deterministic output ensures Git diff stability and supports reproducible state snapshots.

### 2.2 Canonical JSON
All exported objects are normalized into a canonical form:

- stable key ordering  
- removal of volatile/non-meaningful fields  
- uniform structure across modules  
- consistent newline/indent rules  

This enables accurate hashing and clean diffs.

### 2.3 Object-ID-Based Storage
Each Intune object is stored under a folder or file named using its **stable Intune ObjectId**, not the display name.  
This ensures continuity across renames and supports long-term tracking.

### 2.4 Metadata Layer
Each exported object includes an associated metadata file containing:

- display name  
- type and category  
- last modified timestamp in Intune  
- deterministic hash of normalized content  
- diagnostic information (missing references, errors, deleted state)  

Metadata enriches documentation and ensures restore behavior is transparent.

### 2.5 Deleted Object Preservation
If an object is deleted from Intune, the previous export remains and is marked:

```json
"state": "deleted"
```

This preserves history and allows restore if needed.

### 2.6 Git Integration
Each export cycle concludes with:

- object hashing  
- change detection  
- commit when required  

This yields reviewable version history, similar to typical code workflows.

---

## 3. Long-Term Vision

Although initial work focuses on deterministic export and change tracking,
the architecture is designed to support advanced capabilities:

### 3.1 Conflict & Duplication Detection
Identify situations where multiple policies configure the same setting.

### 3.2 Assignment Validation
Identify scenarios where configuration profiles reference:

- deleted groups  
- inaccessible groups  
- conflicting assignments  

### 3.3 GPResult-Like Attribution (Long-Term)
Correlate device-level settings (e.g., `mdmdiagnostics`) back to configuration profiles.

### 3.4 Documentation Generation
Produce human-readable summaries (Markdown, HTML) from metadata & flattened content.

---

## 4. Guiding Constraints

- **No breaking changes** to the existing backup/restore functionality  
- **Minimal invasive modifications** to the main codebase  
- **Extension-first design**: new functionality lives inside dedicated module(s)  
- **Support for large tenants**: 100k+ devices, 1k+ apps, hundreds of profiles  

---

## 5. Summary

This architecture transforms the existing IntuneManagement project into a
deterministic, Git-driven change-tracking platform. It ensures clean,
reliable exports, enhances documentation, and establishes a future-proof basis
for deeper configuration analysis.
