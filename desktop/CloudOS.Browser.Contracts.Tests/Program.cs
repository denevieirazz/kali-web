using System.Text.Json;
using CloudOS.Host.Browser;

var success = BrowserOpenResult.Success(reused: false, windowVisible: true);
using (var document = JsonDocument.Parse(JsonSerializer.Serialize(success)))
{
    var root = document.RootElement;
    Assert(root.GetProperty("opened").GetBoolean(), "opened deve ser true no sucesso.");
    Assert(!root.GetProperty("reused").GetBoolean(), "reused deve preservar false.");
    Assert(root.GetProperty("windowVisible").GetBoolean(), "windowVisible deve ser true antes da resposta da bridge.");
    Assert(!root.TryGetProperty("code", out _), "Sucesso não deve serializar code.");
    Assert(!root.TryGetProperty("message", out _), "Sucesso não deve serializar message.");
}

var failure = BrowserOpenResult.Failure("BROWSER_WINDOW_CREATE_FAILED", "Falha sanitizada.");
using (var document = JsonDocument.Parse(JsonSerializer.Serialize(failure)))
{
    var root = document.RootElement;
    Assert(!root.GetProperty("opened").GetBoolean(), "opened deve ser false na falha.");
    Assert(root.GetProperty("code").GetString() == "BROWSER_WINDOW_CREATE_FAILED", "code deve ser preservado.");
    Assert(root.GetProperty("message").GetString() == "Falha sanitizada.", "message deve ser preservada.");
    Assert(!root.TryGetProperty("reused", out _), "Falha não deve inventar reused.");
    Assert(!root.TryGetProperty("windowVisible", out _), "Falha não deve inventar windowVisible.");
}

Console.WriteLine("PASS browser.open JSON contract");

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
