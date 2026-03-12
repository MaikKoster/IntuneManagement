
# 07 – Settings and Configuration

Change Tracking integrates with the IntuneManagement application's central
settings infrastructure, following the same patterns used by other extensions
such as EndpointManager and the Documentation modules.

This ensures the module behaves as a first‑class neighbor in the ecosystem and
exposes configuration options both in the WPF Settings UI and for headless
CLI automation.

---

## 1. Settings Architecture Overview

The IntuneManagement application centralizes all settings in the **Core**
module, which:

- Loads default settings at startup and owns the settings/UI plumbing.
- Determines persistence (Registry or JSON) depending on the application state.
- Provides global helpers:
  - `Get-Setting <Section> <Key> <Default>`
  - `Save-Setting <Section> <Key> <Value>`

Extensions register settings during their own `Invoke-InitializeModule`
using `Add-SettingsObject`, exactly as other modules do.

---

## 2. Settings Registered by Change Tracking

During module initialization, the following settings section and keys are
registered:

### **Section: Change Tracking**

| Key                         | Type    | Default | Description |
|----------------------------|---------|---------|-------------|
| `CT_EnableLogging`         | Boolean | `false` | Enables logging to `<ExportRoot>/_logs`.
| `CT_ArchiveOriginalExport` | Boolean | `true`  | Controls post‑processing behavior for staging files.
| `CT_ArchiveRoot`           | Folder  | `…/_archive_original_exports` | Root for archived staging files, preserving folder structure.
| `CT_UpdateDeletedStates`   | Boolean | `false` | Whether objects not seen in a run should be marked `"deleted"`.

These settings appear as editable controls in the application’s **Settings UI**
because the extension registers them using the same pattern as other modules.

---

## 3. Precedence Model (Parameter → Setting → Default)

When running the export pipeline, the Change Tracking module resolves
configuration using the following precedence:

1. **Explicit parameter**
2. **Stored application setting**
3. **Module internal default**

This mirrors the behavior of existing modules, which load user preferences via
`Get-Setting` unless overridden.

**Example:**

```powershell
Invoke-IntuneExportChangeTracking `
    -StagingPath "C:\temp\Staging" `
    -ExportRoot  "C:\Git\Intune"
```

will resolve:

- ArchiveRoot → from settings  
- EnableLogging → from settings  
- UpdateDeletedStates → from settings  

unless explicitly provided as parameters.

---

## 4. CLI and Automation Compatibility

The module fully supports running **outside** the main application:

```powershell
Invoke-ChangeTrackingCli `
    -StagingPath "C:\temp\Staging" `
    -ExportRoot  "C:\Git\Intune"
```

If the central settings engine is available (`Get-Setting` exists), settings
are read from the application; otherwise module defaults are used.

This ensures:

- Consistent behavior inside the app  
- Safe execution for headless CI/CD pipelines  
- Zero dependency on the UI  

---

## 5. Summary

- Change Tracking integrates cleanly with the existing settings system.
- It registers a UI‑visible settings section (“Change Tracking”).
- It uses the same typed settings objects as other modules.
- It adheres to the standard precedence approach used throughout the application.
