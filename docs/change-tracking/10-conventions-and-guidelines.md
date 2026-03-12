
# 10 – Conventions and Guidelines

This document provides conventions for extending the Change Tracking module
and ensures alignment with the patterns used across the IntuneManagement
application.

---

## 1. General Principles

- **Be a good neighbor**: follow project patterns, especially around settings,
  logging, and UI integration.
- **Determinism**: every output file must be stable, canonical, and free of
  volatile properties.
- **Non‑intrusion**: Change Tracking enhances behavior without modifying the
  core export pipeline or core modules.

---

## 2. Settings Conventions

### 2.1 Registration

- All settings must be registered in `Invoke-InitializeModule` using
  `Add-SettingsObject`.
- Settings must be grouped under a dedicated section (here: `Change Tracking`).

### 2.2 Precedence (Mandatory)

All Change Tracking settings follow:

**Parameter → App Setting → Module Default**

This ensures deterministic automation while providing user‑friendly defaults.

---

## 3. Logging Conventions

- Logging uses the provided `Write-Log` function with PowerShell‑safe escaping.
- Logging is optional (`CT_EnableLogging`) and disabled by default.
- Log output location:  
  `<ExportRoot>/_logs/ChangeTracking-YYYYMMDD-HHMMSS.log`

---

## 4. Folder Structure Conventions

- Staging folder = input from the existing export pipeline.
- Export root = canonical ID‑based folder structure.
- Archive root = single root folder, preserving the original staging subtree.
- Deleted detection = optional and conservative.

---

## 5. PowerShell Coding Style

- Always escape embedded quotes using backtick ( \`" ), not backslash.
- Avoid .NET APIs unavailable in PS5.1 unless compatibility wrappers exist.
- Prefer verbose output for user feedback; use log only when enabled.

---

## 6. CLI Compatibility

Modules must:

- Allow invocation outside the app.  
- Avoid hard dependencies on UI components.  
- Fall back safely when `Get-Setting` is unavailable.

---

## 7. Future Extensions

- Extend flattening rules.
- Expand diagnostics.
- Add UI button for “Export + Change Tracking”.
