# IntuneManagement

Welcome to **IntuneManagement** — a simplified UI for browsing, searching, and inspecting Intune objects exported as JSON files.

## Available Object Types

Below you'll find all available object types discovered in the `/data` directory.

Each type links to an overview page displaying all objects of that category.

---

{{ objectTypeList }}

---

## How it Works

This static UI lets you:

- Browse Intune objects grouped by type
- View details of any object
- Navigate between overview and detail pages
- Render JSON in a clean UI-friendly way

Ensure that your exported JSON files follow this structure:
```
/data/
  /<ObjectType>/
      file1.json
      file2.json
```

---

## About
Generated as part of the **IntuneManagement project** to make JSON browsing intuitive and fast.
