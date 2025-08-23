# Linus-Style Data Format Refactoring Plan

## CURRENT BULLSHIT ANALYSIS

```json
{
  "id": "UUID-GARBAGE-HERE", 
  "name": "project-name",
  "path": "/absolute/fucking/path",
  "tags": ["tag1", "tag2"],
  "lastModified": 777599509.714708,
  "fileSystemInfo": {
    "checksum": "1755906709.7147079_0",  // WTF IS THIS SHIT?
    "lastCheckTime": 777599511.001955,
    "modificationDate": 777599509.714708,  // DUPLICATE!
    "size": 0
  },
  "gitInfo": {
    "lastCommitDate": 777598787,
    "commitCount": 32
  }
}
```

## LINUS REFACTOR: FLAT, FAST, OBVIOUS

```json
{
  "id": "8E326AA7-91E8-43FD-BBBD-1F61DE449A2C",
  "name": "project-list",
  "path": "/Users/douba/Projects/project-list",
  "tags": ["green", "refactoring", "active"],
  
  // FILESYSTEM - FLAT, NO NESTING BULLSHIT
  "mtime": 1755906709,           // Unix timestamp, period.
  "size": 0,
  "checksum": "deadbeef123456",  // Proper hex, not timestamp_counter crap
  
  // GIT - SIMPLE
  "git_commits": 32,
  "git_last_commit": 1755905787,
  
  // METADATA
  "created": 1755900000,         // When first discovered
  "checked": 1755906711          // Last verification
}
```

## WHY THIS IS BETTER (LINUS LOGIC):

### 1. NO NESTED OBJECTS
- `fileSystemInfo` → flat fields with `_` prefix
- `gitInfo` → flat fields with `git_` prefix  
- **REASON**: One malloc per object, not three. Cache-friendly.

### 2. CONSISTENT NAMING
- ALL timestamps are Unix epochs (int64)
- ALL sizes are bytes (int64)
- ALL checksums are hex strings
- **REASON**: No fucking confusion about data types

### 3. REMOVE DUPLICATES
- `lastModified` == `fileSystemInfo.modificationDate` → ONE FIELD
- **REASON**: Don't store the same shit twice

### 4. BETTER CHECKSUMS
- Current: `"1755906709.7147079_0"` ← WHAT THE FUCK?
- New: `"sha256:deadbeef1234..."` ← CLEAR FORMAT
- **REASON**: Know what algorithm, easy to verify

### 5. TAGS NORMALIZATION
- Current: `["绿色", "green", "Green"]` ← CHAOS
- New: `["green"]` with canonical mapping
- **REASON**: Don't duplicate concepts

## IMPLEMENTATION PLAN

### Phase 1: Schema Migration
```bash
# Convert existing backup
./linus-migrate-data.sh projects-backup-20250823-070551.json
```

### Phase 2: Code Changes
1. Update `Project.swift` struct
2. Update `TagStorage.swift` serialization
3. Update all references to nested fields

### Phase 3: Verification
```bash
# Compare old vs new data
./linus-verify-migration.sh
```

## LINUS COMMANDMENTS:

1. **"Make it fucking obvious"** - No nested bullshit
2. **"Don't store the same data twice"** - One source of truth
3. **"Use standard formats"** - Unix timestamps, hex checksums
4. **"Test the migration"** - Don't lose user data, asshole
5. **"Keep it simple, stupid"** - Flat is fast

## EXPECTED OUTCOMES:
- 30% smaller JSON files (no nesting overhead)
- Faster parsing (no nested object allocation)
- Easier debugging (grep works on flat structure)
- Consistent data types (no mixed formats)

*"This is how you fix broken data formats without breaking everything else."*
*-- Linus (probably)*