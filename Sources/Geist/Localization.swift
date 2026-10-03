// The shell's few native strings in English and German. The language follows
// the preference the web interface stores under "interfaceLanguage", which
// is why this is not a String Catalog: bundle localization cannot switch
// at runtime.
import Foundation

enum DesktopLanguage {
    static func resolve(preference: String?, system: String) -> String {
        if preference == "de" || preference == "en" { return preference! }
        let base = system.lowercased().components(separatedBy: CharacterSet(charactersIn: "-_.@")).first
        return base == "de" ? "de" : "en"
    }
    static var preference: String {
        let saved = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system"
        return ["de", "en"].contains(saved) ? saved : "system"
    }
    static var system: String { resolve(preference: nil, system: Locale.preferredLanguages.first ?? "en") }
    static var current: String { resolve(preference: preference, system: system) }
    static var script: String {
        // Both interpolated values are allowlisted, never raw locale or user input.
        "window.geistSystemLanguage = '\(system)'; window.geistLanguagePreference = '\(preference)'; window.geistDesktop = 'mac';"
    }
}

@MainActor func desktopText(_ english: String) -> String {
    guard DesktopLanguage.current == "de" else { return english }
    return ["Update cancelled — could not stop the model service. Try Stop model service first.": "Update abgebrochen. Der Modelldienst konnte nicht gestoppt werden. Versuche zuerst „Modelldienst stoppen“.",
        "Stopping model service before installing the update…": "Modelldienst wird vor dem Update gestoppt…",
        "Install geisten in Applications?": "geisten unter Programme installieren?",
        "This replaces the previous app. Your models and settings are kept.": "Die bisherige App wird ersetzt. Modelle und Einstellungen bleiben erhalten.",
        "Install and open": "Installieren und öffnen", "geisten could not be installed": "geisten konnte nicht installiert werden",
        "The previous app is kept. Copy geisten to Applications in Finder, then open it there.": "Die bisherige App bleibt erhalten. Kopiere geisten im Finder nach Programme und öffne es dort.",
        "Close the previous geisten app first": "Schließe zuerst die bisherige geisten-App",
        "An update or another window is still open. Your model service has not been stopped.": "Ein Update oder ein anderes Fenster ist noch offen. Der Modelldienst wurde nicht gestoppt.",
        "Restart the older model service?": "Älteren Modelldienst neu starten?",
        "Finish any current task first. geisten will use the installed version. Downloads and models are kept.": "Beende zuerst laufende Aufgaben. geisten verwendet dann die installierte Version. Downloads und Modelle bleiben erhalten.",
        "Restart and continue": "Neu starten und fortfahren",
        "Finish the current task, then reconnect to update geisten.": "Beende die laufende Aufgabe und verbinde dich erneut, um geisten zu aktualisieren.",
        "A newer geisten service is running. Open the newest installed app.": "Ein neuerer geisten-Dienst läuft. Öffne die neueste installierte App.",
        "Restart the older service to use this app.": "Starte den älteren Dienst neu, um diese App zu verwenden.",
        "Settings": "Einstellungen", "Models": "Modelle", "Connect a program": "Programm verbinden", "No model loaded": "Kein Modell geladen", "Model ready": "Modell bereit", "Preparing model…": "Modell wird vorbereitet…", "Model in use": "Modell wird verwendet",
        "Start geisten": "geisten starten", "Start at Login": "Bei Anmeldung starten", "Show Data Folder": "Datenordner anzeigen", "Check for Updates…": "Nach Updates suchen…", "Open geisten": "geisten öffnen", "Quit geisten": "geisten beenden", "Cancel": "Abbrechen",
        "Stop model service": "Modelldienst stoppen", "Stop model service?": "Modelldienst stoppen?",
        "Terminal and editor connections will stop too. Downloaded models are kept.": "Auch Terminal und Editoren werden getrennt. Heruntergeladene Modelle bleiben erhalten.",
        "Starting local service…": "Lokaler Dienst wird gestartet…", "Starting…": "Wird gestartet…",
        "Local service running": "Lokaler Dienst läuft", "Local service stopped": "Lokaler Dienst gestoppt",
        "Start / reconnect": "Starten / neu verbinden", "Cannot read service connection": "Dienstverbindung kann nicht gelesen werden",
        "Service unavailable — check port 8766": "Dienst nicht erreichbar. Prüfe, ob Port 8766 bereits belegt ist.",
        "The interface could not be loaded. Try reconnecting.": "Die Oberfläche konnte nicht geladen werden. Bitte neu verbinden.",
        "Closing this window keeps the model service available to your tools.": "Beim Schließen bleibt der Modelldienst für deine Programme verfügbar."
    ][english] ?? english
}
