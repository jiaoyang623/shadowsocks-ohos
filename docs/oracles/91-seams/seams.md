# Architecture-layer seam oracles

### O-SEAM-01 Profile and selection store
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-02、O-JOURNEY-03
- 强度：强
- 设计依据：架构 S1「Profile and selection store」
- 触发与前置条件：A page reads or writes a profile, the selected id, the order or a counter.
- 可观测点：The store file content, the returned list, the selected id and the profile counters.
- 期望：Every write is atomic. A read returns the last committed state. A profile switch persists the selected id. Counters settle once per session.
- 失败信息：Expected the last committed profile set; the page sees a partial write or a stale selection.
- 来源：架构 S1；需求 R-UA-02、R-UB-01、R-UE-01
- 上游：R-UA-02、R-UB-01、R-UE-01
- 待建测试：[集成] entry/src/test/Seams.test.ets::S1#profile_store_atomic
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-02 Native start and stop
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-03、O-JOURNEY-09
- 强度：强
- 设计依据：架构 S2「Native start and stop」
- 触发与前置条件：The model starts or stops a core instance with a config JSON, an optional tun fd and a stat address.
- 可观测点：The return code, `isRunning()`, `lastError()`, the status file and the traffic sample.
- 期望：A start with a valid config returns 0. A start with an invalid config returns a negative code and a message. A stop returns after the core releases the fd. A second start while running fails.
- 失败信息：Expected a clean start and stop; the core stays running or the UI shows no error.
- 来源：架构 S2；需求 R-UA-02、R-UC-01、R-UK-02
- 上游：R-UA-02、R-UC-01、R-UK-02
- 待建测试：[集成] entry/src/test/Seams.test.ets::S2#native_start_stop
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-03 Tun and stats
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-09
- 强度：强
- 设计依据：架构 S3「Tun and stats」
- 触发与前置条件：The VPN extension passes a tun fd to the core and hosts the stat endpoint.
- 可观测点：The tunnel carries a packet. The 16-byte sample appears at the stat address. The fd is closed once.
- 期望：The core owns a duplicate. The sample is two little-endian u64 values. A destroy closes the app copy without closing the core copy.
- 失败信息：Expected one owner per descriptor; a double close hits an unrelated descriptor.
- 来源：架构 S3；需求 R-UA-02、R-UK-02
- 上游：R-UA-02、R-UK-02
- 待建测试：[集成] entry/src/test/Seams.test.ets::S3#tun_fd_dup
- 状态：pending-test
- 不确定特征：UNCERTAIN-PLATFORM
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-04 Cross-process state
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-09
- 强度：强
- 设计依据：架构 S4「Cross-process state」
- 触发与前置条件：The UI process and the VPN extension exchange status, profile id and the traffic sample through files.
- 可观测点：The status file, the sample file and the settled counter values.
- 期望：The status file keeps the profile id through `stopped`. The sample is cleared after it is added. A kill leaves a readable status.
- 失败信息：Expected one settlement per session; the counter adds a sample twice or loses it.
- 来源：架构 S4；需求 R-UA-11、R-UF-03
- 上游：R-UA-11、R-UF-03
- 待建测试：[集成] entry/src/test/Seams.test.ets::S4#session_settlement
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-05 Remote lists
- 层级：接缝
- 父判据：O-JOURNEY-04、O-JOURNEY-05、O-JOURNEY-06
- 强度：强
- 设计依据：架构 S5「Remote lists」
- 触发与前置条件：The model fetches a subscription, an ACL list or a remote DNS answer.
- 可观测点：The parsed profile list, the cached ACL file and the DNS answer.
- 期望：A fetch failure keeps the previous data. A malformed body is rejected with an error. An ACL include is depth-limited. A remote DNS answer uses TCP.
- 失败信息：Expected the previous list to stay; a partial body replaces it.
- 来源：架构 S5；需求 R-UD-01、R-UE-02、R-UF-01
- 上游：R-UD-01、R-UE-02、R-UF-01
- 待建测试：[集成] entry/src/test/Seams.test.ets::S5#remote_failure_keeps_state
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-06 Platform surfaces
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-09、O-JOURNEY-11
- 强度：强
- 设计依据：架构 S6「Platform surfaces」
- 触发与前置条件：The model requests a notification permission, a continuous task, a picker result or a clipboard read.
- 可观测点：The permission result, the task state, the picked URI and the clipboard text.
- 期望：A denied permission is reported and does not crash the app. A refused continuous task is logged and the foreground listener stays. A cancelled picker returns an empty result.
- 失败信息：Expected a handled denial; the app crashes or blocks the page.
- 来源：架构 S6；需求 R-UA-25、R-UD-06、R-UE-10
- 上游：R-UA-25、R-UD-06、R-UE-10
- 待建测试：[集成] entry/src/test/Seams.test.ets::S6#permission_denied
- 状态：pending-test
- 不确定特征：UNCERTAIN-PLATFORM
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-07 VPN consent
- 层级：接缝
- 父判据：O-JOURNEY-01、O-JOURNEY-09
- 强度：强
- 设计依据：架构 S7「VPN consent」
- 触发与前置条件：The user starts the VPN for the first time or after a revoke.
- 可观测点：The consent result, the extension start and the UI phase.
- 期望：Allow starts the extension. Deny leaves the service stopped with a message. A revoke stops the tunnel and updates the UI.
- 失败信息：Expected a stopped service after deny; the UI claims connected.
- 来源：架构 S7；需求 R-UA-24、R-UK-05
- 上游：R-UA-24、R-UK-05
- 待建测试：[集成] entry/src/test/Seams.test.ets::S7#vpn_consent
- 状态：pending-test
- 不确定特征：UNCERTAIN-PLATFORM
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-SEAM-08 Plugin transport
- 层级：接缝
- 父判据：O-JOURNEY-03、O-JOURNEY-08
- 强度：强
- 设计依据：架构 S8「Plugin transport」
- 触发与前置条件：A profile has a plugin name and options.
- 可观测点：The loopback forwarder, the rewritten server entry and the start return code.
- 期望：A known plugin starts a loopback forwarder and rewrites the entry. An unknown plugin fails the start. UDP through a plugin times out with a clear error.
- 失败信息：Expected the forwarder to carry the stream; the core dials the real server directly.
- 来源：架构 S8；需求 R-UC-30、R-UH-01
- 上游：R-UC-30、R-UH-01
- 待建测试：[集成] entry/src/test/Seams.test.ets::S8#plugin_forwarder
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核
