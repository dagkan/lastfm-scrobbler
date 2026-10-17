using System.Drawing.Drawing2D;

namespace LastFmScrobbler.UI;

public enum NavIcon { Monitor, History, Stats, Friends, Settings, Normalization, About }
public enum CaptionGlyph { Minimize, Maximize, Restore, Close }

/// <summary>
/// Vector-drawn UI icons. Unicode glyphs (▶ ◎ ∑ … and the ─ □ ✕ caption
/// buttons) came out of whatever font happened to be installed with uneven
/// weight and baseline; drawing them ourselves keeps every icon on the same
/// stroke width and optical size regardless of font or DPI.
/// </summary>
internal static class Icons
{
    /// <summary>Draws a 16×16 (logical px) line icon centred in <paramref name="bounds"/>.</summary>
    public static void DrawNav(Graphics g, NavIcon icon, Rectangle bounds, Color color, float scale)
    {
        var old = (g.SmoothingMode, g.PixelOffsetMode);
        g.SmoothingMode   = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;

        float s  = 16f * scale;
        float x0 = bounds.X + (bounds.Width  - s) / 2f;
        float y0 = bounds.Y + (bounds.Height - s) / 2f;
        // Local coordinate helper on a 16-unit grid.
        float P(float v) => v * scale;
        RectangleF R(float x, float y, float w, float h) => new(x0 + P(x), y0 + P(y), P(w), P(h));
        PointF Pt(float x, float y) => new(x0 + P(x), y0 + P(y));

        using var pen = new Pen(color, Math.Max(1f, 1.5f * scale))
        { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
        using var brush = new SolidBrush(color);

        switch (icon)
        {
            case NavIcon.Monitor:
                // play triangle inside a circle
                g.DrawEllipse(pen, R(1.5f, 1.5f, 13, 13));
                using (var path = new GraphicsPath())
                {
                    path.AddPolygon([Pt(6.5f, 5f), Pt(11f, 8f), Pt(6.5f, 11f)]);
                    g.FillPath(brush, path);
                }
                break;

            case NavIcon.History:
                // clock
                g.DrawEllipse(pen, R(1.5f, 1.5f, 13, 13));
                g.DrawLine(pen, Pt(8, 4.5f), Pt(8, 8.5f));
                g.DrawLine(pen, Pt(8, 8.5f), Pt(10.8f, 10.2f));
                break;

            case NavIcon.Stats:
                // three bars
                g.DrawLine(pen, Pt(3.5f, 13.5f), Pt(3.5f, 9f));
                g.DrawLine(pen, Pt(8f,   13.5f), Pt(8f,   3f));
                g.DrawLine(pen, Pt(12.5f,13.5f), Pt(12.5f,6.5f));
                break;

            case NavIcon.Friends:
                // two people
                g.DrawEllipse(pen, R(3.5f, 2.5f, 5, 5));
                g.DrawArc(pen, R(1f, 9f, 10, 9), 180, 180);
                g.DrawArc(pen, R(9.5f, 3f, 4.5f, 4.5f), -70, 220);
                g.DrawArc(pen, R(8f, 9.5f, 7.5f, 8), 250, 110);
                break;

            case NavIcon.Settings:
                // sliders
                for (int i = 0; i < 3; i++)
                {
                    float y = 3.5f + i * 4.5f;
                    g.DrawLine(pen, Pt(2, y), Pt(14, y));
                    float kx = i == 1 ? 5f : (i == 0 ? 10f : 7f);
                    g.FillEllipse(brush, R(kx - 1.6f, y - 1.6f, 3.2f, 3.2f));
                }
                break;

            case NavIcon.Normalization:
                // text lines with a leading "edit" tick
                g.DrawLine(pen, Pt(2, 4),  Pt(14, 4));
                g.DrawLine(pen, Pt(2, 8),  Pt(10, 8));
                g.DrawLine(pen, Pt(2, 12), Pt(12, 12));
                break;

            case NavIcon.About:
                g.DrawEllipse(pen, R(1.5f, 1.5f, 13, 13));
                g.DrawLine(pen, Pt(8, 7.2f), Pt(8, 11.5f));
                g.FillEllipse(brush, R(7.1f, 4.1f, 1.8f, 1.8f));
                break;
        }

        (g.SmoothingMode, g.PixelOffsetMode) = old;
    }

    /// <summary>
    /// Caption-button glyphs the way DWM draws them: 10 logical px, 1 px strokes,
    /// pixel-snapped so the lines don't blur at 100 % scaling.
    /// </summary>
    public static void DrawCaption(Graphics g, CaptionGlyph glyph, Rectangle bounds, Color color, float scale)
    {
        int size = (int)Math.Round(10 * scale);
        int pw   = Math.Max(1, (int)Math.Round(scale));
        int x    = bounds.X + (bounds.Width  - size) / 2;
        int y    = bounds.Y + (bounds.Height - size) / 2;

        using var pen = new Pen(color, pw);

        switch (glyph)
        {
            case CaptionGlyph.Minimize:
                g.SmoothingMode = SmoothingMode.None;
                int my = bounds.Y + bounds.Height / 2;
                g.DrawLine(pen, x, my, x + size, my);
                break;

            case CaptionGlyph.Maximize:
                g.SmoothingMode = SmoothingMode.None;
                g.DrawRectangle(pen, x, y, size - pw, size - pw);
                break;

            case CaptionGlyph.Restore:
                g.SmoothingMode = SmoothingMode.None;
                int off = (int)Math.Round(2 * scale);
                int inner = size - off;
                // back window (top-right), only its visible edges
                g.DrawLine(pen, x + off, y,            x + size - pw, y);
                g.DrawLine(pen, x + size - pw, y,      x + size - pw, y + inner - pw);
                g.DrawLine(pen, x + off, y,            x + off, y + off);
                g.DrawLine(pen, x + inner, y + inner - pw, x + size - pw, y + inner - pw);
                // front window
                g.DrawRectangle(pen, x, y + off, inner - pw, inner - pw);
                break;

            case CaptionGlyph.Close:
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.DrawLine(pen, x, y, x + size, y + size);
                g.DrawLine(pen, x + size, y, x, y + size);
                break;
        }
    }

    /// <summary>Filled heart (GitHub Sponsors style) fitted into <paramref name="r"/>.</summary>
    public static void DrawHeart(Graphics g, RectangleF r, Color color)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = new GraphicsPath();
        float w = r.Width, h = r.Height, x = r.X, y = r.Y;
        path.StartFigure();
        path.AddBezier(x + w / 2, y + h * 0.95f,
                       x - w * 0.15f, y + h * 0.55f,
                       x + w * 0.05f, y - h * 0.05f,
                       x + w / 2, y + h * 0.28f);
        path.AddBezier(x + w / 2, y + h * 0.28f,
                       x + w * 0.95f, y - h * 0.05f,
                       x + w * 1.15f, y + h * 0.55f,
                       x + w / 2, y + h * 0.95f);
        path.CloseFigure();
        using var brush = new SolidBrush(color);
        g.FillPath(brush, path);
    }
}
