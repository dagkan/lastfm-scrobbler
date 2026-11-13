using LastFmScrobbler.Models;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;

namespace LastFmScrobbler.Core;

/// <summary>
/// JSON form of normalization rules for Export / Import. The file is meant to be
/// hand-editable, so <see cref="NormalizationRule.Field"/> is written by name
/// ("Title" / "Artist" / "Album"). Files written by 1.2.22 and earlier used the
/// enum's number (0 / 1 / 2); reading accepts both.
/// </summary>
public static class RuleJson
{
    private static readonly JsonSerializerSettings Settings = new()
    {
        Formatting = Formatting.Indented,
        Converters = { new StringEnumConverter() }, // reads names (any case) and plain integers
    };

    public static string Serialize(IEnumerable<NormalizationRule> rules) =>
        JsonConvert.SerializeObject(rules, Settings);

    public static List<NormalizationRule> Deserialize(string json)
    {
        var rules = JsonConvert.DeserializeObject<List<NormalizationRule>>(json, Settings) ?? [];
        rules.RemoveAll(r => r is null);
        foreach (var r in rules)
        {
            // A hand-edited file may leave fields out or set them to null; the
            // database columns are NOT NULL.
            r.Pattern     ??= string.Empty;
            r.Replacement ??= string.Empty;
            r.Description ??= string.Empty;
            r.AppFilter   ??= string.Empty;
        }
        return rules;
    }
}
