# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ProjectManager (项目管理器) is a macOS SwiftUI application for managing development projects. It provides project discovery, tagging, directory watching, and integration with various editors like Cursor, VSCode, and Trae AI.

## Build and Development Commands

### Primary Build Commands
```bash
# Quick build and package
./build.sh

# Manual build process
swift build -c release

# Version management
./scripts/increment_version.sh [patch|minor|major]
```

### Icon Generation
```bash
# Generate app icon from icon.png (if exists)
./make_icon.sh
```

### Package Structure
- **Platform**: macOS 12+
- **Swift Tools Version**: 5.7
- **Target**: Executable with bundled resources
- **Dependencies**: None (uses system frameworks only)

## Architecture Overview

### Core Components

1. **TagManager** - Central orchestrator managing all application state
   - Manages projects, tags, and watched directories
   - Coordinates between storage, color management, and UI updates
   - Handles incremental project loading and caching

2. **Tag System Integration** - ⚠️ **CRITICAL SYSTEM**
   - **WARNING**: Directly integrates with macOS file system metadata
   - Uses `com.apple.metadata:_kMDItemUserTags` for persistent tag storage
   - **Data Safety**: Tag operations must be atomic and carefully tested
   - See README.md for detailed warnings about tag system modifications

3. **Project Discovery & Indexing**
   - **ProjectIndex**: Scans directories and builds project cache
   - **DirectoryWatcher**: Manages watched directories and incremental updates
   - **Project**: Core model with Git integration and file system metadata

4. **UI Architecture**
   - **ProjectListView**: Main interface with HSplitView layout
   - **SidebarView**: Tag filtering and directory management
   - **MainContentView**: Project grid with search and sorting
   - **ProjectCard**: Individual project display with context menus

### Data Flow

1. **Startup**: Load cached projects → Display immediately → Background refresh
2. **Project Changes**: Incremental detection → Cache update → UI refresh
3. **Tag Operations**: UI action → TagManager → System sync → Cache save
4. **Search/Filter**: Real-time filtering of cached project data

### File System Integration

- **Tag Storage**: macOS extended attributes (`xattr`)
- **Project Cache**: JSON files in Application Support
- **Preferences**: UserDefaults + custom editor settings
- **Git Integration**: Process-based git command execution

## Development Guidelines

### 🔥 REFACTORING CORE PRINCIPLES (CRITICAL)
**When refactoring ANY code in this project:**
1. **UI功能完整性** - 所有现有的UI交互功能必须100%保留
2. **零功能丢失** - 用户能做的每一个操作都必须在重构后继续可用
3. **向后兼容** - 用户数据、偏好设置、标签等必须完全兼容
4. **渐进式重构** - 重构必须是增量的，不能破坏现有功能
5. **测试验证** - 每个重构步骤都要验证功能完整性

### Tag System Safety (⚠️ CRITICAL)
When modifying tag-related code:
1. **Read README.md tag system warnings first**
2. Test on backup data only
3. Verify tag persistence across app restarts
4. Check `TagSystemSync.swift` for implementation details
5. Ensure atomic operations in tag save/load

### Code Style (SwiftUI best practices)
- **No singletons**: Use dependency injection instead
- **Simple interfaces**: Keep protocols and APIs minimal
- **Explicit error handling**: No silent failures
- **Readable SwiftUI code**: Focus on clarity
- **Complete functionality**: No TODOs in production code
- **Incremental refactoring**: Never break existing features
- **Functional cohesion**: Split files when they have multiple unrelated responsibilities

### Key Files to Understand
- `Sources/ProjectManager/Models/TagSystemSync.swift` - Tag system integration
- `Sources/ProjectManager/Models/Project.swift` - Core project model
- `Sources/ProjectManager/Models/TagManager.swift` - Central state management
- `Sources/ProjectManager/ProjectManagerApp.swift` - App lifecycle and preferences

### Performance Considerations
- Project loading uses incremental updates to avoid UI blocking
- Tag operations are debounced (1-second delay for saves)
- File system checks have 5-minute intervals for performance
- Background project scanning preserves UI responsiveness

### Testing Strategy
The application relies on integration with macOS file system features, making testing focus on:
- Tag persistence across system operations
- Project discovery accuracy
- Cache consistency
- Editor integration functionality

### Data Backup
**Project and Tag Backup Files:**
- `projects-backup-20250823-070551.json` - Complete backup of all projects and their tags from Application Support
- Contains full project metadata, paths, tags, and Git information
- Use this file to restore project data after refactoring if needed

### Editor Integration
- Supports multiple editors via `AppOpenHelper`
- Preference-based editor selection
- Fallback mechanisms for missing editors
- Command-line tool detection and direct app launching

## Common Development Tasks

### Adding New Editor Support
1. Update editor detection in preference system
2. Add command-line tool mapping
3. Implement fallback app launching
4. Test editor availability detection

### Modifying Project Discovery
1. Review `ProjectIndex.swift` scanning logic
2. Consider cache invalidation requirements
3. Test incremental update behavior
4. Verify project deduplication

### Tag System Changes (⚠️ High Risk)
1. **MANDATORY**: Review README.md warnings
2. Test with backup project data
3. Verify system tag synchronization
4. Check cross-session persistence
5. Test bulk operations carefully

## File Structure
```
Sources/ProjectManager/
├── Models/          # Core data models and business logic
├── Views/           # SwiftUI view components
├── Utilities/       # Helper functions and integrations
├── Theme/          # Color schemes and styling
└── Resources/      # Assets and configuration files

build.sh            # Primary build script
scripts/            # Version management and build tools
```

This application integrates deeply with macOS file system features and requires careful consideration of data persistence and system integration when making modifications.