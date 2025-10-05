#!/bin/bash

# Script to replace print statements with Logger calls in all Dart files

cd "$(dirname "$0")"

# Counter for files modified
FILES_MODIFIED=0

# Find all Dart files with print statements
while IFS= read -r file; do
    # Check if file contains print statements
    if grep -q "print(" "$file"; then
        echo "Processing: $file"

        # Check if Logger import already exists
        if ! grep -q "import.*logger.dart" "$file"; then
            # Find the last import statement line number
            last_import_line=$(grep -n "^import" "$file" | tail -1 | cut -d: -f1)

            if [ -n "$last_import_line" ]; then
                # Calculate relative path to logger
                file_depth=$(echo "$file" | sed 's|lib/||' | grep -o "/" | wc -l)
                relative_path=""
                for ((i=0; i<file_depth; i++)); do
                    relative_path="../$relative_path"
                done

                # Add Logger import after last import
                sed -i '' "${last_import_line}a\\
import '${relative_path}core/utils/logger.dart';
" "$file"
                echo "  Added Logger import"
            fi
        fi

        # Replace print statements with Logger.debug
        # Pattern 1: print('message');
        sed -i '' "s/print('\([^']*\)');/Logger.debug('\1');/g" "$file"

        # Pattern 2: print("message");
        sed -i '' 's/print("\([^"]*\)");/Logger.debug("\1");/g' "$file"

        # Pattern 3: print('message $variable');
        sed -i '' "s/print('\(.*\)\\\$\(.*\)');/Logger.debug('\1\\\$\2');/g" "$file"

        # Pattern 4: print("message $variable");
        sed -i '' 's/print("\(.*\)\$\(.*\)");/Logger.debug("\1\$\2");/g' "$file"

        FILES_MODIFIED=$((FILES_MODIFIED + 1))
        echo "  Replaced print statements"
    fi
done < <(find lib -name "*.dart" -type f)

echo ""
echo "✅ Modified $FILES_MODIFIED files"
echo "Remaining print statements: $(grep -r "print(" lib --include="*.dart" | wc -l | xargs)"
