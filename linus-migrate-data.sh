#!/bin/bash
# Linus-style migration: brutal, efficient, correct

BACKUP_FILE="$1"
OUTPUT_FILE="projects-linus-format.json"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.json>"
    exit 1
fi

echo "=== LINUS DATA MIGRATION ==="
echo "Input:  $BACKUP_FILE"
echo "Output: $OUTPUT_FILE"

python3 -c "
import json
import hashlib
import time

with open('$BACKUP_FILE') as f:
    old_data = json.load(f)

new_data = []
errors = 0

for old in old_data:
    try:
        # LINUS-STYLE FLAT STRUCTURE
        new = {
            'id': old['id'],
            'name': old['name'], 
            'path': old['path'],
            'tags': old.get('tags', []),
            
            # FILESYSTEM - FLAT
            'mtime': int(old.get('lastModified', 0)),
            'size': old.get('fileSystemInfo', {}).get('size', 0),
            'checksum': 'sha256:' + hashlib.sha256(old['path'].encode()).hexdigest()[:16],
            
            # GIT - SIMPLE  
            'git_commits': old.get('gitInfo', {}).get('commitCount', 0),
            'git_last_commit': int(old.get('gitInfo', {}).get('lastCommitDate', 0)),
            
            # METADATA
            'created': int(old.get('lastModified', 0)),  # Best guess
            'checked': int(time.time())
        }
        new_data.append(new)
        
    except Exception as e:
        errors += 1
        print(f'ERROR migrating project {old.get(\"name\", \"UNKNOWN\")}: {e}')

# WRITE MIGRATED DATA
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(new_data, f, indent=2, ensure_ascii=False)

print(f'MIGRATION COMPLETE:')
print(f'  Processed: {len(old_data)} projects')
print(f'  Migrated:  {len(new_data)} projects') 
print(f'  Errors:    {errors}')
print(f'  Output:    $OUTPUT_FILE')

# STATS COMPARISON
old_size = len(json.dumps(old_data))
new_size = len(json.dumps(new_data))
savings = (old_size - new_size) / old_size * 100

print(f'SIZE REDUCTION: {old_size} -> {new_size} bytes ({savings:.1f}% smaller)')
"

echo "=== VERIFICATION ==="
echo "Top 3 migrated projects:"
head -50 "$OUTPUT_FILE" | python3 -m json.tool | head -30