#!/usr/bin/env python3
"""
Flutter Project Structure Analysis
Analyzes the Flutter project structure and dependencies
"""

import os
import re
import yaml
from pathlib import Path
from typing import Dict, List

def analyze_pubspec():
    """Analyze pubspec.yaml for dependencies"""
    pubspec_path = Path("pubspec.yaml")
    if not pubspec_path.exists():
        return {"error": "pubspec.yaml not found"}
    
    try:
        with open(pubspec_path, 'r') as f:
            pubspec = yaml.safe_load(f)
            
        deps = pubspec.get('dependencies', {})
        dev_deps = pubspec.get('dev_dependencies', {})
        
        return {
            "name": pubspec.get('name'),
            "version": pubspec.get('version'),
            "sdk_constraints": pubspec.get('environment', {}),
            "dependencies_count": len(deps),
            "dev_dependencies_count": len(dev_deps),
            "has_testing_deps": any(dep in dev_deps for dep in ['flutter_test', 'mocktail', 'patrol']),
            "dependencies": list(deps.keys()),
            "dev_dependencies": list(dev_deps.keys())
        }
    except Exception as e:
        return {"error": str(e)}

def analyze_file_structure():
    """Analyze the Flutter project file structure"""
    structure = {}
    dart_files = list(Path('.').rglob('*.dart'))
    
    structure['total_dart_files'] = len(dart_files)
    structure['directories'] = {}
    
    for dart_file in dart_files:
        dir_name = str(dart_file.parent)
        if dir_name not in structure['directories']:
            structure['directories'][dir_name] = []
        structure['directories'][dir_name].append(dart_file.name)
    
    return structure

def analyze_imports(file_path):
    """Analyze imports in a Dart file"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            
        imports = re.findall(r"import\s+['\"]([^'\"]+)['\"];", content)
        return {
            "imports": imports,
            "flutter_imports": [imp for imp in imports if imp.startswith('package:flutter/')],
            "local_imports": [imp for imp in imports if not imp.startswith('package:') and not imp.startswith('dart:')],
            "package_imports": [imp for imp in imports if imp.startswith('package:') and not imp.startswith('package:flutter/')]
        }
    except Exception as e:
        return {"error": str(e)}

def analyze_main_files():
    """Analyze key files in the project"""
    key_files = {
        'main.dart': 'lib/main.dart',
        'app.dart': 'lib/app.dart',
        'pubspec.yaml': 'pubspec.yaml'
    }
    
    analysis = {}
    
    for name, path in key_files.items():
        file_path = Path(path)
        if file_path.exists():
            if path.endswith('.dart'):
                analysis[name] = analyze_imports(file_path)
                # Get file size and line count
                with open(file_path, 'r') as f:
                    content = f.read()
                    analysis[name]['lines'] = len(content.split('\n'))
                    analysis[name]['size'] = len(content)
            analysis[name]['exists'] = True
        else:
            analysis[name] = {'exists': False}
    
    return analysis

def main():
    print("🔍 Analyzing Flutter Project Structure...")
    print("=" * 50)
    
    # Analyze pubspec.yaml
    pubspec_info = analyze_pubspec()
    if "error" not in pubspec_info:
        print(f"📱 Project: {pubspec_info['name']}")
        print(f"📦 Version: {pubspec_info['version']}")
        print(f"🔧 Dependencies: {pubspec_info['dependencies_count']}")
        print(f"🧪 Dev Dependencies: {pubspec_info['dev_dependencies_count']}")
        print(f"✅ Has Testing Deps: {pubspec_info['has_testing_deps']}")
    else:
        print(f"❌ Pubspec Error: {pubspec_info['error']}")
    
    print("\n" + "=" * 50)
    
    # Analyze file structure
    structure = analyze_file_structure()
    print(f"📁 Total Dart Files: {structure['total_dart_files']}")
    print(f"📂 Directories: {len(structure['directories'])}")
    
    # Show key directories
    key_dirs = ['lib', 'test', 'lib/core', 'lib/features', 'lib/data']
    for dir_name in key_dirs:
        if dir_name in structure['directories']:
            files_count = len(structure['directories'][dir_name])
            print(f"  • {dir_name}: {files_count} files")
    
    print("\n" + "=" * 50)
    
    # Analyze main files
    main_files = analyze_main_files()
    for file_name, info in main_files.items():
        if info.get('exists'):
            print(f"✅ {file_name}")
            if 'lines' in info:
                print(f"    Lines: {info['lines']}, Size: {info['size']} bytes")
                if 'imports' in info:
                    print(f"    Imports: {len(info['imports'])} total")
                    print(f"    Flutter: {len(info['flutter_imports'])}, Packages: {len(info['package_imports'])}")
        else:
            print(f"❌ {file_name} - Missing")
    
    print("\n" + "=" * 50)
    print("📊 PROJECT ASSESSMENT")
    print("=" * 50)
    
    # Overall assessment
    has_main = main_files.get('main.dart', {}).get('exists', False)
    has_pubspec = 'error' not in pubspec_info
    has_tests = any('test' in dir_name for dir_name in structure['directories'])
    proper_structure = all(dir_name in structure['directories'] for dir_name in ['lib', 'test'])
    
    score = 0
    total_checks = 4
    
    if has_main:
        score += 1
        print("✅ Has main.dart")
    else:
        print("❌ Missing main.dart")
    
    if has_pubspec:
        score += 1
        print("✅ Valid pubspec.yaml")
    else:
        print("❌ Invalid pubspec.yaml")
    
    if has_tests:
        score += 1
        print("✅ Has test files")
    else:
        print("❌ No test files found")
    
    if proper_structure:
        score += 1
        print("✅ Proper Flutter structure")
    else:
        print("❌ Missing proper structure")
    
    percentage = (score / total_checks) * 100
    print(f"\n🏆 Project Health: {score}/{total_checks} ({percentage:.0f}%)")
    
    if percentage >= 75:
        print("🟢 Project structure looks good!")
    elif percentage >= 50:
        print("🟡 Project has some issues but is workable")
    else:
        print("🔴 Project has significant structural issues")

if __name__ == "__main__":
    main()