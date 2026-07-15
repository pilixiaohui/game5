# game5 Bug 与体验问题模板

## 1. 先分类，再分级

同一个观察可以关联多个问题，但每条问题只有一个主要类型和一个可验证的主张。

| type | 定义 | 示例 |
| --- | --- | --- |
| `DEFECT` | 实现违反已确认规则、接口或显示事实 | 撤离后单位重复、按钮显示可用但命令必定拒绝 |
| `USABILITY` | 规则正确，但目标、操作、信息或恢复难以理解 | 玩家找不到进攻入口、无法解释能源停机 |
| `BALANCE` | 规则正确，但数值导致无意义选择、等待或单一优势策略 | 出口数分钟完成、某房间永远最优 |
| `CONTENT` | 可用机制不足以支撑目标时长、变化或继续动力 | 完成出口后无新目标，只能重复等待 |
| `ACCESSIBILITY` | 视觉、听觉、运动、输入或认知呈现排除目标玩家 | 颜色是唯一状态通道、130% 缩放裁切按钮 |
| `PERFORMANCE` | 帧时间、加载、内存或模拟吞吐不满足登记规格 | 4 倍速导致持续掉 tick |
| `TEST_HARNESS` | 测试、埋点或报告工具破坏或遗漏证据 | 关键命令没有结果事件、录像时间不同步 |
| `DESIGN_QUESTION` | 证据提示风险，但当前契约没有明确期望 | 玩家希望占领节点持续受袭，范围尚未决定 |

不要把“玩家未完成任务”自动登记为玩家错误。先判断是操作、反馈、机制、数值、内容还是测试脚本造成。

## 2. 严重度

严重度只描述对玩家、状态和验收结论的影响，不描述团队想多快修。

| severity | 定义 | 典型情形 | 终验影响 |
| --- | --- | --- | --- |
| `S0 CATASTROPHIC` | 数据或运行环境遭到不可接受破坏 | 存档不可恢复、跨目录写坏文件、安全或隐私泄露 | 立即停止，整版失败 |
| `S1 BLOCKER` | 核心流程无法继续且没有合理绕行，或权威状态错误 | 无法启动、核心软锁、资源/单位重复、必经节点不可占领 | 整版失败 |
| `S2 MAJOR` | 主要体验或功能严重受损，但存在绕行 | 反复误导、重要设置无效、严重卡顿、某类玩家无法完成任务 | 核心路径内则失败；其他情况最多条件通过 |
| `S3 MINOR` | 局部问题，不改变主要决策或结果 | 个别文字、轻微布局、短暂表现异常 | 可带入，但需评估聚集效应 |

频率低不自动降低 `S0/S1`。一次可复现的数据损坏仍是 `S0`。

## 3. 修复优先级

| priority | 含义 |
| --- | --- |
| `P0` | 停止发放当前构建，立即处理或回滚 |
| `P1` | 下一次可测试构建前必须处理 |
| `P2` | 已进入迭代计划，有明确负责人和目标版本 |
| `P3` | 已接受进入待办，不影响当前验收范围 |

严重度和优先级必须分别填写。例如已锁定到首版后的 `S2 CONTENT` 仍可能是 `P2`，但必须由范围决策人书面接受，不能修改严重度来制造通过。

## 4. 标准问题模板

```markdown
# G5-ISSUE-<流水号> <一句话描述可观察问题>

## 分类
- type: DEFECT / USABILITY / BALANCE / CONTENT / ACCESSIBILITY / PERFORMANCE / TEST_HARNESS / DESIGN_QUESTION
- severity: S0 / S1 / S2 / S3
- priority: P0 / P1 / P2 / P3
- status: NEW / TRIAGED / IN_PROGRESS / READY_TO_VERIFY / VERIFIED / REOPENED / ACCEPTED_DEVIATION
- detected_by: AUTOMATION / PLAYTEST / REVIEW / TELEMETRY / SUPPORT
- affected_gate: ACC-...

## 构建与环境
- build_commit:
- executable_sha256:
- save_version:
- session_id:
- participant_id: 仅匿名 ID
- segment:
- seed:
- OS / CPU / GPU / RAM:
- resolution / DPI / UI scale / window mode:
- input:

## 前置状态
- 新档或载入档:
- save_generation:
- 当前 tick / speed:
- 资源、能源、单位、房间、节点、战场、候选摘要:

## 复现步骤
1.
2.
3.

## 预期
引用规则、验收项、界面承诺或设计假设，避免只写“应该正常”。

## 实际
只写可观察结果和权威状态，不先推测原因。

## 影响
- 玩家是否能继续:
- 是否存在绕行及其代价:
- 状态或存档是否损坏:
- 是否跨分辨率、种子或玩家分层:

## 频率
- attempts:
- reproduced:
- affected_participants / exposed_participants:

## 证据
- event sequence / command_id:
- video timestamp:
- log path and relevant error ID:
- save archive SHA-256:
- screenshot:

## 初步归因
可留空。必须与“实际”分开。

## 修复与验证
- owner:
- target_build:
- changed_contract_or_content:
- focused_test:
- regression_suite:
- verified_build:
- verifier:
- verification_evidence:
```

## 5. 可用性与体验问题附加字段

`USABILITY / BALANCE / CONTENT / DESIGN_QUESTION` 必须追加：

```markdown
## 玩家行为证据
- task_id:
- task_prompted_at:
- natural_discovery: true / false
- highest_help_level: H0 / H1 / H2 / H3 / H4
- stall_duration_ms:
- player_words:
- expected_mental_model:
- observed_mental_model:
- eventual_recovery:

## 样本分布
- NOVICE exposed / affected:
- GENRE exposed / affected:
- RETURNING exposed / affected:
- ACCESS exposed / affected:

## 体验数据
- related_PXI_construct:
- related_metric_id:
- before_after_or_comparator:
```

单个负面评价可以形成研究观察，但若没有行为、录像、状态或重复样本支持，不直接升级为机制缺陷。反之，玩家没有抱怨也不能消除已经发生的软锁或数据损坏。

## 6. 复现状态

| reproducibility | 标准 |
| --- | --- |
| `ALWAYS` | 相同前置、种子和操作每次发生 |
| `INTERMITTENT` | 多次尝试中部分发生，已记录比例 |
| `ONCE_WITH_EVIDENCE` | 只发生一次，但日志/录像/存档足以证明 |
| `NOT_REPRODUCED` | 团队未复现，但原证据未被否定 |
| `INSUFFICIENT_EVIDENCE` | 无法确认实际发生了什么；转为研究观察，不静默关闭 |

关闭问题不要求所有缺陷都达到 `ALWAYS`。修复应针对被证据支持的状态边界，并使用原存档或最小夹具验证。

## 7. 状态流转

```text
NEW -> TRIAGED -> IN_PROGRESS -> READY_TO_VERIFY -> VERIFIED
  \                         \-> REOPENED --------/
   \-> ACCEPTED_DEVIATION
```

- `VERIFIED`：在包含修复的构建上重跑原复现步骤和相关回归，证据已归档。
- `ACCEPTED_DEVIATION`：范围决策人书面接受，写明到期版本和玩家影响。`S0/S1` 不能用此状态签发通过。
- `REOPENED`：原症状、同一根因或修复引入的等价阻断再次出现。

“开发者本机没有复现”不是关闭状态。

## 8. 去重规则

- 根因相同、表现位置不同：一个主问题，使用受影响场景列表。
- 表现相同、状态边界不同：分别登记，避免一个修复掩盖另一根因。
- 可用性问题与实现缺陷同时存在：建立关联问题，分别验证“规则正确”和“玩家能理解”。
- 同一问题影响多个参与者：追加样本和频率，不复制多条票。

## 9. 终验阻断规则

- 任一开放 `S0` 或 `S1`：`FAIL`。
- 核心循环、存档、最低分辨率、主要输入或目标无障碍范围中的开放 `S2`：`FAIL`。
- 非核心开放 `S2`：只能由验收负责人签发 `CONDITIONAL PASS`，必须有负责人、目标版本和复测项。
- 大量相同类型 `S3` 造成阅读、操作或视觉系统性障碍时，按整体影响升级为 `S2`。
- `TEST_HARNESS S1/S2` 使关键证据不可用时，不能把受影响场次计入终验。

## 10. 问题登记表

| issue_id | title | type | severity | priority | affected_gate | frequency | owner | target | status | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |
