# Views 目录说明

最后核对：2026-08-07

`Views` 只存放 iPhone App 的 SwiftUI 页面、页面专属 ViewModel、展示模型和视图支撑代码。

目录采用两层分类：

1. **一级目录按用户入口划分**：App、今日、健康、目标、我的、公共组件。
2. **二级目录按具体功能划分**：例如健康下面再分睡眠、压力、报告和趋势。

这样可以避免两种问题：一级目录太多难查找，以及大量页面堆在同一个目录里。

业务数据真值、HealthKit/CloudKit Repository 和同步策略不以本目录为准。涉及 iCloud 数据时，必须同时遵循仓库根目录的 `AGENTS.md`、`bio-balance-iOS/AGENTS.md` 和 `ICLOUD_DATA_ARCHITECTURE.md`。

## 一级目录总览

| 一级目录 | 对应入口 | 负责内容 |
|---|---|---|
| [App/](App/) | App 全局流程 | 启动、首次引导、登录、购买、法务、底部导航和深链 |
| [Today/](Today/) | 底部 `今日` Tab | 今日仪表盘、今日 AI 解读、当日心律详情 |
| [Health/](Health/) | 底部 `健康` Tab | 健康首页、指标、健康记录、睡眠、压力、趋势、报告和好友共享 |
| [Care/](Care/) | 无独立入口（由健康首页 `CareHubView` 进入） | 健康护理：护理计划、康复计划、症状日记、习惯计划 |
| [Goals/](Goals/) | 底部 `目标` Tab | 目标管理、每日行动和健身目标 |
| [Profile/](Profile/) | 底部 `我的` Tab | 个人首页、账号、设备、设置、隐私、帮助和品牌信息 |
| [Shared/](Shared/) | 无独立入口 | 多个一级模块真正共用的 AI 页面、设计规范、布局、组件和状态页 |

底部导航由 [App/Navigation/MainTabView.swift](App/Navigation/MainTabView.swift) 统一承载，当前为 4 个 Tab：

| Tab | 根页面 |
|---|---|
| `今日` | [Today/Dashboard/DashboardView.swift](Today/Dashboard/DashboardView.swift) |
| `健康` | [Health/Hub/HealthHubView.swift](Health/Hub/HealthHubView.swift) |
| `目标` | [Goals/Home/GoalsView.swift](Goals/Home/GoalsView.swift) |
| `我的` | [Profile/Home/ProfileView.swift](Profile/Home/ProfileView.swift) |

## 完整目录树

```text
Views/
│
├── App/                         # App 全局流程，不属于某个业务 Tab
│   ├── Navigation/              # 底部 Tab、深链、跨 Tab 路由和全局弹层
│   ├── Launch/                  # 冷启动过场和启动加载视图
│   ├── Onboarding/              # 首次启动引导和新手提示
│   ├── Auth/                    # 登录、注册和找回密码
│   ├── Commerce/                # 会员付费墙、恢复购买和 StoreKit 测试配置
│   ├── Legal/                   # 隐私政策和服务条款
│   └── Debug/                   # 无产品入口的组件实验室和占位录入表单
│
├── Today/                       # 底部「今日」Tab
│   ├── Dashboard/               # 今日首页、布局编辑及仅供今日页使用的卡片
│   └── Heart/                   # 今日心率节律详情
│
├── Health/                      # 底部「健康」Tab 及其所有下钻页面
│   ├── Hub/                     # 健康首页、首页展示模型和健康导航入口
│   ├── Profile/                 # 长期健康档案、主观评估、ViewModel 和组件
│   ├── Metrics/                 # 心率、HRV、VO2 Max、步态等单项指标详情
│   ├── Activity/                # 步数、能量、站立、活动和训练详情
│   ├── Body/                    # 身体年龄、体脂、体温和身高体重编辑
│   ├── Wellness/                # 每日健康、日照、身体症状和自我观察
│   ├── Behavior/                # 行为分析和长期习惯信号
│   ├── Nutrition/               # 饮品打卡、餐食识别和营养记录
│   ├── MentalHealth/            # 情绪记录和心理测评
│   ├── Reproductive/            # 经期打卡、孕期、胎动和女性健康记录
│   ├── Medication/              # 用药计划、用药打卡、药症资料和处方
│   ├── Sleep/                   # 睡眠、环境音、阶段分析、鼾声和睡眠环境
│   ├── Stress/                  # 压力详情、记录、呼吸训练和正念
│   ├── Sedentary/               # 久坐监测和久坐打断
│   ├── Trends/                  # 长期趋势首页和各分类趋势详情
│   ├── Reports/                 # 报告根页、日报、周报、月报、告警历史和分享
│   ├── Sharing/                 # 好友健康摘要和 iCloud 私密共享
│   └── Shared/                  # 仅供 Health 使用的指标提醒、范围控件、标签布局和图片选择器
│
├── Care/                        # 健康护理（由健康首页进入，无独立底部入口）
│   ├── CareHubView.swift        # 护理中心首页（健康首页入口）
│   ├── CarePlanImportView.swift # 护理计划导入
│   ├── CareTaskCardView.swift   # 护理任务卡片
│   ├── CareTaskEditView.swift   # 护理任务编辑
│   ├── CareAdherenceView.swift  # 护理依从性
│   ├── RehabilitationPlanView.swift  # 康复计划
│   ├── HabitPlanView.swift      # 习惯计划
│   ├── SymptomJournalView.swift # 症状日记
│   └── JournalCardView.swift    # 日记卡片
│
├── Goals/                       # 底部「目标」Tab
│   ├── Home/                    # 目标首页、目标管理和进度
│   ├── DailyAction/             # 每日行动和当日打卡时间线
│   └── Fitness/                 # 健身日历、训练仪表盘、详情弹层和庆祝动画
│
├── Profile/                     # 底部「我的」Tab
│   ├── Home/                    # 我的首页、首页组件和活力热力图
│   ├── Account/                 # 我的信息和账号资料编辑
│   ├── Devices/                 # 我的设备和 Apple Watch 使用说明
│   ├── Settings/                # 通知、主题、Widget、缓存和 iCloud 管理
│   ├── Privacy/                 # 隐私与安全页面
│   ├── Support/                 # FAQ、帮助与反馈
│   └── About/                   # 品牌故事和商务合作
│
└── Shared/                      # 多个一级模块共同使用的视图能力
    ├── AI/                      # 今日、健康档案和健身共同使用的健康 AI 页面
    ├── DesignSystem/            # 跨一级模块共用的健康详情视觉规范和压力样式
    ├── Layout/                  # 自适应布局和通用网格
    ├── Presentation/            # Sheet、弹层和页面展示规范
    ├── Components/              # 跨模块通用日期、免责声明等组件
    ├── States/                  # 加载、同步、离线、空数据和错误状态页面
    └── Alerts/                  # 跨模块异常提醒和提示浮层
```

## 各一级目录的放置规则

### `App`

放置不属于某个业务 Tab 的全局流程。

- `Navigation`：只放应用级导航。`MainTabView` 还负责跨 Tab 深链与模态路由；新增健康入口时要同时核对 `MainTabView` 和 `HealthHubDestination`。
- `Launch`：只处理冷启动过程，不放普通页面的加载状态。
- `Onboarding`：首次启动引导和跨页面新手提示。
- `Auth`：登录、注册、找回密码和游客身份选择。
- `Commerce`：`PaywallView` 与 `BalenWatchSubscriptions.storekit`。
- `Legal`：隐私政策与服务条款。
- `Debug`：没有产品入口的界面实验代码。这里的手动录入表单不会持久化，不得当作正式健康数据入口。

### `Today`

只放服务于底部 `今日` Tab 的页面。

- `Dashboard`：今日首页本体、核心网格、头部、恢复个性化和今日页布局编辑；长期画像卡片只承载可展开的摘要、依据与本周建议，完整画像仍导航到 `Health/Profile`。
- `Heart`：当天心率节律详情。

今日、健康档案和健身页面共用的 AI 解读界面放在 `Shared/AI`，不能重新放回 `Today/AI`。

如果组件离开今日页仍有多个模块使用，应迁到 `Shared`；如果是完整健康指标详情，应放到 `Health`。

### `Health`

这是最大的一级模块，因此必须继续按健康子领域拆分，禁止把新文件直接堆在 `Health/` 根目录。

- `Hub`：健康 Tab 首页和导航分发。`HealthHubPresentation` 只负责能力分组与展示模型。
- `Profile`：长期健康档案及主观评估，不等同于底部 `我的` Tab 的个人资料。
- `Metrics`：单项指标详情，例如 HRV、心率、VO2 Max、步态不对称。
- `Activity`：活动量、能量、步数、站立和训练。
- `Body`：身体年龄、体脂、手腕温度和身高体重。
- `Wellness`：每日综合健康、日照记录、症状与自我观察。
- `Behavior`：行为影响分析和长期习惯信号。
- `Nutrition`：饮品打卡、餐食识别和营养记录。
- `MentalHealth`：情绪记录和心理测评。
- `Reproductive`：经期打卡、孕期、胎动等生殖健康记录。
- `Medication`：用药计划、用药打卡、药症分析和处方识别。
- `Sleep`：睡眠专题及与睡眠相关的环境音记录。
- `Stress`、`Sedentary`：各自完整的健康专题。
- `Trends`：长期趋势与趋势导出。
- `Reports`：报告根页、日报、周报、月报、告警历史、详情图表和报告分享。
- `Sharing`：好友健康摘要与 iCloud 共享。
- `Shared`：只能被 Health 内多个二级模块复用的指标提醒、范围控件、标签布局和媒体桥接。

`WalkingAsymmetryDetailView` 等已经独立的详情页应直接复用，不要复制回 Dashboard 或 Hub。

#### 好友共享隐私边界

`Health/Sharing` 只负责界面和交互，不能扩大 CloudKit 的数据边界：

- 仅打开好友页不得创建云端健康记录。
- 只有用户显式发起邀请并创建 CKShare 后才持续更新。
- 健康摘要和共享待办对受邀方只读。
- 粗略位置默认关闭，不得上传精确位置或位置轨迹。
- 不得把全量 HealthKit 数据、原始音频、图片或模型对话写入 CloudKit。
- iCloud 不可用时，本地健康功能仍应继续工作。

具体字段白名单、删除语义和失败降级以 `ICLOUD_DATA_ARCHITECTURE.md` 为准。

### `Care`

健康护理相关页面，当前没有独立底部入口，由健康首页 `HealthHubView` 内的 `CareHubView` 进入。
文件必须放在 `Care/` 下，不要堆到 `Health/` 根目录或顶层 `Shared/`。

- `CareHubView`：护理中心首页。
- 护理计划 / 康复计划 / 症状日记 / 习惯计划：计划与记录页面。
- 新增护理类页面时，先确认是否由 `CareHubView` 或护理计划详情进入，再决定路由位置。

### `Goals`

只放置底部 `目标` Tab 的目标管理、每日行动编排和健身目标页面。

- `Home`：目标创建、目标管理和进度。
- `DailyAction`：当天行动卡片与行为时间线。
- `Fitness`：健身节律、训练打卡、训练详情和恢复分析。

`DailyAction` 可以调用健康记录弹层，例如 `Health/Nutrition/DrinkCheckinSheet` 和
`Health/Wellness/SunlightSheetView`，但这些页面的数据语义和主要入口属于健康模块，文件仍放在 `Health`。

不要再新增或恢复旧的 `HabitView`。每日行动本体使用 `DailyActionView`，目标首页使用 `GoalsView`。

### `Profile`

放置底部 `我的` Tab 以及从个人中心进入的管理页面。

- `Home`：个人首页、首页卡片和活力热力图。
- `Account`：昵称、账号和个人资料编辑。
- `Devices`：设备与 Apple Watch 说明。
- `Settings`：应用设置、通知、提醒、主题、Widget、缓存和 iCloud 管理。
- `Privacy`：隐私与安全。
- `Support`：FAQ 和帮助反馈。
- `About`：品牌与商务信息。

`Profile/Settings` 是个人中心下的二级入口，不是底部 Tab 根页面。

### `Shared`

只有至少两个一级模块实际共用的界面代码才放这里。

- `Layout`：不包含业务语义的布局容器。
- `AI`：至少两个一级模块共用的完整 AI 页面和页面 ViewModel。
- `DesignSystem`：跨一级模块共用的视觉常量、页面背景和领域样式。
- `Presentation`：通用页面、Sheet 和弹层展示方式。
- `Components`：通用日期文本、免责声明等。
- `States`：加载、同步、离线、空数据和错误状态。
- `Alerts`：跨模块异常提醒。

下面这些内容不应放进顶层 `Shared`：

- 只供健康模块使用的指标设置、布局或媒体桥接，应放 `Health/Shared`。
- 生殖健康记录，应放 `Health/Reproductive`。
- 趋势导出，应放 `Health/Trends`。
- 目标完成庆祝，应放 `Goals/Fitness` 或对应目标子模块。
- 睡眠音频推断界面，应放 `Health/Sleep`。

## 当前未接入产品路由的页面

当前没有发现只有声明/Preview、且没有产品入口的页面；已确认废弃的旧页面已从工程中移除。

`App/Debug` 下的内容只供开发预览。
（`Shared/States/BackendStatusBanner` 已随「无自建后端」改造移除。）
重新接入上述页面时，必须同时补上明确路由并更新本节。

`WidgetSettingsView` 已接入「个人 → 应用设置 → 手机小组件」。该页会读取真实共享快照并提供添加教程。
此外，最大摄氧量已承接今日页现有卡片，REM/深睡已承接睡眠阶段卡，夜间 HRV 基线已承接 HRV 详情，
行为影响与睡眠-压力关联已归入报告页的「深入分析」。其他候选页与当前详情、报告或目标流程重复，不为了曝光页面而新增入口。

## 新增页面判断顺序

新增或移动页面时按下面顺序判断：

1. 它从哪个一级入口进入：App、今日、健康、目标还是我的？
2. 它属于哪个具体功能：睡眠、压力、报告、设备、饮品等？
3. 它是否只服务一个模块？如果是，放在该模块内，不放 `Shared`。
4. 它是否被两个以上一级模块实际使用？如果是，才考虑顶层 `Shared`。
5. 它是页面专属 ViewModel 或展示模型吗？跟随页面放置。
6. 它是 Repository、同步器或业务数据真值吗？不要放进 `Views`。

## 文档维护约定

发生以下变化时必须同步更新本文件：

- 底部 Tab 或根页面变化。
- `MainTabView`、`HealthHubDestination` 的路由变化。
- 页面移动到其他一级或二级目录。
- 大页面拆分出新的模块内子目录。
- `Health/Shared` 与顶层 `Shared` 的边界变化。
- 页面删除、改名或正式废弃。
- 好友共享能力或隐私边界变化。
