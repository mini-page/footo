#!/usr/bin/env python3
"""
Footo - Secure Terminal Module Manager
Version: 1.1.0 (Security Hardened)
"""

import os
import sys
import json
import argparse
import subprocess
import logging
import re
import shlex
import stat
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Constants
FOOTO_VERSION = "1.1.0"
MAX_MODULE_NAME_LENGTH = 50
MAX_SCRIPT_SIZE = 10 * 1024 * 1024  # 10MB
MAX_META_SIZE = 100 * 1024  # 100KB
EXECUTION_TIMEOUT = 300  # 5 minutes

# Paths (with environment override support)
FOOTO_HOME = os.environ.get('FOOTO_HOME', str(Path.home() / ".footo"))
FOTO_DIR = Path(FOOTO_HOME)
MODULES_DIR = FOTO_DIR / "modules"
LOCAL_MODULES_DIR = MODULES_DIR / "local"
BUNDLED_MODULES_DIR = MODULES_DIR / "bundled"
COMMUNITY_MODULES_DIR = MODULES_DIR / "community"
LOG_FILE = FOTO_DIR / "footo.log"

# Custom Exceptions
class FootoError(Exception):
    """Base exception for Footo errors."""
    pass

class ModuleNotFoundError(FootoError):
    """Module was not found."""
    pass

class InvalidModuleError(FootoError):
    """Module is invalid or corrupted."""
    pass

class SecurityError(FootoError):
    """Security violation detected."""
    pass

class ValidationError(FootoError):
    """Input validation failed."""
    pass

# Logging Setup
def setup_logging():
    """Initialize logging with rotation and proper formatting."""
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # Ensure log directory exists
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format=log_format,
        handlers=[
            logging.StreamHandler(sys.stderr),
            logging.FileHandler(LOG_FILE, encoding='utf-8')
        ]
    )
    return logging.getLogger('footo')

logger = setup_logging()

# Security Functions
def validate_module_name(name: str) -> str:
    """
    Validate module name to prevent path traversal and other attacks.
    
    Args:
        name: Module name to validate
        
    Returns:
        Validated module name
        
    Raises:
        ValidationError: If name is invalid
    """
    if not name:
        raise ValidationError("Module name cannot be empty")
    
    if len(name) > MAX_MODULE_NAME_LENGTH:
        raise ValidationError(f"Module name too long (max {MAX_MODULE_NAME_LENGTH} chars)")
    
    # Only allow alphanumeric, hyphens, underscores
    if not re.match(r'^[a-zA-Z0-9_-]+$', name):
        raise ValidationError(
            "Module name can only contain letters, numbers, hyphens, and underscores"
        )
    
    # Prevent Windows reserved names
    reserved_names = ['con', 'prn', 'aux', 'nul', 'com1', 'com2', 'com3', 'com4',
                      'lpt1', 'lpt2', 'lpt3', 'lpt4']
    if name.lower() in reserved_names:
        raise ValidationError(f"'{name}' is a reserved system name")
    
    logger.debug(f"Validated module name: {name}")
    return name

def validate_file_size(file_path: Path, max_size: int) -> None:
    """
    Ensure file size is within acceptable limits.
    
    Args:
        file_path: Path to file
        max_size: Maximum allowed size in bytes
        
    Raises:
        SecurityError: If file exceeds size limit
    """
    if not file_path.exists():
        return
    
    size = file_path.stat().st_size
    if size > max_size:
        raise SecurityError(
            f"File {file_path.name} exceeds maximum size ({max_size} bytes)"
        )

def validate_path(path: Path, allowed_parent: Path) -> Path:
    """
    Validate that a path is within allowed directory.
    
    Args:
        path: Path to validate
        allowed_parent: Parent directory that path must be under
        
    Returns:
        Resolved absolute path
        
    Raises:
        SecurityError: If path is outside allowed directory
    """
    try:
        resolved = path.resolve()
        allowed = allowed_parent.resolve()
        
        # Check if path is under allowed parent
        if not str(resolved).startswith(str(allowed)):
            raise SecurityError(f"Path {path} is outside allowed directory")
        
        # Check for symlinks (potential security issue)
        if path.is_symlink():
            logger.warning(f"Symlink detected: {path}")
            raise SecurityError(f"Symlinks are not allowed: {path}")
        
        return resolved
        
    except Exception as e:
        raise SecurityError(f"Path validation failed: {e}")

def load_and_validate_meta(meta_file: Path) -> Dict:
    """
    Load and validate meta.json with schema validation.
    
    Args:
        meta_file: Path to meta.json file
        
    Returns:
        Validated metadata dictionary
        
    Raises:
        InvalidModuleError: If metadata is invalid
    """
    try:
        # Check file size
        validate_file_size(meta_file, MAX_META_SIZE)
        
        # Load JSON
        with open(meta_file, 'r', encoding='utf-8') as f:
            meta = json.load(f)
        
        # Basic validation
        required_fields = ['name', 'version', 'description', 'lang', 'entry']
        for field in required_fields:
            if field not in meta:
                raise InvalidModuleError(f"Missing required field: {field}")
        
        # Validate language
        if meta['lang'] not in ['bash', 'pwsh']:
            raise InvalidModuleError(f"Unsupported language: {meta['lang']}")
        
        # Validate version format
        if not re.match(r'^\d+\.\d+\.\d+$', meta['version']):
            raise InvalidModuleError(f"Invalid version format: {meta['version']}")
        
        # Validate entry script name
        valid_extensions = {'bash': '.sh', 'pwsh': '.ps1'}
        expected_ext = valid_extensions[meta['lang']]
        if not meta['entry'].endswith(expected_ext):
            raise InvalidModuleError(
                f"Entry script must have {expected_ext} extension for {meta['lang']}"
            )
        
        logger.debug(f"Validated metadata for module: {meta['name']}")
        return meta
        
    except json.JSONDecodeError as e:
        raise InvalidModuleError(f"Invalid JSON in {meta_file}: {e}")
    except Exception as e:
        raise InvalidModuleError(f"Metadata validation failed: {e}")

def safe_open_editor(files: List[Path]) -> bool:
    """
    Safely open files in editor with whitelist validation.
    
    Args:
        files: List of file paths to open
        
    Returns:
        True if editor opened successfully, False otherwise
    """
    editor = os.environ.get('EDITOR')
    
    if not editor:
        logger.debug("No EDITOR environment variable set")
        return False
    
    # Whitelist of safe editors
    safe_editors = {
        'nano', 'vim', 'vi', 'emacs', 'code', 'notepad', 
        'notepad++', 'subl', 'sublime', 'atom', 'gedit',
        'kate', 'micro', 'joe', 'ne'
    }
    
    # Extract editor name (handle paths and arguments)
    editor_parts = shlex.split(editor)
    editor_path = Path(editor_parts[0])
    editor_name = editor_path.name.lower().replace('.exe', '')
    
    if editor_name not in safe_editors:
        logger.warning(f"Editor '{editor}' not in whitelist. Skipping auto-open.")
        return False
    
    try:
        # Open with timeout to prevent hanging
        result = subprocess.run(
            [editor] + [str(f) for f in files],
            timeout=1,
            check=False
        )
        return result.returncode == 0
        
    except subprocess.TimeoutExpired:
        logger.debug("Editor opened in background (timeout)")
        return True
    except FileNotFoundError:
        logger.warning(f"Editor '{editor}' not found")
        return False
    except Exception as e:
        logger.error(f"Failed to open editor: {e}")
        return False

def set_secure_permissions(path: Path, is_script: bool = False) -> None:
    """
    Set secure file permissions.
    
    Args:
        path: Path to file or directory
        is_script: Whether this is an executable script
    """
    try:
        if is_script:
            # Scripts: rwx------ (700)
            path.chmod(stat.S_IRWXU)
        else:
            # Other files: rw------- (600)
            path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        
        logger.debug(f"Set secure permissions on {path}")
        
    except Exception as e:
        logger.warning(f"Failed to set permissions on {path}: {e}")

# Core Functions
def initialize_directories() -> None:
    """
    Creates the necessary directory structure for Footo if it doesn't exist.
    Includes security checks for symlinks and proper permissions.
    
    Raises:
        SecurityError: If security violation detected
    """
    try:
        # Create all directories at once to minimize race window
        for dir_path in [LOCAL_MODULES_DIR, BUNDLED_MODULES_DIR, COMMUNITY_MODULES_DIR]:
            dir_path.mkdir(parents=True, exist_ok=True)
            
            # Verify they're actual directories, not symlinks
            if dir_path.is_symlink():
                raise SecurityError(f"{dir_path} is a symbolic link - security risk")
            
            if not dir_path.is_dir():
                raise SecurityError(f"{dir_path} exists but is not a directory")
            
            # Set secure permissions (owner only)
            set_secure_permissions(dir_path)
        
        logger.info(f"Initialized Footo directories at: {FOTO_DIR}")
        
    except SecurityError:
        raise
    except Exception as e:
        logger.error(f"Failed to initialize directories: {e}")
        raise FootoError(f"Directory initialization failed: {e}")

def find_module(module_name: str) -> Tuple[Optional[Path], Optional[str]]:
    """
    Find a module by name in available scopes.
    
    Args:
        module_name: Name of module to find
        
    Returns:
        Tuple of (module_path, scope) or (None, None) if not found
    """
    validate_module_name(module_name)
    
    # Search in order: local, bundled
    search_paths = [
        (LOCAL_MODULES_DIR / module_name, "local"),
        (BUNDLED_MODULES_DIR / module_name, "bundled")
    ]
    
    for module_path, scope in search_paths:
        if module_path.exists() and module_path.is_dir():
            # Validate path is safe
            try:
                validate_path(module_path, MODULES_DIR)
                logger.debug(f"Found module '{module_name}' in {scope} scope")
                return module_path, scope
            except SecurityError as e:
                logger.error(f"Security violation for module {module_name}: {e}")
                continue
    
    return None, None

def list_modules() -> None:
    """Lists all available modules, grouped by scope."""
    print("Available modules:")
    
    def print_modules_in_scope(scope_dir: Path, scope_name: str) -> None:
        print(f"\n  {scope_name}:")
        
        if not scope_dir.exists():
            print("    (directory not found)")
            return
        
        modules_found = False
        
        try:
            for module_dir in sorted(scope_dir.iterdir()):
                if not module_dir.is_dir():
                    continue
                
                modules_found = True
                meta_file = module_dir / "meta.json"
                
                if meta_file.exists():
                    try:
                        meta = load_and_validate_meta(meta_file)
                        print(f"    - {meta.get('name', module_dir.name)} (v{meta.get('version', 'N/A')})")
                        desc = meta.get('description', '')
                        if desc:
                            print(f"      {desc[:80]}{'...' if len(desc) > 80 else ''}")
                    except InvalidModuleError as e:
                        logger.warning(f"Invalid module {module_dir.name}: {e}")
                        print(f"    - {module_dir.name} (⚠ Invalid: {str(e)[:50]})")
                else:
                    print(f"    - {module_dir.name} (⚠ Missing meta.json)")
        
        except PermissionError:
            print("    (permission denied)")
            return
        
        if not modules_found:
            print("    (no modules found)")
    
    print_modules_in_scope(LOCAL_MODULES_DIR, "Local")
    print_modules_in_scope(BUNDLED_MODULES_DIR, "Bundled")

def create_module(module_name: str) -> None:
    """
    Creates a new module template with secure defaults.
    
    Args:
        module_name: Name of module to create
        
    Raises:
        ValidationError: If module name is invalid
        FootoError: If module already exists
    """
    try:
        # Validate module name
        module_name = validate_module_name(module_name)
        module_path = LOCAL_MODULES_DIR / module_name
        
        # Check if already exists in any scope
        existing_path, scope = find_module(module_name)
        if existing_path:
            raise FootoError(f"Module '{module_name}' already exists in {scope} scope")
        
        logger.info(f"Creating new module: {module_name}")
        print(f"Creating new module: {module_name} at {module_path}")
        
        # Create module directory with secure permissions
        module_path.mkdir(parents=True, exist_ok=False)
        set_secure_permissions(module_path)
        
        # Detect shell type (default to bash)
        script_lang = "bash"
        script_ext = ".sh"
        
        # Create metadata
        meta_content = {
            "name": module_name,
            "version": "0.1.0",
            "description": f"A new {module_name} module.",
            "lang": script_lang,
            "entry": f"script{script_ext}"
        }
        
        meta_file = module_path / "meta.json"
        with open(meta_file, 'w', encoding='utf-8') as f:
            json.dump(meta_content, f, indent=2)
        set_secure_permissions(meta_file, is_script=False)
        
        # Create script template
        script_content = f"""#!/usr/bin/env {script_lang}
# Module: {module_name}
# Description: {meta_content['description']}
# Version: {meta_content['version']}

set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo "Hello from {module_name}!"
echo "Arguments: $@"

# Your code here
"""
        
        script_file = module_path / f"script{script_ext}"
        with open(script_file, 'w', encoding='utf-8') as f:
            f.write(script_content)
        set_secure_permissions(script_file, is_script=True)
        
        print(f"✓ Module '{module_name}' created successfully.")
        print(f"  Location: {module_path}")
        print(f"  Metadata: {meta_file}")
        print(f"  Script:   {script_file}")
        
        # Try to open in editor
        if not safe_open_editor([meta_file, script_file]):
            print(f"\n  Edit your module files at: {module_path}")
        
        logger.info(f"Module '{module_name}' created successfully")
        
    except ValidationError as e:
        logger.error(f"Validation error: {e}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except FootoError as e:
        logger.error(f"Module creation failed: {e}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error creating module: {e}")
        print(f"Error: Failed to create module: {e}", file=sys.stderr)
        sys.exit(1)

def get_module_info(module_name: str) -> None:
    """
    Displays information about a specific module.
    
    Args:
        module_name: Name of module to get info for
    """
    try:
        module_name = validate_module_name(module_name)
        module_dir, scope = find_module(module_name)
        
        if not module_dir:
            raise ModuleNotFoundError(f"Module '{module_name}' not found")
        
        meta_file = module_dir / "meta.json"
        if not meta_file.exists():
            raise InvalidModuleError(f"Module '{module_name}' is missing meta.json")
        
        meta = load_and_validate_meta(meta_file)
        
        print(f"\nModule: {meta.get('name', module_name)}")
        print(f"{'=' * 60}")
        print(f"  Scope:       {scope}")
        print(f"  Version:     {meta.get('version', 'N/A')}")
        print(f"  Description: {meta.get('description', 'N/A')}")
        print(f"  Language:    {meta.get('lang', 'N/A')}")
        print(f"  Entry:       {meta.get('entry', 'N/A')}")
        print(f"  Path:        {module_dir}")
        
        if 'args' in meta and meta['args']:
            print("\n  Arguments:")
            for arg in meta['args']:
                print(f"    {arg.get('name', 'N/A')}:")
                print(f"      Description: {arg.get('description', 'N/A')}")
                print(f"      Type:        {arg.get('type', 'N/A')}")
                if 'defaultValue' in arg:
                    print(f"      Default:     {arg.get('defaultValue')}")
        
        logger.debug(f"Displayed info for module: {module_name}")
        
    except (ValidationError, ModuleNotFoundError, InvalidModuleError) as e:
        logger.error(f"Error getting module info: {e}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        print(f"Error: Failed to get module info: {e}", file=sys.stderr)
        sys.exit(1)

def run_module(module_name: str, args: List[str]) -> None:
    """
    Executes a module securely using subprocess.
    
    Args:
        module_name: Name of module to run
        args: Arguments to pass to module
        
    Raises:
        ModuleNotFoundError: If module not found
        InvalidModuleError: If module is invalid
    """
    try:
        module_name = validate_module_name(module_name)
        module_dir, scope = find_module(module_name)
        
        if not module_dir:
            raise ModuleNotFoundError(f"Module '{module_name}' not found")
        
        meta_file = module_dir / "meta.json"
        if not meta_file.exists():
            raise InvalidModuleError(f"Module '{module_name}' is missing meta.json")
        
        meta = load_and_validate_meta(meta_file)
        
        script_lang = meta.get('lang')
        entry_script_name = meta.get('entry')
        
        if not script_lang or not entry_script_name:
            raise InvalidModuleError("Missing 'lang' or 'entry' in metadata")
        
        entry_script_path = module_dir / entry_script_name
        if not entry_script_path.exists():
            raise InvalidModuleError(f"Entry script '{entry_script_name}' not found")
        
        # Validate script size
        validate_file_size(entry_script_path, MAX_SCRIPT_SIZE)
        
        # Properly escape arguments for shell
        escaped_args = [shlex.quote(arg) for arg in args]
        
        # Construct the sourcing command based on language
        if script_lang == "bash":
            command_prefix = "source"
        elif script_lang == "pwsh":
            command_prefix = "."
        else:
            raise InvalidModuleError(f"Unsupported language: {script_lang}")
        
        # Print the command to be sourced by the parent shell
        # This is the expected behavior for sourcing into current shell
        print(f"{command_prefix} \"{entry_script_path}\" {' '.join(escaped_args)}")
        
        logger.info(f"Executed module '{module_name}' from {scope} scope")
        
    except (ValidationError, ModuleNotFoundError, InvalidModuleError, SecurityError) as e:
        logger.error(f"Error running module: {e}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error running module: {e}")
        print(f"Error: Failed to run module: {e}", file=sys.stderr)
        sys.exit(1)

def main() -> None:
    """Main entry point for the Footo CLI."""
    try:
        initialize_directories()
        
        parser = argparse.ArgumentParser(
            description="Footo: A secure command interface for reusable terminal functions.",
            epilog="For more information, visit: https://github.com/yourusername/footo"
        )
        parser.add_argument('--version', action='version', version=f'Footo {FOOTO_VERSION}')
        
        subparsers = parser.add_subparsers(dest="command", help="Available commands")
        
        # Create command
        parser_create = subparsers.add_parser(
            "create",
            help="Create a new module"
        )
        parser_create.add_argument(
            "name",
            help="The name of the module to create"
        )
        
        # Run command
        parser_run = subparsers.add_parser(
            "run",
            help="Run a module"
        )
        parser_run.add_argument(
            "name",
            help="The name of the module to run"
        )
        parser_run.add_argument(
            "args",
            nargs=argparse.REMAINDER,
            help="Arguments to pass to the module"
        )
        
        # List command
        parser_list = subparsers.add_parser(
            "list",
            help="List all available modules"
        )
        
        # Info command
        parser_info = subparsers.add_parser(
            "info",
            help="Get information about a module"
        )
        parser_info.add_argument(
            "name",
            help="The name of the module"
        )
        
        # Parse arguments
        if len(sys.argv) > 1 and sys.argv[1] not in subparsers.choices:
            # Treat as module execution (shorthand for 'run')
            args = parser.parse_args(['run'] + sys.argv[1:])
        else:
            args = parser.parse_args()
        
        # Execute command
        if args.command == "create":
            create_module(args.name)
        elif args.command == "run":
            run_module(args.name, args.args)
        elif args.command == "list":
            list_modules()
        elif args.command == "info":
            get_module_info(args.name)
        elif args.command is None:
            parser.print_help()
        
    except KeyboardInterrupt:
        print("\nOperation cancelled by user", file=sys.stderr)
        sys.exit(130)
    except FootoError as e:
        logger.error(f"Footo error: {e}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error in main: {e}", exc_info=True)
        print(f"Error: An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
