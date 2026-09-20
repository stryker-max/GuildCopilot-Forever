# Guild Copilot Forever – Entwicklung

## 0.1.0-beta.1: eigenständige Beta-Portierung

Ausgangsstand: TBC 0.9.142, Commit `71e650473b90e7d39ae4b814678ce64abe8c694a`. Der lokale Forever-Client und die dazugehörigen Blizzard-UI-Quellen melden `1.60.1.69913`. Der API-Abgleich basiert auf dem Quellstand `70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e` des UI-Mirrors.

Die Projekte sind vollständig getrennt. Änderungen und Pakete in diesem Repository betreffen ausschließlich `GuildCopilotForever`; `GuildCopilot` und die Anniversary-Installation sind keine Auslieferungsziele. Der übernommene MIT-Code behält seine Urheberangaben. Der alte Windows-Installer, Companion, Updatepfad und CurseForge-Workflow gehören nicht in dieses Projekt.

`Client.lua` kapselt die API-Unterschiede, ohne globale Blizzard-Funktionen zu überschreiben. `C_SkillInfo.GetSkillLineInfo` und `C_Spell.GetSpellInfo` liefern Strukturen, die explizit in die erwarteten Rückgabewerte übersetzt werden. Die Rezeptdaten stammen aus `C_TradeSkillUI`; Listen- und Datenquellenereignisse lösen erneute Scans aus. Talentpunkte stammen aus dem dokumentierten siebten Rückgabewert von `C_SpecializationInfo.GetSpecializationInfo`.

Die Datenspeicherung verwendet ausschließlich `GuildCopilotForeverDB`, der Datenaustausch `GCPForever`. Namensschlüssel erhalten in Forever ihren Realmanteil. Die öffentliche Alt-Kampflog-API wird nicht durch interne oder geschützte APIs ersetzt. Ausrüstung kann weiterhin erfasst werden, aber TBC-BiS-Wissen und Pflichtverzauberungsslots werden nicht auf neue Spielregeln übertragen. Eine passende Forever-Regelbasis muss später anhand bestätigter Spieldaten ergänzt werden.

## Nächste Abnahme

Die [Beta-Checkliste](docs/BETA-ABNAHME.md) im Spiel ausführen: Start, Sichtprüfung, Neustart/Persistenz, zwei Gildenmitglieder, Berufe, Auftrag, Gruppenwechsel und Kampfende. Erst mit diesen Ergebnissen kann tatsächliche Mehrspieler-Kompatibilität bestätigt werden.

## Nach belastbaren Daten

- Forever-Regelsatz für Ausrüstung und Verzauberungspflichten, jeweils mit Quellen und eigener Regelversion.
- Bestätigte Instanzvorgaben und Gruppengrößen.
- Anpassungen nach weiteren Beta-Builds; Diagnose über `/gcpf client`.
- Separate CurseForge-Projektanlage nur bei einer ausdrücklichen Veröffentlichungsentscheidung.
