# E2E case index

The baseline pairs Android shadowsocks-android v5.3.5-nightly (commit ae28fd9) with HarmonyOS 5.3.5 (commit e123804) and has 348 E2E cases in 11 units.

## Cases per unit

| Unit | Title | Cases | Implemented | Partial | Missing | Android only | Doc link |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U01 | Main shell, navigation drawer, connect control, stats bar | 39 | 29 | 6 | 0 | 4 | [U01](U01.md) |
| U02 | Profile list, row layout, search, reorder, delete, share popup | 46 | 39 | 1 | 0 | 6 | [U02](U02.md) |
| U03 | Profile editor and UDP fallback | 31 | 23 | 5 | 0 | 3 | [U03](U03.md) |
| U04 | Import and export flows | 35 | 26 | 8 | 0 | 1 | [U04](U04.md) |
| U05 | Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge | 24 | 21 | 1 | 0 | 2 | [U05](U05.md) |
| U06 | Custom rules and ACL | 35 | 29 | 3 | 0 | 3 | [U06](U06.md) |
| U07 | Per-app proxy, Apps VPN mode | 28 | 21 | 2 | 0 | 5 | [U07](U07.md) |
| U08 | Plugin picker and plugin options | 30 | 10 | 6 | 0 | 14 | [U08](U08.md) |
| U09 | Global settings | 26 | 9 | 12 | 0 | 5 | [U09](U09.md) |
| U10 | QR scanner and About | 25 | 14 | 4 | 0 | 7 | [U10](U10.md) |
| U11 | System surfaces: notification, tile, shortcuts, boot, Tasker | 29 | 3 | 4 | 0 | 22 | [U11](U11.md) |
| Total | 11 units | 348 | 224 | 52 | 0 | 72 | |

Counts come from the unit JSON files in `machine/`.

## Coverage of the HarmonyOS port

Missing cases are what the port must add. Partial cases are what the port must finish. Android-only cases cannot be ported as they are. Implemented cases are the current baseline.

| Parity | Case | Title | Unit |
| --- | --- | --- | --- |
| partial | TC-U01-12 | Open the drawer and see the six entries | U01 |
| partial | TC-U01-13 | Select Settings from the drawer | U01 |
| partial | TC-U01-16 | A service mode change rebinds the connection | U01 |
| partial | TC-U01-22 | Ctrl+T runs the connection test and replaces a running one | U01 |
| partial | TC-U01-32 | An invalid profile stops the start with the exception message | U01 |
| partial | TC-U01-38 | Recreate the activity and restore the drawer item and open state | U01 |
| partial | TC-U02-44 | The subscription icon opens the profile editor | U02 |
| partial | TC-U03-02 | A manually added profile starts from the code defaults and copies the current profile's feature settings | U03 |
| partial | TC-U03-13 | The Encrypt Method menu stores the chosen method value | U03 |
| partial | TC-U03-15 | Selecting a plugin enables Configure… and loads its options | U03 |
| partial | TC-U03-25 | An uninstalled plugin id shows Unknown plugin and disables Configure… | U03 |
| partial | TC-U03-29 | The password dialog stores a new password on OK, keeps it on Cancel, and shows one bullet per character | U03 |
| partial | TC-U04-05 | Replace from file keeps counters for the same server | U04 |
| partial | TC-U04-09 | Imported profiles inherit the current feature settings | U04 |
| partial | TC-U04-12 | Export all profiles to the clipboard writes URL lines | U04 |
| partial | TC-U04-18 | The share popup exports one profile to the clipboard | U04 |
| partial | TC-U04-19 | A QR encoding failure reports and closes | U04 |
| partial | TC-U04-29 | A refused clipboard write fails the row export | U04 |
| partial | TC-U04-34 | Only an ss:// link opens the import screen | U04 |
| partial | TC-U04-35 | A link import copies the current feature settings | U04 |
| partial | TC-U05-15 | A re-listed Obsolete profile takes the new transport fields | U05 |
| partial | TC-U06-19 | Connect with the custom-rules route | U06 |
| partial | TC-U06-20 | Custom rules default is forced to bypass | U06 |
| partial | TC-U06-24 | Preset ACL files are deployed for the core | U06 |
| partial | TC-U07-04 | The spinner gives way to rows with icon, label, and package with UID | U07 |
| partial | TC-U07-07 | Search matches labels, packages, and UIDs, and clearing restores every row | U07 |
| partial | TC-U08-01 | The Plugin row shows the selected plugin label and icon | U08 |
| partial | TC-U08-02 | A plugin id that resolves to no installed plugin reads Unknown plugin | U08 |
| partial | TC-U08-03 | The picker moves the current plugin first, and dismissing changes nothing | U08 |
| partial | TC-U08-04 | Picking Disabled clears the plugin and disables Configure… | U08 |
| partial | TC-U08-09 | The built-in editor stores a valid options string on OK | U08 |
| partial | TC-U08-22 | A plugin profile runs TCP only, and a UDP fallback profile with a plugin is refused | U08 |
| partial | TC-U09-01 | Open Settings from the navigation drawer | U09 |
| partial | TC-U09-02 | Advanced expands the hidden rows and the next visit collapses them | U09 |
| partial | TC-U09-03 | The service mode row shows the three entries and marks the current one | U09 |
| partial | TC-U09-04 | Choosing Proxy only stores the mode and disables the transproxy port | U09 |
| partial | TC-U09-06 | A service mode change rebinds the main screen to the new service class | U09 |
| partial | TC-U09-16 | Auto Connect turns the boot receiver on and off | U09 |
| partial | TC-U09-17 | Auto Connect starts off on a fresh install because the receiver ships disabled | U09 |
| partial | TC-U09-20 | Leaving Settings clears the state listener and returning re-subscribes | U09 |
| partial | TC-U09-21 | Starting the service sets the boot receiver from the stored Auto Connect value | U09 |
| partial | TC-U09-22 | Stopping without restart disables the boot receiver and keeps isAutoConnect | U09 |
| partial | TC-U09-24 | Each service mode entry stores its own value under serviceMode | U09 |
| partial | TC-U09-25 | The SOCKS5 port is the local listener in proxy and VPN modes | U09 |
| partial | TC-U10-03 | Scan a code that holds no ss:// URL | U10 |
| partial | TC-U10-12 | The scanner closes at most once | U10 |
| partial | TC-U10-21 | A scan copies the feature settings of the current profile | U10 |
| partial | TC-U10-23 | The About body is selectable and hides when empty | U10 |
| partial | TC-U11-01 | The ongoing notification appears when the service starts | U11 |
| partial | TC-U11-02 | The notification traffic line updates while the screen is on | U11 |
| partial | TC-U11-06 | A start without a profile posts an empty notification then stops | U11 |
| partial | TC-U11-27 | Screen events during Connecting do not change the traffic subscription | U11 |
| android-only | TC-U01-04 | The service button is disabled until a stopped service is bound | U01 |
| android-only | TC-U01-17 | The service process dies and the UI recovers | U01 |
| android-only | TC-U01-27 | A guarded process exits and stops the service without a tap | U01 |
| android-only | TC-U01-34 | The drawer closes by a swipe | U01 |
| android-only | TC-U02-27 | A missing file manager reports the file manager message | U02 |
| android-only | TC-U02-31 | The edit icon crashes on a profile deleted elsewhere | U02 |
| android-only | TC-U02-32 | A committed delete leaves the selected profile id stale | U02 |
| android-only | TC-U02-33 | A drag is refused while the service is Idle or Stopping | U02 |
| android-only | TC-U02-34 | A row tap does nothing while the service is Idle | U02 |
| android-only | TC-U02-43 | A search during a pending removal brings the profile back | U02 |
| android-only | TC-U03-17 | An untrusted plugin shows the warning snackbar | U03 |
| android-only | TC-U03-26 | The ? button opens the plugin help and shows its message | U03 |
| android-only | TC-U03-30 | Uninstalling the selected plugin disables Configure… and shows Unknown plugin | U03 |
| android-only | TC-U04-20 | No file manager installed | U04 |
| android-only | TC-U05-08 | Refresh runs while idle and reports progress | U05 |
| android-only | TC-U05-10 | A duplicate start request stops the service and the active run | U05 |
| android-only | TC-U06-21 | A failing import URL aborts the connect | U06 |
| android-only | TC-U06-22 | A malformed IMPORT_URL line fails the start | U06 |
| android-only | TC-U06-23 | A preset ACL refresh retries and then fails | U06 |
| android-only | TC-U07-08 | INTERNET apps, retained packages, and android appear, never the client | U07 |
| android-only | TC-U07-09 | Installing or removing a package reloads the list | U07 |
| android-only | TC-U07-24 | A failed profile update in Apply Settings throws after the earlier writes | U07 |
| android-only | TC-U07-26 | Import reports failure when the platform returns no clipboard text | U07 |
| android-only | TC-U07-27 | A VPN start fails with the reboot message when establish returns null | U07 |
| android-only | TC-U08-06 | An untrusted plugin shows the warning snackbar | U08 |
| android-only | TC-U08-07 | Long-pressing a plugin row opens its app info screen | U08 |
| android-only | TC-U08-08 | The unlock warning shows for a non-direct-boot plugin with Auto Connect on | U08 |
| android-only | TC-U08-12 | The plugin's configuration activity returns new options, and a second run is cancelled | U08 |
| android-only | TC-U08-13 | The plugin's activity can request the fallback editor | U08 |
| android-only | TC-U08-14 | The ? button opens plugin help and shows the returned message | U08 |
| android-only | TC-U08-17 | Installing or removing a plugin package refreshes the list and the summary | U08 |
| android-only | TC-U08-21 | Two providers with the same plugin id show a conflict toast and fail the list build | U08 |
| android-only | TC-U08-24 | A plugin without ACTION_HELP shows no ? button | U08 |
| android-only | TC-U08-25 | A canceled or crashed help activity shows no alert | U08 |
| android-only | TC-U08-26 | A configuration activity that crashes is treated as canceled | U08 |
| android-only | TC-U08-27 | RESULT_OK without EXTRA_OPTIONS clears the stored options | U08 |
| android-only | TC-U08-28 | A provider without the plugin id metadata breaks discovery | U08 |
| android-only | TC-U08-29 | A help result without a message shows an empty ? alert | U08 |
| android-only | TC-U09-05 | Cycle every service mode entry and let the transproxy port follow | U09 |
| android-only | TC-U09-18 | API 23 has no lock-screen row | U09 |
| android-only | TC-U09-19 | The lock-screen switch on without direct boot support stores true but protects nothing | U09 |
| android-only | TC-U09-23 | The lock-screen switch deletes the device-protected copy without direct boot support | U09 |
| android-only | TC-U09-26 | Transproxy listens on the Transproxy port and forwards to the SOCKS5 port | U09 |
| android-only | TC-U10-04 | Deny the camera permission and get the image picker | U10 |
| android-only | TC-U10-05 | Camera binding fails and the image picker opens | U10 |
| android-only | TC-U10-06 | A device without a back camera uses the front camera | U10 |
| android-only | TC-U10-10 | Cancel the fallback image picker after a denial | U10 |
| android-only | TC-U10-13 | Open the scanner from the Scan QR code launcher shortcut | U10 |
| android-only | TC-U10-18 | Open the OSS licences from the Other licenses link | U10 |
| android-only | TC-U10-24 | The About toolbar icon opens the navigation drawer | U10 |
| android-only | TC-U11-07 | The tile label shows the profile name only while the device is unlocked | U11 |
| android-only | TC-U11-08 | A tile tap while connecting cancels the connection and stops | U11 |
| android-only | TC-U11-09 | A tile tap while connected stops the service | U11 |
| android-only | TC-U11-10 | A tile tap while stopped starts the service | U11 |
| android-only | TC-U11-11 | A tile tap before the service binds is replayed | U11 |
| android-only | TC-U11-12 | A tile tap on a locked device unlocks first | U11 |
| android-only | TC-U11-13 | The Toggle shortcut stops a running service | U11 |
| android-only | TC-U11-14 | A shortcut creation request returns the Toggle shortcut | U11 |
| android-only | TC-U11-15 | The Scan QR code shortcut opens the scanner | U11 |
| android-only | TC-U11-16 | Auto Connect starts the service after boot | U11 |
| android-only | TC-U11-17 | A boot broadcast with Auto Connect off does not start the service | U11 |
| android-only | TC-U11-18 | Selecting a Tasker profile row returns the setting | U11 |
| android-only | TC-U11-19 | A fired Tasker setting switches profile and restarts the service | U11 |
| android-only | TC-U11-20 | A fired Tasker setting with the switch off stops the service | U11 |
| android-only | TC-U11-21 | Each service mode has its own notification channel | U11 |
| android-only | TC-U11-22 | The tile service requires the tile permission and runs direct boot aware | U11 |
| android-only | TC-U11-23 | A tile long press opens the main screen | U11 |
| android-only | TC-U11-24 | The launcher menu offers the two static shortcuts | U11 |
| android-only | TC-U11-25 | A locked device starts the service from the device-protected profile | U11 |
| android-only | TC-U11-26 | Shutdown counters survive in the device profile and flush after unlock | U11 |
| android-only | TC-U11-28 | Each boot action starts only in its own direct boot mode | U11 |
| android-only | TC-U11-29 | The Tasker editor lists the current profile first, then the active profiles | U11 |
| implemented | TC-U01-01 | Connect with the VPN consent granted | U01 |
| implemented | TC-U01-02 | Deny the VPN consent | U01 |
| implemented | TC-U01-03 | Start with no selected profile | U01 |
| implemented | TC-U01-05 | Disconnect from Connected | U01 |
| implemented | TC-U01-06 | The progress ring appears during a slow connect | U01 |
| implemented | TC-U01-07 | A failed start reports the service message | U01 |
| implemented | TC-U01-08 | The stats bar is hidden while not connected | U01 |
| implemented | TC-U01-09 | Tap the stats bar to test the connection | U01 |
| implemented | TC-U01-10 | The connection test fails with an HTTP error code | U01 |
| implemented | TC-U01-11 | Traffic counters update and reset | U01 |
| implemented | TC-U01-14 | Back press closes the drawer first | U01 |
| implemented | TC-U01-15 | FAQ opens the FAQ page in a custom tab | U01 |
| implemented | TC-U01-18 | Ctrl+G toggles the service | U01 |
| implemented | TC-U01-19 | Service errors appear as a snackbar above the service button | U01 |
| implemented | TC-U01-20 | The stats bar hides when the list scrolls up | U01 |
| implemented | TC-U01-21 | Open the app while the service is already running | U01 |
| implemented | TC-U01-23 | The connection test fails with a network error | U01 |
| implemented | TC-U01-24 | Stop the service while it is connecting | U01 |
| implemented | TC-U01-25 | The drawer opens by an edge swipe and closes by the scrim | U01 |
| implemented | TC-U01-26 | FAQ with no handler shows the URL | U01 |
| implemented | TC-U01-28 | Stopping during a test clears the test status | U01 |
| implemented | TC-U01-29 | Stopping after a successful test clears the result | U01 |
| implemented | TC-U01-30 | Stopping after a failed test clears the error | U01 |
| implemented | TC-U01-31 | Select About and replace the fragment in the shared holder | U01 |
| implemented | TC-U01-33 | A second stop request while the service is Stopping is ignored | U01 |
| implemented | TC-U01-35 | Connected before the delayed show sets the ring to full | U01 |
| implemented | TC-U01-36 | Stopping during the fill hides the determinate ring | U01 |
| implemented | TC-U01-37 | Start another test after a successful test | U01 |
| implemented | TC-U01-39 | Start the service without a consent dialog when consent is granted | U01 |
| implemented | TC-U02-01 | Selecting a profile while stopped marks it and persists the choice | U02 |
| implemented | TC-U02-02 | Selecting another profile while connected restarts the tunnel with it | U02 |
| implemented | TC-U02-03 | A row tap does nothing while the service is stopping | U02 |
| implemented | TC-U02-04 | Search filters by name and host, ignoring case | U02 |
| implemented | TC-U02-05 | A query with no match shows an empty list and keeps the selection | U02 |
| implemented | TC-U02-06 | Clearing the query restores every profile in its stored order | U02 |
| implemented | TC-U02-07 | Search is available while the list holds one profile | U02 |
| implemented | TC-U02-08 | Dragging a row down stores the new order | U02 |
| implemented | TC-U02-09 | The first row crossover of a drag commits a pending swipe deletion | U02 |
| implemented | TC-U02-10 | Swiping a row toward the start edge removes it and offers Undo | U02 |
| implemented | TC-U02-11 | Undo restores the swiped row at its old position | U02 |
| implemented | TC-U02-12 | Dismissing the undo snackbar deletes the profile | U02 |
| implemented | TC-U02-13 | A second swipe accumulates in the same undo offer | U02 |
| implemented | TC-U02-14 | The row share icon opens a popup with QR code and clipboard export | U02 |
| implemented | TC-U02-15 | The QR code menu item shows the profile as a 264dp QR image | U02 |
| implemented | TC-U02-16 | Import from Clipboard adds parsed profiles | U02 |
| implemented | TC-U02-17 | Import from Clipboard fails when no URL parses | U02 |
| implemented | TC-U02-18 | Manual Settings opens an editor for a profile seeded from the current profile | U02 |
| implemented | TC-U02-19 | Export to Clipboard copies every active profile as ss:// links | U02 |
| implemented | TC-U02-20 | The edit icon opens the profile editor | U02 |
| implemented | TC-U02-21 | Import from file appends the parsed profiles | U02 |
| implemented | TC-U02-22 | Replace from file clears the old profiles when the first profile is created | U02 |
| implemented | TC-U02-23 | Replace from a file with no profile keeps every stored profile | U02 |
| implemented | TC-U02-24 | Export to file writes the profile JSON array | U02 |
| implemented | TC-U02-25 | Export to file writes nothing when the picker returns no document or the profiles cannot be read | U02 |
| implemented | TC-U02-26 | An unreadable or invalid import file reports its error | U02 |
| implemented | TC-U02-28 | A QR encoding failure dismisses the dialog and reports the error | U02 |
| implemented | TC-U02-29 | A refused clipboard write shows the export failure message | U02 |
| implemented | TC-U02-30 | A failed profile update aborts the drop | U02 |
| implemented | TC-U02-35 | The edit and subscription icons are disabled on the active profile while connected | U02 |
| implemented | TC-U02-36 | The swipe is refused on the active profile while connected | U02 |
| implemented | TC-U02-37 | The row title falls back to the host and port | U02 |
| implemented | TC-U02-38 | The list shows active profiles in userOrder | U02 |
| implemented | TC-U02-39 | An empty database gets one default profile | U02 |
| implemented | TC-U02-40 | The secondary line is hidden when its text is empty | U02 |
| implemented | TC-U02-41 | The undo snackbar reports a count for several removals | U02 |
| implemented | TC-U02-42 | A UDP fallback profile is locked with its selected profile | U02 |
| implemented | TC-U02-45 | A long-press without a row crossover keeps the pending deletion | U02 |
| implemented | TC-U02-46 | An unrelated result snackbar commits the pending deletion | U02 |
| implemented | TC-U03-01 | Apply saves the edited fields into the profile row and closes the editor | U03 |
| implemented | TC-U03-03 | Back with a dirty draft and Yes saves before leaving | U03 |
| implemented | TC-U03-04 | Back with a dirty draft and No discards the draft | U03 |
| implemented | TC-U03-05 | Cancel in the unsaved-changes dialog keeps the editor open | U03 |
| implemented | TC-U03-06 | Back with a clean draft closes the editor with no dialog | U03 |
| implemented | TC-U03-07 | The toolbar close icon discards a dirty draft without asking | U03 |
| implemented | TC-U03-08 | Remove asks for confirmation and Yes deletes the profile | U03 |
| implemented | TC-U03-09 | A subscription-active profile locks the transport rows | U03 |
| implemented | TC-U03-10 | IPv6 Route is disabled when the service mode is not VPN | U03 |
| implemented | TC-U03-11 | Apps VPN mode opens the app list and marks the draft dirty only when it turns on | U03 |
| implemented | TC-U03-12 | The Remote Port dialog filters to five digits and the saved port is normalized | U03 |
| implemented | TC-U03-14 | The Route menu stores the chosen route token | U03 |
| implemented | TC-U03-16 | Plugin options with a control character are rejected with a snackbar | U03 |
| implemented | TC-U03-18 | The fallback chooser omits the edited profile and every plugin profile | U03 |
| implemented | TC-U03-19 | Choosing a fallback profile stores its id and the summary follows | U03 |
| implemented | TC-U03-20 | A launch with a stale profile id closes the editor before it draws | U03 |
| implemented | TC-U03-21 | Apply trims the spaces around the host | U03 |
| implemented | TC-U03-22 | The editor toolbar shows Profile config | U03 |
| implemented | TC-U03-23 | The fallback chooser closes when no editing id is stored | U03 |
| implemented | TC-U03-24 | Closing the fallback chooser stores nothing | U03 |
| implemented | TC-U03-27 | Remove and No keeps the profile | U03 |
| implemented | TC-U03-28 | Dismissing the unsaved-changes dialog keeps the editor open | U03 |
| implemented | TC-U03-31 | The profile list serializes the tapped profile into the private draft store before it starts the editor | U03 |
| implemented | TC-U04-01 | Clipboard import adds a profile | U04 |
| implemented | TC-U04-02 | Clipboard import with no valid URL fails | U04 |
| implemented | TC-U04-03 | File import appends every profile in a JSON file | U04 |
| implemented | TC-U04-04 | Cancelling the file picker changes nothing | U04 |
| implemented | TC-U04-06 | Replace from a file without profiles leaves the list | U04 |
| implemented | TC-U04-07 | Nested JSON import finds every profile | U04 |
| implemented | TC-U04-08 | A JSON entry with a bad port is skipped | U04 |
| implemented | TC-U04-10 | A udp_fallback object becomes a second profile | U04 |
| implemented | TC-U04-11 | proxy_apps settings import into the profile | U04 |
| implemented | TC-U04-13 | Export to file writes the Android JSON shape | U04 |
| implemented | TC-U04-14 | Manual Settings seeds a profile and opens the editor | U04 |
| implemented | TC-U04-15 | An ss:// link asks before adding its profile | U04 |
| implemented | TC-U04-16 | An ss:// link with no valid data is rejected | U04 |
| implemented | TC-U04-17 | The share popup shows the profile QR code | U04 |
| implemented | TC-U04-21 | The exported ss:// URL has the Android form | U04 |
| implemented | TC-U04-22 | No on the link dialog discards the profile | U04 |
| implemented | TC-U04-23 | A malformed JSON document reports the parse error | U04 |
| implemented | TC-U04-24 | One bad document does not discard the good one | U04 |
| implemented | TC-U04-25 | An empty clipboard fails the import | U04 |
| implemented | TC-U04-26 | A clipboard with a bad URL keeps the valid one | U04 |
| implemented | TC-U04-27 | A file with no profile leaves the list unchanged | U04 |
| implemented | TC-U04-28 | A refused clipboard write fails the aggregate export | U04 |
| implemented | TC-U04-30 | Cancelling the save picker writes no file | U04 |
| implemented | TC-U04-31 | A null profile list writes no export file | U04 |
| implemented | TC-U04-32 | A write failure reports the exception message | U04 |
| implemented | TC-U04-33 | Dismissing the link dialog discards the profile | U04 |
| implemented | TC-U05-01 | Add a valid subscription URL | U05 |
| implemented | TC-U05-02 | An empty or malformed field keeps OK disabled | U05 |
| implemented | TC-U05-03 | A cleartext http URL warns but is accepted | U05 |
| implemented | TC-U05-04 | Any URL scheme with a handler passes validation | U05 |
| implemented | TC-U05-05 | Edit a stored URL from its row | U05 |
| implemented | TC-U05-06 | Remove from the dialog and restore with Undo | U05 |
| implemented | TC-U05-07 | Swipe a row to delete it | U05 |
| implemented | TC-U05-09 | The refresh menu item follows the idle state | U05 |
| implemented | TC-U05-11 | Stop cancels a running refresh | U05 |
| implemented | TC-U05-12 | One failed download does not stop the others | U05 |
| implemented | TC-U05-13 | A body that raises a JSON parse error is skipped | U05 |
| implemented | TC-U05-14 | A profile missing from the new body becomes Obsolete | U05 |
| implemented | TC-U05-16 | Stored duplicate name-plus-address profiles are removed | U05 |
| implemented | TC-U05-17 | A user-configured profile is never touched | U05 |
| implemented | TC-U05-18 | A new subscription profile starts from the current profile's feature settings | U05 |
| implemented | TC-U05-19 | Deleting a subscription URL keeps the profiles it created | U05 |
| implemented | TC-U05-20 | The URL list survives a restart and drops invalid lines | U05 |
| implemented | TC-U05-21 | Rows sort by host, port, then URL.file | U05 |
| implemented | TC-U05-22 | A refresh with no stored URL still obsoletes every subscription profile | U05 |
| implemented | TC-U05-23 | A body of bare literals produces no toast and no profile | U05 |
| implemented | TC-U05-24 | Every download fails and every subscription profile becomes Obsolete | U05 |
| implemented | TC-U06-01 | Open Custom rules from the drawer | U06 |
| implemented | TC-U06-02 | Add a subnet through Manual Settings | U06 |
| implemented | TC-U06-03 | Generic template rejects an invalid pattern and recovers | U06 |
| implemented | TC-U06-04 | Domain template stores an anchored pattern | U06 |
| implemented | TC-U06-05 | URL template warns on cleartext http | U06 |
| implemented | TC-U06-06 | Edit an existing rule and save it | U06 |
| implemented | TC-U06-07 | Remove a rule from the edit dialog | U06 |
| implemented | TC-U06-08 | Import rules from the clipboard | U06 |
| implemented | TC-U06-09 | Import fails on a clipboard with no rule | U06 |
| implemented | TC-U06-10 | Import the bundled GFW list in one tap | U06 |
| implemented | TC-U06-11 | Swipe a row away and undo it | U06 |
| implemented | TC-U06-12 | Swipe does nothing while a selection is active | U06 |
| implemented | TC-U06-13 | Swipe is blocked while the custom-rules route runs | U06 |
| implemented | TC-U06-14 | Long press starts the selection and tap toggles | U06 |
| implemented | TC-U06-15 | Select all and copy the rules as ACL | U06 |
| implemented | TC-U06-16 | Cut removes the selection after copying | U06 |
| implemented | TC-U06-17 | Back ends the action mode and keeps the rules | U06 |
| implemented | TC-U06-18 | Remove selected rules and read the count | U06 |
| implemented | TC-U06-25 | An empty Generic rule is stored as an empty row | U06 |
| implemented | TC-U06-26 | Cancel and dismissal leave the list unchanged | U06 |
| implemented | TC-U06-27 | Manual Settings shows no Remove button | U06 |
| implemented | TC-U06-28 | Dismissing the undo snackbar keeps the removal | U06 |
| implemented | TC-U06-29 | Leaving the screen flushes the snackbar and ends the action mode | U06 |
| implemented | TC-U06-30 | A second removal joins the undo snackbar | U06 |
| implemented | TC-U06-31 | Cut removes the selection when the clipboard write fails | U06 |
| implemented | TC-U06-32 | A proxy_all clipboard drops its subnets | U06 |
| implemented | TC-U06-33 | Changing the profile route opens the swipe gate | U06 |
| implemented | TC-U06-34 | A connect with no user file still writes the served ACL | U06 |
| implemented | TC-U06-35 | An edit after a connect leaves the served ACL stale | U06 |
| implemented | TC-U07-01 | Opening Apps VPN mode turns it on for the edited profile | U07 |
| implemented | TC-U07-02 | On and Bypass switch modes without losing the selected apps | U07 |
| implemented | TC-U07-03 | Off closes the screen and opening it again turns the mode back on | U07 |
| implemented | TC-U07-05 | Tapping an unselected row selects the app | U07 |
| implemented | TC-U07-06 | Tapping a selected row removes the app | U07 |
| implemented | TC-U07-10 | Apply Settings to All Profiles copies the list and bypass flag only | U07 |
| implemented | TC-U07-11 | Export writes the mode flag and the package list | U07 |
| implemented | TC-U07-12 | A refused clipboard write reports failure | U07 |
| implemented | TC-U07-13 | Import applies the mode flag and package list from the clipboard | U07 |
| implemented | TC-U07-14 | Import of an empty clipboard changes nothing | U07 |
| implemented | TC-U07-15 | Import without a newline clears the package list | U07 |
| implemented | TC-U07-16 | A VPN start in On mode allows only the selected packages | U07 |
| implemented | TC-U07-17 | An empty allowed list leaves every app inside the VPN | U07 |
| implemented | TC-U07-18 | A VPN start in Bypass mode disallows selected and client packages | U07 |
| implemented | TC-U07-19 | Per-app edits stay in the shared draft until the editor saves them | U07 |
| implemented | TC-U07-20 | Profile JSON always carries proxy_apps, with bypass and android_list only when enabled | U07 |
| implemented | TC-U07-21 | Off from On closes the screen and keeps the stored bypass flag and list | U07 |
| implemented | TC-U07-22 | Import of a first line other than true selects On and replaces the selection | U07 |
| implemented | TC-U07-23 | Apply Settings reports failure when the profile list is unreadable | U07 |
| implemented | TC-U07-25 | The keyboard search action leaves the filtered list as it is | U07 |
| implemented | TC-U07-28 | A cancelled app scan leaves the spinner in place | U07 |
| implemented | TC-U08-05 | Picking a different plugin enables Configure… and shows its own options | U08 |
| implemented | TC-U08-10 | A control character in the options is rejected | U08 |
| implemented | TC-U08-11 | Cancel in the options editor discards the edit | U08 |
| implemented | TC-U08-15 | Connecting with an unknown plugin fails | U08 |
| implemented | TC-U08-16 | A subscription-owned profile locks the plugin controls | U08 |
| implemented | TC-U08-18 | The plugin id and options round-trip through ss and JSON | U08 |
| implemented | TC-U08-19 | First selection of a plugin prefills its default config | U08 |
| implemented | TC-U08-20 | The profile list row shows the plugin id | U08 |
| implemented | TC-U08-23 | Option text uses semicolons, equals signs, backslash escapes, and bare flags | U08 |
| implemented | TC-U08-30 | Back or an outside tap discards the options edit | U08 |
| implemented | TC-U09-07 | The service mode and port rows lock while the tunnel runs | U09 |
| implemented | TC-U09-08 | The rows unlock when the service reaches Stopped | U09 |
| implemented | TC-U09-09 | Editing the SOCKS5 port with a valid value persists it and the core uses it | U09 |
| implemented | TC-U09-10 | Cancel keeps the stored port | U09 |
| implemented | TC-U09-11 | A port below 1025 is stored but the core falls back to the default | U09 |
| implemented | TC-U09-12 | A port above 65535 is stored but the core falls back to the default | U09 |
| implemented | TC-U09-13 | An empty port shows Not set and the default applies | U09 |
| implemented | TC-U09-14 | The port field takes digits only and at most five characters | U09 |
| implemented | TC-U09-15 | The Local DNS port becomes the dnsgw address in VPN mode | U09 |
| implemented | TC-U10-01 | Scan a valid SIP002 QR code and add its profile | U10 |
| implemented | TC-U10-02 | Scan a code that holds two ss:// URLs | U10 |
| implemented | TC-U10-07 | Import a profile from a chosen image | U10 |
| implemented | TC-U10-08 | Import an image that holds no ss:// URL | U10 |
| implemented | TC-U10-09 | Cancel the menu image picker | U10 |
| implemented | TC-U10-11 | An image that cannot be read shows a long error toast | U10 |
| implemented | TC-U10-14 | About shows the app version | U10 |
| implemented | TC-U10-15 | About shows the licence text and the open source list | U10 |
| implemented | TC-U10-16 | Follow the Shadowsocks website link in About | U10 |
| implemented | TC-U10-17 | Follow a mailto link in About | U10 |
| implemented | TC-U10-19 | About shows the app version and the licence | U10 |
| implemented | TC-U10-20 | A link with no handler falls back to a snackbar | U10 |
| implemented | TC-U10-22 | A scan skips a malformed URL and imports the valid one | U10 |
| implemented | TC-U10-25 | About keeps its last line above the navigation bar | U10 |
| implemented | TC-U11-03 | Traffic updates stop while the screen is off and resume on | U11 |
| implemented | TC-U11-04 | Stop from the notification stops the service and removes it | U11 |
| implemented | TC-U11-05 | Tapping the notification body opens the app | U11 |

## How to run a case

At this baseline, a case is manual on both platforms. No automated E2E runner exists for the Android app or for the HarmonyOS port.

1. Read the case in its unit document. Prepare each precondition.
2. Run the case on the Android app. The Android result defines the expected behavior.
3. Run the case on the HarmonyOS app. Compare each step with the expected list.
4. Do one step at a time. Record the evidence before the next step.
5. Record this evidence for each step:
   - A screenshot after the step. Use a screen recording for a state change.
   - The screen text from a user interface dump.
   - The app log from `adb logcat` on Android or `hdc hilog` on HarmonyOS.
   - The state that the step changes, such as the profile store or a preferences file.
   - The server log and a packet capture for a network step.
6. Name each file with the case ID and the step number. Example: `TC-U01-01-step-2.png`.
7. Record the case result: pass or fail. Add the parity tag from `context/harmonyos-inventory.md`.
