# 追番订阅设计

本文档描述 Mutsumi 追番功能的服务端设计：每周自动抓取最新一集。
所有设计决策都附实测依据，测量日期 2026-08-20，样本取自 `api.animes.garden`。

## 目录

- [设计目标](#设计目标)
- [实测：标题属性解析覆盖率](#实测标题属性解析覆盖率)
- [语言：硬过滤（token + 字形双通道）](#语言硬过滤token--字形双通道)
- [数据模型](#数据模型)
- [属性解析器](#属性解析器)
- [偏好打分模型](#偏好打分模型)
- [决策流程](#决策流程)
- [集数解析](#集数解析)
- [配置流程](#配置流程)
- [API](#api)
- [调度器](#调度器)
- [分期](#分期)
- [明确不做的事](#明确不做的事)

## 设计目标

1. 每周番剧更新后自动下载最新一集，无需人工介入。
2. 用户在添加订阅时选择字幕组，并按偏好（分辨率、编码、语言等）自动挑选发布版本。
3. 宁可漏一集等人处理，也不要错配一集。

### 上游选择：不用 RSS

项目已在 `lib/features/anime_garden/data/anime_garden_repository.dart:26` 使用
`POST https://api.animes.garden/resources`。追番所需的增量能力全在同一端点上，实测可用：

| 参数 | 类型 | 用途 |
| --- | --- | --- |
| `after` / `before` | Date | 时间水位线，增量扫描的基础 |
| `subjects` | number[] | **就是 Bangumi subject id**，与 `Anime.bangumi_id` 对齐 |
| `fansubs` | string[] | 字幕组过滤 |
| `search` / `include` / `keywords` / `exclude` | string[] | 标题搜索 / 至少含一个 / 全部包含 / 排除 |
| `types` | string[] | 追番固定 `['动画']`，排除 `合集` |

`/feed.xml` 的过滤能力是 `/resources` 的子集，且需额外引入 XML 解析依赖。没有理由用 RSS。

响应中的 `magnet` + `tracker` 可直接拼成项目现有的 `downloadLink`；`id` / `providerId`
提供稳定去重键。

### 架构：全局单次 sweep

实测 `types=['动画']` 全站近 24 小时仅 **82** 条资源，一页 100 即可覆盖一整天。因此不按订阅逐个查询，
而是一次请求扫全站增量，再在服务端本地匹配所有订阅：

```
每 15 分钟：
  POST /resources { types:['动画'], after: <游标> }   ← 1 个请求
  → ~5-10 条新资源
  → 对每条资源，遍历所有订阅的匹配规则
  → 命中 → 解析集数 → 查重 → 打分 → 下载 → 建 Episode
  → 推进游标
```

订阅 30 个和 1 个的上游开销完全一样。手动「立即检查」走另一条路径：按订阅带
`subjects` + `search` 精确查询。

## 实测：标题属性解析覆盖率

**这张表是后续所有设计决策的依据。** 样本为近 21 天 `types=['动画']` 的 400 条真实标题。

| 维度 | 覆盖率 | 实际分布 | 用途 |
| --- | ---: | --- | --- |
| `language.script` | 58.5% → **79.3%** | 见下节 | **硬过滤** |
| `language.has_jp` | 14.7% | 简日/繁日/简繁日 | 软偏好 |
| `resolution` | 98.0% | 1080p:382　720p:6　2160p:4 | 软偏好 + 排除 |
| `codec` | 79.2% | avc:237　hevc:76　**av1:4** | 软偏好 |
| `bitdepth` | 12.8% | 10bit:65　8bit:12 | 软偏好（低权重） |
| ~~`audio`~~ | 76.2% | aac:297　flac:4　opus:4 | 不采用 |
| ~~`source`~~ | 77.2% | webrip:99　baha:72　cr:68　abema:42 | 不采用 |

音频与来源不纳入模型：aac 占 297/400 而 flac 仅 4 条，实际没有可排序的空间。
用户若确实在意，用 [`must_include`](#must_include自定义必含列表) 自行指定即可。

`bitdepth` 覆盖率只有 12.8%，意味着 87% 的候选在这个维度上拿中性分、不产生区分度。
它仍然纳入，但**权重必须低**——否则少数写了 `10bit` 的标题会不成比例地占优，
而没写的那些很可能也是 10bit。

从这份数据得出三条结论：

1. **1080p 占 95.5%。** 分辨率偏好几乎没有区分度——设成什么都是同一批结果。它的价值在于排除
   720p 和 2160p，而不是在 1080p 内部排序。

2. **AV1 只占 1%（4/400）。** AV1 确实存在且稳定产出（`极影字幕社` 固定用 `AV1_opus` 格式），
   但若偏好列表只写 `[av1]`，所有 avc 发布会得 0 分，效果等同硬过滤。
   **要表达偏好就必须把可接受项全部列进去按序排**：`[av1, hevc, avc]`。

3. **软偏好维度未命中时给中性分，不给零分。** 标题没写 `1080p` 的发布很可能就是 1080p，
   只是没写。若给零分，打分会退化成隐式软过滤，系统性惩罚标题写得简短的发布——
   而这跟质量无关。语言维度是例外，见下节。

## 语言：硬过滤（token + 字形双通道）

### 为什么语言必须硬过滤

实测发现语言与其他维度性质不同。按发布者统计近 28 天 600 条样本的语言标注：

```
Kirara Fantasia   209 条   token 全部未标注 → 字形判定: 繁体:79  简体:19
桜都字幕组          16 条   简体:6  简繁:5  繁体:5
爱恋字幕社           9 条   简体:5  繁体:4
悠哈璃羽字幕社        6 条   简体:3  繁体:3
ANi               56 条   繁体:56（100% 一致）
Nix-Raws          79 条   简繁:79（100% 一致）
GMTeam            14 条   简体:14（100% 一致）
```

关键在于：**这些组是同一集同时发简体版和繁体版**，两个版本都存在。所以语言不是
「可用性过滤」（内容有没有），而是「**版本选择**」（两个都有，要哪个）。

这是硬过滤唯一正确的场合。软打分做不了这件事——同一集的简繁两版几乎同时发布，
都会落进同一个等待窗口，而分差很容易被字幕组权重淹没，结果就是随机拿到一个。

### 语言其实是两个正交的轴

实测标题里的语言标记同时编码了两件事——**中文字形**和**是否附带日文字幕轨**——必须拆开处理。

下表是**按检测顺序互斥归类**后的实测分布（600 条）。不能用独立匹配计数：
`简繁日` 同时含子串 `简繁` 和 `繁日`，独立统计会重复计入。

| 判定 | 条数 | 占比 | `script`（硬过滤） | `has_jp`（软偏好） |
| --- | ---: | ---: | --- | --- |
| `简繁` | 126 | 21.0% | `{简, 繁}` | false |
| `繁体` | 90 | 15.0% | `{繁}` | false |
| 字形→繁 | 81 | 13.5% | `{繁}` | 判不出 |
| `简体` | 53 | 8.8% | `{简}` | false |
| `简繁日` | 33 | 5.5% | `{简, 繁}` | **true** |
| `简日` | 31 | 5.2% | `{简}` | **true** |
| 字形→简 | 31 | 5.2% | `{简}` | 判不出 |
| `繁日` | 24 | 4.0% | `{繁}` | **true** |
| `粤语` | 6 | 1.0% | `∅` | 始终排除 |
| 字形→简繁 | 1 | 0.2% | `{简, 繁}` | 判不出 |
| 无法判定 | 124 | 20.7% | — | — |

`script` 判定率 **79.3%**；`has_jp = true` 共 88 条，占 **14.7%**。

- **`script` 是硬过滤**：`简` / `繁` 二选一，`{简,繁}` 同时满足两者。见上一节的理由。
- **`has_jp` 是软偏好**：`简日` / `繁日` / `简繁日` 表示附带日文字幕轨。
  只占 14.7%，所以它**绝不能作硬过滤**——那会砍掉 85% 的候选。
  作为排序依据则刚好：有就优先，没有也照收。

样例（`[简繁日内封]`、`[简日内嵌]`、`[简日双语]`）显示这些标记描述的是**字幕轨集合**。
三明治摆烂组同一集同时发了 `[简日内嵌]` 和 `[繁日内嵌]` 两版——又一个版本选择的例证。

### 检测：token 优先，字形兜底

显式 token 只覆盖 58.5%，但最大的发布者（Kirara Fantasia，占全站 35%）从不写 token。
补一条字形通道后 `script` 判定率升到 **79.3%**：

```python
# 通道一：显式 token。顺序至关重要——'简繁日' 同时含子串 '简繁' 和 '繁日'，
# 必须排在两者之前，否则会被误判。
LANG = [
  ('简繁日', {'简','繁'}, True,  r'简繁日|簡繁日|简日繁|chs?&cht&jp'),
  ('简日',   {'简'},      True,  r'简日|簡日|chs&jp|gb&jp|sc&jp'),
  ('繁日',   {'繁'},      True,  r'繁日|cht&jp|big5&jp|tc&jp'),
  ('简繁',   {'简','繁'}, False, r'简繁|簡繁|繁简|chs?&cht|sc&tc|gb&big5'),
  ('简体',   {'简'},      False, r'简体|簡體|简中|' + W(r'chs|gb|sc')),
  ('繁体',   {'繁'},      False, r'繁体|繁體|繁中|' + W(r'cht|big5|tc')),
  ('粤语',   set(),       False, r'粤语|粵語|粤日|粵日'),
]

# 通道二：字形判别（token 未命中时启用）
SIMP = set('从开战记说汉学见关门时过这来对会后义无电场头语边谁龙灵万与术医儿岁传华车东马鸟鱼历罗虽变态样张')
TRAD = set('從開戰記說漢學見關門時過這來對會後義無電場頭語邊誰龍靈萬與術醫兒歲傳華車東馬鳥魚歷羅雖變態樣張')

def detect_language(title):
    """→ (script: set[str], has_jp: bool) 或 (None, False) 表示无法判定"""
    low = title.lower()
    for _, script, has_jp, pattern in LANG:
        if re.search(pattern, low):
            return script, has_jp          # 粤语返回空 set，硬过滤阶段必然不通过
    simp = sum(c in SIMP for c in title)
    trad = sum(c in TRAD for c in title)
    if simp and not trad: return {'简'}, False
    if trad and not simp: return {'繁'}, False
    if simp and trad:     return {'简','繁'}, False
    return None, False                     # 剩余 24.5%：纯英日标题，无判别字
```

注意 `粤语` 返回空 `script`，所以任何 `language_mode` 都不会通过——不需要额外的排除逻辑。

字形集只收录简繁**一对一**且常用于番剧标题的字。不要收录多对一的字（如 `台/臺`）
或简繁同形字，否则会误判。字形通道只能判 `script`，判不出 `has_jp`
（日文假名在标题里普遍存在，与是否有日文字幕轨无关）。

### 配置项

```
language_mode     str   any | 简 | 繁      硬过滤，默认 简
language_unknown  str   accept | reject   script 判不出时如何处理，默认 accept
prefer_subtitle   json  list[str]          软偏好，默认 ['日', '无']
```

语义：

- 硬过滤：`language_mode in script`，`{简,繁}` 同时满足 `简` 和 `繁`
- `粤语` 因 `script` 为空而**始终排除**，除非显式写入 `must_include`
- `script` 判不出时由 `language_unknown` 决定
- 软偏好：`prefer_subtitle: ['日','无']` 使 `has_jp=true` 得 1.0、`false` 得 0.5；
  想反过来优先纯中文（体积小）就写 `['无','日']`

### 实测通过率

600 条样本，只计 `script` 硬过滤（`has_jp` 不参与，它只影响排序）：

| `language_mode` | `language_unknown` | 通过 | 占比 |
| --- | --- | ---: | ---: |
| `简` | `accept` | 399 | **66.5%** |
| `简` | `reject` | 275 | 45.8% |
| `繁` | `accept` | 479 | 79.8% |
| `繁` | `reject` | 355 | 59.2% |
| `any` | `accept` | 594 | 99.0% |
| `any` | `reject` | 470 | 78.3% |

`language_unknown` 默认 `accept` 的理由：设成 `reject` 会把那批无判别字的标题
（124 条，20.7%）全部丢掉，其中包含相当多来自 Kirara Fantasia 的纯英日标题。
想要绝对严格的用户可以改成 `reject`，`/preview` 会当场显示通过率变化。

注意 `简` + `reject` 只剩 45.8%——这个组合能保证拿到的一定是简体，但会显著减少候选，
对冷门番可能导致长期抓不到。建议只在候选充足的热门番上使用。

`繁` 的通过率始终高于 `简`（79.8% vs 66.5%），因为繁体标注更普遍且字形通道判出的
繁体（81 条）远多于简体（31 条）。这不代表繁体资源更好，只是标注习惯的差异。

### 顺带修正客户端

客户端目前硬编码 `include: ['简']`（`anime_garden_repository.dart:31`）。
实测繁体(177) 多于简繁(168) 和简体(93)，而 `include` 是字面匹配，
所以这个条件会漏掉全部依赖字形判定的资源（含最大发布者）。
建议客户端搜索改为不带语言条件，把语言判定交给统一的 `detect_language`。

## 数据模型

三张新表。`preference_profiles` 独立出来是因为用户不该为每部番重复配一遍画质偏好。

### `preference_profiles`

```
id                int   pk
name              str   '默认' / '严格简体' / '收藏级'
is_default        bool  新建订阅时继承哪一个

-- 硬过滤
language_mode     str   any | 简 | 繁      default '简'
language_unknown  str   accept | reject   default 'accept'
must_include      json  list[str]  全部必须出现，用户自定义
exclude_tokens    json  list[str]  任一命中即丢弃

-- 软偏好（有序，靠前 = 更想要）
prefer_resolution json  list[str]  default ['1080p','2160p']
prefer_codec      json  list[str]  default ['av1','hevc','avc']
prefer_subtitle   json  list[str]  default ['日','无']        简日/繁日 优先
prefer_bitdepth   json  list[str]  default ['10bit','8bit']

weights           json  dict[str,float]   见打分模型
neutral_score     float default 0.5       软偏好维度未命中时的得分

accept_now_score  float default 0.85      达到即立即下载，不等待
grace_hours       float default 3.0       等待窗口，见决策流程
```

### `subscriptions`

一部番一行，必须绑定一个已存在的 `Anime`——海报、集数、名称、`bangumi_id` 全部复用。

```
id                  int   pk
anime_id            int   fk anime.id, unique, ondelete CASCADE
enabled             bool  default true
profile_id          int   fk preference_profiles.id

fansubs             json  list[str]   有序 = 优先级，用户在添加时选择
allow_no_fansub     bool  是否接受个人发布 / 无字幕组
search_keywords     json  list[str]   → search
must_include        json  list[str]   叠加在 profile 之上（取并集）
exclude_keywords    json  list[str]   叠加在 profile 之上（取并集）
use_subject_id      bool  是否用 anime.bangumi_id 收窄
resource_types      json  default ['动画']

profile_overrides   json  nullable    仅覆盖 profile 的部分字段
episode_offset_override int nullable  Bangumi 数据有误时的人工兜底

cursor_at           datetime
last_checked_at     datetime
last_found_at       datetime
last_error          text
created_by          int   fk users.id
```

### `subscription_episodes`

台账。承担候选池、可观测性、失败重试退避三个职责。

```
id                int   pk
subscription_id   int   fk, ondelete CASCADE
episode_index     int   解析后的本季集号
resource_id       int   AnimeGarden id
resource_title    text
score             float 打分结果
attributes        json  解析出的属性，排查用
download_hash     str(40) nullable
state             str   candidate | matched | downloading | imported
                        | needs_review | skipped | failed
reason            text  skip / fail 的原因
first_seen_at     datetime   等待窗口的计时起点
created_at, updated_at

unique(subscription_id, episode_index, resource_id)
index(subscription_id, episode_index, state)
index(resource_id)
```

> **去重的权威来源是 `Episode.index` 是否已存在**，不是这张台账。
> 种子一加上就立刻建 Episode 行（`add_downloaded_episodes` 的现有行为），
> 所以「我有没有第 N 集」在下载开始那一刻即为真，不存在竞态窗口。
> 台账的 unique 约束是第二道防线。

## 属性解析器

### 一个必须避开的正则陷阱

真实标题用 `_`、`.`、`x` 做分隔符，而这些（`_`）在正则里是**单词字符**，所以 `\b` 边界会失效：

```python
re.search(r'\bav1\b', 'GB_CN AV1_opus 1080p'.lower())   # → None，漏掉了
```

`AV1` 和 `_opus` 之间没有单词边界。必须改用显式的字符类否定：

```python
W = lambda s: r'(?<![a-z0-9])(?:' + s + r')(?![a-z0-9])'
re.search(W(r'av1'), 'gb_cn av1_opus 1080p')            # → 命中
```

这个陷阱同样影响 `AACx2`、`H.264`、`x265` 等写法。**上一节的覆盖率数字就是修正这个正则后重测的**——
修正前 AV1 覆盖率被误报为 0%。

### 正则表

全部对 `title.lower()` 匹配，按列表顺序取第一个命中。

语言的检测规则见[上一节](#检测token-优先字形兜底)，此处是其余三个软偏好维度。

| 维度 | 取值 | 正则 |
| --- | --- | --- |
| resolution | `2160p` | `2160p|3840x2160|W(4k)` |
| | `1080p` | `1080p?|1920x1080|fhd` |
| | `720p` | `720p?|1280x720` |
| | `480p` | `480p|848x480` |
| codec | `av1` | `W(av1)` |
| | `hevc` | `hevc|W(h\.?265|x265)` |
| | `avc` | `W(avc|h\.?264|x264)` |
| bitdepth | `10bit` | `10-?bits?|yuv420p10|hi10p` |
| | `8bit` | `(?<!\d)8-?bits?` |

`2160p` 必须排在 `1080p` 之前，否则 `3840x2160` 会被 `1080p?` 的宽松写法干扰。

`8bit` 的前置否定 `(?<!\d)` 是必需的：没有它，`yuv420p10` 之类的写法里
`0p10` 后面若跟 `8bit` 之外的数字组合可能误命中，且 `10bit` 本身以 `10` 结尾、
`0` 属于 `\d`，宽松写法下容易互相干扰。先匹配 `10bit` 再匹配 `8bit` 也是同一个原因。

解析结果整体存入 `subscription_episodes.attributes`，便于事后排查「为什么选了这个版本」。

### `must_include`：自定义必含列表

音频、色深、来源、容器这些维度不各建一个字段，统一由用户自己指定：

```
must_include: [flac]              # 只要无损音轨
must_include: [10bit]             # 只要 10bit
must_include: [BDRip, FLAC]       # 收藏级：蓝光源 + 无损
must_include: []                  # 默认为空，不作任何要求
```

语义是**全部必须出现**（对应 AnimeGarden 的 `keywords` 参数），大小写不敏感，
按子串匹配标题，不走上面的维度解析。profile 与 subscription 两级的 `must_include`
取**并集**——两边都要满足。

这条是硬过滤，所以要提醒用户：加得越多候选越少。UI 上每加一项都应通过 `/preview`
即时显示剩余候选数，这是唯一能防止用户把自己过滤到零的手段。

`exclude_tokens` 同理，语义是**任一命中即丢弃**。

## 偏好打分模型

### 单维度得分

```
维度 d 的有序偏好列表 P_d = [p0, p1, ..., p_{N-1}]，靠前越想要

score_d = 1 - i/N        若解析结果命中 P_d[i]
        = neutral_score  若该维度解析不出（默认 0.5）
        = 0              若解析出的值不在 P_d 中
```

三分支的区别很关键：**「没写」和「写了但我不想要」不是一回事**，前者给中性分，后者给零分。

### 字幕组得分

字幕组不走属性解析，直接用 `subscriptions.fansubs` 的下标：

```
score_fansub = 1 - i/N   若发布者是 fansubs[i]
             = neutral   若无字幕组且 allow_no_fansub = true
             = neutral   若 fansubs 为空（用户没做选择，该维度无信息）
             = 丢弃      若不在 fansubs 列表中（fansubs 非空时视为硬过滤）
```

`fansubs` 为空时给 neutral 而不是 0 很重要：这个维度权重 45，全给 0 会把总分上限压到
0.55，`accept_now_score` 永远达不到，等于给所有候选都强加一个 `grace_hours` 的延迟。

字幕组是唯一默认作硬过滤的维度——因为它是用户在添加时**明确勾选**的，
不存在「未命中是因为没写」的问题（`fansub` 是结构化字段，不是从标题猜的）。

### 总分

```
total = Σ (weights[d] × score_d) / Σ weights[d]
```

`language.script`、`must_include`、`exclude_tokens` 已在硬过滤阶段处理完，不参与排序。
参与打分的是五个维度：

```yaml
weights:
  fansub:     45    # 用户明确勾选的，最重要
  resolution: 22    # 98% 覆盖率，可靠
  codec:      15    # 79% 覆盖率
  subtitle:   12    # 简日/繁日 优先；14.7% 覆盖率
  bitdepth:    6    # 12.8% 覆盖率，权重必须低
```

`subtitle` 和 `bitdepth` 的权重刻意压低，因为它们覆盖率低（14.7% / 12.8%），
对多数候选返回 neutral。给高权重不会让偏好更"生效"，只会让少数标注详细的发布
凭标注本身而非质量胜出。

若某维度权重设为 0，等价于完全忽略该维度。

### 配置示例

「只要简体、优先带日文字幕、优先 1080p、优先 av1、优先 10bit」写出来是这样：

```yaml
# preference_profiles: '默认'
language_mode:     简                  # 硬过滤
language_unknown:  accept              # 见语言章节的通过率表
must_include:      []
exclude_tokens:    [720p, 480p, 粤语]

prefer_subtitle:   [日, 无]            # 简日/繁日/简繁日 优先
prefer_resolution: [1080p, 2160p]      # 2160p 体积大，排后面
prefer_codec:      [av1, hevc, avc]    # av1 只占 1%，必须把可接受项都列上
prefer_bitdepth:   [10bit, 8bit]

neutral_score:     0.5
accept_now_score:  0.85
grace_hours:       3.0
```

```yaml
# preference_profiles: '收藏级'
language_mode:     简
language_unknown:  reject              # 严格，代价见通过率表
must_include:      [BDRip]
exclude_tokens:    [720p, 480p, 粤语]

prefer_subtitle:   [日, 无]
prefer_resolution: [2160p, 1080p]
prefer_codec:      [av1, hevc, avc]
prefer_bitdepth:   [10bit, 8bit]

grace_hours:       72.0                # 蓝光发布慢，窗口开大
```

三个软偏好列表都遵循同一条规则：**把所有可接受的取值按顺序列全，不要只写最想要的那一个。**
`prefer_bitdepth: [10bit]` 会让所有明确标注 `8bit` 的发布得 0 分——而 8bit 完全可看，
只是不如 10bit。写成 `[10bit, 8bit]` 才是「优先 10bit」，写成 `[10bit]` 是「只要 10bit」。

注意 `prefer_codec` 里 `av1` 排第一但 `hevc`、`avc` 都在列表内。如果只写 `[av1]`，
所有 avc 发布会得 0 分（「写了但不想要」），实际效果等同硬过滤，99% 的资源被压到最低分——
那不是「偏好 av1」，是「只要 av1」。**要表达偏好，就必须把可接受的选项全部列进去，按顺序排。**

## 决策流程

打分只有在存在多个候选时才有意义，所以必须配一个等待窗口。否则第一个到达的发布永远直接胜出，
偏好配置形同虚设。

```
资源命中订阅
  │
  ├─ 硬过滤（任一不通过即丢弃，记 skipped + reason）
  │    ├─ 字幕组不在 fansubs 列表
  │    ├─ 语言不满足 language_mode / language_unknown
  │    ├─ must_include 未全部出现
  │    ├─ 命中 exclude_tokens
  │    └─ 命中合集 / 区间 / 非正片特征
  │
  ├─ 解析集数（见下节）
  │    ├─ 解析不出 ──────────────────────→ needs_review
  │    └─ Episode.index 已存在 ──────────→ 丢弃
  │
  ├─ 解析属性 → 打分
  │
  ├─ total ≥ accept_now_score ──────────→ 立即下载
  │
  └─ 否则 → 写入候选池 (state=candidate, first_seen_at=now)

每轮 sweep 末尾，检查候选池：
  对每个 (subscription, episode_index) 分组：
    now - min(first_seen_at) ≥ grace_hours ?
      → 取组内最高分候选下载，其余标 skipped
      → 平分时取 first_seen_at 更早的
```

几个要点：

- 等待窗口是**按 (订阅, 集号) 计时**的，起点是该集第一个候选出现的时间。所以一集最多等
  `grace_hours`，不会因为后续有新候选进来而无限延后。
- `accept_now_score` 默认 0.85 的含义：命中首选字幕组 + 首选分辨率基本就能达到，
  所以「我只看某个组」的用户感受不到任何延迟。
- `grace_hours = 0` 就退化成先到先得，这是给不在意版本的用户的选项。
- qBittorrent 不可用时整轮跳过且**不推进游标**，下一轮自然重试。

## 集数解析

下载决策发生在拿到文件列表**之前**，所以只能从标题判断集数。现有的 `_matchesEpisodeIndex`
（`anime_garden_episode_match_controller.dart:307`）是对文件名做事后匹配，用不上。

### Bangumi 提供了两套合法编号

`GET /v0/episodes?subject_id=X` 的每条记录同时有 `ep`（季内集号）和 `sort`（绝对集号）。
实测 `offset = sort - ep` 在每部番内**恒为单一值**：

| 番剧 | `ep` 范围 | `sort` 范围 | offset |
| --- | --- | --- | ---: |
| 葬送的芙莉莲 S1 | 1..28 | 1..28 | 0 |
| 咒术回战 怀玉·玉折 | 1..23 | 25..47 | 24 |
| 咒术回战 死灭回游 | 1..12 | 48..59 | 47 |
| 我推的孩子 S2 | 1..13 | 12..24 | 11 |
| 进击的巨人 最终季 | 1..16 | 60..75 | 59 |
| Re:Zero S4 奪還篇 | 1..8 | 78..85 | 77 |

所以**不需要让用户填 offset**，也不需要猜标题用的是哪套编号——只看解析出的数字 `N`
落在哪个区间：

```
Re:Zero S4 奪還篇:  ep 1..8   sort 78..85
  "- 79"    → 落在 sort 区间 → ep = 79 - 77 = 2   ✓「站起来」2026-08-19
  "S04E02"  → 落在 ep 区间   → ep = 2             ✓ 同一集
```

`episode_offset` 不需要作为字段存储：服务端本来就必须拉 Bangumi episodes（自动入库的集需要
正确集名），`ep` / `sort` / `airdate` 就在同一个响应里，offset 现算即可。只保留
`episode_offset_override` 应对 Bangumi 数据本身有误的情况。

### 区间重叠时用 airdate 判定

`offset < 本季集数` 时两区间会重叠。实测【我推的孩子】S2：offset=11 但有 13 集，
所以 `N=12,13` 有歧义。

需要说明这不是 SP 混入导致的：实测 Bangumi 的 SP / OP / ED 使用 `sort=0` 或小数
（`7.5`、`20.5`），**从不占用整数 sort 槽位**，本篇的 sort 在两季内都是连续的。
真正的原因是上一季（11 集）比本季（13 集）短，offset 必然小于本季集数。

这时用 `airdate` 判定：

```
N=12 → 季内解读 = ep 12「重逢」    2024-09-25
     → 绝对解读 = ep 1 「东京BLADE」2024-07-03      相隔约 12 周
```

字幕组发布时间与播出时间通常只差几天，12 周的间距是决定性的。取
`|resource.createdAt - episode.airdate|` 更小的那个解读。

### 先擦掉技术标注，再找集号

标题里绝大多数数字都不是集号：`1080p`、`10bit`、`x264`、`AAC 2.0`、`v2`、`1920x1080`。
**必须在集数解析之前把这些 token 整段抹成空白**，而不是事后用数值黑名单排除——
`8` 和 `10` 既是色深也是合法集号，黑名单会让每部番的第 8、10 集永远解析不出来。
抹除只用于集数与合集判定，属性解析仍读原始标题。

同一处理还解决了区间误判：`x264-10bit` 抹除后不再含数字，而
**真实区间不带空格**（`01-12`、`[01-24]`）或带显式单位（`01-12话`），
带空格的 ` - ` 是「`作品 S2 - 05`」这类分隔符，必须判为单集。
只按 `\d+-\d+` 匹配会把所有带阿拉伯数字季号的标题全部丢掉。

### 解析顺序（短路）

1. 命中 `SxxEyy` → 取 `yy`，校验 `xx` 与季号一致
2. 命中合集 / 区间特征（`合集`、`01-12`、`1-24`、`BDRip` 且无单集号）→ **skip**
3. 命中非正片关键词（`NCOP`/`NCED`/`PV`/`SP`/`OVA`/`特別編`/`CM`/`菜单`）→ **skip**
4. 命中 `&nbsp;- N` / `[N]` / `第N话` / `第N集` → 取 `N`
   - 容许 `END`/`FIN`/`完` 尾缀，`v2` 视为同集重发
   - 小数集（`10.5`）单独处理，不并入正片序列
5. `N` 落在 `ep` 区间还是 `sort` 区间 → 换算成季内集号；重叠则用 airdate 判定
6. 都不命中 → `needs_review`，**不猜**

### 一条合理性护栏

解析出的集数如果 `airdate` 还在未来，说明解析错了 → 直接拦下进 `needs_review`。
这条比任何正则都可靠，能挡住一大类误判。

`airdate` 同时用于首页「追番中」分区的「下一集预计时间」，不需要自己推算周更规律。

## 配置流程

### 添加订阅

1. 用户在 Anime 详情页点「追番」。
2. 服务端用 `subjects=[anime.bangumi_id]` 拉取该番已有资源，**聚合出真实候选列表**，
   而不是让用户手打字幕组名。实测输出：

   ```
   Re:Zero S4 奪還篇 (subject=633836)     葬送的芙莉莲 S1 (subject=400602)
     8 条  Kirara Fantasia                5 条  (无字幕组/个人发布)
     3 条  (无字幕组/个人发布)              3 条  拨雪寻春
     2 条  天月動漫發佈組
     2 条  ANi
     1 条  Nix-Raws
   ```

   用户看到的是这部番实际有谁在发、发得勤不勤。**必须为「无字幕组」留显式选项**——
   从数据看这类占比不低（芙莉莲 S1 样本里是最大类）。

3. 字幕组多选，顺序即优先级（拖拽排序）。
4. 画质偏好默认继承 `is_default` 的 profile，可在本订阅内覆盖。
5. 底部挂 `/preview` 的实时结果。

### `/preview` 是必需的，不是加分项

预览返回「按当前规则，最近若干集会选中哪个发布、得分多少、其余候选为何落选」。

没有它，用户要等一周才知道规则配错了——这是这类功能最主要的挫败感来源。
而且预览必须与 worker **共用同一份**解析和打分代码，否则两者会漂移，预览就失去全部意义。
这是整个功能里唯一非做不可的代码共享点。

## API

```
GET    /api/v1/subscriptions                    列表，含下次检查时间、最近命中
POST   /api/v1/subscriptions                    创建
PUT    /api/v1/subscriptions/{id}               改过滤条件 / 开关
DELETE /api/v1/subscriptions/{id}
POST   /api/v1/subscriptions/{id}/check          立即检查
GET    /api/v1/subscriptions/{id}/episodes       台账，含 needs_review 与候选池
POST   /api/v1/subscriptions/preview             试跑规则，不下载
GET    /api/v1/subscriptions/fansubs?bangumi_id= 聚合该番的字幕组候选列表

GET    /api/v1/preference-profiles
POST   /api/v1/preference-profiles
PUT    /api/v1/preference-profiles/{id}
DELETE /api/v1/preference-profiles/{id}
```

权限沿用现有约定：写操作 `require_download_permission`（与「添加下载任务」同级，Guest 不可），
读操作 `get_current_user`。`/preview` 归入写侧——它是配置流程的一部分，且会代表用户打上游；
`/fansubs` 与 `/episodes` 是读操作。`docs/permissions.md` 的权限表已同步。

## 调度器

`run.py` 是 `workers=1` 单进程，因此进程内 asyncio 调度器即安全，不需要分布式锁。

```python
# app/main.py lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    task = asyncio.create_task(subscription_worker())
    yield
    task.cancel()
```

```yaml
# config.yaml 新增段
subscription:
  enabled: true
  interval_minutes: 15
  cold_start_days: 7        # 游标为空时回溯多久，避免首次抓全站历史
  max_pages_per_sweep: 5    # 上游异常时的保险
  auto_import: true         # false = 只入台账不下载，观察模式
```

- 加抖动，避免整点集中打上游。
- **每个订阅独立 try/except**：失败写 `last_error` 后继续，一个订阅不能拖垮整轮。

## 复用现有代码

服务端改动以新增为主。项目 schema 其实已经为「每集一个独立种子」做好了准备：

| 能力 | 位置 | 用途 |
| --- | --- | --- |
| `Episode.download_hash` | `models/anime.py:55`（migration 0003） | 每周单集种子各有自己的 hash，**存储结构不用改** |
| `_episode_file_path()` | `routes/anime.py:485` | 已是 `episode.download_hash or anime.download_hash` |
| `_download_save_path()` | `routes/qbittorrent.py:534` | 每种子落 `data/<hash>/`，天然不冲突 |
| `add_downloaded_episodes` | `routes/anime.py:158` | 增量加集 + 跨番剧同步文件优先级 |
| `download_torrent_files` | `routes/qbittorrent.py:55` | 等元数据、选文件、自动带同名字幕、分类、分享率 |
| `_wait_for_metadata` | `routes/qbittorrent.py:338` | 由 `fetch_torrent_metadata_files()` 包装给 worker 调用。worker 不能走路由用的单次 `_fetch_metadata`——刚提交的磁力还没有元数据，没人替它重试 |
| `AnimeGardenEpisodeMatchPage` | `anime_garden_episode_match_page.dart` | `needs_review` 的人工兜底 UI |

需新增的服务端外部客户端（`httpx` 已在依赖内）：

- `services/animegarden_service.py` — sweep 查询
- `services/bangumi_service.py` — episodes（`ep`/`sort`/`airdate`/集名），带缓存

### 下载后的文件匹配

单集种子通常只含 1 个视频文件：

1. 复用 `_wait_for_metadata()` 拿文件列表
2. 过滤视频扩展名且 `size > 10MB`（沿用 `_buildDefaultMatches` 的既有门槛）
3. **恰好 1 个** → 自动选中，集名取自 Bangumi，调 `add_downloaded_episodes` 入库
4. **多于 1 个** → **不猜**，标 `needs_review`，交由现成的匹配页人工处理

## 分期

### P1 — 能跑

- migration 0004 建三张表
- `animegarden_service` + `bangumi_service`
- sweep worker + 标题集数解析（ep/sort 双区间 + airdate 判定 + 未来集护栏）
- 属性解析器 + 打分模型 + 等待窗口
- CRUD / `preview` / `fansubs` 接口
- 详情页追番开关 + 字幕组选择器 + 偏好继承

### P2 — 好用

- 客户端处理 `needs_review` 队列
- 偏好 profile 管理页（全局 + 每订阅覆盖）
- 集数补齐后自动停订
- 候选池可视化：让用户看到「正在等更好的版本」

### P3 — 可选

- 磁盘配额保护（空间不足时暂停订阅，而非填满盘）
- 新集下载完成通知
- 订阅规则导入 / 导出

## 明确不做的事

- **不做版本升级替换。** 下载完成后若出现更高分的发布，不删除重下。删档重下会浪费带宽、
  打断正在观看的用户、并使 `WatchProgress` 的 `episode_id` 关联失去意义。收益不足以抵消风险。
- **不做客户端交互式搜索迁移。** 客户端的 AnimeGarden / Bangumi 搜索保持直连。
  当前 `apiVersion` 只在设置页展示（`settings_home_controller.dart:35`），
  没有任何兼容校验；一旦搜索改走服务端，「新客户端 + 旧服务端」会直接 404。
  若将来要迁移，应先补上启动时的版本校验，并采用透传代理而非重新包装业务逻辑。
- **不为音频 / 来源 / 容器各建一个偏好维度。** 实测这些维度没有排序空间
  （aac 297 : flac 4）。统一交给 `must_include`，用户想卡就自己写，不想卡就留空。
- **`has_jp` 不作硬过滤。** 只占 14.7%，硬要求会砍掉 85% 的候选。它只影响排序。

## 实测依据

- 上游 API：`api.animes.garden` `/resources`（`after` / `subjects` / `fansubs` / `types`）
- 集数元数据：`api.bgm.tv` `/v0/episodes`（`ep` / `sort` / `airdate` / `type`）
- 全站日增量：`types=['动画']` 近 24 小时 **82** 条
- 属性覆盖率：近 21 天 `types=['动画']` **400** 条真实标题
- 语言标注与字形判定、按发布者一致性、各档通过率：近 28 天 **600** 条 / 33 个发布者
- 集数编号（`ep` / `sort` / offset 恒定性）：6 部番，覆盖首季 / 续季 / 分割季
- SP 是否占用整数 `sort` 槽位：我推的孩子 S1 + S2（结论：不占用，SP 用 `sort=0` 或小数）
- 测量日期：2026-08-20

所有数字都可用文档内给出的参数复现。若上游资源结构变化（例如某大发布者改变标注习惯），
覆盖率和通过率需重测——`language_unknown` 的默认值直接依赖「最大发布者不写 token」这一事实。
