# 完成记录

> 变更：`CHG-20261028-hos-parity`
> 基线：`e123804+dirty`
> 日期：2026-10-28
> verdict: incomplete

| 条件 | 结果 | 证据 |
| --- | --- | --- |
| 四层设计齐全，判据与设计对应 | 满足 | `requirements/`、`architecture.md`、`hld.md`、`lld.md`、`docs/oracles/` |
| 判据检查无 P0 | 满足 | `checks/specs.txt`：PASS，0 failures，3 warnings |
| 集成、单元与旅程 E2E 全绿 | 部分满足 | 宿主 500/500，Rust 39/39，设备 5/5；VPN tun E2E 未跑 |
| 测试报告属于最终代码 | 满足 | `checks/final.txt`、`checks/host-tests.txt`、`checks/e2e-final.txt` |
| E2E 报告发布且链接 200 | 满足 | `checks/e2e-published.txt` |
| UI 还原核对 | 部分满足 | `checks/ui-parity/main-screen.md`：主页面逐控件比对，参照为 Android 5.3.5-nightly 实机截图；其余页面未核对 |
| 高层次复查门禁 clear | 满足 | `checks/high-level-review.json`：187 条，8/8 维度，0 条强漏项未处置 |
| 高层次复查报告发布 | 满足 | `checks/high-level-review-published.txt` |
| 四层人工确认 | 未满足 | `flow.json` 的 gates：四层均为 `pending` |
| 结果确认（用户原话） | 未满足 | 用户尚未回复交付物 |

本批次完成了 5.4.0 对齐后的全部功能开发，宿主与设备测试全绿。
但不能判定为 `done`：四层人工门禁与结果门禁仍为 `pending`，VPN tun E2E 需真机，UI 还原核对缺参照。

## 交付物

- 主页面、资料编辑、订阅、自定义规则、设置、关于、应用选择、UDP 回退、二维码弹窗。
- 模型层：资料存储与选择、导入导出、订阅刷新、插件选项、按应用代理、ACL 与自定义规则、会话流量结算。
- 原生：x86_64 与 arm64-v8a 两个 ABI。
- 测试：500 条宿主用例，设备套件 `SslocalNativeTest` 与 `SocksE2eTest`。

## 报告链接

E2E 报告： http://100.111.99.60/proj/shadowsocks-ohos/e2e/CHG-20261028-hos-parity/index.html

高层次复查报告： http://100.111.99.60/proj/shadowsocks-ohos/review/high-level-CHG-20261028-hos-parity/index.html

四层审核页：

- 需求： http://100.111.99.60/proj/shadowsocks-ohos/review/requirements/index.html
- 架构： http://100.111.99.60/proj/shadowsocks-ohos/review/architecture/index.html
- HLD： http://100.111.99.60/proj/shadowsocks-ohos/review/hld/index.html
- LLD： http://100.111.99.60/proj/shadowsocks-ohos/review/lld/index.html

## 未达成项与后果

1. 四层人工确认未补齐。后果：批次不能作为下一批次的已完成基线；设计若有返工，代码与判据要跟着改。
2. 用户未确认交付物。后果：`verdict` 只能写 `incomplete`。
3. `VpnE2eTest` 未跑。后果：VPN 路由、DNS、ACL 的设备侧证据来自 6.1.1 真机历史记录，不来自本批次。
4. UI 还原核对只覆盖主页面。后果：子页面的视觉差异仍没有量化证据；主页面已按 Android 实机截图对齐。
5. 60 条弱漏项仍为 `open`。后果：不影响门禁，但需在下一批次逐条处置或接受。

## 缺口登记

| ID | 事项 | 来源 | 归属 | 状态 |
| --- | --- | --- | --- | --- |
| BL-540-01 | 审查四层审核页并给结果确认 | `checks/high-level-review.json`、四层审核页 | owner=user 接收批次=CHG-20261029-hos-parity-signoff | open |
| BL-540-02 | 真机运行 `VpnE2eTest`，需华为签名 | `checks/e2e-final.txt`、`docs/hos-emulator-vpn.md` | owner=user 接收批次=CHG-20261029-hos-parity-signoff | open |
| BL-540-03 | 补子页面 UI 还原证据，主页面已完成（`checks/ui-parity/`） | `checks/final.txt`、`checks/ui-parity/main-screen.md` | owner=user 接收批次=CHG-20261029-hos-parity-signoff | open |
| BL-540-04 | 处置 60 条弱漏项 | `checks/high-level-review.json` | owner=ai 接收批次=CHG-20261029-hos-parity-weak-review | open |

## 流转检查

`check-flow.cjs` 退出非 0。命中的 P0 都与上表一致：

- 7 条 `upstream-missing`：四层的 `review-decisions.json` 与 `human-verdict` 缺失。
- 3 条 `upstream-missing`：UI 还原证据、报告、发布记录缺失。
- 1 条 `completion-incomplete`：本文件判 `incomplete`，批次不得合入。

没有其它 P0。人补齐后重跑。

## 交接

下一批次开工时回读本文件与 `flow.json` 的 `openItems`，把 `BL-540-01` 到
`BL-540-04` 与本批次改动面相交的条目写进 `handoff.prior`。四层审核页与两份
报告已在线，可直接审阅。
