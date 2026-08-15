using System.Globalization;
using System.Runtime.CompilerServices;
using CloudOS.Host.Browser;

internal static class BrowserChromeThemeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        var dark = BrowserChromeTheme.Resolve(BrowserThemeMode.Dark, systemIsLight: true);
        var light = BrowserChromeTheme.Resolve(BrowserThemeMode.Light, systemIsLight: false);
        var systemLight = BrowserChromeTheme.Resolve(BrowserThemeMode.System, systemIsLight: true);
        var systemDark = BrowserChromeTheme.Resolve(BrowserThemeMode.System, systemIsLight: false);

        Assert(!dark.IsLight, "dark mode resolves a dark palette");
        Assert(light.IsLight, "light mode resolves a light palette");
        Assert(systemLight == BrowserChromeTheme.Light, "system mode follows Windows light theme");
        Assert(systemDark == BrowserChromeTheme.Dark, "system mode follows Windows dark theme");
        Assert(dark.Window != light.Window && dark.Chrome != light.Chrome && dark.Input != light.Input,
            "light and dark chrome remain visually distinct");
        Assert(Contrast(dark.TextPrimary, dark.Window) >= 7.0,
            "dark primary text keeps strong contrast");
        Assert(Contrast(light.TextPrimary, light.Window) >= 7.0,
            "light primary text keeps strong contrast");
        Assert(Contrast(dark.TextSecondary, dark.Chrome) >= 4.5,
            "dark secondary chrome text meets WCAG AA contrast");
        Assert(Contrast(light.TextSecondary, light.Chrome) >= 4.5,
            "light secondary chrome text meets WCAG AA contrast");

        Console.WriteLine("PASS browser chrome theme palettes and contrast");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException($"FAIL {message}");
    }

    private static double Contrast(string foreground, string background)
    {
        var fg = Luminance(Parse(foreground));
        var bg = Luminance(Parse(background));
        var lighter = Math.Max(fg, bg);
        var darker = Math.Min(fg, bg);
        return (lighter + 0.05) / (darker + 0.05);
    }

    private static (double R, double G, double B) Parse(string hex)
    {
        var value = hex.TrimStart('#');
        if (value.Length != 6) throw new InvalidOperationException("Palette colors must use #RRGGBB.");
        return (
            int.Parse(value[..2], NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d,
            int.Parse(value[2..4], NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d,
            int.Parse(value[4..6], NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d);
    }

    private static double Luminance((double R, double G, double B) color) =>
        0.2126 * Linear(color.R) + 0.7152 * Linear(color.G) + 0.0722 * Linear(color.B);

    private static double Linear(double component) =>
        component <= 0.03928
            ? component / 12.92
            : Math.Pow((component + 0.055) / 1.055, 2.4);
}
