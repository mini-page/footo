# Footo: Your Reusable Terminal Command Companion

---

**Footo** provides a unified command interface for creating, managing, and executing reusable terminal functions called modules. It's designed to be a simple, cross-platform tool for developers, sysadmins, and power users who want to build a personal library of frequently used commands.

### Our Mission

Our mission is to streamline your command-line workflow by making it easy to create, share, and use powerful, reusable terminal functions. We believe that you shouldn't have to reinvent the wheel every time you want to perform a common task. With Footo, you can build a library of modules that are tailored to your specific needs, and then execute them with a single command, regardless of your operating system or shell.

### Key Features

*   **Create and Organize Custom Modules:** Easily create your own modules with a simple, standardized structure.
*   **Cross-Platform:** Works on Windows, Linux, and macOS.
*   **Shell Agnostic:** Supports both PowerShell and Bash scripts.
*   **Layered Scopes:** Keep your personal scripts separate from bundled and community-provided modules.
*   **Simple, Intuitive CLI:** A clean and easy-to-use command-line interface for managing your modules.

### Installation

#### Windows (PowerShell)

```powershell
.\install.ps1
```

#### Linux/macOS (Bash/Zsh)

```bash
chmod +x install.sh
./install.sh
```

After installation, please restart your terminal.

### Usage

*   **List all modules:**
    ```bash
    footo list
    ```
*   **Get information about a module:**
    ```bash
    footo info <moduleName>
    ```
*   **Create a new module:**
    ```bash
    footo create <moduleName>
    ```
*   **Run a module:**
    ```bash
    footo run <moduleName> [args...]
    ```

### Module Development

Creating a new module is as simple as running `footo create <moduleName>`. This will create a new directory in your local modules folder with a `meta.json` file and a script file. Edit the script file to add your desired functionality, and your new module is ready to go!

### Contributing

We welcome contributions from the community! If you have an idea for a new feature, a bug fix, or a new module that you think would be useful to others, please feel free to open an issue or a pull request on our GitHub repository.

### License

This project is licensed under the MIT License. See the `LICENSE` file for details.
