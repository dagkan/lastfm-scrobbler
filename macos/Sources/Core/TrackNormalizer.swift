import Foundation

struct TrackNormalizer: Sendable {
    private let rules: [NormalizationRule]

    init(rules: [NormalizationRule]) {
        self.rules = rules
    }

    func normalize(_ track: Track) -> Track {
        var t = track
        for rule in rules where rule.isEnabled {
            switch rule.field {
            case .title:   t.title = apply(rule, to: t.title)
            case .artist:  t.artist = apply(rule, to: t.artist)
            case .album:   t.album = apply(rule, to: t.album)
            }
        }
        t.title = t.title.trimmingCharacters(in: .whitespaces)
        t.artist = t.artist.trimmingCharacters(in: .whitespaces)
        t.album = t.album.trimmingCharacters(in: .whitespaces)
        return t
    }

    private func apply(_ rule: NormalizationRule, to value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: rule.replacement)
    }
}
