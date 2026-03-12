
# IntuneManagement – Change Tracking Extension

This extension enhances the IntuneManagement export pipeline by providing
fully deterministic, canonicalized outputs suitable for version control,
automation, and CI/CD environments.

It integrates tightly with the application's existing settings and UI
infrastructure while remaining fully functional as a standalone module.

---

## Documentation

### Core Documents
- **01 – Overview**
- **02 – Goals and Scope**
- **03 – Design Principles**
- **04 – Data Model and Files**
- **05 – Export Pipeline (Updated)**
- **06 – Running Change Tracking (Updated)**
- **07 – Settings and Configuration (New)**
- **08 – UI Integration (Future)**
- **09 – Diagnostics and Flattened Views (Future)**
- **10 – Conventions and Guidelines (New)**

### Future
- 11 – Test Samples / Scenarios
- 12 – API Reference
- 13 – Developer Appendix

---

## Key Features
- Deterministic canonical JSON transformation
- Metadata generation (`meta.json`)
- SHA‑256 hashing for diff‑friendly exports
- Optional logging with standard Write-Log formatting
- Optional archival of staging exports
- Optional deletion detection
- Full CLI support via `Invoke-ChangeTrackingCli`
- Automatic integration with the IntuneManagement Settings UI

---

## Running the Module
Typical full pipeline example:
```powershell
Invoke-IntuneExport -Path "C:	emp\Staging"
Invoke-IntuneExportChangeTracking -StagingPath "C:	emp\Staging" -ExportRoot "C:\Git\Intune"
```

---

## License
This module is designed to integrate with the IntuneManagement open source
project and follows the same licensing model.
