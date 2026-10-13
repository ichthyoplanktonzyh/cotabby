# 学习单位、词典与对应显示：2026-10-13

后续已恢复完整 GE 指令，包括数量建议；本页保留改动前的历史实验记录。
最新原生对照与显示计时见 [GE 恢复报告](ge-restoration-2026-10-13.md)。

本轮实现译文先显示、离线学习单位异步补充、可选模型对应异步补充。点击边界与意义对应范围独立：`look forward to` 整组查词；`seeing`、`you` 可分别点击，也可被同一意义范围覆盖。显示标记不修改句子，复制仍是完整原译文。

## 实现与验证

- `LearningUnitRecognizer` 只匹配词库头词、记录词形与显式模式中的保守单词槽位。代词槽位不猜任意名词短语；常见 `'s` 缩写不能冒充所有格。未知表达回退到可点击的单词。
- `LearningLexiconService` actor 共享一份懒加载词库；识别、系统词典调用不阻塞 MainActor。词库为 Wiktionary / Kaikki 的独立 CC BY-SA 4.0 表达子集，34,397 条、11,543,088 字节，覆盖 13 个语言代码（简繁中文共库），覆盖不均，保留英文释义。
- 双击译文中的表达打开一个非激活词典窗口；内部单词与返回整个表达复用同一会话和窗口。短语未命中明确显示；系统回退只有在检测范围覆盖整个查询时才返回定义，不拼接内部单词释义。
- 中性下划线与原意对应颜色分开。对应完成前不预填对应颜色；对齐不能拆散一个完整学习单位。一个对应可包含多个单位。任一阶段失败保留译文，迟到结果不能附到新句子上。
- 初轮 59 项 Release 回归通过；最后词典绘制/面板 5 项、提示词 2 项及耗时实验分别通过。数据导入、历史实验脚本 9 项通过。数据按已跟踪 URL/hash 恢复后，最终 JSON 与原资源逐字节相同。

## 显示耗时

设备：Apple M1 Max，32 GiB，macOS；Release app-hosted fixture。使用现有 Gemma 4 E4B Q4_K_M 分析权重，SHA-256 `370c2879f17648d337b0ab4e208fdce348e24d1060064e93d7645daafd56d39c`。

起点是完整译文第一次经过生产浮窗 NSView bitmap 绘制；终点是学习单位下划线或对应背景色实际绘制。走真实协调器、词库、模型控制器、分析服务、解析器和 TextKit/SwiftUI 卡片。翻译器提供固定句子对，输入停顿、AX 捕获和翻译模型生成耗时不包含在下表中。名义轮询间隔 5ms，调度、布局及绘制仍会增加误差；不是端到端打字延迟或屏幕扫描时间。

| 场景 | 学习单位显示 | 对应颜色显示 |
|---|---:|---:|
| 首次，新词库 owner / 未加载分析上下文，两轮各 1 次 | 635–673 ms | 6.51–9.36 s |
| 后续，同进程词库与分析模型已加载，共 4 次 | 12–19 ms | 0.74–0.78 s |
| 重复句子，协调器缓存命中，两轮各 1 次 | 与译文首次绘制同时 | 与译文首次绘制同时 |

“首次”不代表清空操作系统文件缓存。模型加载占首次对应等待的大部分。缓存记录的 0ms 表示首次绘制已包含结果，不是计算与绘制绝对零耗时。样本仅三个中文到英文短句，不能当作整体延迟分布或跨语言覆盖率。

## 对应质量边界

三个句子分别是“我期待见到你。”“你可以慢慢来。”“我会照顾你。”。学习单位独立识别了 `look forward to`、`take … time`、`take care of`；词典与单词下钻可用。

当前模型在两轮均输出整句一组对应，结构与定位合法，但细粒度学习价值不足。第二轮只补了简短的“优先有意义的部分，短问候/固定表达可整组”规则，未改善这三个样本；没有恢复固定 3–6 块要求。两轮冷加载不同不能解释为提示词速度收益。本轮完成数据结构与交互，不能据此宣称模型对应质量已解决；应用不会凭词库自行编造原意映射。

历史 GE 实验提示词已冻结；本轮产品提示词单独导出为 `Learning`，避免改写旧实验结论。

## 证据与重跑

[摘要 JSON](learning-units-2026-10-13.json)；原始记录和位图在 `build/LanguageLearning/LearningUnitStudy/`。`Latency-Release` 为第一轮，`Latency-Refined` 为粒度规则复测。`final-tests.xcresult`、`dictionary-final.xcresult`、`latency-refined.xcresult` 分别保留执行结果。

`LearningDisplayLatencyTests` 默认跳过；在 Release build-for-testing 生成的 xctestrun 的测试 target `EnvironmentVariables` 和 `TestingEnvironmentVariables` 中设置：

```text
COTABBY_ANALYSIS_GGUF=/path/to/Gemma-4-E4B-Q4_K_M.gguf
COTABBY_LEARNING_LATENCY_OUTPUT=/path/to/new-output-folder
```

随后用 `test-without-building -only-testing:CotabbyTests/LearningDisplayLatencyTests -parallel-testing-enabled NO` 单独运行；保留 repo-scoped `-derivedDataPath build/DerivedData`。不要同时构建或运行其他模型实验。此 fixture 不更新安装应用或修改用户偏好。
