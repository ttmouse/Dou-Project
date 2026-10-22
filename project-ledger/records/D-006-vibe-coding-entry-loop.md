# D-006：以 30 秒进入工作状态作为 vibe coding P0

```json
{
  "id": "D-006",
  "kind": "decision",
  "status": "active",
  "summary": "ProjectManager 面向 vibe coding 爱好者时，P0 是让用户在 30 秒内从选择目录进入项目工作状态",
  "scope": ["Sources/ProjectManager/Views", "Sources/ProjectManager/Models", "Sources/ProjectManager/Utilities"],
  "sources": ["project-ledger/evidence/2026-09-20-p0-vibe-loop.md", "README.md", "USER_GUIDE.md"],
  "relations": [{"type": "related_to", "target": "D-002"}],
  "key": "product-entry-loop",
  "recorded_at": "2026-09-20"
}
```

## 决定

首要用户闭环是：启动应用 → 选择项目目录 → 看到扫描结果 → 一键打开编辑器继续工作。标签、热力图、分支高级操作不应先于该闭环。

扫描反馈采用非阻断呈现，不阻塞用户继续操作。同一工作状态必须只有一个可见呈现，不再叠加已有刷新浮层。扫描完成提示只短暂展示，随后自动收起。

## 依据

用户在 2026-09-20 当前会话明确要求先做“P0 30 秒闭环”，并明确：原有刷新浮层是阻断式的，倾向改为非阻断方案；同时纠正扫描状态实现不应重复呈现、扫描结束后不应持续显示。

## 验证状态

已在代码中验证并实现：新增目录和刷新目录都显示主界面非阻断扫描状态；移除原有阻断式刷新浮层；完成状态 1.5 秒后回到空闲。发布版构建成功，应用已启动。真实交互验收仍待用户体验确认。
