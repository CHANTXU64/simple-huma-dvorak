# simple-huma-dvorak

虎码（tigress）的 Rime 方案，给 macOS 的鼠须管（Squirrel）用。码表用 Dvorak 键面上的字母，
配合 Karabiner 把键盘改成 Dvorak 后直接敲码。

## 安装

```sh
./build.sh            # 生成 build/ 目录（会读 tools/ 下的字表、拼装词典）
```

把 `build/` 里的内容拷到 `~/Library/Rime/`，再重新部署（`Squirrel --reload`，改了 Lua 或 schema 建议直接重启 Squirrel）。

个人词库放在 `tigress_user.dict.yaml`，已被 `.gitignore` 忽略，不会进公开仓库；本地存在时 `build.sh` 会把它排在词典最前面。

## Lua 小工具（`lua/`，在 `rime.lua` 里注册）

| 文件 | 作用 |
|---|---|
| `core2022_filter.lua` | 自定义字符集过滤（常用字集） |
| `add_user_word.lua` | 先分段上屏，再敲整词码，候选最后会冒出拼好的词，选中即加入 `user_words.tsv`。只追加在最后，不改词序 |
| `ascii_toggle.lua` | Ctrl+Space 切换中/西文；敲到一半时先把已敲的字母上屏再切换（Karabiner 把 Ctrl+Space 改成 Ctrl+右Option+Space） |
| `swap_fix.lua` | 左右手按快了、相邻两键顺序颠倒时自动纠正，见下 |
| `omit_fix.lua` | 只敲了一简字那一个键、漏了第二键（如 一个 `uchi` 打成 `uhi`）时自动补键，见下 |
| `typing_log.lua` | 把输入过程记成本地日志，供事后分析，见最后一节 |

另外：右 Shift 单击也能切中/西文（`commit_code`），各应用的默认中/西文状态在 `squirrel.custom.yaml` 的 `app_options` 里。

## swap_fix：左右手抢拍自动纠正

打字快的时候，左右手交替的相邻两键容易顺序颠倒，比如想打 提交（`grax`）打成了 白癜风（`garx`）。
这个滤镜在输入满 4 码时，把相邻、左右手交替的两键对调后查词典，满足条件就把对调后的词放到第一位，
候选注释是 `↔`。

规则（全部满足才会改顺序，其余输入的顺序完全不动）：

- 只对调第 2、3 键和第 3、4 键，第 1 键不动
- 对调后的第一候选是词（至少两字），权重不低于 `min_target_weight`
- 实际敲出的第一候选是词（或没有候选），权重不超过 `max_typed_weight`，比较常用的词绝不会被顶掉
- 对调后的词要比实际敲出的词常用 N 倍以上，N 随被顶掉的词浮动：权重不超过 `low_weight`
  的凑数词只要 `ratio_low` 倍，权重到 `max_typed_weight` 时要 `ratio_high` 倍，中间按对数插值

参数写在 `tigress.schema.yaml` 的 `swap_fix:` 下，缺省值：

```yaml
swap_fix:
  max_typed_weight: 400
  low_weight: 60
  ratio_low: 3
  ratio_high: 10
  min_target_weight: 500
```

开关 `swap_fix` 在 Rime 的方案菜单里切换（默认开）。不学习、不记录任何东西，出错时退化成原样输出。

代价：按默认参数，约三千多个冷门 4 码词（多数是词典里权重很低的凑数词）在敲对时也会被对调后更常用的词顶到第二位。
想更保守就调小 `max_typed_weight` 或调大 `ratio_*`。

注意：词条权重在 librime 里存的是 `ln(原始权重) + ln(1e-8)`，`swap_fix.lua` 里的 `LOG_OFFSET` 就是为此而设。

## omit_fix：一简字漏第二键自动补全

虎码每个键有一个"一简字"（`u`=一、`y`=我、`g`=的……），敲一个键就能出。手快时打 2 字词，容易只敲一简字的那一个键就走，
漏掉它本该有的第二键：想打 一个（`uchi`），"一"是 `u` 的一简字，只敲了 `u`，成了 `uhi`（漏了 `c`）。
`uhi` 不是任何词的码，候选只有编码提示（补全）列出的 `一人善射，百夫决拾` 之类冷门词。

这个滤镜在输入正好 3 码、且这个 3 码在词典里**没有任何精确词条**时，补上漏掉的键，
把补出的常用词放到第一位，候选注释是 `⊕`：

- 补的键只能是"第 1 个字的第 2 键"（插在第 1 键后）或"第 2 个字的第 2 键"（补在末尾），补出的是 2 字词
- 漏键的那个字必须恰好是它第一键的一简字；不是的不补（比如 `眼` 不是 `'` 的一简字，`''a` 不会被补成 `'c'a` 眼睛）
- 词典里的正式 3 码（简码词如 `uhh` 一个人、3 码单字）一律不动
- 判断规则与 swap_fix 相同（权重上限、随词频浮动的倍数、词本身的最低权重），参数在 `omit_fix:` 下，缺省值同 swap_fix
- 开关 `omit_fix` 在 Rime 方案菜单里（默认开）；触发时会写一条 `omit_fix` 日志事件

按默认参数，约 75 个 3 码状态会被改动（63 个原本有补全候选，12 个原本没有）。敲成语等 4 字词本来就会敲全 4 码，不会停在 3 码，所以不单独保护补全里的成语。

## typing_log：输入日志与分析

`lua/typing_log.lua` 把输入过程写到 `~/Library/Rime/typing_log.YYYY-MM-DD.jsonl`（每行一个 JSON，只在本机，不会过期；文件创建时权限是 0200，只写，属主也读不了），
用来找出自己常犯的错、优化码表和规则。开关 `typing_log` 在 Rime 方案菜单里（默认开），关掉后什么都不写；西文模式下的按键不记。

记录的事件：

| `e` | 含义 |
|---|---|
| `commit` | 上屏的词 `text`、当时敲的码 `code`、选了第几个候选 `idx`（从 0 数）；Squirrel 1.1.2 取不到当前应用，所以没有应用字段 |
| `bs` | 退格。`composing=false` 是敲码之外的退格（多半在删刚上屏的字），`true` 时 `code` 是退格前的码 |
| `cancel` | 敲了码按 Esc 取消 |
| `swap_fix` / `omit_fix` | 自动纠正了一次（带原词和纠正后的词） |

做不到的：Rime 看不到应用里的文本，鼠标选中删除、Cmd+Delete 之类的删除记不到，只能看到按了 Backspace。

分析前先给自己开读权限，看完再收回：

```sh
chmod u+r ~/Library/Rime/typing_log.*.jsonl
python3 -I tools/typing_log_report.py            # 默认读 ~/Library/Rime，可加 --days 7
chmod u-r ~/Library/Rime/typing_log.*.jsonl
```

脚本靠"上屏 → 若干退格 → 再上屏"的序列还原纠错，按码的差异分类（左右手换位 / 同手换位 / 错一个键 …），
列出出现最多的"打出→改成"，并统计 swap_fix 的命中和疑似误伤。也可以直接把日志文件交给 AI 去分析。

注意：日志里有你上屏的全部中文内容，不要提交、不要上传；权限只是防误读（备份、同步、别的工具随手读到），不是真正的加密，同一用户能 chmod 回来；想清空直接删 `typing_log.*.jsonl`。
