# T1 查询DTO契约

| 项目 | 内容 |
| --- | --- |
| 文档层级 | T1，应用查询契约 |
| 契约版本 | `query-dto.v1.0` |
| 权威主题 | 页面只读查询、请求模式、响应DTO、错误状态、一致性和刷新边界 |
| 当前状态 | 第一版查询身份与DTO已封闭；查询投影器待按本文实现 |
| 适用范围 | 全局外壳、虫巢、地图、战场、进化、虫群、日志与存档页面 |
| 机器来源 | `res://data/contracts/v1/query_registry.json` |
| 直接依赖 | `L5_页面信息架构与交互契约.md`、`l3-interface.v1.0`、`runtime-expression.v1.0` |

页面只读取查询DTO，不读取领域状态字典、内容内部索引、事件`details`或场景节点缓存。每个响应来自一个完整稳定快照，页面不能把多个不同状态版本的结果拼成新的玩法结论。

---

## 1. 请求与响应信封

请求统一字段：

```text
query_id
request_id
parameters
expected_state_version?
```

响应统一字段：

```text
query_id
request_id
query_version
state_version
snapshot_step
status
data
error
```

`status`只允许：`ok`、`empty`、`not_found`、`invalid_request`、`unavailable`和`stale_version`。`ok`必须返回登记DTO；错误状态的`data = null`并返回`dto.error.v1`。`empty`按各查询登记决定返回`null`或结构完整的空DTO。

加载中是应用层等待请求的表现状态，不是领域响应状态。页面可以保留旧快照，但必须标记其状态版本并禁止基于旧资格直接提交命令；命令提交仍会在当前边界重新验证。

## 2. 类型系统

机器注册表使用有限类型：基础类型、已登记枚举、`dto:*`、`array<*>`以及命令注册表提供的`interface_command_draft`。DTO字段必须声明名称、类型和必填性；未知字段不自动透传。

混合整数/浮点预览使用`dto.numeric_value.v1`，同时携带`value_type`和单位。页面不得把格式化文本反向解析成玩法值。

所有集合按稳定ID或契约声明的游标排序。数组位置不是实例身份，页面更新必须以稳定ID为键。

## 3. 第一版查询目录

| 查询ID | 主要页面 | 返回DTO |
| --- | --- | --- |
| `query.global_shell` | 全局顶部带、主动战场带和异常汇总 | `dto.global_shell.v1` |
| `query.hive.overview` | 虫巢剖面 | `dto.hive_overview.v1` |
| `query.hive.room_group_detail` | 房间群详情 | `dto.room_group_detail.v1` |
| `query.command.preview` | 建设、重组、批次、同化和撤离确认 | `dto.command_preview.v1` |
| `query.world.overview` | 世界地图 | `dto.world_map.v1` |
| `query.world.region` | 区域网状地图 | `dto.region_map.v1` |
| `query.world.node` | 节点观察与进攻入口 | `dto.node_detail.v1` |
| `query.battle.active` | 节点长战场 | `dto.battle_snapshot.v1` |
| `query.evolution.overview` | 进化页 | `dto.evolution_overview.v1` |
| `query.evolution.candidate_group` | 候选选择弹层 | `dto.candidate_group_detail.v1` |
| `query.ascension.preview` | 飞升预览 | `dto.ascension_preview.v1` |
| `query.swarm.overview` | 虫群页 | `dto.swarm_overview.v1` |
| `query.ledger.page` | 资源账目 | `dto.ledger_page.v1` |
| `query.event_log.page` | 事件日志 | `dto.event_log_page.v1` |
| `query.command.result` | 命令回执和拒绝显示 | `dto.command_result.v1` |
| `query.save.slots` | 标题页和存档槽页 | `dto.save_slots.v1` |

`query.command.preview`的输入不是任意字典，而是通过`l3-interface.v1.0`字段模式验证的命令草案。预览不创建命令ID、不预留资源、不推进随机流；返回的资格和差异只对应响应中的`state_version`。

## 4. 权威与派生边界

每个查询机器定义列出`authority_roots`。投影器可以计算显示所需汇总，但必须在同一查询内由权威状态形成。例如：

- 战况进度、出生、死亡和剩余数量由`query.battle.active`一次返回。
- 房间堵塞原因、功率服务和任务进度由房间查询一次返回。
- 飞升点、具体永久收益和领袖差异由飞升查询使用编译表达式形成。
- `legal_commands`由领域资格检查形成，页面不根据按钮状态自行推导。

页面不得跨查询计算占领、支付、伤亡、产出完成、同化成功或撤离回流。

## 5. 刷新与增量边界

第一版不提供字段级增量DTO。事件的`invalidation_group`只表示哪些查询缓存失效；应用层随后取得完整新DTO，并按稳定ID替换对应投影。

- 同一`state_version`的重复查询必须返回规范等价结果。
- 新响应版本小于页面现有版本时丢弃。
- 分页账目使用稳定条目ID游标，事件日志使用`global_sequence`游标；新条目不能改变已返回页的成员顺序。
- 页面错过全部事件后，重新执行当前页面查询必须恢复正确状态。

以后若增加字段级补丁，必须建立新的查询契约版本，不能把补丁混入`query-dto.v1.0`完整快照。

## 6. 空、缺失与错误

- 无主动战场：`query.battle.active -> empty, data = null`。
- 空账目或空日志页：`empty`并返回结构完整、数组为空的分页DTO。
- 稳定ID不存在：`not_found`，不返回相似对象或默认对象。
- 请求缺字段、未知字段或类型错误：`invalid_request`。
- 请求声明的预期版本已过期：`stale_version`。
- 会话未建立、配置错误或状态根不可读：`unavailable`。

错误DTO只给出稳定错误码和事实ID，不提供策略建议，不泄露堆栈或内部公式。

## 7. 版本与兼容

删除字段、改变类型或必填性、改变状态语义、排序、分页规则、权威根或空值策略都必须提升查询版本。只增加新查询可以提升次版本；旧查询在兼容期内必须保持原DTO。

存档不保存页面DTO。载入后所有页面都从当前状态根重新投影。

## 8. 验收

| ID | 必须证明 |
| --- | --- |
| T1C-010 | 16个查询ID、请求字段、响应DTO、状态、权威根和失效组均可机器解析 |
| T1C-011 | 所有DTO类型、枚举和嵌套引用闭合且无重复字段 |
| T1C-012 | 页面不能取得领域可变字典或事件诊断载荷 |
| T1C-013 | 任意页面丢失事件后可由完整查询快照重建 |
| T1C-014 | 不同状态版本不会被页面拼接成权威结论 |
