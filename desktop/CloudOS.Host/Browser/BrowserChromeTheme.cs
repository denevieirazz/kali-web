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
    string Input);

public static class BrowserChromeTheme
{
    public static BrowserChromePalette Resolve(BrowserThemeMode mode, bool systemIsLight)
    {
        var light = mode == BrowserThemeMode.Light || (mode == BrowserThemeMode.System && systemIsLight);
        return light ? Light : Dark;
    }

    public static BrowserChromePalette Dark { get; } = new(
        IsLight: false,
        Window: "#08111F",
        Chrome: "#0D1726",
        Surface: "#142238",
        SurfaceAlt: "#101B2D",
        SurfaceHover: "#1B2C46",
        SurfacePressed: "#223653",
        ActiveTab: "#1A2A43",
        InactiveTab: "#0D1726",
        Border: "#263A56",
        TextPrimary: "#F5F7FB",
        TextSecondary: "#BAC8DA",
        TextMuted: "#8092A8",
        Accent: "#4C8DFF",
        AccentHover: "#6DA2FF",
        Danger: "#FF6B7A",
        Success: "#5FD39B",
        Input: "#0B1524");

    public static BrowserChromePalette Light { get; } = new(
        IsLight: true,
        Window: "#F2F5FA",
        Chrome: "#E8EEF7",
        Surface: "#FFFFFF",
        SurfaceAlt: "#F7F9FC",
        SurfaceHover: "#E1E9F4",
        SurfacePressed: "#D4E0EE",
        ActiveTab: "#FFFFFF",
        InactiveTab: "#E8EEF7",
        Border: "#C8D4E3",
        TextPrimary: "#182234",
        TextSecondary: "#4B5E75",
        TextMuted: "#6F8198",
        Accent: "#2563EB",
        AccentHover: "#1D4ED8",
        Danger: "#D9465F",
        Success: "#14865A",
        Input: "#FFFFFF");
}
