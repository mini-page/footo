**Software Requirements Specification (SRS)**
**Project Name:** Footo
**Version:** 1.0.0
**Scope:** V1 (Local + Bundled Modules, No Community Sync Yet)

---

### 1. Purpose

Footo provides a unified command interface for creating, managing, and executing reusable terminal functions called modules. Modules are script-based and stored under standardized directories. The tool allows direct execution of modules in the user’s active shell environment, ensuring cross-platform usability across Bash and PowerShell.

---

### 2. Core Objectives

* Allow users to create and organize custom command modules.
* Support module execution directly inside the active shell context.
* Maintain layered module scopes: local and bundled.
* Provide a consistent folder structure across operating systems.
* Offer a single installation path that works on Windows, Linux, and macOS.

---

### 3. System Environment

**Supported Shells (v1):**

* PowerShell (Windows, Linux, macOS)
* Bash (Linux, macOS, WSL, MSYS)

**Supported OS:**

* Windows 10+
* Linux distros using glibc or musl
* macOS 11+

---

### 4. Definitions

| Term            | Meaning                                                          |
| --------------- | ---------------------------------------------------------------- |
| Module          | A directory containing metadata and an executable script.        |
| Local Modules   | User-created modules stored in `~/.footo/modules/local/`         |
| Bundled Modules | Modules shipped with Footo stored in `~/.footo/modules/bundled/` |
| Script Entry    | The main script file specified in metadata.                      |
| Meta.json       | Metadata file describing module properties.                      |

---

### 5. System Architecture

#### 5.1 Directory Layout

```
~/.footo/
  modules/
    local/
      <moduleName>/
        meta.json
        script.ps1 or script.sh
    bundled/
      <moduleName>/
        meta.json
        script.ps1 or script.sh
    community/   (reserved, not active in v1)
```

#### 5.2 Metadata Specification (`meta.json`)

```
{
  "name": "<string>",
  "version": "<semver>",
  "description": "<string>",
  "lang": "pwsh" | "bash",
  "entry": "<file name>"
}
```

#### 5.3 Module Execution Flow

1. User invokes: `footo <module>`
2. Footo searches module in:

   * Local scope
   * Bundled scope
3. Load metadata.
4. Validate `lang` against active shell.
5. Execute entry script by sourcing.

---

### 6. Functional Requirements

| ID    | Requirement                | Description                                                                                   |
| ----- | -------------------------- | --------------------------------------------------------------------------------------------- |
| FR-01 | Module Creation            | `footo create <moduleName>` creates a module template with metadata and opens default editor. |
| FR-02 | Module Execution           | `footo <moduleName>` runs the module script sourced into current shell.                       |
| FR-03 | Explicit Execution         | `footo run <moduleName> [args]` passes additional arguments to module script.                 |
| FR-04 | Module Listing             | `footo list` displays all modules grouped by scope.                                           |
| FR-05 | Module Metadata Inspection | `footo info <moduleName>` reads and prints metadata.                                          |
| FR-06 | Initialization             | First execution triggers auto-setup of `~/.footo` structure.                                  |

---

### 7. Non-Functional Requirements

| Category        | Requirement                                                                                          |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| Performance     | Execution overhead must not exceed 30ms beyond script runtime.                                       |
| Reliability     | Footo must not corrupt user shell environment; sourced scripts must remain user-controlled.          |
| Portability     | Behavior must be identical across supported OS and shells.                                           |
| Security        | No remote fetching or network operations in v1. No code signing enforcement. Local execution only.   |
| Maintainability | Codebase must separate shell detection, metadata loader, and dispatcher logic into distinct modules. |

---

### 8. Constraints

* Only Bash and PowerShell scripts supported in v1.
* Mixed-shell execution is not allowed.
* Community module sync is out of scope until v2.

---

### 9. External Interfaces

#### 9.1 Installation Interface

PowerShell installer command:

```
iex (irm https://raw.githubusercontent.com/<repo>/install.ps1)
```

Installer responsibilities:

* Create `~/.footo/` structure.
* Place Footo binary/script into PATH.

#### 9.2 Environment Variables

| Name   | Function                                        |
| ------ | ----------------------------------------------- |
| EDITOR | Preferred editor opened during module creation. |

---

### 10. Data Structures

#### 10.1 Internal Registry Map

```
registry = {
  "local": [moduleName: metaPath],
  "bundled": [moduleName: metaPath]
}
```

#### 10.2 Execution Context Object

```
context = {
  shellType: "pwsh" | "bash",
  modulePath: "<resolved path>",
  entryScript: "<resolved file>",
  args: []
}
```

---

### 11. Initialization Workflow

```
if ~/.footo not exists:
    create base directory structure
load bundled modules
load local modules
build registry
```

---

### 12. Versioning Policy

* Semantic versioning used.
* v1.x: Local + Bundled only.
* v2.x: Community repo integration.
* v3.x: Language extensibility pipeline.

---

### 13. Future Extensions (Not Implemented in v1)

* Remote module registry.
* Rating and trust model for community modules.
* Module sandbox execution mode.
* Audit logs for execution.

---

### 14. Deliverables

* Executable binary or single multi-shell dispatcher script.
* Installer script.
* Minimal default bundled modules.
* README containing:

  * Installation
  * Usage
  * Module development guide

End.
