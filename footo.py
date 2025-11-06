
import os
import sys
import json
import argparse
import subprocess
from pathlib import Path

FOTO_DIR = Path.home() / ".footo"
MODULES_DIR = FOTO_DIR / "modules"
LOCAL_MODULES_DIR = MODULES_DIR / "local"
BUNDLED_MODULES_DIR = MODULES_DIR / "bundled"
COMMUNITY_MODULES_DIR = MODULES_DIR / "community"

def initialize_directories():
    """Creates the necessary directory structure for Footo if it doesn't exist."""
    if not FOTO_DIR.exists():
        print("Initializing Footo directories...")
    FOTO_DIR.mkdir(exist_ok=True)
    MODULES_DIR.mkdir(exist_ok=True)
    LOCAL_MODULES_DIR.mkdir(exist_ok=True)
    BUNDLED_MODULES_DIR.mkdir(exist_ok=True)
    COMMUNITY_MODULES_DIR.mkdir(exist_ok=True)
    if not FOTO_DIR.exists(): # Only print if it was actually created
        print(f"Created directory structure at: {FOTO_DIR}")

def list_modules():
    """Lists all available modules, grouped by scope."""
    print("Available modules:")

    def print_modules_in_scope(scope_dir, scope_name):
        print(f"  {scope_name}:")
        if not scope_dir.exists() or not any(scope_dir.iterdir()):
            print("    (no modules found)")
            return

        for module_dir in sorted(scope_dir.iterdir()):
            if module_dir.is_dir():
                meta_file = module_dir / "meta.json"
                if meta_file.exists():
                    try:
                        with open(meta_file, 'r') as f:
                            meta = json.load(f)
                        print(f"    - {meta.get('name', module_dir.name)} (v{meta.get('version', 'N/A')})")
                        print(f"      {meta.get('description', '')}")
                    except json.JSONDecodeError:
                        print(f"    - {module_dir.name} (Error: Invalid meta.json)")
                else:
                    print(f"    - {module_dir.name} (Error: meta.json not found)")

    print_modules_in_scope(LOCAL_MODULES_DIR, "local")
    print_modules_in_scope(BUNDLED_MODULES_DIR, "bundled")

def create_module(module_name):
    """Creates a new module template."""
    module_path = LOCAL_MODULES_DIR / module_name

    if module_path.exists():
        print(f"Error: Module '{module_name}' already exists in local scope.")
        return

    # Check if module exists in bundled scope (to avoid name conflicts)
    if (BUNDLED_MODULES_DIR / module_name).exists():
        print(f"Error: Module '{module_name}' already exists in bundled scope. Please choose a different name.")
        return

    print(f"Creating new module: {module_name} at {module_path}")
    module_path.mkdir(parents=True)

    # Determine shell type for default script
    # For now, default to bash. Will implement shell detection later.
    script_lang = "bash"
    script_ext = ".sh"

    meta_content = {
        "name": module_name,
        "version": "0.1.0",
        "description": f"A new {module_name} module.",
        "lang": script_lang,
        "entry": f"script{script_ext}"
    }

    meta_file = module_path / "meta.json"
    with open(meta_file, 'w') as f:
        json.dump(meta_content, f, indent=2)

    script_content = f"#!/{script_lang}/bin/{script_lang}\n\necho \"Hello from {module_name}!\"\n"
    script_file = module_path / f"script{script_ext}"
    with open(script_file, 'w') as f:
        f.write(script_content)

    print(f"Module '{module_name}' created successfully.")
    print(f"You can edit your module files here: {module_path}")

    # Attempt to open editor
    editor = os.environ.get('EDITOR')
    if editor:
        try:
            print(f"Opening files in {editor}...")
            subprocess.run([editor, str(meta_file), str(script_file)])
        except FileNotFoundError:
            print(f"Warning: Editor '{editor}' not found. Please open files manually.")
    else:
        print("Warning: EDITOR environment variable not set. Please open files manually.")

def get_module_info(module_name):
    """Displays information about a specific module."""
    module_meta = None
    module_scope = None
    module_dir = None

    # Check local scope
    local_module_path = LOCAL_MODULES_DIR / module_name
    if local_module_path.exists() and local_module_path.is_dir():
        module_dir = local_module_path
        module_scope = "local"
    else:
        # Check bundled scope
        bundled_module_path = BUNDLED_MODULES_DIR / module_name
        if bundled_module_path.exists() and bundled_module_path.is_dir():
            module_dir = bundled_module_path
            module_scope = "bundled"

    if module_dir:
        meta_file = module_dir / "meta.json"
        if meta_file.exists():
            try:
                with open(meta_file, 'r') as f:
                    module_meta = json.load(f)
                
                print(f"Module: {module_meta.get('name', module_name)}")
                print(f"  Scope: {module_scope}")
                print(f"  Version: {module_meta.get('version', 'N/A')}")
                print(f"  Description: {module_meta.get('description', 'N/A')}")
                print(f"  Language: {module_meta.get('lang', 'N/A')}")
                print(f"  Entry Script: {module_meta.get('entry', 'N/A')}")
                print(f"  Path: {module_dir}")

                if 'args' in module_meta and module_meta['args']:
                    print("\n  Arguments:")
                    for arg in module_meta['args']:
                        print(f"    {arg.get('name', 'N/A')}:")
                        print(f"      Description: {arg.get('description', 'N/A')}")
                        print(f"      Type: {arg.get('type', 'N/A')}")
                        if 'defaultValue' in arg:
                            print(f"      Default: {arg.get('defaultValue')}")

            except json.JSONDecodeError:
                print(f"Error: Invalid meta.json for module '{module_name}' at {meta_file}")
        else:
            print(f"Error: meta.json not found for module '{module_name}' at {module_dir}")
    else:
        print(f"Error: Module '{module_name}' not found in local or bundled scope.")

def run_module(module_name, args):
    """Executes a module by printing the command to source it."""
    module_meta = None
    module_dir = None

    # Search for module
    local_module_path = LOCAL_MODULES_DIR / module_name
    if local_module_path.exists() and local_module_path.is_dir():
        module_dir = local_module_path
    else:
        bundled_module_path = BUNDLED_MODULES_DIR / module_name
        if bundled_module_path.exists() and bundled_module_path.is_dir():
            module_dir = bundled_module_path

    if not module_dir:
        print(f"Error: Module '{module_name}' not found in local or bundled scope.", file=sys.stderr)
        sys.exit(1)

    meta_file = module_dir / "meta.json"
    if not meta_file.exists():
        print(f"Error: meta.json not found for module '{module_name}' at {module_dir}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(meta_file, 'r') as f:
            module_meta = json.load(f)
    except json.JSONDecodeError:
        print(f"Error: Invalid meta.json for module '{module_name}' at {meta_file}", file=sys.stderr)
        sys.exit(1)

    script_lang = module_meta.get('lang')
    entry_script_name = module_meta.get('entry')

    if not script_lang or not entry_script_name:
        print(f"Error: 'lang' or 'entry' missing in meta.json for module '{module_name}'.", file=sys.stderr)
        sys.exit(1)

    entry_script_path = module_dir / entry_script_name
    if not entry_script_path.exists():
        print(f"Error: Entry script '{entry_script_name}' not found for module '{module_name}' at {module_dir}", file=sys.stderr)
        sys.exit(1)

    # Construct the sourcing command based on language
    if script_lang == "bash":
        command_prefix = "source"
    elif script_lang == "pwsh":
        command_prefix = "."
    else:
        print(f"Error: Unsupported script language '{script_lang}' for module '{module_name}'.", file=sys.stderr)
        sys.exit(1)

    # Escape arguments for shell execution
    escaped_args = [f"\'{arg}\'" for arg in args] # Simple escaping, might need more robust solution

    # Print the command to be sourced by the parent shell
    print(f"{command_prefix} \"{entry_script_path}\" {' '.join(escaped_args)}")

def main():
    """Main entry point for the Footo CLI."""
    initialize_directories()

    parser = argparse.ArgumentParser(description="Footo: A command interface for reusable terminal functions.")
    subparsers = parser.add_subparsers(dest="command")

    # To be implemented: create, run, list, info commands
    parser_create = subparsers.add_parser("create", help="Create a new module.")
    parser_create.add_argument("name", help="The name of the module to create.")

    parser_run = subparsers.add_parser("run", help="Run a module.")
    parser_run.add_argument("name", help="The name of the module to run.")
    parser_run.add_argument("args", nargs=argparse.REMAINDER, help="Arguments to pass to the module.")

    parser_list = subparsers.add_parser("list", help="List all available modules.")

    parser_info = subparsers.add_parser("info", help="Get information about a module.")
    parser_info.add_argument("name", help="The name of the module.")

    # If no command is given, treat it as a module execution
    if len(sys.argv) > 1 and sys.argv[1] not in subparsers.choices:
        # This is where the module execution logic will go
        # For now, we'll just print a message
        print(f"Attempting to execute module: {sys.argv[1]}")
        # In a real implementation, this would trigger the `run` command logic.
        # For now, we'll re-parse with 'run' as the command.
        args = parser.parse_args(['run'] + sys.argv[1:])
    else:
        args = parser.parse_args()

    if args.command == "create":
        create_module(args.name)
    elif args.command == "run":
        run_module(args.name, args.args)
    elif args.command == "list":
        list_modules()
    elif args.command == "info":
        get_module_info(args.name)
    elif args.command is None and len(sys.argv) == 1:
        parser.print_help()


if __name__ == "__main__":
    main()
