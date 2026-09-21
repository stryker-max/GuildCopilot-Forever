# Prüfung im laufenden Spiel

Ziel: WoW Forever Beta 1.60.1.69913. Automatisierte Tests laufen außerhalb des Spiels und bestätigen keine Server- oder Mehrspielerfunktion.

1. WoW nach der Erstinstallation vollständig neu starten. In der Addon-Liste steht **Guild Copilot Forever 0.1.0-beta.2**.
2. `/gcpf client`: Interface 16001, Datenbank `GuildCopilotForeverDB`, Präfix `GCPForever`. `/gcpf` öffnet das Hauptfenster; alle Seiten durchsehen.
3. Profil bestätigen, Fenster verschieben und eine Einstellung ändern. `/reload`, Ab-/Anmelden und vollständigen Client-Neustart prüfen. Bleiben die Werte erhalten? Falls nicht, zuerst den SavedVariables-Zustand des Beta-Clients prüfen; keine WTF-Dateien löschen.
4. Mit einem zweiten Gildenmitglied desselben Regelsets, derselben Fraktion und Addon-Version `/gcpf ver` prüfen. Profile, Abmeldungen und Rezeptkataloge abgleichen. Vorname und Nachname müssen vollständig mit der Clientanzeige übereinstimmen; gleicher Vorname mit anderem Nachnamen muss getrennt bleiben. Auch Weiterleitung von Rezepten und Abklingzeiten prüfen.
5. Berufsfenster öffnen, Berufsrang, Rezept, Materialzahl und tatsächliche Ausbeute vergleichen, neues Rezept lernen. Die Werkstatt muss sich aktualisieren. Herstellen über den vorgesehenen Klick prüfen; eine abgewiesene API darf keinen Erfolg melden. Mehrfachausbeute und optionale Reagenzien gesondert prüfen.
6. Ein Gildenmitglied erstellt einen Auftrag, ein anderes nimmt ihn an und meldet Fertigung/Übergabe. Menge, Materialmodell und Nachrichten müssen übereinstimmen.
7. Gruppensuche mit frei gewählter Instanz testen; Rekrutierungstext bewusst per Klick posten, Antwort und Einladung prüfen.
8. Ausrüstung vor und nach einem Gegenstandswechsel prüfen. Im Kampf darf keine blockierte Inspect-Aktion oder Fehlermeldung ausgelöst werden; nach Kampfende aktualisiert sich die eigene Prüfung.
9. Die Raidauswertung erklärt ihre Nichtverfügbarkeit. Es gibt keine Warcraft-Logs-Seite und keine TBC-BiS-/Raidvorgaben.
10. Talente schon unter Level 30 prüfen: eigene Punkte, bestätigtes Umskillen und Inspect eines Gruppenmitglieds. Ein unbestätigter Talententwurf darf nicht veröffentlicht werden. Fehlende oder gesperrte Daten dürfen keine Spezialisierung erfinden.
11. Während einer Client-Sendesperre darf eine Warteschlange keine Pakete verlieren; nach Freigabe muss sie fortsetzen. Anschließend Profil- und Rezeptabgleich erneut prüfen.
12. Eine leere Raiderliste bei Charakteren unter Stufe 60 ist erwartbar. Mitgliederzahl, eigene Profildaten und bekannte Profile getrennt prüfen; `/gcpf client` erklärt die Grenze.

Bei Fehlern: erste vollständige Lua-Fehlermeldung, auslösende Aktion und Ausgabe von `/gcpf client` festhalten. Die ersten Schritte ohne zusätzliche Addons gegenprüfen, falls ein Addon-Konflikt vermutet wird.
