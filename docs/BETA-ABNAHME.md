# Prüfung im laufenden Spiel

Ziel: WoW Forever Beta 1.60.1.69913. Automatisierte Tests laufen außerhalb des Spiels und bestätigen keine Server- oder Mehrspielerfunktion.

1. WoW nach der Erstinstallation vollständig neu starten. In der Addon-Liste steht **Guild Copilot Forever 0.1.0-beta.1**.
2. `/gcpf client`: Interface 16001, Datenbank `GuildCopilotForeverDB`, Präfix `GCPForever`. `/gcpf` öffnet das Hauptfenster; alle Seiten durchsehen.
3. Profil bestätigen, Fenster verschieben und eine Einstellung ändern. `/reload`, Ab-/Anmelden und vollständigen Client-Neustart prüfen. Bleiben die Werte erhalten? Falls nicht, zuerst den SavedVariables-Zustand des Beta-Clients prüfen; keine WTF-Dateien löschen.
4. Mit einem zweiten Gildenmitglied derselben Forever-Version `/gcpf ver` prüfen. Profile, Abmeldungen und Rezeptkataloge abgleichen. Zwei gleichnamige Charaktere mit verschiedenen Realmzusätzen müssen getrennt bleiben.
5. Berufsfenster öffnen, Rezept und Materialzahl vergleichen, neues Rezept lernen. Die Werkstatt muss sich aktualisieren. Herstellen über den vorgesehenen Klick prüfen.
6. Ein Gildenmitglied erstellt einen Auftrag, ein anderes nimmt ihn an und meldet Fertigung/Übergabe. Menge, Materialmodell und Nachrichten müssen übereinstimmen.
7. Gruppensuche mit frei gewählter Instanz testen; Rekrutierungstext bewusst per Klick posten, Antwort und Einladung prüfen.
8. Ausrüstung vor und nach einem Gegenstandswechsel prüfen. Im Kampf darf keine blockierte Inspect-Aktion oder Fehlermeldung ausgelöst werden; nach Kampfende aktualisiert sich die eigene Prüfung.
9. Die Raidauswertung erklärt ihre Nichtverfügbarkeit. Es gibt keine Warcraft-Logs-Seite und keine TBC-BiS-/Raidvorgaben.

Bei Fehlern: erste vollständige Lua-Fehlermeldung, auslösende Aktion und Ausgabe von `/gcpf client` festhalten. Die ersten Schritte ohne zusätzliche Addons gegenprüfen, falls ein Addon-Konflikt vermutet wird.
