# 局部成果：A 方案

> 验证资料管理：本文保留结论与复现方法；原始截图、日志、逐局记录和冻结源码仅存于 Git 忽略的 `.tmp/`，不随云端提交。历史记录路径仅供本地排查，清理后可按脚本、参数和版本重新生成。

这是观察反馈，不增加资源、行动或保护次数，不修改模拟公式与 80% 连续 5 世代胜利条件。

- 温饱：仅追踪农艺改良或更多务农实际改变的、行动前温饱低于 1 的土地；本轮结束时至少一个追踪对象温饱达到 1 才完成。
- 探索：仅追踪制度试验实际新建立的探索制度；至少一半追踪对象在每个世代的前后快照都保持探索型，完整存续一轮才完成。
- 技术：本轮真实技术流记录的来源必须是该行动实际提高相应技术的土地，去向是原始选区外的直接邻格，流量为正。同种技术匹配；选区内部学习与自然强源不能完成此目标。
- 每类每局仅完成一次。失败行动可以在后续轮重新尝试；已完成历史不随衰退消失；重开全部清空。
- 提前终局且未满整轮时，不完成温饱或探索目标。传播可在本轮演进时即时记录。

## 玩家文案与表现

主界面沿用现有 nextGoal 行，完成后显示最新局部成果；达到全球胜利占比时仍优先显示连续达标进度。完成历史在原有“文明进程”滚动面板顶部展示；不自动开面板、不增加 Toast。

温饱文案仅表达追踪范围：恢复温饱的范围不到一半为“少许改善”，至少一半为“明显改善”，全部为“大幅改善”。这些区分不影响触发条件、奖励或世界状态；玩家不看到格数。不是食物产量或人口增幅评级。

探索显示“探索制度站稳了脚跟”，技术显示“技术开始传向周边”。详情说明观察范围与自然演进的影响，不把整个世界的变化都归因于玩家。

## 接入 API

`require("OriginProgress").Local` 与 `require("OriginLocalMilestones")` 返回同一模块。

1. `state = Local.New()`：一局一个独立状态，启动和重开时重新创建。
2. `candidate = Local.Capture(world, action, x, y, withProtection)`：必须在 `Simulation.ApplyAction` 前调用，保存完整原始选区与行动前快照；无效行动返回 nil。
3. `Local.CommitAction(state, world, candidate)`：仅在 ApplyAction 返回成功后调用，绑定实际行动记录。失败、错配或重复登记返回 false。
4. `events = Local.Evaluate(state, world)`：每世代结算后调用。顺序读取历史并补读遗漏世代，返回本次新完成的事件；重复调用返回空数组。

`state.completed[kind]` 保存 food / exploration / technology 首次事件，`state.history` 按完成顺序保存全部事件。事件字段：kind、title、detail、generation、round、action、region={x,y,size}、evidence。evidence 保留 fedIndices/hungryTotal、survivedIndices/establishedTotal 或 flow，全部复制自行动/报告，不修改源数据。

地区名称后续可以按事件 region 和 evidence 索引对接 world.cellRegionIds / world.regions。判定始终绑定原 5×5 选区，不以点击后的地区名称、选区或地区边界替代。

## 验证与证据边界

运行 `py -3.11 scripts/verify_local_milestones.py`，复用项目现有 `.tmp/winability-deps` 中的 lupa 2.8 / Lua 5.4。结果保存到 `.tmp/verification/local-milestones/local-milestones-results.json`，含来源哈希。

OriginLocalMilestonesTests 检查触发边界、真实传播、失败与重复、存续中断、历史与重开及正式世界逐世代等价。OriginLocalMilestonesViewTests 在独立 Lua 运行时使用控件替身执行真实 main/View 回调，验证行为与声明式属性，不证明排版或渲染正确。

OriginLocalMilestonesAcceptance 是独立引擎入口，包含真实 UI 指针事件、横屏/小屏边界、历史与重开检查。它采用明确的测试夹具，不代表正式地图通关。

2026-10-08 已在安装后的 Windows Runtime 中通过 `OriginRuntimeAcceptance.lua` 包装入口完成真实窗口验收：原有14项全部通过，另有3项衰退后历史保留检查和6项默认河流地图检查，共23项。真实 backbuffer 截图已保存并读取；标准历史见 `.tmp/screenshots/cloud-submit-20261010/runtime-v16-milestones-history.png`，模拟780×420、UI倍率1.8的小屏历史见 `.tmp/screenshots/cloud-submit-20261010/runtime-v16-milestones-compact.png`。正式重开清空完成记录及候选目标。

首次运行发现 `nextGoal` 超出固定高度进度栏；`Journey` 已改为按真实文本行高撑开。复验不再出现这项边界失败或布局溢出警告。控件替身的5项回归也通过，证据为 `.tmp/verification/cloud-submit-20261010/local-milestones-view-results.json`；旧版完整模型测试证据保留，未用替身结果代替引擎排版验收。

详细结果与源码摘要：`.tmp/verification/cloud-submit-20261010/runtime-v16-acceptance-results.json`。验收通过真实 UI 事件分发执行 PointerDown/PointerUp，没有通过操作系统鼠标或手机实测；小屏为引擎内模拟。Windows 窗口采集工具超时后，改用引擎 `Graphics:TakeScreenShot` 读取真实像素。Runtime仍报告天空贴图和themis组件两条启动错误，CLI `preview check` 因此为FAIL；游戏成功启动、23项检查及截图结果单独留证，不把该FAIL改写成PASS。
