using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace CloudOS.Bootstrap;

internal sealed class BootstrapInstanceGuard : IDisposable
{
    private Mutex? _mutex;
    private bool _ownsMutex;

    public bool TryAcquire()
    {
        var sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sid)))[..20];
        _mutex = new Mutex(true, $"Local\\CloudOS.Bootstrap.{suffix}", out var createdNew);
        _ownsMutex = createdNew;
        return createdNew;
    }

    public void Dispose()
    {
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { }
        }
        _mutex?.Dispose();
    }
}
