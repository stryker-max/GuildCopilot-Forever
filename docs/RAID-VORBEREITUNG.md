# Verbrauchsmaterialien und Vorbereitung in Forever

Stand: Guild Copilot 0.1.0-beta.4, WoW Forever 1.60.1.69913 (Interface 16001). Produktname **Guild Copilot**, Hauptbefehl **`/gcp`**.

## Was jetzt erfasst wird

Vor dem Pull **`/gcp raidcheck`** eingeben oder auf der Raidseite „Vorbereitung erfassen“ klicken. Der Check speichert die letzte Momentaufnahme pro Charakter, einschließlich Zeitstempel. Ein neuer erfolgreicher Check ersetzt sie; es gibt noch keine Verlaufsauswertung. „Ausrüstung prüfen“ öffnet die vorhandene Ausrüstungsseite.

- Alle vollständig lesbaren hilfreichen Effekte jedes erreichbaren Gruppen-/Raidmitglieds, einschließlich Klassenbuffs. Das ist keine auf Essen, Fläschchen oder Elixiere gefilterte Liste und keine Bewertung der Raidbereitschaft.
- Eigene Verbrauchsgegenstände aus Rucksack und ausgerüsteten Taschen, anhand der vom Client gelieferten Gegenstandsklasse „Consumable“. Gleiche Gegenstände werden addiert. Bank und fremde Taschen werden nicht gelesen; Vorräte werden nicht über den Gildensync geteilt.
- Offline, entfernte, im Kampf befindliche oder geschützte Mitglieder: **unbekannt**, niemals automatisch „Buff fehlt“. Teilweise lesbare Bufflisten werden ebenfalls als unbekannt angezeigt. Unvollständig lesbare Taschen werden ausdrücklich gekennzeichnet.

Während eines Kampfes bzw. eines vom Client gemeldeten laufenden Bossversuchs wird keine Momentaufnahme erstellt. Es erfolgt keine automatische Erfassung. Persistenz übernimmt WoW über die vorhandenen SavedVariables; `/reload` und Neustart sind im Spiel zu prüfen.

## Was die Daten nicht beweisen

Ein aktiver Buff belegt weder den Zeitpunkt noch die Zahl der Anwendungen. Ein verringerter Taschenbestand kann auch durch Handel, Verschieben oder Wegwerfen entstehen. Deshalb gibt es keine daraus abgeleiteten Trank-, Elixier- oder Essenszähler und keine Pflichtliste aus TBC.

Eine belastbare Bewertung „vorbereitet/nicht vorbereitet“ benötigt zusätzlich einen verifizierten Forever-Katalog der Effekte und Gegenstände sowie gewünschte Raidregeln. Ein solcher Katalog ist hier noch nicht enthalten.

## Geprüfte Client-Schnittstellen

Referenz ist die Blizzard-UI aus genau Build 69913, gespiegelt am Commit `70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e`:

- [UnitAuraDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua): `C_UnitAuras.GetAuraDataByIndex` erfordert Aura-Zugriff und kann bei eingeschränktem Zugriff geschützte Werte liefern. Guild Copilot wertet solche Werte nicht aus.
- [ItemDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua): `C_Item.GetItemInfoInstant` liefert unter anderem die Gegenstandsklasse; Namen kommen vom Client statt aus einer TBC-Datenbank.
- [InstanceEncounterDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/InstanceEncounterDocumentation.lua): `IsEncounterInProgress` verhindert einen Check während eines laufenden Bossversuchs, auch wenn der eigene Charakter gerade nicht im Kampf ist.
- [DamageMeterDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua) und [DamageMeterConstantsDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterConstantsDocumentation.lua): Die öffentliche Schadensanzeige bietet Sitzungs-/Kampfwerte wie Schaden, Heilung, Unterbrechungen und Tode. Sie enthält keine Verbrauchsmaterial-Metrik; Sitzungsdaten sind außerdem im Kampf eingeschränkt. Diese API ist keine Grundlage für Verbrauchszähler.
- [CombatLogSecureDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogSecureDocumentation.lua): Der aktuelle Ereigniszugriff ist `SecureOnly`. Die frühere öffentliche TBC-Schnittstelle wird nicht über interne APIs ersetzt.

## Möglichkeit für eine spätere Auswertung nach dem Raid

Ein separater Import einer vom Forever-Client tatsächlich erzeugten lokalen Kampfprotokolldatei könnte Anwendungen nach dem Raid zählen, **wenn** ihr Format die dafür erforderlichen Ereignisse und Spielerzuordnungen enthält. Dafür liegt noch keine reale Forever-Logprobe vor; Verfügbarkeit, Vollständigkeit und brauchbare Ereignisse sind nicht bestätigt. Es gibt in dieser Version weder einen solchen Importer noch eine Warcraft-Logs-Anbindung.

Vor einer Umsetzung müssen eine echte Datei außerhalb des laufenden Kampfes geprüft, Spell-/Item-Zuordnungen für Forever bestätigt und fehlende Daten sauber von null Anwendungen getrennt werden. Einschränkungen des Clients werden dabei nicht umgangen. Die derzeitige Momentaufnahme bleibt unabhängig davon nutzbar.
