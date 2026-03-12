
# 06 – Running Change Tracking (Updated)

## 1. Prerequisites

- Change Tracking module imported.
- Settings optionally configured via the application Settings UI
  (Enable Logging, Archive Behavior, Archive Root, Deleted State Handling).

---

## 2. Running Inside the Application

The module uses:

**Parameter → Setting → Default** precedence.

Typical execution:

```powershell
Invoke-IntuneExport -Path "C:\temp\Staging"
Invoke-IntuneExportChangeTracking `
    -StagingPath "C:\temp\Staging" `
    -ExportRoot  "C:\Git\Intune"
```

If the user has modified settings in the Settings UI, those values will
automatically be applied unless explicitly overridden on the command line.

**Example (override archive root only):**

```powershell
Invoke-IntuneExportChangeTracking `
    -StagingPath "C:\temp\Staging" `
    -ExportRoot  "C:\Git\Intune" `
    -ArchiveRoot "D:\Archive"
```

---

## 3. Running Outside the Application

When invoked without the UI loaded, the module:

- Uses explicit parameters when provided.
- Falls back to stored settings **if** the settings API is available.
- Otherwise uses module defaults.

CLI wrapper:

```powershell
Invoke-ChangeTrackingCli `
    -StagingPath "C:\temp\Staging" `
    -ExportRoot  "C:\Git\Intune"
```

This ensures predictable behavior in CI/CD pipelines.

---

## 4. Logging

If `EnableLogging` is enabled (via settings or parameter), logs are written to:

```
<ExportRoot>/_logs/ChangeTracking-YYYYMMDD-HHMMSS.log
```

---

## 5. Summary Output

The module concludes with a summary:

```
[ChangeTracking] Summary:
  Processed : <n>
  Changed   : <n>
  Unchanged : <n>
  Archived  : <n>
  Deleted   : <n>   # only if enabled
```
