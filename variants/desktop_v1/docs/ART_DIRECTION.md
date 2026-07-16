# 首局视觉垂直切片美术方向

## 1. 视觉目标与资产契约

风格名：**异体生物工业档案 / Xenobiotic Bio-Industrial Field Manual**。

目标是在桌面端首屏立刻建立“异种巢群 + 现场档案”身份，并在首局
10–15 分钟内让三类巢室、三类虫群以及资源、威胁、占领、交战、撤离
五类状态在 24–64 px 显示尺寸仍可快速区分。位图只承担身份、轮廓和状态
提示；所有名称、数值、按钮文案和本地化文本继续由 Godot 控件渲染。

目标视口为 1280×720、1600×900、1920×1080。标题图使用全屏底层，
图标进入已有按钮、槽位、指标和状态带，不改变玩法数据、输入、存档结构，
不覆盖文字、焦点描边或高密度信息。

## 2. 色板

| 角色 | 色值 | 用途 |
| --- | --- | --- |
| 石墨黑 | `#071014` | 全局底、标题负空间 |
| 设备黑 | `#0E1A1E` | 面板和机械外壳 |
| 骨白 | `#E8EFEA` | 主文字、骨质切面 |
| 冷灰 | `#93A6A6` | 次级文字、失活信息 |
| 生物质绿 | `#82D67B` | 资源、友方、有机生长 |
| 信息青 | `#57C4C3` | 观察、孵化、孢体与线路 |
| 热能琥珀 | `#E2BA60` | 能源、选择、撤离和热结构 |
| 威胁朱红 | `#DC785F` | 敌对、交战、危险操作 |

石墨黑和骨白构成中性层级；四种语义色只做局部标记，不用大面积泛光。
任何状态都不得只靠色相表达。

## 3. 形状与材质语言

- 巢室：设备舱外框与有机内脏并置。滤囊使用横向多叶囊和筛孔；代谢腔
  使用放射肋片与热核；孵化室使用竖向卵形摇篮和顶部缺口。
- 虫群：工蜂是低重心三角轮廓、成对前肢和点状腹节；噬咬体是前倾楔形、
  双弯颚和背部锯齿；根脉孢体是圆形孢囊、下垂根叉和纵向菌褶。
- 状态：资源为闭合种荚和内向叶脉；威胁为三尖外刺和斜向划痕；占领为
  闭合六边边界和向内锁定纹；交战为相向双颚和交叉冲击纹；撤离为向左
  打开的楔口和回撤斜纹。
- 材质：半写实 2D 科学图谱式绘制，几丁质硬边、菌膜半哑光、根脉分叉、
  实验设备模块接缝。轮廓优先于表面细节，局部生物发光面积不超过主体的
  12%。

## 4. 状态语义

| 状态 | 颜色 | 非颜色编码 | 目标挂接点 |
| --- | --- | --- | --- |
| 资源 | 生物质绿 | 闭合种荚、叶脉点纹 | 顶部资源带、虫群资产指标 |
| 威胁 | 威胁朱红 | 三尖外刺、右上方向划痕 | 未占领区域、敌方代表 |
| 占领 | 生物质绿 / 信息青 | 闭合六边界、内向锁定纹 | 已占领区域节点 |
| 交战 | 威胁朱红 / 琥珀 | 相向双颚、交叉冲击纹 | 主动战场带、战斗页 |
| 撤离 | 热能琥珀 | 左开楔口、反向斜纹 | 撤离按钮与确认状态 |

选择态继续由现有琥珀焦点框表达，不替换状态图标本身，避免“选择”和
“状态”混为一谈。

## 5. 禁用项

- 单一紫蓝配色、紫色主光、厚重暗雾、全屏泛光；
- 装饰性渐变球、漂浮光斑、卡通贴纸感、库存图感；
- 图片内嵌文字、数字、标志、水印、边框标签；
- 仅靠颜色区分状态、细碎到 24 px 消失的纹理；
- 角色化面孔、品牌、额外叙事角色、血腥内脏特写；
- 拉伸改变宽高比、透明边缘色溢出、未验收草稿进入正式资源目录。

## 6. 资产清单

| 文件 | 用途 / 节点 | 源规格 | Alpha | 实际显示 |
| --- | --- | --- | --- | --- |
| `title_hive_field_manual_v1.png` | 标题页全屏底层 | 1920×1080 | 无 | cover，全视口 |
| `room_biomass_filter_v1.png` | 腐殖滤囊槽位 | 256×256 | 有 | 44–56 px |
| `room_thermal_metabolism_v1.png` | 热化代谢腔槽位 | 256×256 | 有 | 44–56 px |
| `room_embryo_hatchery_v1.png` | 胚流孵化室槽位 | 256×256 | 有 | 44–56 px |
| `swarm_worker_v1.png` | 采质工蜂指标 | 256×256 | 有 | 40–56 px |
| `swarm_biter_v1.png` | 噬咬体指标 / 战场 | 256×256 | 有 | 32–56 px |
| `swarm_root_spore_v1.png` | 根脉孢体指标 / 战场 | 256×256 | 有 | 32–56 px |
| `state_resource_v1.png` | 资源语义 | 256×256 | 有 | 24–40 px |
| `state_threat_v1.png` | 威胁语义 | 256×256 | 有 | 24–40 px |
| `state_owned_v1.png` | 占领语义 | 256×256 | 有 | 24–40 px |
| `state_engaged_v1.png` | 交战语义 | 256×256 | 有 | 24–40 px |
| `state_retreat_v1.png` | 撤离语义 | 256×256 | 有 | 24–40 px |

标题图以 1920×1080 RGBA8 计约 7.91 MiB；11 枚 256×256 RGBA8 图标
合计约 2.75 MiB，未压缩估算 VRAM 总量约 10.66 MiB，低于 32 MiB。

## 7. 生成来源与提示词契约

原计划来源为 Multica 运行时预配置的 GPT Image CLI，模型
`gpt-image-2`。12 项 medium 任务全部在三次等待后超时；随后以单任务、
low 质量、并发 1 分别探测 `gpt-image-2` 和 `gpt-image-1-mini`，并在
沙箱外重复探测，仍全部超时且未产出文件。因此下列提示词是本轮实际提交
过的最终提示词记录，但**不是正式 PNG 的来源**。逐项完整提示词和请求
控制保存在 `docs/art_v1_generation_manifest.jsonl`。

标题图最终提示词：

> Use case: Godot desktop game title background. Asset type: full-bleed
> 16:9 title artwork behind live UI. Primary request: a colossal alien hive
> colony specimen instantly readable as a xenobiotic swarm origin, its
> chitin chambers, fungal membranes and branching roots restrained by modular
> bio-industrial field equipment. Scene/backdrop: graphite-black laboratory
> field station, bone-white specimen plates and clamps, sparse cyan instruments,
> biomass-green tissue, amber thermal chambers and tiny vermilion hazard
> markers. Style/medium: semi-realistic 2D scientific field-manual plate,
> crisp silhouette, fine engraved material study, restrained local
> bioluminescence. Composition/framing: wide 16:9, dominant hive mass from
> lower-left through center, clear low-detail dark negative space in upper-left
> and the rightmost 28 percent for live title and menu controls, no frame.
> Lighting/mood: clinical directional light, readable darks, no fog.
> Constraints: no text, no letters, no numbers, no logo, no watermark; actual
> biological-industrial subject must remain inspectable; no UI mockup.
> Avoid: purple-blue dominance, decorative gradient orbs, bokeh, heavy bloom,
> dark mist, stock-art look, cartoon sticker style, gore, embedded typography,
> cropped hive silhouette.

图标共用最终提示词骨架，每张只替换 `Subject` 与语义色：

> Use case: Godot strategy game semantic icon. Asset type: isolated 2D icon
> readable at 24–64 pixels. Subject: <资产清单中的轮廓与非颜色编码>.
> Style/medium: semi-realistic xenobiotic scientific field-manual specimen,
> crisp thick outer silhouette, simplified chitin and membrane detail,
> restrained local bioluminescence, bio-industrial construction. Composition:
> one centered object, 78 percent canvas coverage, generous clean margin,
> no cast shadow. Color palette: graphite, bone-white and <语义色>; never
> magenta on the subject. Background: perfectly flat solid #FF00FF chroma key.
> Constraints: no text, letters, numbers, logo, watermark, frame or extra
> objects; preserve the specified notch, texture and direction encoding.
> Avoid: purple-blue dominance, gradient background, fog, bloom halo, sticker
> outline, stock icon, cartoon face, clipping, tiny detached particles.

正式 PNG 的实际来源是仓库内可复现的 Godot 4.7 栅格绘制脚本
`tools/render_art_v1.gd`，不含外部下载、第三方素材或未知许可内容。
标题在 1920×1080 SubViewport 中直接绘制；图标在 1024×1024 透明
SubViewport 中以轮廓、色块、划痕和方向纹构造，再用 Lanczos 缩放到
256×256。噬咬体在第一次人工检查后由朱红主体修为骨白主体、绿色身份点
与局部朱红颚部，避免和敌方威胁混淆。绘制器可重复生成全部正式资产；
本轮没有把失败草稿或色键中间图放入正式目录。

## 8. Godot 导入与验收

- 标题：PNG、sRGB、`compress/mode=0`（Lossless）、mipmap 关闭、repeat
  关闭、过滤继承项目默认；`TextureRect.STRETCH_KEEP_ASPECT_COVERED`。
- 图标：PNG RGBA、`compress/mode=0`（Lossless）、mipmap 关闭、repeat
  关闭、过滤继承项目默认；不使用 atlas，避免 24 px 状态图出现采样串色。
- 不提交 `.godot/imported/` 可再生缓存；Godot 真实导入后只记录源文件和
  可审计的 `.import` 设置。
- 画面验收：三个目标视口分别捕获标题、虫巢、虫群、区域图、战斗页；
  检查非空、缺失纹理、裁切、文字/按钮/焦点遮挡、最小显示辨识度及对比度。
- 运行验收不改变正式终验状态；本轮只提供艺术集成自检，后续仍需验证集成
  与独立体验验收。

## 9. 最终文件属性与资源预算

| 文件 | 字节 | 实际格式 / 尺寸 / Alpha |
| --- | ---: | --- |
| `title_hive_field_manual_v1.png` | 98,403 | PNG RGBA8，1920×1080，无透明像素 |
| `room_biomass_filter_v1.png` | 16,193 | PNG RGBA8，256×256，透明四角 |
| `room_thermal_metabolism_v1.png` | 29,776 | PNG RGBA8，256×256，透明四角 |
| `room_embryo_hatchery_v1.png` | 16,437 | PNG RGBA8，256×256，透明四角 |
| `swarm_worker_v1.png` | 15,679 | PNG RGBA8，256×256，透明四角 |
| `swarm_biter_v1.png` | 21,030 | PNG RGBA8，256×256，透明四角 |
| `swarm_root_spore_v1.png` | 16,519 | PNG RGBA8，256×256，透明四角 |
| `state_resource_v1.png` | 21,265 | PNG RGBA8，256×256，透明四角 |
| `state_threat_v1.png` | 22,943 | PNG RGBA8，256×256，透明四角 |
| `state_owned_v1.png` | 21,431 | PNG RGBA8，256×256，透明四角 |
| `state_engaged_v1.png` | 23,775 | PNG RGBA8，256×256，透明四角 |
| `state_retreat_v1.png` | 15,257 | PNG RGBA8，256×256，透明四角 |

正式 PNG 源文件合计 **318,708 bytes（0.304 MiB）**，低于 20 MiB。
按 RGBA8 完全展开估算为 **11,177,984 bytes（10.66 MiB）VRAM**，低于
32 MiB；单图最长边 1920，低于 2048。

Godot 4.7 在隔离用户目录中完成真实导入。12 项设置一致：
`compress/mode=0`（Lossless）、`mipmaps/generate=false`、
`roughness/mode=0`、`process/fix_alpha_border=true`、
`process/premult_alpha=false`、`detect_3d/compress_to=1`。运行时只
从 `res://assets/art_v1/` 加载，无外链。

## 10. Godot 接入

- `scripts/ui/art_assets.gd` 集中预加载 12 张正式纹理并提供巢室、虫群、
  状态映射；所有引用进入 Godot Resource 管线。
- 标题图由 `main.gd` 以 cover 模式置于全屏底层，只在标题态显示；
  104 px 现有品牌标记和实时文字继续由 Godot 绘制。
- 三类巢室进入 `RoomSlot` 右侧 48 px 图标；三类虫群进入总账 48 px
  指标，并在战场以 20–26 px 代表投影。
- 资源、威胁、占领、交战、撤离图标进入顶部资源带、区域节点、主动战场
  带、战斗标题和撤离命令；选择态仍保留现有琥珀焦点框。
- 为满足真实 1280×720 画面，页面上下内边距由 14 调为 7，地图画布最小
  高度由 480 调为 420，战场画布最小高度由 390 调为 300；三者在更大
  视口继续自适应扩展。未修改玩法数值、输入、存档或根工程。

## 11. 实机截图与视觉结论

`scripts/capture_art_v1.sh` 在 Godot 4.7、Linux/X11、Mesa llvmpipe、
隔离 `HOME/XDG_*` 下捕获并验证：

- 1280×720：标题、虫巢、虫群、区域图、战斗；
- 1600×900：标题、虫巢、虫群、区域图、战斗；
- 1920×1080：标题、虫巢、虫群、区域图、战斗。

15 张原图位于 `artifacts/art_v1/captures/`，接触表位于
`artifacts/art_v1/contact_sheet.png`；`artifacts/.gdignore` 使这些
证据不进入运行时纹理导入。截图门检查源纹理尺寸、标题无
透明像素、图标透明四角和主体覆盖，并要求每个截图采样颜色不少于 12、
所有可见 Control 完全在视口内、按钮与单行标签不裁切。最终结果
`ART_V1_CAPTURE_OK count=15`。

人工检查确认：标题首屏异种巢群身份非空且主轮廓完整；三类巢室和三类
虫群在 1280 最小视口仍由不同轮廓辨认；威胁三尖、占领闭合六边、交战
相向双颚、撤离左开楔口不只依赖颜色；没有缺图、文字遮挡、按钮遮挡、
底边裁切或装饰性泛光。石墨底上的骨白、冷灰、绿、青、琥珀、朱红对比度
分别约为 16.43:1、7.54:1、10.84:1、9.23:1、10.45:1、6.31:1。

本结论是美术自检，不替代 Godot 验证集成或独立体验验收，也不改变正式
终验证据 `INVALID / NOT_RUN` 的现状。

## 12. 启动与现有验证

- Godot 4.7 隔离用户目录编辑器导入：PASS，无脚本解析或缺失资源错误。
- `./scripts/capture_art_v1.sh`：PASS，15 张，三个视口、五个页面。
- 默认 `./scripts/verify.sh`：在 `acceptance-regressions` 固定 80 秒
  门上超时（exit 124）；超时前已完成核心规则、撤离 I/O 和飞升布局，
  真实自动保存在 33.674 秒到达边界。该结果必须保留，不声明默认门 PASS。
- `ACCEPTANCE_TIMEOUT_SECONDS=120 ./scripts/verify_acceptance_regressions.sh`：
  PASS，5 cases、3 resolutions、487 assertions。
- `ACCEPTANCE_TIMEOUT_SECONDS=120 ./scripts/verify.sh`：PASS；覆盖核心
  7 cases / 88 assertions、撤离窗口 63 assertions、飞升 3 resolutions /
  58 assertions、既有截图 6 张、存档进程、5 组事务恢复、保存前恢复、
  主读 I/O、持久化保护 89 assertions、故障注入 1934 assertions，以及
  超时/进程组清理。
