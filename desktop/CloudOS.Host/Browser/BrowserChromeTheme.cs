namespace CloudOS.Host.Browser;

public enum BrowserThemeMode
{
    System,
    Light,
    Dark
}

public sealed record BrowserChromePalette(
    bool IsLight,
    string Window,
    string Chrome,
    string Surface,
    string SurfaceAlt,
    string SurfaceHover,
    string SurfacePressed,
    string ActiveTab,
    string InactiveTab,
    string Border,
    string TextPrimary,
    string TextSecondary,
    string TextMuted,
    string Accent,
    string AccentHover,
    string Danger,
    string Success,
    string Input,
    string Selection);

public static class BrowserChromeTheme
{
    public static BrowserChromePalette Resolve(BrowserThemeMode mode, bool systemIsLight)
    {
        var light = mode == BrowserThemeMode.Light || (mode == BrowserThemeMode.System && systemIsLight);
        return light ? Light : Dark;
    }

    public static BrowserChromePalette Dark { get; } = new(
        IsLight: false,
        Window: "#171A1F",
        Chrome: "#20242B",
        Surface: "#2A3038",
        SurfaceAlt: "#252A31",
        SurfaceHover: "#343B45",
        SurfacePressed: "#3E4652",
        ActiveTab: "#252A31",
        InactiveTab: "#20242B",
        Border: "#3A424D",
        TextPrimary: "#F3F5F7",
        TextSecondary: "#C7CDD5",
        TextMuted: "#9099A6",
        Accent: "#4C8DFF",
        AccentHover: "#6EA4FF",
        Danger: "#FF6D7D",
        Success: "#55D69E",
        Input: "#171B21",
        Selection: "#5B8DEF");

    public static BrowserChromePalette Light { get; } = new(
        IsLight: true,
        Window: "#F7F8FA",
        Chrome: "#E7E9ED",
        Surface: "#FFFFFF",
        SurfaceAlt: "#FFFFFF",
        SurfaceHover: "#EEF1F5",
        SurfacePressed: "#E1E6EC",
        ActiveTab: "#FFFFFF",
        InactiveTab: "#E7E9ED",
        Border: "#D4D9E0",
        TextPrimary: "#20242A",
        TextSecondary: "#4F5965",
        TextMuted: "#778290",
        Accent: "#2563EB",
        AccentHover: "#1D4ED8",
        Danger: "#D9465F",
        Success: "#16865A",
        Input: "#F1F3F5",
        Selection: "#7FA7F5");
}
