# HLD-layer unit oracles

Each oracle covers one unit behavior cluster. The anchors point to planned unit tests.

### O-UNIT-01 Main shell, navigation drawer, connect control, stats bar
- 层级：单点
- 父判据：O-SEAM-02、O-SEAM-03
- 强度：强
- 设计依据：HLD C-02, C-03, C-04；LLD U01
- 触发与前置条件：The user operates the Main shell, navigation drawer, connect control, stats bar controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U01 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Main shell, navigation drawer, connect control, stats bar; the HarmonyOS screen or store differs.
- 来源：HLD C-02, C-03, C-04；需求 R-UA-01、R-UA-16、R-UA-30
- 上游：R-UA-01、R-UA-16、R-UA-30
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U01#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-02 Profile list, row layout, search, reorder, delete, share popup
- 层级：单点
- 父判据：O-SEAM-01
- 强度：强
- 设计依据：HLD C-01；LLD U02
- 触发与前置条件：The user operates the Profile list, row layout, search, reorder, delete, share popup controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U02 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Profile list, row layout, search, reorder, delete, share popup; the HarmonyOS screen or store differs.
- 来源：HLD C-01；需求 R-UB-01、R-UB-26、R-UB-51
- 上游：R-UB-01、R-UB-26、R-UB-51
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U02#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-03 Profile editor and UDP fallback
- 层级：单点
- 父判据：O-SEAM-01、O-SEAM-02
- 强度：强
- 设计依据：HLD C-01, C-02；LLD U03
- 触发与前置条件：The user operates the Profile editor and UDP fallback controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U03 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Profile editor and UDP fallback; the HarmonyOS screen or store differs.
- 来源：HLD C-01, C-02；需求 R-UC-01、R-UC-21、R-UC-41
- 上游：R-UC-01、R-UC-21、R-UC-41
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U03#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-04 Import and export flows
- 层级：单点
- 父判据：O-SEAM-01
- 强度：强
- 设计依据：HLD C-01；LLD U04
- 触发与前置条件：The user operates the Import and export flows controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U04 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Import and export flows; the HarmonyOS screen or store differs.
- 来源：HLD C-01；需求 R-UD-01、R-UD-29、R-UD-56
- 上游：R-UD-01、R-UD-29、R-UD-56
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U04#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-05 Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge
- 层级：单点
- 父判据：O-SEAM-05
- 强度：强
- 设计依据：HLD C-05；LLD U05
- 触发与前置条件：The user operates the Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U05 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge; the HarmonyOS screen or store differs.
- 来源：HLD C-05；需求 R-UE-01、R-UE-15、R-UE-29
- 上游：R-UE-01、R-UE-15、R-UE-29
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U05#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-06 Custom rules and ACL
- 层级：单点
- 父判据：O-SEAM-05
- 强度：强
- 设计依据：HLD C-06；LLD U06
- 触发与前置条件：The user operates the Custom rules and ACL controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U06 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Custom rules and ACL; the HarmonyOS screen or store differs.
- 来源：HLD C-06；需求 R-UF-01、R-UF-18、R-UF-35
- 上游：R-UF-01、R-UF-18、R-UF-35
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U06#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-07 Per-app proxy, Apps VPN mode
- 层级：单点
- 父判据：O-SEAM-06
- 强度：强
- 设计依据：HLD C-08；LLD U07
- 触发与前置条件：The user operates the Per-app proxy, Apps VPN mode controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U07 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Per-app proxy, Apps VPN mode; the HarmonyOS screen or store differs.
- 来源：HLD C-08；需求 R-UG-01、R-UG-18、R-UG-36
- 上游：R-UG-01、R-UG-18、R-UG-36
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U07#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-08 Plugin picker and plugin options
- 层级：单点
- 父判据：O-SEAM-08
- 强度：强
- 设计依据：HLD C-02；LLD U08
- 触发与前置条件：The user operates the Plugin picker and plugin options controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U08 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Plugin picker and plugin options; the HarmonyOS screen or store differs.
- 来源：HLD C-02；需求 R-UH-01、R-UH-16、R-UH-30
- 上游：R-UH-01、R-UH-16、R-UH-30
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U08#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-09 Global settings
- 层级：单点
- 父判据：O-SEAM-06
- 强度：强
- 设计依据：HLD C-01；LLD U09
- 触发与前置条件：The user operates the Global settings controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U09 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for Global settings; the HarmonyOS screen or store differs.
- 来源：HLD C-01；需求 R-UI-01、R-UI-18、R-UI-35
- 上游：R-UI-01、R-UI-18、R-UI-35
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U09#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-10 QR scanner and About
- 层级：单点
- 父判据：O-SEAM-06
- 强度：强
- 设计依据：HLD C-01；LLD U10
- 触发与前置条件：The user operates the QR scanner and About controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U10 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for QR scanner and About; the HarmonyOS screen or store differs.
- 来源：HLD C-01；需求 R-UJ-01、R-UJ-15、R-UJ-28
- 上游：R-UJ-01、R-UJ-15、R-UJ-28
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U10#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-UNIT-11 System surfaces: notification, tile, shortcuts, boot, Tasker
- 层级：单点
- 父判据：O-SEAM-03、O-SEAM-06
- 强度：强
- 设计依据：HLD C-07；LLD U11
- 触发与前置条件：The user operates the System surfaces: notification, tile, shortcuts, boot, Tasker controls on HarmonyOS.
- 可观测点：The control state, the screen text, the persisted store and the service state.
- 期望：Every rule in U11 behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.
- 失败信息：Expected the Android behavior for System surfaces: notification, tile, shortcuts, boot, Tasker; the HarmonyOS screen or store differs.
- 来源：HLD C-07；需求 R-UK-01、R-UK-22、R-UK-43
- 上游：R-UK-01、R-UK-22、R-UK-43
- 待建测试：[单元] entry/src/test/UnitParity.test.ets::U11#behaviors
- 状态：pending-test
- 不确定特征：none
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

