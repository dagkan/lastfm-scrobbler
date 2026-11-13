using System.Text.RegularExpressions;
using LastFmScrobbler.Core;
using LastFmScrobbler.Localization;
using LastFmScrobbler.Models;

namespace LastFmScrobbler.UI;

/// <summary>
/// Add / edit one normalization rule. The rule passed in is only modified when the
/// dialog is confirmed (DialogResult.OK); persisting it is the caller's job.
/// </summary>
public class RuleEditForm : Form
{
    private static readonly Color CBack  = Color.FromArgb(28, 28, 28);
    private static readonly Color CFg    = Color.FromArgb(220, 220, 220);
    private static readonly Color CDim   = Color.FromArgb(110, 110, 110);
    private static readonly Color CInput = Color.FromArgb(36, 36, 36);
    private static readonly Color CError = Color.FromArgb(230, 90, 90);

    private static readonly RuleField[] Fields = [RuleField.Title, RuleField.Artist, RuleField.Album];

    private readonly NormalizationRule _rule;
    private readonly bool  _isNew;
    private readonly Color _accent;

    private ComboBox _fieldBox    = null!;
    private TextBox  _descBox     = null!;
    private TextBox  _patternBox  = null!;
    private TextBox  _replaceBox  = null!;
    private TextBox  _appBox      = null!;
    private CheckBox _enabledChk  = null!;
    private TextBox  _sampleBox   = null!;
    private Label    _errorLbl    = null!;
    private Label    _resultLbl   = null!;
    private Button   _saveBtn     = null!;

    public RuleEditForm(NormalizationRule rule, bool isNew, Color accent)
    {
        _rule   = rule;
        _isNew  = isNew;
        _accent = accent;
        InitializeComponent();
        UpdateState();
    }

    /// <summary>Display name of a rule field in the current UI language.</summary>
    public static string FieldLabel(RuleField field) => Loc.T("RuleField" + field);

    private void InitializeComponent()
    {
        Text            = Loc.T(_isNew ? "RuleDlgAddTitle" : "RuleDlgEditTitle");
        StartPosition   = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        ShowInTaskbar   = false;
        Font            = FontManager.Regular(9.5f);
        BackColor       = CBack;
        ForeColor       = CFg;

        const int lx = 16, lw = 150, rx = 172, rw = 380, step = 38;
        int y = 18;

        void RowLabel(string text) => Controls.Add(new Label
        {
            Text      = text,
            Location  = new Point(lx, y + 5),
            Size      = new Size(lw, 20),
            ForeColor = CDim,
            Font      = FontManager.Regular(9f),
            AutoEllipsis = true,
        });

        if (_rule.IsBuiltIn)
        {
            Controls.Add(new Label
            {
                Text      = Loc.T("RuleBuiltInNote"),
                Location  = new Point(lx, y),
                Size      = new Size(rx + rw - lx, 20),
                ForeColor = CDim,
                Font      = FontManager.Regular(8.5f),
                AutoEllipsis = true,
            });
            y += 30;
        }

        // Field
        RowLabel(Loc.T("LblRuleField"));
        _fieldBox = new ComboBox
        {
            Name = "RuleField", AccessibleName = Loc.T("LblRuleField"),
            DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat,
            BackColor = CInput, ForeColor = CFg, Font = FontManager.Regular(9.5f),
            Location = new Point(rx, y), Size = new Size(180, 26),
            Enabled = !_rule.IsBuiltIn,
        };
        foreach (var f in Fields) _fieldBox.Items.Add(FieldLabel(f));
        _fieldBox.SelectedIndex = Math.Max(0, Array.IndexOf(Fields, _rule.Field));
        Controls.Add(_fieldBox);
        y += step;

        // Description
        RowLabel(Loc.T("LblRuleDescription"));
        _descBox = Input("RuleDescription", Loc.T("LblRuleDescription"), rx, y, rw);
        _descBox.Text = _rule.Description;
        if (_rule.IsBuiltIn) { _descBox.ReadOnly = true; _descBox.TabStop = false; _descBox.ForeColor = CDim; }
        Controls.Add(_descBox);
        y += step;

        // Pattern (+ inline validation message)
        RowLabel(Loc.T("LblRulePattern"));
        _patternBox = Input("RulePattern", Loc.T("LblRulePattern"), rx, y, rw);
        _patternBox.Text = _rule.Pattern;
        _patternBox.TextChanged += (_, _) => UpdateState();
        Controls.Add(_patternBox);
        y += 28;
        // One reserved line, always there, so the rows below do not jump when a
        // message appears or clears.
        _errorLbl = new Label
        {
            Name = "RulePatternError",
            Location = new Point(rx, y), Size = new Size(rw, 18),
            ForeColor = CError, Font = FontManager.Regular(8.5f), AutoEllipsis = true, UseMnemonic = false,
        };
        Controls.Add(_errorLbl);
        y += 24;

        // Replacement
        RowLabel(Loc.T("LblRuleReplacement"));
        _replaceBox = Input("RuleReplacement", Loc.T("LblRuleReplacement"), rx, y, rw);
        _replaceBox.Text = _rule.Replacement;
        _replaceBox.PlaceholderText = Loc.T("RuleReplaceHint");
        _replaceBox.TextChanged += (_, _) => UpdateState();
        Controls.Add(_replaceBox);
        y += step;

        // App filter
        RowLabel(Loc.T("LblRuleApp"));
        _appBox = Input("RuleApp", Loc.T("LblRuleApp"), rx, y, rw);
        _appBox.Text = _rule.AppFilter;
        _appBox.PlaceholderText = Loc.T("RuleAppHint");
        Controls.Add(_appBox);
        y += step;

        // Enabled
        _enabledChk = new CheckBox
        {
            Name = "RuleEnabled", Text = Loc.T("ChkRuleEnabled"), AutoSize = true,
            Location = new Point(rx, y + 2), ForeColor = CFg, Font = FontManager.Regular(9.5f),
            Checked = _rule.IsEnabled,
        };
        Controls.Add(_enabledChk);
        y += 36;

        Controls.Add(new Panel { Location = new Point(lx, y), Size = new Size(rx + rw - lx, 1), BackColor = Color.FromArgb(48, 48, 48) });
        y += 14;

        // Try it: sample text in → result out, with the options the scrobbler really uses
        RowLabel(Loc.T("LblRuleTest"));
        _sampleBox = Input("RuleSample", Loc.T("LblRuleTest"), rx, y, rw);
        _sampleBox.PlaceholderText = Loc.T("RuleTestHint");
        _sampleBox.TextChanged += (_, _) => UpdateState();
        Controls.Add(_sampleBox);
        y += 34;

        RowLabel(Loc.T("LblRuleResult"));
        _resultLbl = new Label
        {
            Name = "RuleResult",
            Location = new Point(rx, y + 5), Size = new Size(rw, 20),
            ForeColor = CFg, Font = FontManager.Regular(9.5f), AutoEllipsis = true, UseMnemonic = false,
        };
        Controls.Add(_resultLbl);
        y += 42;

        _saveBtn = MakeBtn(Loc.T("Save"), 110, 32);
        _saveBtn.Name      = "RuleSave";
        _saveBtn.Location  = new Point(rx, y);
        _saveBtn.ForeColor = Color.White;
        _saveBtn.Click    += (_, _) => Confirm();

        var cancelBtn = MakeBtn(Loc.T("Cancel"), 100, 32);
        cancelBtn.Name         = "RuleCancel";
        cancelBtn.Location     = new Point(rx + 120, y);
        cancelBtn.DialogResult = DialogResult.Cancel;

        Controls.AddRange([_saveBtn, cancelBtn]);
        AcceptButton = _saveBtn;
        CancelButton = cancelBtn;

        ClientSize = new Size(rx + rw + 20, y + 32 + 18);

        // Start typing where it matters: a new rule needs a pattern first.
        Shown += (_, _) => (_isNew || _rule.IsBuiltIn ? _patternBox : _descBox).Focus();
    }

    /// <summary>Null when the pattern compiles; otherwise the message to show.</summary>
    private static string? ValidatePattern(string pattern)
    {
        if (pattern.Length == 0) return Loc.T("RulePatternEmpty");
        try
        {
            _ = new Regex(pattern, TrackNormalizer.RuleOptions);
            return null;
        }
        catch (ArgumentException ex) { return ShortRegexError(ex); }
    }

    /// <summary>
    /// .NET words a parse error as "Invalid pattern '&lt;the whole pattern&gt;' at offset N. &lt;reason&gt;".
    /// The pattern is in the box right above the message, so drop the echo and keep
    /// position + reason — that fits the single line reserved for it. (The reason
    /// itself comes from the runtime and is not translated.)
    /// </summary>
    private static string ShortRegexError(ArgumentException ex)
    {
        var m = Regex.Match(ex.Message, @" at offset (\d+)\. (.+)$", RegexOptions.Singleline);
        return m.Success
            ? string.Format(Loc.T("RulePatternInvalid"), m.Groups[1].Value, m.Groups[2].Value)
            : ex.Message;
    }

    private void UpdateState()
    {
        var pattern = _patternBox.Text;
        var error   = ValidatePattern(pattern);

        _errorLbl.Text      = error ?? "";
        _errorLbl.ForeColor = pattern.Length == 0 ? CDim : CError; // "nothing typed yet" is a hint, not an error
        _saveBtn.Enabled    = error is null;
        _saveBtn.BackColor = error is null ? _accent : Color.FromArgb(52, 52, 52);

        var sample = _sampleBox.Text;
        if (error is not null || sample.Length == 0)
        {
            _resultLbl.Text = "";
            return;
        }

        try
        {
            // Same call the scrobbler makes (TrackNormalizer.Apply), then its final Trim().
            _resultLbl.Text = Regex.Replace(sample, pattern, _replaceBox.Text,
                TrackNormalizer.RuleOptions, TrackNormalizer.RuleTimeout).Trim();
        }
        catch (RegexMatchTimeoutException) { _resultLbl.Text = sample; } // the scrobbler skips the rule too
        catch (ArgumentException ex)       { _resultLbl.Text = ex.Message; }
    }

    private void Confirm()
    {
        if (ValidatePattern(_patternBox.Text) is not null) return;

        if (!_rule.IsBuiltIn)
        {
            _rule.Field = Fields[Math.Max(0, _fieldBox.SelectedIndex)];
            var desc = _descBox.Text.Trim();
            _rule.Description = desc.Length > 0 ? desc : Loc.T("NewRule");
        }
        // Pattern and replacement are kept verbatim — leading/trailing spaces can be intentional.
        _rule.Pattern     = _patternBox.Text;
        _rule.Replacement = _replaceBox.Text;
        _rule.AppFilter   = _appBox.Text.Trim();
        _rule.IsEnabled   = _enabledChk.Checked;

        DialogResult = DialogResult.OK;
        Close();
    }

    private static TextBox Input(string name, string accessibleName, int x, int y, int w) => new()
    {
        Name           = name,
        AccessibleName = accessibleName,
        Location       = new Point(x, y),
        Size           = new Size(w, 26),
        BackColor      = CInput,
        ForeColor      = CFg,
        BorderStyle    = BorderStyle.FixedSingle,
        Font           = FontManager.Regular(9.5f),
    };

    private static Button MakeBtn(string text, int w, int h) => new()
    {
        Text                    = text,
        Size                    = new Size(w, h),
        FlatStyle               = FlatStyle.Flat,
        BackColor               = Color.FromArgb(40, 40, 40),
        ForeColor               = CFg,
        Cursor                  = Cursors.Hand,
        UseVisualStyleBackColor = false,
        FlatAppearance          = { BorderSize = 0 },
    };
}
