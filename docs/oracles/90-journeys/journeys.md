# Requirements-layer journey oracles

Each journey follows one unit flow from the requirements model.

### O-JOURNEY-01 Main shell navigation drawer connect control stats bar
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UA-01、R-UA-16、R-UA-30；需求模型 flow f_u01
- 触发与前置条件：The phone user opens the Main shell, navigation drawer, connect control, stats bar screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Main shell, navigation drawer, connect control, stats bar; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UA-01、R-UA-16、R-UA-30
- 上游：R-UA-01、R-UA-16、R-UA-30
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U01Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-02 Profile list row layout search reorder delete share popup
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UB-01、R-UB-26、R-UB-51；需求模型 flow f_u02
- 触发与前置条件：The phone user opens the Profile list, row layout, search, reorder, delete, share popup screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Profile list, row layout, search, reorder, delete, share popup; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UB-01、R-UB-26、R-UB-51
- 上游：R-UB-01、R-UB-26、R-UB-51
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U02Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-03 Profile editor and UDP fallback
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UC-01、R-UC-21、R-UC-41；需求模型 flow f_u03
- 触发与前置条件：The phone user opens the Profile editor and UDP fallback screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Profile editor and UDP fallback; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UC-01、R-UC-21、R-UC-41
- 上游：R-UC-01、R-UC-21、R-UC-41
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U03Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-04 Import and export flows
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UD-01、R-UD-29、R-UD-56；需求模型 flow f_u04
- 触发与前置条件：The phone user opens the Import and export flows screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Import and export flows; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UD-01、R-UD-29、R-UD-56
- 上游：R-UD-01、R-UD-29、R-UD-56
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U04Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-05 Subscriptions URL list add edit remove dialog refresh service and profile merge
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UE-01、R-UE-15、R-UE-29；需求模型 flow f_u05
- 触发与前置条件：The phone user opens the Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UE-01、R-UE-15、R-UE-29
- 上游：R-UE-01、R-UE-15、R-UE-29
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U05Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-06 Custom rules and ACL
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UF-01、R-UF-18、R-UF-35；需求模型 flow f_u06
- 触发与前置条件：The phone user opens the Custom rules and ACL screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Custom rules and ACL; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UF-01、R-UF-18、R-UF-35
- 上游：R-UF-01、R-UF-18、R-UF-35
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U06Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-07 Per app proxy Apps VPN mode
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UG-01、R-UG-18、R-UG-36；需求模型 flow f_u07
- 触发与前置条件：The phone user opens the Per-app proxy, Apps VPN mode screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Per-app proxy, Apps VPN mode; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UG-01、R-UG-18、R-UG-36
- 上游：R-UG-01、R-UG-18、R-UG-36
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U07Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-08 Plugin picker and plugin options
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UH-01、R-UH-16、R-UH-30；需求模型 flow f_u08
- 触发与前置条件：The phone user opens the Plugin picker and plugin options screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Plugin picker and plugin options; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UH-01、R-UH-16、R-UH-30
- 上游：R-UH-01、R-UH-16、R-UH-30
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U08Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-09 Global settings
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UI-01、R-UI-18、R-UI-35；需求模型 flow f_u09
- 触发与前置条件：The phone user opens the Global settings screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for Global settings; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UI-01、R-UI-18、R-UI-35
- 上游：R-UI-01、R-UI-18、R-UI-35
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U09Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-10 QR scanner and About
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UJ-01、R-UJ-15、R-UJ-28；需求模型 flow f_u10
- 触发与前置条件：The phone user opens the QR scanner and About screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for QR scanner and About; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UJ-01、R-UJ-15、R-UJ-28
- 上游：R-UJ-01、R-UJ-15、R-UJ-28
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U10Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

### O-JOURNEY-11 System surfaces notification tile shortcuts boot Tasker
- 层级：旅程
- 父判据：无（旅程层没有父判据）
- 强度：强
- 设计依据：需求 R-UK-01、R-UK-22、R-UK-43；需求模型 flow f_u11
- 触发与前置条件：The phone user opens the System surfaces: notification, tile, shortcuts, boot, Tasker screen on HarmonyOS with at least one profile.
- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.
- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.
- 失败信息：Expected the Android behavior for System surfaces: notification, tile, shortcuts, boot, Tasker; the HarmonyOS screen differs or the operation fails silently.
- 来源：需求 R-UK-01、R-UK-22、R-UK-43
- 上游：R-UK-01、R-UK-22、R-UK-43
- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::U11Journey#flow
- 状态：pending-test
- 不确定特征：NOT-EVALUATED
- 归属：owner=red 接收批次=CHG-20261028-hos-parity
- 复核：待复核

