import Foundation

/// 自动标签生成器 - Phase 1: 基于文件特征的规则引擎
///
/// 设计原则：
/// 1. 零延迟：基于文件特征，无需外部调用
/// 2. 可解释：规则清晰，用户可理解
/// 3. 可扩展：新规则易添加
enum AutoTagger {

    // MARK: - 标签生成规则

    struct TagRule {
        let name: String
        let condition: (FileManager, String) -> Bool
        let tags: [String]

        func matches(at path: String, using fileManager: FileManager = .default) -> Bool {
            return condition(fileManager, path)
        }
    }

    /// 所有定义的规则
    static let rules: [TagRule] = [
        // 前端技术栈
        TagRule(
            name: "Node.js 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/package.json")
            },
            tags: ["frontend", "nodejs", "javascript"]
        ),
        TagRule(
            name: "React 项目",
            condition: { fm, path in
                let packagePath = "\(path)/package.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: packagePath)) else { return false }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                let deps = (json["dependencies"] as? [String: Any]) ?? [:]
                let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
                return deps["react"] != nil || devDeps["react"] != nil
            },
            tags: ["react"]
        ),
        TagRule(
            name: "Vue 项目",
            condition: { fm, path in
                let packagePath = "\(path)/package.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: packagePath)) else { return false }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                let deps = (json["dependencies"] as? [String: Any]) ?? [:]
                let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
                return deps["vue"] != nil || devDeps["vue"] != nil
            },
            tags: ["vue"]
        ),
        TagRule(
            name: "TypeScript 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/tsconfig.json")
            },
            tags: ["typescript"]
        ),

        // 后端技术栈
        TagRule(
            name: "Python 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/requirements.txt") ||
                fm.fileExists(atPath: "\(path)/pyproject.toml") ||
                fm.fileExists(atPath: "\(path)/setup.py")
            },
            tags: ["backend", "python"]
        ),
        TagRule(
            name: "Java 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/pom.xml") ||
                fm.fileExists(atPath: "\(path)/build.gradle")
            },
            tags: ["backend", "java"]
        ),
        TagRule(
            name: "Kotlin 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/build.gradle.kts")
            },
            tags: ["backend", "kotlin"]
        ),
        TagRule(
            name: "Go 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/go.mod")
            },
            tags: ["backend", "golang"]
        ),
        TagRule(
            name: "Rust 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/Cargo.toml")
            },
            tags: ["backend", "rust"]
        ),
        TagRule(
            name: "Ruby 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/Gemfile")
            },
            tags: ["backend", "ruby"]
        ),

        // Swift 项目
        TagRule(
            name: "Swift 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/Package.swift") ||
                fm.fileExists(atPath: "\(path)/Package.resolved")
            },
            tags: ["swift"]
        ),

        // DevOps
        TagRule(
            name: "Docker 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/Dockerfile") ||
                fm.fileExists(atPath: "\(path)/docker-compose.yml") ||
                fm.fileExists(atPath: "\(path)/docker-compose.yaml")
            },
            tags: ["docker", "devops"]
        ),
        TagRule(
            name: "Kubernetes 项目",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/k8s") ||
                fm.fileExists(atPath: "\(path)/kubernetes")
            },
            tags: ["kubernetes", "devops"]
        ),

        // 工具/配置
        TagRule(
            name: "Git 仓库",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/.git")
            },
            tags: ["git"]
        ),
        TagRule(
            name: "CI/CD",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/.github/workflows") ||
                fm.fileExists(atPath: "\(path)/.gitlab-ci.yml") ||
                fm.fileExists(atPath: "\(path)/Jenkinsfile")
            },
            tags: ["cicd"]
        ),
        TagRule(
            name: "测试覆盖",
            condition: { fm, path in
                fm.fileExists(atPath: "\(path)/__tests__") ||
                fm.fileExists(atPath: "\(path)/tests")
            },
            tags: ["tests"]
        ),

        // 文档/代码质量
        TagRule(
            name: "README 存在",
            condition: { fm, path in
                ["README.md", "README.txt", "README.rst"].contains {
                    fm.fileExists(atPath: "\(path)/\($0)")
                }
            },
            tags: ["documentation"]
        ),
        TagRule(
            name: "LINT 配置",
            condition: { fm, path in
                [".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.yml",
                 ".pylintrc", ".flake8", ".rubocop.yml",
                 ".golangci.yml"].contains {
                    fm.fileExists(atPath: "\(path)/\($0)")
                }
            },
            tags: ["linting"]
        ),
    ]

    // MARK: - 公共 API

    /// 为指定项目路径生成自动标签
    /// - Parameters:
    ///   - projectPath: 项目目录路径
    ///   - existingTags: 现有标签（避免重复）
    /// - Returns: 生成的标签集合
    static func generateTags(for projectPath: String, existingTags: Set<String> = []) -> Set<String> {
        var autoTags: Set<String> = []

        for rule in rules {
            if rule.matches(at: projectPath) {
                for tag in rule.tags {
                    if !existingTags.contains(tag) {
                        autoTags.insert(tag)
                    }
                }
            }
        }

        return autoTags
    }

    /// 批量为多个项目生成标签
    /// - Parameters:
    ///   - projectPaths: 项目路径数组
    ///   - existingTags: 现有标签映射（路径 -> 标签集）
    /// - Returns: 项目路径到生成标签的映射
    static func generateTagsBatch(
        for projectPaths: [String],
        existingTags: [String: Set<String>] = [:]
    ) -> [String: Set<String>] {
        var results: [String: Set<String>] = [:]

        for path in projectPaths {
            results[path] = generateTags(for: path, existingTags: existingTags[path] ?? [])
        }

        return results
    }

    /// 为指定的 Project 对象应用自动标签
    /// - Parameters:
    ///   - project: 项目对象
    ///   - overwrite: 是否覆盖现有标签（默认 false，仅追加）
    /// - Returns: 更新后的 Project 对象
    static func applyAutoTags(to project: Project, overwrite: Bool = false) -> Project {
        let newTags = generateTags(for: project.path, existingTags: project.tags)

        if overwrite {
            return Project(
                id: project.id,
                name: project.name,
                path: project.path,
                tags: newTags,
                mtime: project.mtime,
                size: project.size,
                checksum: project.checksum,
                git_commits: project.git_commits,
                git_last_commit: project.git_last_commit,
                git_daily: project.git_daily,
                startupCommand: project.startupCommand,
                customPort: project.customPort,
                created: project.created,
                checked: project.checked
            )
        } else {
            let mergedTags = project.tags.union(newTags)
            return Project(
                id: project.id,
                name: project.name,
                path: project.path,
                tags: mergedTags,
                mtime: project.mtime,
                size: project.size,
                checksum: project.checksum,
                git_commits: project.git_commits,
                git_last_commit: project.git_last_commit,
                git_daily: project.git_daily,
                startupCommand: project.startupCommand,
                customPort: project.customPort,
                created: project.created,
                checked: project.checked
            )
        }
    }

    /// 调试信息：返回指定路径匹配的规则名称
    static func debugRules(for projectPath: String) -> [String] {
        return rules.filter { $0.matches(at: projectPath) }.map { $0.name }
    }
}
