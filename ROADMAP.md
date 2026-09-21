# Guild Copilot – Entwicklung

## 0.1.0-beta.6: Übersicht für alle Stufen

Die Übersicht zeigt ausgewählte Raider-Ränge ohne Levelbegrenzung. Rangfilter, Sortierung und Listenlimit bleiben erhalten; die Prüfung der Rekrutierungsabdeckung ist davon getrennt. Frühere Hinweise zur leeren Level-60-Übersicht gelten ab beta.6 nicht mehr.

## 0.1.0-beta.5: Minimap-Button am Rand

Der angeheftete Button folgt dem aktuellen Minimap-Rand. Normales Ziehen heftet an und verschiebt entlang des Rings; Umschalt + Ziehen platziert frei. Vergrößerte Karten, Größenänderungen und verschiedene UI-Skalierungen sind berücksichtigt; bestehende freie Positionen bleiben erhalten. Im Spiel nach `/reload` beide Modi und das erneute Anheften bei der verwendeten Minimap-Größe prüfen.

## 0.1.0-beta.4: Postfach und Raidvorbereitung

Die Paketprüfung kontrolliert nun sämtliche ZIP-Zeitstempel. Implizite Ordner mit wechselnder Uhrzeit werden nicht erzeugt, damit aufeinanderfolgende Builds zuverlässig bytegleich bleiben.

Das Postfach verarbeitet lesbare Whisper auch mit geschützten Begleitdaten und führt bekannte Unterhaltungen unabhängig vom Suchfenster fort. Antwortentwürfe, Paketgrenzen, Empfangsreihenfolge, Löschmarkierungen und aktive Bewerber bei voller Inbox sind abgesichert. Der Erkennungsstatus erklärt leere Suchwortlisten.

Die Raidseite bietet eine gespeicherte Momentaufnahme über `/gcp raidcheck`: lesbare Gruppen-Buffs und eigene Verbrauchsvorräte vor dem Pull. Sie bewertet keine unbestätigten Forever-Pflichtbuffs und zählt keinen tatsächlichen Verbrauch. Für eine spätere Auswertung benutzter Verbrauchsmaterialien fehlen eine reale Forever-Logprobe und bestätigte Spell-/Item-Zuordnungen. Die öffentliche Schadensanzeige liefert hierfür keine Verbrauchsmetrik. [Quellen und Grenzen](docs/RAID-VORBEREITUNG.md).

Noch im Spiel abzunehmen: Postfach zwischen zwei Gildenmitgliedern einschließlich Suchende, fehlgeschlagener Antwort und Neustart; Vorbereitungscheck mit erreichbaren, entfernten und offline Mitgliedern sowie tatsächlichen Forever-Verbrauchsgegenständen. Die Offline-Tests prüfen Verträge und Fehlerfälle, keine Serverzustellung.

## 0.1.0-beta.3: bestehenden Namen und Befehl beibehalten

Der Produktname bleibt **Guild Copilot**, der Befehl **`/gcp`** mit Alias **`/guildcopilot`**. Das gilt auch für Titel, Einstellungen, Chat-Ausgaben, Einrichtungsassistent und Übersetzungen. Das vorhandene GitHub-Repository `stryker-max/GuildCopilot-Forever` enthält die Forever-Fassung; seine technische Trennung ist keine Produktumbenennung.

## 0.1.0-beta.2: Abgleich mit dem Forever-Client

Große Rezepte behalten ihre vollständigen Reagenzienlisten durch zusammengesetzte FD/FC-Transfers. Rezeptabgleiche erfordern beta.2 auf beiden Seiten; alte C/D-Transfers werden weiterhin gelesen. Der unberührte beta.1-Gildenfortschrittswert wird beim Laden korrigiert, bearbeitete Gildenprofile bleiben erhalten.

Die erste Portierung enthielt noch unzutreffende Annahmen über Realmnamen und Talentabfragen. Der aktuelle Stand verwendet das zweiteilige Forever-Namensmodell und das öffentliche `C_Traits`-Gruppenmodell aus Blizzards `Camelot`-UI. Berufs-Hauptpfad, Fehler bei der Herstellung, lange Sync-Identitäten, Paketgrößen, Client-Sendesperren und der TBC-Gildenfortschrittswert sind korrigiert. Die Diagnose erklärt die weiterhin auf Level 60 gefilterte Raiderliste. Die [Quellenbasis](docs/FOREVER-GRUNDLAGE.md) und [Spielabnahme](docs/BETA-ABNAHME.md) beschreiben den aktuellen Zielstand.

Die Vertragsprüfungen laufen gegen Quelle und entpacktes Paket. Die tatsächliche Namensdarstellung, Mehrspieler-Kommunikation, Rezeptausbeute und Persistenz nach Neustart bleiben Teil der Abnahme im laufenden Beta-Client. Ein erfolgreicher Offline-Test ist dafür keine Freigabe. Die nachstehenden Angaben zu Talentabfragen und Realmanteilen dokumentieren den ursprünglichen Stand beta.1; sie sind durch beta.2 ersetzt.

## 0.1.0-beta.1: eigenständige Beta-Portierung

Ausgangsstand: TBC 0.9.142, Commit `71e650473b90e7d39ae4b814678ce64abe8c694a`. Der lokale Forever-Client und die dazugehörigen Blizzard-UI-Quellen melden `1.60.1.69913`. Der API-Abgleich basiert auf dem Quellstand `70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e` des UI-Mirrors.

Die Projekte sind vollständig getrennt. Änderungen und Pakete in diesem Repository betreffen ausschließlich `GuildCopilotForever`; `GuildCopilot` und die Anniversary-Installation sind keine Auslieferungsziele. Der übernommene MIT-Code behält seine Urheberangaben. Der alte Windows-Installer, Companion, Updatepfad und CurseForge-Workflow gehören nicht in dieses Projekt.

`Client.lua` kapselt die API-Unterschiede, ohne globale Blizzard-Funktionen zu überschreiben. `C_SkillInfo.GetSkillLineInfo` und `C_Spell.GetSpellInfo` liefern Strukturen, die explizit in die erwarteten Rückgabewerte übersetzt werden. Die Rezeptdaten stammen aus `C_TradeSkillUI`; Listen- und Datenquellenereignisse lösen erneute Scans aus. Talentpunkte stammen aus dem dokumentierten siebten Rückgabewert von `C_SpecializationInfo.GetSpecializationInfo`.

Die Datenspeicherung verwendet ausschließlich `GuildCopilotForeverDB`, der Datenaustausch `GCPForever`. Namensschlüssel erhalten in Forever ihren Realmanteil. Aufträge verwenden für Spieleridentitäten eine eigene Längengrenze; Reservierungen sowie fragmentierte Kern- und Zustandspakete werden mit langen Realmnamen getestet. Die öffentliche Alt-Kampflog-API wird nicht durch interne oder geschützte APIs ersetzt. Ausrüstung kann weiterhin erfasst werden, aber TBC-BiS-Wissen und Pflichtverzauberungsslots werden nicht auf neue Spielregeln übertragen. Eine passende Forever-Regelbasis muss später anhand bestätigter Spieldaten ergänzt werden.

## Nächste Abnahme

Die [Beta-Checkliste](docs/BETA-ABNAHME.md) im Spiel ausführen: Start, Sichtprüfung, Neustart/Persistenz, zwei Gildenmitglieder, Berufe, Auftrag, Gruppenwechsel und Kampfende. Erst mit diesen Ergebnissen kann tatsächliche Mehrspieler-Kompatibilität bestätigt werden.

## Nach belastbaren Daten

- Forever-Regelsatz für Ausrüstung und Verzauberungspflichten, jeweils mit Quellen und eigener Regelversion.
- Bestätigte Instanzvorgaben und Gruppengrößen.
- Anpassungen nach weiteren Beta-Builds; Diagnose über `/gcp client`.
- Separate CurseForge-Projektanlage nur bei einer ausdrücklichen Veröffentlichungsentscheidung.
