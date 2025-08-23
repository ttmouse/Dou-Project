#!/bin/bash
# Tag backup script - Linus style: simple, direct, works
# Backs up macOS extended attributes containing project tags

BACKUP_FILE="project-tags-backup-$(date +%Y%m%d-%H%M%S).txt"

echo "Starting tag backup to: $BACKUP_FILE"
echo "# Project Tags Backup - $(date)" > "$BACKUP_FILE"
echo "# Format: path|tags" >> "$BACKUP_FILE"

# Find all directories with tags and dump them
find . -type d -name ".git" -prune -o -type d -print0 | \
    while IFS= read -r -d '' dir; do
        # Get raw binary data and convert to readable format
        tags_raw=$(xattr -p com.apple.metadata:_kMDItemUserTags "$dir" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Convert hex to binary and parse with plutil
            echo -n "$tags_raw" | xxd -r -p | plutil -convert json -o - - 2>/dev/null | \
            if read tags_json; then
                echo "$dir|$tags_json" >> "$BACKUP_FILE"
            else
                echo "$dir|RAW:$tags_raw" >> "$BACKUP_FILE"
            fi
        fi
    done

echo "Backup complete: $BACKUP_FILE"
wc -l "$BACKUP_FILE"