import AppKit
import Foundation

final class AliasProvider {
    static let shared = AliasProvider()

    /// Curated English aliases for common localized titles.
    private let curated: [String: [String]] = [
        "Ablage": ["File"],
        "Bearbeiten": ["Edit"],
        "Darstellung": ["View"],
        "Fenster": ["Window"],
        "Hilfe": ["Help"],
        "Datei": ["File"],
        "Edition": ["Edit"],
        "Présentation": ["View"],
        "Fenêtre": ["Window"],
        "Aide": ["Help"],
        "Archivo": ["File"],
        "Edición": ["Edit"],
        "Visualización": ["View"],
        "Ventana": ["Window"],
        "Ayuda": ["Help"],
        "ファイル": ["File"],
        "編集": ["Edit"],
        "表示": ["View"],
        "ウィンドウ": ["Window"],
        "ヘルプ": ["Help"],
        "Öffnen": ["Open"],
        "Speichern": ["Save"],
        "Schließen": ["Close"],
        "Drucken": ["Print"],
        "Kopieren": ["Copy"],
        "Einfügen": ["Paste"],
        "Ausschneiden": ["Cut"],
        "Rückgängig": ["Undo"],
        "Wiederholen": ["Redo"],
        "Ouvrir": ["Open"],
        "Enregistrer": ["Save"],
        "Fermer": ["Close"],
        "Imprimer": ["Print"],
        "Copier": ["Copy"],
        "Coller": ["Paste"],
        "Couper": ["Cut"],
        "Annuler": ["Undo"]
    ]

    func aliases(for title: String, path: [String], bundleID: String?) -> [String] {
        var result: [String] = []
        if let mapped = curated[title] {
            result.append(contentsOf: mapped)
        }
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let english = englishString(for: title, in: bundle),
           english != title {
            result.append(english)
        }
        return Array(Set(result))
    }

    private func englishString(for title: String, in bundle: Bundle) -> String? {
        guard let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
            ?? bundle.path(forResource: "MainMenu", ofType: "strings", inDirectory: nil, forLocalization: "en")
        else {
            return nil
        }
        guard let dict = NSDictionary(contentsOfFile: enPath) as? [String: String] else { return nil }
        return dict[title]
    }
}
