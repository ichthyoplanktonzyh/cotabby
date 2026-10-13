# 数量要求与 DeepSeek V4.1 Flash 对照：2026-10-13

已完成 504 次正式请求：Gemma C/D 共168次，DeepSeek A/B/C/D 共336次。每组28个固定原文/译文对，各重复3轮，每组分母84。任务是对既定译文进行语块切分与对齐，不生成新的译文，不包含输入停顿、AX或UI。

结论：数量指导有帮助。Gemma 的整句单组明显减少；DeepSeek D 的实际可用返回更多，完成时间基本持平。但模型并没有普遍给出3–6组：例外和“完整表达优先”使它们仍常返回两组，需要进一步明确粒度标准。

## 提示词与运行条件

- A/B/C 逐字复用上一轮冻结提示词。A含解释；B去掉解释，保留对象和NDJSON；C为连续片段的二维数组方案。
- D仅在C的数据段之前插入数量规则，没有同时改格式示例、系统提示词或其他指令。其原文如下：

```text
6. Aim for 3–6 corresponding meaning groups for an ordinary sentence. A short sentence or fixed expression may have 1–3 groups. For a long sentence, split by clauses and allow more than 6 groups when needed. Keep complete expressions intact; do not split mechanically just to reach the count or merge different meanings just to stay below it.
```

- Gemma使用同一文本GGUF、Q4_K_M、Ollama配置和模型摘要；种子42/43/44，温度0.3、top_p0.9、8192上下文、4096输出预算、关闭思考，两个额外校准请求不计分。C/D在同一运行中轮换。
- DeepSeek接口为https://api.deepseek.com/chat/completions，模型deepseek-flash，官方当前对应V4.1 Flash。显式thinking=disabled，temperature0.3，max_tokens4096，不强制JSON模式。官方非思考模式top_p固定1，故不传入；API没有提供本次可用的seed控制，三轮是重复测量而非相同随机种子。所有请求按单客户端串行发出。[官方发布说明](https://api-docs.deepseek.com/news/news260910/)、[请求参数](https://api-docs.deepseek.com/api/create-chat-completion/)。
- 云端时间包含网络、服务排队、预填充及缓存影响。记录缓存命中和响应fingerprint，但无法拆出纯模型推理耗时；本次336次均正常HTTP响应、没有额外思考输出，响应模型名均deepseek-flash，fingerprint一致。

## 完整结果

“程序通过”要求完整严格格式、准确且不重叠的摘取、正常结束、无思考、至少一个唯一可定位的双边组，以及最多40组。它不等于语义正确或每个组均可唯一定位。“三项AI评分均为2”是对应正确性、切分学习价值、重要意思覆盖的辅助审查结果，不是认证准确率。

| 模型 | 组别 | 格式合法 | 程序通过 | 程序通过且三项AI评分均为2 | 完成P50/P95 |
|---|---|---:|---:|---:|---:|
| DeepSeek V4.1 Flash | A | 80/84 | 49/84 | 15/84 | 3.30s / 4.16s（n=49） |
| DeepSeek V4.1 Flash | B | 78/84 | 63/84 | 22/84 | 2.56s / 2.91s（n=63） |
| DeepSeek V4.1 Flash | C | 63/84 | 59/84 | 53/84 | 2.31s / 3.24s（n=59） |
| DeepSeek V4.1 Flash | D | 79/84 | 72/84 | 66/84 | 2.30s / 2.72s（n=72） |
| Gemma4 E4B | C | 84/84 | 84/84 | 45/84 | 1.61s / 2.61s（n=84） |
| Gemma4 E4B | D | 84/84 | 82/84 | 67/84 | 2.03s / 3.11s（n=82） |

上表完成耗时只统计程序通过请求，必须结合n和失败数理解；机器可读结果另保留所有请求耗时、失败、首次内容和首次可用对应组。

## 数量与质量

- Gemma：C单组60/84，D单组29/84；D仍有49次两组，仅6次三组。程序通过从84变82，多出的两次失败都是重复对应整段译文。AI辅助可用结果从45变67，改善主要来自长句不再整体成块。
- DeepSeek：C有15次单组、31次两组、17次三组（其余21次格式失败）；D有9次单组、29次两组、36次三组、4次四组、1次六组（其余5次格式失败）。3–6组占格式合法输出的17/63→41/79。由于允许例外，这只是观察分布，不是硬性数量合规率。
- DeepSeek D的程序通过+质量参考结果53→66，但不能表述为语义准确率提升：格式合法次数本身从63→79；格式合法子集的三项评分均为2比例分别56/63、70/79，几乎相同。它主要改善了可用性及分组形态。
- DeepSeek A/B更倾向逐词或词尾切分，导致条件/否定构式拆散、重复覆盖，A还增加解释输出。C/D更符合本次学习目标。A/B也有把无对应片段写为[""]、改写原文或重叠引用的问题；实验严格统计，不修复后重新算成功。

同一条Gemma第一轮长报告句，C返回原文和译文整句一组，D返回：

```json
[["我原本想今天把报告发给你", "I originally planned to send you the report today"],
 ["但还需要确认两个数字", "but I still need to check two figures"],
 ["所以可能要等到明天上午", "so it may have to wait until tomorrow morning"]]
```

“我一到家就给你打电话。”在D中分为“我一到家↔as soon as I get home”和“就给你打电话↔I will call you”；这是两组，但保留了有价值的结构。能力短句仍可能整句成一组，显示“短句/固定表达”例外还不够明确。

## 延迟怎么理解

- DeepSeek A/B/C/D完成中位数为3.30/2.56/2.31/2.30秒。首个文字出现中位数均约2.1秒，主要等待发生在输出之前；它包含网络、排队和预填充，不能全部归因于网络。D的首次可用对应组中位数约2.21秒，P95约2.72秒。
- 同原文、同轮次且C/D都通过的52对云端请求，D/C完成时间比中位数0.986，差值中位数−32毫秒；没有证据表明数量要求显著拖慢该配置，也未做统计显著性或等效性检验。
- Gemma C/D完成中位数1.61/2.03秒，首次可用对应组约1.38/1.38秒；82对共同通过请求的D/C时间比中位数1.189，差值中位数+283毫秒。两个成功子集各自P50相减约417毫秒，与配对差值不同。
- 本次DeepSeek D与Gemma D的AI参考可用结果66/84与67/84、完成中位数2.30与2.03秒，不能据此宣称云端全面胜过本地。上一轮Gemma B的75/84是历史参考，不是本轮同时重跑的B组。

## 审查、使用量与下一步

- 云端158份、本地46份去重输出覆盖全部格式合法结果；分别复用28和44份旧评分，前提是整份语料和归一化对应组完全相同。其余由GPT-6 Luna xhigh独立审查，隐藏模型/组别标签，沿用原rubric，不按是否3–6组直接打分。AI评分尤其在粒度上存在主观性；上轮12项交叉审查也显示粒度分歧，本轮没有追加人工语言能力认证。
- 云端总输入89049 tokens（缓存命中24690、未命中64359），输出38417 tokens，共127466 tokens；没有额外自动重试。这里记录用量，不推算未经核实的账单金额。
- 建议保留D的软数量目标，并明确例外为哪些表达；提供完整外层数组示例以减少剩余格式错误。继续以完整构式和意义对应为优先，数量规则不能单独定义粒度。生产提示词/解析器尚未改动，翻译本身的云端时延需要另外测量。
- 18项实验脚本单测通过；504个请求/流包一一核验，提示词、数量单变量、重复轮次、原始输出重建和时间戳均检查通过。生成文件中没有密钥形态值；密钥只用于本次内存认证，没有写入项目/配置/日志。
- 未训练模型、未构建或更新App；已安装二进制SHA256不变，Ollama当前无驻留模型，build/DerivedData不存在。

[机器可读结果](alignment-quantity-results-2026-10-13.json)

[云端原始证据](/Users/shadow/cotabby/build/LanguageLearning/AlignmentQuantityEval/20261013T032534Z-cloud)；[本地原始证据](/Users/shadow/cotabby/build/LanguageLearning/AlignmentQuantityEval/20261013T034137Z-local)。
