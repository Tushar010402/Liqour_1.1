#!/usr/bin/env python3
import os
import re
from pathlib import Path

def get_relative_logger_path(dart_file_path):
    """Calculate relative path to logger.dart from a given file"""
    # Get path relative to lib/
    rel_from_lib = Path(dart_file_path).relative_to(Path('lib'))
    depth = len(rel_from_lib.parts) - 1
    prefix = '../' * depth
    return f"{prefix}core/utils/logger.dart"

def add_logger_import(content, dart_file_path):
    """Add Logger import if not present"""
    if 'logger.dart' in content:
        return content

    # Find last import statement
    import_pattern = r'^import\s+[\'"].*[\'"];?\s*$'
    lines = content.split('\n')
    last_import_idx = -1

    for i, line in enumerate(lines):
        if re.match(import_pattern, line):
            last_import_idx = i

    if last_import_idx >= 0:
        logger_path = get_relative_logger_path(dart_file_path)
        logger_import = f"import '{logger_path}';"
        lines.insert(last_import_idx + 1, logger_import)
        return '\n'.join(lines)

    return content

def replace_print_statements(content):
    """Replace print() with Logger.debug()"""
    # This handles most common print patterns
    # Pattern: print('...');  or print("...");
    content = re.sub(r'\bprint\s*\(', 'Logger.debug(', content)
    return content

def process_file(filepath):
    """Process a single Dart file"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # Check if file has print statements
        if 'print(' not in content:
            return False

        # Add Logger import
        content = add_logger_import(content, filepath)

        # Replace print with Logger.debug
        content = replace_print_statements(content)

        # Write back
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

        return True
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

def main():
    os.chdir(Path(__file__).parent)

    dart_files = list(Path('lib').rglob('*.dart'))
    files_modified = 0

    for filepath in dart_files:
        if process_file(filepath):
            files_modified += 1
            print(f"✓ {filepath}")

    print(f"\n✅ Modified {files_modified} files")

    # Count remaining prints
    remaining = 0
    for filepath in dart_files:
        with open(filepath, 'r') as f:
            remaining += f.read().count('print(')

    print(f"Remaining print statements: {remaining}")

if __name__ == '__main__':
    main()
