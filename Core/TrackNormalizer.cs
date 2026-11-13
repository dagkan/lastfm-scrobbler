using System.Text.RegularExpressions;
using LastFmScrobbler.Models;

namespace LastFmScrobbler.Core;

public class TrackNormalizer
{
    private List<NormalizationRule> _rules = [];

    public void UpdateRules(List<NormalizationRule> rules)
    {
        _rules = rules.Where(r => r.IsEnabled).ToList();
    }

    public Track Normalize(Track original)
    {
        var track = original.Clone();

        foreach (var rule in _rules)
        {
            if (!string.IsNullOrEmpty(rule.AppFilter) &&
                !(track.SourceApp?.Contains(rule.AppFilter, StringComparison.OrdinalIgnoreCase) ?? false))
                continue;

            switch (rule.Field)
            {
                case RuleField.Title:
                    track.Title = Apply(track.Title, rule);
                    break;
                case RuleField.Artist:
                    track.Artist = Apply(track.Artist, rule);
                    break;
                case RuleField.Album:
                    track.Album = Apply(track.Album, rule);
                    if (track.AlbumArtist != null)
                        track.AlbumArtist = Apply(track.AlbumArtist, rule);
                    break;
            }
        }

        // Trim trailing/leading whitespace after rules
        track.Title = track.Title.Trim();
        track.Artist = track.Artist.Trim();
        track.Album = track.Album.Trim();

        return track;
    }

    /// <summary>Regex options every rule runs with — shared with the rule editor's validation/preview.</summary>
    public const RegexOptions RuleOptions = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
    public static readonly TimeSpan RuleTimeout = TimeSpan.FromMilliseconds(100);

    private static string Apply(string input, NormalizationRule rule)
    {
        try
        {
            return Regex.Replace(input, rule.Pattern, rule.Replacement, RuleOptions, RuleTimeout);
        }
        catch (RegexMatchTimeoutException)
        {
            return input;
        }
        catch (ArgumentException)
        {
            // Invalid regex — skip rule
            return input;
        }
    }
}
