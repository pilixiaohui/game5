# game5 PXI 问卷与访谈

## 1. 使用声明

本文件依据 PXI 官方英文问卷整理：

- 完整 PXI 论文：<https://doi.org/10.1016/j.ijhcs.2019.102370>
- 官方使用指南：<https://playerexperienceinventory.org/docs>
- 官方英文问卷：<https://playerexperienceinventory.org/assets/docs/PXI_English.pdf>
- miniPXI 论文：<https://doi.org/10.1145/3549507>
- 官方 miniPXI：<https://playerexperienceinventory.org/assets/docs/miniPXI_English.pdf>

英文题项是计量基准。下列中文为 game5 内部辅助译文，尚未经过独立中文量表验证；使用中文结果时不得宣称可直接与官方基准数据比较。

形成性轮次使用 miniPXI 11 项；正式终验使用完整 33 项。单个场次不能同时填写两套问卷后把结果合并。

## 2. 施测规则

1. 在游玩结束后立即填写，主持人先不讨论设计、不解释规则、不展示缺陷列表。
2. 题项在问卷工具中按参与者随机排序，不按维度连续显示。
3. 保持原英文措辞、七点量尺和标签。需要中文时同时显示英文和冻结后的中文辅助译文。
4. 不删除看起来“不适合当前版本”的题项。若确实删除或改写，结果必须标为自定义问卷。
5. 不展示维度名，不告诉参与者哪些题测量同一概念。
6. 每题只能选择一个值；不强迫参与者填写人口信息。
7. PXI完成前不询问“好不好玩”“是不是太简单”等可能影响答案的问题。

## 3. 七点评分

| 分值 | English label | 中文辅助标签 |
| --- | --- | --- |
| `-3` | Strongly disagree | 非常不同意 |
| `-2` | Disagree | 不同意 |
| `-1` | Slightly disagree | 略微不同意 |
| `0` | Neither disagree nor agree | 既不反对也不赞同 |
| `+1` | Slightly agree | 略微赞同 |
| `+2` | Agree | 赞同 |
| `+3` | Strongly agree | 非常赞同 |

## 4. 完整 PXI 题库

题库按维度列出仅为了审计和计分。实际呈现时必须随机题序。

| item_id | 维度 | Official English item | 中文辅助译文 |
| --- | --- | --- | --- |
| `MEA-1` | Meaning | Playing the game was meaningful to me. | 游玩这款游戏对我来说是有意义的。 |
| `MEA-2` | Meaning | The game felt relevant to me. | 我觉得这款游戏与我有关联。 |
| `MEA-3` | Meaning | Playing this game was valuable to me. | 游玩这款游戏对我来说是有价值的。 |
| `CUR-1` | Curiosity | I wanted to explore how the game evolved. | 我想探索游戏会如何发展。 |
| `CUR-2` | Curiosity | I wanted to find out how the game progressed. | 我想知道游戏会如何推进。 |
| `CUR-3` | Curiosity | I felt eager to discover how the game continued. | 我渴望了解游戏接下来会怎样。 |
| `MAS-1` | Mastery | I felt I was good at playing this game. | 我觉得自己擅长玩这款游戏。 |
| `MAS-2` | Mastery | I felt capable while playing the game. | 游玩时我觉得自己能够胜任。 |
| `MAS-3` | Mastery | I felt a sense of mastery playing this game. | 游玩时我感到自己掌握了这款游戏。 |
| `AUT-1` | Autonomy | I felt free to play the game in my own way. | 我觉得可以按照自己的方式游玩。 |
| `AUT-2` | Autonomy | I felt like I had choices regarding how I wanted to play this game. | 我觉得可以选择自己想要的游玩方式。 |
| `AUT-3` | Autonomy | I felt a sense of freedom about how I wanted to play this game. | 对于如何游玩，我感到有自由度。 |
| `IMM-1` | Immersion | I was no longer aware of my surroundings while I was playing. | 游玩时我不再留意周围环境。 |
| `IMM-2` | Immersion | I was immersed in the game. | 我沉浸在游戏中。 |
| `IMM-3` | Immersion | I was fully focused on the game. | 我完全专注于游戏。 |
| `PF-1` | Progress Feedback | The game informed me of my progress in the game. | 游戏让我知道自己的进展。 |
| `PF-2` | Progress Feedback | I could easily assess how I was performing in the game. | 我能轻松判断自己的表现。 |
| `PF-3` | Progress Feedback | The game gave clear feedback on my progress towards the goals. | 游戏清楚反馈了我朝目标推进的程度。 |
| `AA-1` | Audiovisual Appeal | I enjoyed the way the game was styled. | 我喜欢这款游戏的风格呈现。 |
| `AA-2` | Audiovisual Appeal | I liked the look and feel of the game. | 我喜欢这款游戏的外观与整体感受。 |
| `AA-3` | Audiovisual Appeal | I appreciated the aesthetics of the game. | 我欣赏这款游戏的美学表现。 |
| `CH-1` | Challenge | The game was not too easy and not too hard to play. | 这款游戏既不会太容易，也不会太难。 |
| `CH-2` | Challenge | The game was challenging but not too challenging. | 游戏有挑战，但不会难得过头。 |
| `CH-3` | Challenge | The challenges in the game were at the right level of difficulty for me. | 游戏挑战的难度对我来说恰当。 |
| `EC-1` | Ease of Control | It was easy to know how to perform actions in the game. | 我很容易知道如何在游戏中执行操作。 |
| `EC-2` | Ease of Control | The actions to control the game were clear to me. | 游戏的控制操作对我来说很清楚。 |
| `EC-3` | Ease of Control | I thought the game was easy to control. | 我认为这款游戏容易控制。 |
| `GR-1` | Goals and Rules | I grasped the overall goal of the game. | 我理解了游戏的总体目标。 |
| `GR-2` | Goals and Rules | The goals of the game were clear to me. | 游戏目标对我来说很清楚。 |
| `GR-3` | Goals and Rules | I understood the objectives of the game. | 我理解游戏中的具体目标。 |
| `ENJ-1` | Enjoyment | I liked playing the game. | 我喜欢游玩这款游戏。 |
| `ENJ-2` | Enjoyment | The game was entertaining. | 这款游戏具有娱乐性。 |
| `ENJ-3` | Enjoyment | I had a good time playing this game. | 我在游玩这款游戏时感到愉快。 |

## 5. miniPXI 11 项

miniPXI使用下列官方选题，每个维度只有一题。形成性轮次可以快速比较构建，但单题维度不应替代终验的完整量表。

| 顺序基准 | item_id | 维度 |
| --- | --- | --- |
| 1 | `AA-2` | Audiovisual Appeal |
| 2 | `CH-1` | Challenge |
| 3 | `EC-1` | Ease of Control |
| 4 | `GR-2` | Goals and Rules |
| 5 | `PF-3` | Progress Feedback |
| 6 | `AUT-1` | Autonomy |
| 7 | `CUR-1` | Curiosity |
| 8 | `IMM-3` | Immersion |
| 9 | `MAS-1` | Mastery |
| 10 | `MEA-1` | Meaning |
| 11 | `ENJ-3` | Enjoyment |

实际呈现仍须随机顺序。`顺序基准` 仅用于核对官方选题。

## 6. 答卷记录

| 字段 | 值 |
| --- | --- |
| session_id |  |
| participant_id |  |
| segment |  |
| build commit |  |
| seed |  |
| questionnaire | `FULL_PXI_33 / MINI_PXI_11` |
| language | `EN / ZH_AIDED` |
| started_at_utc |  |
| completed_at_utc |  |
| randomized_order_id |  |

答卷数据使用长表保存：

| participant_id | item_id | response | answered_at_utc |
| --- | --- | --- | --- |
|  |  |  |  |

`response` 只能是 `-3` 至 `+3` 的整数或明确缺失值，不能保存为“赞同”等本地化字符串。

## 7. 计分规则

完整 PXI 每个维度取三个题项的算术平均：

```text
construct_score = sum(item responses in construct) / 3
```

miniPXI 的维度分数就是该维度单题值。

规则：

- 不计算跨维度 PXI 总分。
- 不把 `0` 当作缺失值。
- 某维度任一题缺失时，该参与者该维度记为 `MISSING`，不自行均值填补。
- 排除整份答卷必须记录原因，且保留原始答卷。
- 分别报告 `NOVICE`、`GENRE`、`RETURNING` 和相关 `ACCESS` 样本。
- 每个维度报告样本数、均值、中位数、四分位数、负向比例和置信区间。
- 终验判定使用 [05_逐项通过标准.md](05_逐项通过标准.md) 中冻结的维度门槛。

## 8. 中文辅助译文控制

在未完成正式中文验证前，至少执行：

1. 两名双语人员独立正向翻译。
2. 合并译文并记录有歧义的术语。
3. 由未见英文原题的人员回译英文。
4. 与官方英文逐题核对概念，不追求字面一致而改变含义。
5. 对新玩家和类型玩家分别做认知访谈，确认他们如何解释每一题。
6. 冻结译文版本并在答卷中记录。

本文件当前译文可用于内部先导轮，不用于官方基准比较。

## 9. game5 自定义诊断题

以下题目不是 PXI。它们必须放在 PXI 完成之后，并在数据中使用 `G5-*` ID，不能混入 PXI 维度分数。

同样使用 `-3` 至 `+3`：

| item_id | 题目 | 对应设计风险 |
| --- | --- | --- |
| `G5-CONT-1` | 在规定场次结束时，我仍想继续游玩。 | 继续动力 |
| `G5-CHOICE-1` | 我的房间、单位或突变选择实际改变了结果。 | 选择是否有意义 |
| `G5-PACE-1` | 等待和推进之间的节奏对我来说合适。 | 放置节奏 |
| `G5-ENERGY-1` | 我能理解生产为何运行、变慢或停止。 | 能源与阻塞反馈 |
| `G5-RETREAT-1` | 我能理解撤离会保留什么、损失什么。 | 战斗结算透明度 |
| `G5-REPLAY-1` | 如果地图和候选发生变化，我愿意开始另一轮。 | 重玩意图 |

这些题用于定位问题，不具备 PXI 的验证和基准地位。

## 10. 开放访谈

PXI 和自定义题完成后再提问：

1. 本局最满意的一个决策是什么？你看到了什么结果？
2. 哪个决策最像“无论怎么选都一样”？
3. 哪段时间是在有计划地等待，哪段时间只是没有事做？
4. 你如何判断当前军队能否应对节点？
5. 失败或撤离后，你是否知道如何恢复？实际做了什么？
6. 三个候选中你为何选当前一个？另外两个在什么情况下更有价值？
7. 哪个界面信息最可信？哪个信息让你产生了错误预期？
8. 如果只能改变一件事，你会改变机制、节奏、信息还是表现中的哪一项？为什么？

主持人追问“你能指出当时的画面或操作吗”，将意见与录像、事件或存档对应。

## 11. 维度汇总模板

| segment | construct | n_valid | mean | median | q1 | q3 | negative_rate | 95% CI | threshold | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  | Ease of Control |  |  |  |  |  |  |  |  |  |
|  | Goals and Rules |  |  |  |  |  |  |  |  |  |
|  | Progress Feedback |  |  |  |  |  |  |  |  |  |
|  | Challenge |  |  |  |  |  |  |  |  |  |
|  | Autonomy |  |  |  |  |  |  |  |  |  |
|  | Curiosity |  |  |  |  |  |  |  |  |  |
|  | Mastery |  |  |  |  |  |  |  |  |  |
|  | Immersion |  |  |  |  |  |  |  |  |  |
|  | Meaning |  |  |  |  |  |  |  |  |  |
|  | Audiovisual Appeal |  |  |  |  |  |  |  |  |  |
|  | Enjoyment |  |  |  |  |  |  |  |  |  |
