# Control tree index

This index covers the Android mobile module at baseline v5.3.5-nightly (commit ae28fd9).

## Units

| Unit | Title | Controls | Rules | Flows | States | Doc link |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| U01 | Main shell, navigation drawer, connect control, stats bar | 26 | 30 | 6 | 5 | [units/U01.md](units/U01.md) |
| U02 | Profile list, row layout, search, reorder, delete, share popup | 30 | 51 | 8 | 3 | [units/U02.md](units/U02.md) |
| U03 | Profile editor and UDP fallback | 61 | 41 | 9 | 5 | [units/U03.md](units/U03.md) |
| U04 | Import and export flows | 29 | 56 | 9 | 3 | [units/U04.md](units/U04.md) |
| U05 | Subscriptions | 20 | 29 | 6 | 4 | [units/U05.md](units/U05.md) |
| U06 | Custom rules and ACL | 30 | 35 | 10 | 8 | [units/U06.md](units/U06.md) |
| U07 | Per-app proxy, Apps VPN mode | 25 | 34 | 8 | 4 | [units/U07.md](units/U07.md) |
| U08 | Plugin picker and plugin options | 29 | 30 | 6 | 5 | [units/U08.md](units/U08.md) |
| U09 | Global settings | 34 | 35 | 8 | 6 | [units/U09.md](units/U09.md) |
| U10 | QR scanner and About | 35 | 28 | 5 | 3 | [units/U10.md](units/U10.md) |
| U11 | System surfaces: notification, tile, shortcuts, boot, Tasker | 21 | 43 | 11 | 5 | [units/U11.md](units/U11.md) |
| Total | 11 units | 340 | 412 | 86 | 51 | |

## Screens and dialogs

| Control ID | Label | Unit | Doc link |
| --- | --- | --- | --- |
| C-U01-001 | Shadowsocks main screen | U01 | [units/U01.md](units/U01.md) |
| C-U01-002 | Toolbar fragment container | U01 | [units/U01.md](units/U01.md) |
| C-U01-014 | Main content container | U01 | [units/U01.md](units/U01.md) |
| C-U01-024 | VPN connection consent | U01 | [units/U01.md](units/U01.md) |
| C-U02-001 | Profiles | U02 | [units/U02.md](units/U02.md) |
| C-U02-021 | share popup | U02 | [units/U02.md](units/U02.md) |
| C-U02-024 | QR code | U02 | [units/U02.md](units/U02.md) |
| C-U02-029 | Open file | U02 | [units/U02.md](units/U02.md) |
| C-U02-030 | Save file | U02 | [units/U02.md](units/U02.md) |
| C-U03-001 | Profile config | U03 | [units/U03.md](units/U03.md) |
| C-U03-022 | Changes not saved. Do you want to save? | U03 | [units/U03.md](units/U03.md) |
| C-U03-026 | Are you sure you want to remove this profile? | U03 | [units/U03.md](units/U03.md) |
| C-U03-029 | Password | U03 | [units/U03.md](units/U03.md) |
| C-U03-035 | Edit text | U03 | [units/U03.md](units/U03.md) |
| C-U03-039 | Encrypt Method | U03 | [units/U03.md](units/U03.md) |
| C-U03-040 | Route | U03 | [units/U03.md](units/U03.md) |
| C-U03-050 | UDP Fallback | U03 | [units/U03.md](units/U03.md) |
| C-U04-001 | Profiles | U04 | [units/U04.md](units/U04.md) |
| C-U04-015 | Share popup | U04 | [units/U04.md](units/U04.md) |
| C-U04-018 | QR code | U04 | [units/U04.md](units/U04.md) |
| C-U04-021 | Url import | U04 | [units/U04.md](units/U04.md) |
| C-U04-022 | Add this Shadowsocks Profile? | U04 | [units/U04.md](units/U04.md) |
| C-U04-027 | System file picker (open) | U04 | [units/U04.md](units/U04.md) |
| C-U04-028 | System file picker (save) | U04 | [units/U04.md](units/U04.md) |
| C-U05-001 | Subscriptions | U05 | [units/U05.md](units/U05.md) |
| C-U05-008 | Edit subscription | U05 | [units/U05.md](units/U05.md) |
| C-U06-001 | Custom rules | U06 | [units/U06.md](units/U06.md) |
| C-U06-017 | Edit rule | U06 | [units/U06.md](units/U06.md) |
| C-U07-001 | Apps VPN mode | U07 | [units/U07.md](units/U07.md) |
| C-U08-001 | Profile config | U08 | [units/U08.md](units/U08.md) |
| C-U08-008 | Plugin picker | U08 | [units/U08.md](units/U08.md) |
| C-U08-016 | Configure… | U08 | [units/U08.md](units/U08.md) |
| C-U08-021 | ? | U08 | [units/U08.md](units/U08.md) |
| C-U08-022 | Plugin configuration activity | U08 | [units/U08.md](units/U08.md) |
| C-U08-023 | App info | U08 | [units/U08.md](units/U08.md) |
| C-U09-001 | Settings | U09 | [units/U09.md](units/U09.md) |
| C-U09-011 | Service mode | U09 | [units/U09.md](units/U09.md) |
| C-U09-020 | SOCKS5 proxy port | U09 | [units/U09.md](units/U09.md) |
| C-U09-024 | Local DNS port | U09 | [units/U09.md](units/U09.md) |
| C-U09-028 | Transproxy port | U09 | [units/U09.md](units/U09.md) |
| C-U10-001 | Scan QR code | U10 | [units/U10.md](units/U10.md) |
| C-U10-007 | Camera permission prompt (system) | U10 | [units/U10.md](units/U10.md) |
| C-U10-009 | Image picker (system, image/*) | U10 | [units/U10.md](units/U10.md) |
| C-U10-013 | About | U10 | [units/U10.md](units/U10.md) |
| C-U10-030 | Open source licenses | U10 | [units/U10.md](units/U10.md) |
| C-U10-031 | Send email | U10 | [units/U10.md](units/U10.md) |
| C-U10-032 | Custom Tab browser | U10 | [units/U10.md](units/U10.md) |
| C-U11-030 | Shadowsocks | U11 | [units/U11.md](units/U11.md) |

## Parity summary

| Parity value | Case count |
| --- | ---: |
| implemented | 63 |
| partial | 93 |
| missing | 136 |
| android-only | 56 |
| Total | 348 |

Each case takes one parity value from `context/harmonyos-inventory.md`: implemented, partial, missing, or android-only.
