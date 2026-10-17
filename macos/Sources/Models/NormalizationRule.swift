import Foundation

enum NormalizationField: String, CaseIterable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
}

struct NormalizationRule: Identifiable, Sendable {
    var id: Int64
    var field: NormalizationField
    var pattern: String
    var replacement: String
    var isEnabled: Bool
    var description: String
    var isBuiltIn: Bool

    static func getDefaults() -> [NormalizationRule] {
        var rules: [NormalizationRule] = []
        var id: Int64 = 1

        func rule(_ field: NormalizationField, _ desc: String, _ pattern: String, _ replacement: String) -> NormalizationRule {
            let r = NormalizationRule(id: id, field: field, pattern: pattern, replacement: replacement,
                                     isEnabled: true, description: desc, isBuiltIn: true)
            id += 1
            return r
        }

        rules.append(rule(.album, "Strip edition tags",
            #"[\(\[]?\s*(Deluxe|Expanded|Anniversary|Remastered|Bonus Track Version|Collector's Edition)(\s+Edition)?\s*[\)\]]?"#, ""))
        rules.append(rule(.title, "Strip remaster suffix",
            #"\s*-\s*Remastered\s+\d{4}"#, ""))
        rules.append(rule(.title, "Strip version tags",
            #"[\(\[]\s*(Remastered \d{4}|Radio Edit|Single Version|Album Version)\s*[\)\]]"#, ""))
        rules.append(rule(.artist, "Normalize featuring",
            #"\b(featuring|ft\.?)\b"#, "feat."))

        return rules
    }
}
