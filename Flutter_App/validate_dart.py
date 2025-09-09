#!/usr/bin/env python3
"""
Dart Code Validation Script
Validates Dart code syntax, imports, and structure without Flutter SDK
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Tuple

class DartValidator:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.errors = []
        self.warnings = []
        self.files_checked = 0
        
    def validate_project(self) -> Dict[str, any]:
        """Validate entire Dart project"""
        print("🔍 Starting Dart project validation...")
        
        # Find all Dart files
        dart_files = list(self.project_root.rglob("*.dart"))
        print(f"📁 Found {len(dart_files)} Dart files to validate")
        
        results = {
            'files_checked': 0,
            'syntax_errors': [],
            'import_errors': [],
            'structure_issues': [],
            'warnings': [],
            'summary': {}
        }
        
        for dart_file in dart_files:
            self._validate_dart_file(dart_file, results)
            results['files_checked'] += 1
            
        self._generate_summary(results)
        return results
    
    def _validate_dart_file(self, file_path: Path, results: Dict):
        """Validate individual Dart file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Basic syntax validation
            self._check_syntax(file_path, content, results)
            
            # Import validation
            self._check_imports(file_path, content, results)
            
            # Structure validation
            self._check_structure(file_path, content, results)
            
        except Exception as e:
            results['syntax_errors'].append({
                'file': str(file_path),
                'error': f"Failed to read file: {str(e)}"
            })
    
    def _check_syntax(self, file_path: Path, content: str, results: Dict):
        """Basic Dart syntax validation"""
        lines = content.split('\n')
        
        for i, line in enumerate(lines, 1):
            line = line.strip()
            if not line or line.startswith('//'):
                continue
                
            # Check for unmatched braces
            if line.count('{') != line.count('}'):
                open_braces = line.count('{') - line.count('}')
                if abs(open_braces) > 1:  # Allow single brace mismatch per line
                    results['syntax_errors'].append({
                        'file': str(file_path),
                        'line': i,
                        'error': f"Potential brace mismatch: {line[:50]}..."
                    })
            
            # Check for semicolon issues (basic check)
            if (line.endswith('}') or line.endswith(';')) and '=' in line and not line.startswith('//'):
                continue  # Likely valid
            elif (re.search(r'\w+\s*=\s*[^;{]+$', line) and 
                  not line.endswith(',') and 
                  not any(x in line for x in ['if', 'for', 'while', 'switch', 'try', '=>'])):
                results['syntax_errors'].append({
                    'file': str(file_path),
                    'line': i,
                    'error': f"Missing semicolon: {line[:50]}..."
                })
    
    def _check_imports(self, file_path: Path, content: str, results: Dict):
        """Validate import statements"""
        lines = content.split('\n')
        
        for i, line in enumerate(lines, 1):
            line = line.strip()
            
            # Check import format
            if line.startswith('import '):
                # Basic import format validation
                if not re.match(r"import\s+['\"][\w/:.]+['\"];?", line):
                    results['import_errors'].append({
                        'file': str(file_path),
                        'line': i,
                        'error': f"Invalid import format: {line}"
                    })
                
                # Check for missing semicolon in imports
                if not line.endswith(';'):
                    results['import_errors'].append({
                        'file': str(file_path),
                        'line': i,
                        'error': f"Missing semicolon in import: {line}"
                    })
    
    def _check_structure(self, file_path: Path, content: str, results: Dict):
        """Check code structure and patterns"""
        # Check for class definitions
        class_matches = re.findall(r'class\s+(\w+)', content)
        
        # Check if file name matches class name (convention)
        file_name = file_path.stem
        if class_matches and len(class_matches) == 1:
            class_name = class_matches[0]
            expected_filename = self._camel_to_snake(class_name)
            if file_name != expected_filename and not file_name.endswith('_test'):
                results['warnings'].append({
                    'file': str(file_path),
                    'warning': f"File name '{file_name}' doesn't match class '{class_name}' (expected: {expected_filename})"
                })
        
        # Check for proper widget structure
        if 'extends StatelessWidget' in content or 'extends StatefulWidget' in content:
            if 'Widget build(BuildContext context)' not in content:
                results['structure_issues'].append({
                    'file': str(file_path),
                    'error': "Widget missing build method"
                })
    
    def _camel_to_snake(self, name: str) -> str:
        """Convert CamelCase to snake_case"""
        return re.sub('(.)([A-Z][a-z]+)', r'\1_\2', name).lower()
    
    def _generate_summary(self, results: Dict):
        """Generate validation summary"""
        total_issues = (len(results['syntax_errors']) + 
                       len(results['import_errors']) + 
                       len(results['structure_issues']))
        
        results['summary'] = {
            'total_files': results['files_checked'],
            'total_issues': total_issues,
            'total_warnings': len(results['warnings']),
            'syntax_errors': len(results['syntax_errors']),
            'import_errors': len(results['import_errors']),
            'structure_issues': len(results['structure_issues']),
            'status': 'PASS' if total_issues == 0 else 'ISSUES_FOUND'
        }

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 validate_dart.py <flutter_project_path>")
        sys.exit(1)
    
    project_path = sys.argv[1]
    if not os.path.exists(project_path):
        print(f"Error: Project path '{project_path}' does not exist")
        sys.exit(1)
    
    validator = DartValidator(project_path)
    results = validator.validate_project()
    
    # Print results
    print("\n" + "="*60)
    print("📋 DART VALIDATION RESULTS")
    print("="*60)
    
    summary = results['summary']
    print(f"📁 Files Checked: {summary['total_files']}")
    print(f"🐛 Total Issues: {summary['total_issues']}")
    print(f"⚠️  Warnings: {summary['total_warnings']}")
    print(f"📊 Status: {summary['status']}")
    
    if results['syntax_errors']:
        print(f"\n❌ SYNTAX ERRORS ({len(results['syntax_errors'])})")
        for error in results['syntax_errors'][:5]:  # Show first 5
            print(f"  • {os.path.basename(error['file'])}:{error.get('line', '?')} - {error['error']}")
        if len(results['syntax_errors']) > 5:
            print(f"  ... and {len(results['syntax_errors']) - 5} more")
    
    if results['import_errors']:
        print(f"\n📦 IMPORT ERRORS ({len(results['import_errors'])})")
        for error in results['import_errors'][:5]:  # Show first 5
            print(f"  • {os.path.basename(error['file'])}:{error.get('line', '?')} - {error['error']}")
        if len(results['import_errors']) > 5:
            print(f"  ... and {len(results['import_errors']) - 5} more")
    
    if results['structure_issues']:
        print(f"\n🏗️  STRUCTURE ISSUES ({len(results['structure_issues'])})")
        for error in results['structure_issues']:
            print(f"  • {os.path.basename(error['file'])} - {error['error']}")
    
    if results['warnings']:
        print(f"\n⚠️  WARNINGS ({len(results['warnings'])})")
        for warning in results['warnings'][:3]:  # Show first 3
            print(f"  • {os.path.basename(warning['file'])} - {warning['warning']}")
        if len(results['warnings']) > 3:
            print(f"  ... and {len(results['warnings']) - 3} more")
    
    print("\n" + "="*60)
    
    # Exit with appropriate code
    sys.exit(0 if summary['total_issues'] == 0 else 1)

if __name__ == "__main__":
    main()