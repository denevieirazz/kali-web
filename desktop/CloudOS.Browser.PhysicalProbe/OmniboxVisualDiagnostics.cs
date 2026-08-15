using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CloudOS.Browser.PhysicalProbe;

internal static class OmniboxVisualDiagnostics
{
    internal const double ClipToleranceDip = 0.5;

    internal static OmniboxVisualReport Measure(TextBox box, string stage, bool requireCaret, bool requireSelection)
    {
        box.ApplyTemplate();
        box.UpdateLayout();

        var contentHost = box.Template.FindName("PART_ContentHost", box) as FrameworkElement
            ?? throw new InvalidOperationException($"{stage}: PART_ContentHost ausente.");
        contentHost.UpdateLayout();

        if (contentHost.ActualWidth <= 1 || contentHost.ActualHeight <= 1)
            throw new InvalidOperationException($"{stage}: viewport do texto sem dimensões.");

        var viewport = new Rect(0, 0, contentHost.ActualWidth, contentHost.ActualHeight);
        var boxToHost = box.TransformToVisual(contentHost);

        var textRectLocal = TextLayoutBounds(box);
        var textRect = boxToHost.TransformBounds(textRectLocal);
        EnsureInside(textRect, viewport, stage, "texto");

        var dpi = VisualTreeHelper.GetDpi(box);
        var formatted = new FormattedText(
            string.IsNullOrEmpty(box.Text) ? "Ag" : box.Text,
            CultureInfo.CurrentUICulture,
            box.FlowDirection,
            new Typeface(box.FontFamily, box.FontStyle, box.FontWeight, box.FontStretch),
            box.FontSize,
            box.Foreground,
            dpi.PixelsPerDip)
        {
            MaxLineCount = 1,
            Trimming = TextTrimming.None
        };

        if (textRect.Height + ClipToleranceDip < formatted.Height)
            throw new InvalidOperationException(
                $"{stage}: caixa de layout do texto ({textRect.Height:0.##}) menor que a altura formatada ({formatted.Height:0.##}).");

        Rect? caretRect = null;
        if (requireCaret)
        {
            if (!box.IsKeyboardFocusWithin)
                throw new InvalidOperationException($"{stage}: caret exigido sem foco de teclado.");

            var caretLocal = box.GetRectFromCharacterIndex(Math.Clamp(box.CaretIndex, 0, box.Text.Length), true);
            if (caretLocal.IsEmpty)
                throw new InvalidOperationException($"{stage}: bounds do caret ausentes.");

            var transformedCaret = boxToHost.TransformBounds(caretLocal);
            EnsureInside(transformedCaret, viewport, stage, "caret");
            if (box.CaretBrush is null || IsTransparent(box.CaretBrush))
                throw new InvalidOperationException($"{stage}: caret sem brush visível.");
            caretRect = transformedCaret;
        }

        Rect? selectionRect = null;
        if (requireSelection)
        {
            if (box.SelectionLength <= 0)
                throw new InvalidOperationException($"{stage}: seleção exigida mas vazia.");
            if (box.SelectionBrush is null || IsTransparent(box.SelectionBrush) || box.SelectionOpacity < 0.2)
                throw new InvalidOperationException($"{stage}: seleção sem brush/opacidade visível.");

            var selectionStart = box.SelectionStart;
            var selectionEnd = Math.Max(selectionStart, selectionStart + box.SelectionLength - 1);
            var first = box.GetRectFromCharacterIndex(selectionStart, false);
            var last = box.GetRectFromCharacterIndex(selectionEnd, true);
            if (first.IsEmpty || last.IsEmpty)
                throw new InvalidOperationException($"{stage}: bounds da seleção ausentes.");
            var unionLocal = Rect.Union(first, last);
            var transformedSelection = boxToHost.TransformBounds(unionLocal);
            EnsureInside(transformedSelection, viewport, stage, "seleção");
            selectionRect = transformedSelection;
        }

        return new OmniboxVisualReport(
            stage,
            Math.Round(box.ActualHeight, 2),
            Math.Round(contentHost.ActualHeight, 2),
            ToReport(viewport),
            ToReport(textRect),
            caretRect is null ? null : ToReport(caretRect.Value),
            selectionRect is null ? null : ToReport(selectionRect.Value),
            Math.Round(formatted.Height, 2),
            Math.Round(ClipToleranceDip, 2));
    }

    private static Rect TextLayoutBounds(TextBox box)
    {
        if (string.IsNullOrEmpty(box.Text))
        {
            var empty = box.GetRectFromCharacterIndex(0, true);
            if (empty.IsEmpty)
                throw new InvalidOperationException("omnibox: bounds de linha vazia ausentes.");
            return empty;
        }

        Rect? union = null;
        for (var index = 0; index < box.Text.Length; index++)
        {
            var rect = box.GetRectFromCharacterIndex(index, index == box.Text.Length - 1);
            if (rect.IsEmpty) continue;
            union = union is null ? rect : Rect.Union(union.Value, rect);
        }

        return union ?? throw new InvalidOperationException("omnibox: bounds de texto renderizado ausentes.");
    }

    private static void EnsureInside(Rect content, Rect viewport, string stage, string label)
    {
        if (content.IsEmpty)
            throw new InvalidOperationException($"{stage}: bounds de {label} vazios.");

        if (content.Top < viewport.Top - ClipToleranceDip)
            throw new InvalidOperationException(
                $"{stage}: {label} cortado no topo ({content.Top:0.##} < {viewport.Top:0.##}).");
        if (content.Bottom > viewport.Bottom + ClipToleranceDip)
            throw new InvalidOperationException(
                $"{stage}: {label} cortado embaixo ({content.Bottom:0.##} > {viewport.Bottom:0.##}).");
    }

    private static bool IsTransparent(System.Windows.Media.Brush brush) =>
        brush is SolidColorBrush solid && solid.Color.A == 0;

    private static RectReport ToReport(Rect rect) => new(
        Math.Round(rect.X, 2),
        Math.Round(rect.Y, 2),
        Math.Round(rect.Width, 2),
        Math.Round(rect.Height, 2));
}
