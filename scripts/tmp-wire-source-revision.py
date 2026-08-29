from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Launcher: bind the frontend build and Host build/start to the same checkout SHA.
launcher_path = Path('scripts/launch/start-cloudos.ps1')
launcher = launcher_path.read_text(encoding='utf-8').replace('\r\n', '\n')
launcher = replace_once(
    launcher,
    '    }    $hostPid = 0\n',
    '    }\n    $hostPid = 0\n',
    'launcher-formatting'
)
launcher = replace_once(
    launcher,
    "Start-Process -FilePath $hostExe -ArgumentList @('--root', $script:CloudOSRoot) -WindowStyle Hidden",
    "Start-Process -FilePath $hostExe -ArgumentList @('--root', $script:CloudOSRoot, '--expected-source-revision', [string]$currentCheckout.sha) -WindowStyle Hidden",
    'existing-host-signal-revision'
)
launcher = replace_once(
    launcher,
    "    $env:CLOUDOS_SESSION_LOG_DIR = [string]$session.logDirectory\n",
    "    $env:CLOUDOS_SESSION_LOG_DIR = [string]$session.logDirectory\n"
    "    $sourceRevision = ([string]$session.git.sha).Trim().ToLowerInvariant()\n"
    "    if ($sourceRevision -notmatch '^[a-f0-9]{40}$') { throw \"SOURCE_REVISION_INVALID:$sourceRevision\" }\n"
    "    $env:VITE_CLOUDOS_SOURCE_REVISION = $sourceRevision\n",
    'launcher-source-revision'
)
launcher = replace_once(
    launcher,
    "-Arguments @('build',$hostProject,'-c','Release','--no-restore','--nologo','--verbosity','minimal')",
    "-Arguments @('build',$hostProject,'-c','Release','--no-restore','--nologo','--verbosity','minimal',\"-p:CloudOSSourceRevision=$sourceRevision\")",
    'host-build-revision'
)
launcher = replace_once(
    launcher,
    "$hostArgs = @('--root',$script:CloudOSRoot,'--bootstrap-pipe',$bootstrapPipe.name)\n",
    "$hostArgs = @('--root',$script:CloudOSRoot,'--bootstrap-pipe',$bootstrapPipe.name,'--expected-source-revision',$sourceRevision)\n",
    'host-start-revision'
)
launcher = replace_once(
    launcher,
    "                hostRuntimePid=$hostRuntime.Id\n                shellWindowReady=$true\n",
    "                hostRuntimePid=$hostRuntime.Id\n                sourceRevision=$sourceRevision\n                shellWindowReady=$true\n",
    'readiness-revision'
)
launcher_path.write_text(launcher, encoding='utf-8')

# Host handshake state exposes the compiled revision.
main_path = Path('desktop/CloudOS.Host/MainWindow.xaml.cs')
main = main_path.read_text(encoding='utf-8')
main = replace_once(
    main,
    '        platform = "windows",\n        version = typeof(MainWindow).Assembly.GetName().Version?.ToString() ?? "1.0.0"\n',
    '        platform = "windows",\n        sourceRevision = CloudOsBuildIdentity.SourceRevision,\n        version = typeof(MainWindow).Assembly.GetName().Version?.ToString() ?? "1.0.0"\n',
    'host-state-revision'
)
main_path.write_text(main, encoding='utf-8')

# Frontend refuses a Host compiled from another checkout when production build identity exists.
bridge_path = Path('frontend/src/services/nativeHostBridge.ts')
bridge = bridge_path.read_text(encoding='utf-8')
bridge = replace_once(
    bridge,
    '  platform: string;\n  version: string;\n',
    '  platform: string;\n  sourceRevision?: string;\n  version: string;\n',
    'frontend-host-state-type'
)
bridge = replace_once(
    bridge,
    "}\n\nfunction snapshotSessions(sessions: NativeSession[]) {\n",
    "}\n\nconst EXPECTED_SOURCE_REVISION = String(import.meta.env.VITE_CLOUDOS_SOURCE_REVISION || '').trim().toLowerCase();\n\nfunction snapshotSessions(sessions: NativeSession[]) {\n",
    'frontend-expected-revision'
)
old_connect = """    const connection = this.request('bridge.handshake', {})
      .then(() => {
        this.ready = true;
        return true;
      })
"""
new_connect = """    const connection = this.request<{ protocol: number; host: NativeHostState }>('bridge.handshake', {})
      .then((handshake) => {
        if (/^[a-f0-9]{40}$/.test(EXPECTED_SOURCE_REVISION)) {
          const hostRevision = String(handshake?.host?.sourceRevision || '').trim().toLowerCase();
          if (hostRevision !== EXPECTED_SOURCE_REVISION) {
            throw new NativeHostError(
              'STALE_NATIVE_HOST',
              `O Host nativo pertence a outra revisão do CloudOS (esperado ${EXPECTED_SOURCE_REVISION}, recebido ${hostRevision || 'ausente'}).`
            );
          }
        }
        this.ready = true;
        return true;
      })
"""
bridge = replace_once(bridge, old_connect, new_connect, 'frontend-handshake-revision')
bridge_path.write_text(bridge, encoding='utf-8')

# Host contract project links build identity helper.
test_project_path = Path('desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj')
test_project = test_project_path.read_text(encoding='utf-8')
test_project = replace_once(
    test_project,
    '    <Compile Include="..\\CloudOS.Host\\Native\\NativeLaunchContainmentPolicy.cs" Link="Native\\NativeLaunchContainmentPolicy.cs" />\n',
    '    <Compile Include="..\\CloudOS.Host\\Native\\NativeLaunchContainmentPolicy.cs" Link="Native\\NativeLaunchContainmentPolicy.cs" />\n'
    '    <Compile Include="..\\CloudOS.Host\\Runtime\\CloudOsBuildIdentity.cs" Link="Runtime\\CloudOsBuildIdentity.cs" />\n',
    'host-test-build-identity-link'
)
test_project_path.write_text(test_project, encoding='utf-8')

# Pure contract test for revision matching rules.
program_path = Path('desktop/CloudOS.Host.Tests/Program.cs')
program = program_path.read_text(encoding='utf-8')
program = replace_once(
    program,
    'using CloudOS.Host.Native;\nusing CloudOS.Host.Security;\n',
    'using CloudOS.Host.Native;\nusing CloudOS.Host.Runtime;\nusing CloudOS.Host.Security;\n',
    'host-test-runtime-using'
)
program = replace_once(
    program,
    '    ("native launch accepts only direct host descriptors", NativeLaunchAcceptsOnlyDirectDescriptors),\n',
    '    ("compiled Host revision requires exact source identity", CompiledHostRevisionRequiresExactIdentity),\n'
    '    ("native launch accepts only direct host descriptors", NativeLaunchAcceptsOnlyDirectDescriptors),\n',
    'host-test-list-build-identity'
)
method = """static void CompiledHostRevisionRequiresExactIdentity()
{
    var revisionA = new string('a', 40);
    var revisionB = new string('b', 40);
    Assert(CloudOsBuildIdentity.MatchesExpected(revisionA, revisionA), "Equal source revisions must match.");
    Assert(CloudOsBuildIdentity.MatchesExpected(revisionA.ToUpperInvariant(), revisionA), "Revision normalization must be case-insensitive.");
    Assert(!CloudOsBuildIdentity.MatchesExpected(revisionA, revisionB), "Different revisions must never match.");
    Assert(!CloudOsBuildIdentity.MatchesExpected("unknown", revisionA), "A Host without compiled identity must fail closed when an expected revision exists.");
    Assert(!CloudOsBuildIdentity.MatchesExpected(revisionA, "abc123"), "Malformed expected revisions must fail closed.");
}

"""
program = replace_once(
    program,
    'static void NativeLaunchAcceptsOnlyDirectDescriptors()\n',
    method + 'static void NativeLaunchAcceptsOnlyDirectDescriptors()\n',
    'host-test-method-build-identity'
)
program_path.write_text(program, encoding='utf-8')
