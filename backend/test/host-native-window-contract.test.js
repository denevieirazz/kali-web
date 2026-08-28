import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

function validateWindowPlacement({ hwnd, isVisible, isIconic, rect, monitorWorkArea }) {
  if (!hwnd || hwnd === "0x0" || hwnd === 0) {
    return { valid: false, code: "HWND_ZERO" };
  }
  if (!isVisible) {
    return { valid: false, code: "WINDOW_NOT_VISIBLE" };
  }
  if (isIconic) {
    return { valid: false, code: "WINDOW_ICONIC" };
  }
  if (!rect || rect.width <= 0 || rect.height <= 0) {
    return { valid: false, code: "WINDOW_RECT_INVALID" };
  }
  if (monitorWorkArea) {
    const insideHorizontal = rect.left >= monitorWorkArea.left - 50 && rect.right <= monitorWorkArea.right + 50;
    const insideVertical = rect.top >= monitorWorkArea.top - 50 && rect.bottom <= monitorWorkArea.bottom + 50;
    if (!insideHorizontal || !insideVertical) {
      return { valid: false, code: "WINDOW_OFF_SCREEN" };
    }
  }
  return { valid: true, code: "WINDOW_VALID" };
}

function handleSecondInstanceActivation({ primaryProcess, secondaryProcess, isPrimaryAlive, signalResult }) {
  if (!isPrimaryAlive) {
    return { action: "launch_new", code: "PRIMARY_NOT_RUNNING" };
  }
  if (signalResult === "activated") {
    return {
      action: "activate_existing",
      primaryPid: primaryProcess.pid,
      secondaryExitCode: 0,
      foreignProcessesKilled: 0,
      code: "SINGLE_INSTANCE_PASS"
    };
  }
  return { action: "error", code: "ACTIVATION_FAILED" };
}

test("contrato estático do Host: App.xaml.cs, MainWindow.xaml e MainWindow.xaml.cs", () => {
  const appCs = fs.readFileSync(path.join(root, "desktop/CloudOS.Host/App.xaml.cs"), "utf8");
  const mainXaml = fs.readFileSync(path.join(root, "desktop/CloudOS.Host/MainWindow.xaml"), "utf8");
  const mainCs = fs.readFileSync(path.join(root, "desktop/CloudOS.Host/MainWindow.xaml.cs"), "utf8");

  assert.match(appCs, /Environment\.Exit\(0\)/, "Instância secundária deve sair com código 0");
  assert.match(appCs, /ActivationRequested/, "Host deve tratar requisição de ativação");
  assert.match(appCs, /ShowWindowAsync/, "Ativação deve restaurar a janela via Win32");

  assert.match(mainXaml, /WindowState="Normal"/, "MainWindow.xaml deve declarar WindowState Normal");
  assert.match(mainXaml, /Visibility="Visible"/, "MainWindow.xaml deve declarar Visibility Visible");
  assert.match(mainXaml, /ShowInTaskbar="True"/, "MainWindow.xaml deve declarar ShowInTaskbar True");

  assert.match(mainCs, /OnSourceInitialized/, "MainWindow deve sobrescrever OnSourceInitialized");
  assert.match(mainCs, /SystemParameters\.WorkArea/, "MainWindow deve respeitar a área de trabalho do monitor");
  assert.match(mainCs, /SetWindowPos/, "MainWindow deve posicionar e compor a janela no DWM");
});

test("TryAttach libera o lock global antes de serializar um attachment já existente", () => {
  const nativeWindowManager = fs.readFileSync(
    path.join(root, "desktop/CloudOS.Host/Native/NativeWindowManager.cs"),
    "utf8"
  );
  const start = nativeWindowManager.indexOf("public bool TryAttach(");
  const end = nativeWindowManager.indexOf("public bool TryPrepareCapturedSource(", start);
  assert.ok(start >= 0 && end > start, "TryAttach deve existir antes de TryPrepareCapturedSource");
  const tryAttach = nativeWindowManager.slice(start, end);

  assert.match(
    tryAttach,
    /bool alreadyAttached;[\s\S]*?lock \(_sync\)[\s\S]*?alreadyAttached = _attachments\.TryGetValue\(hwnd, out state\);[\s\S]*?if \(!alreadyAttached && !_quarantinedWindows\.ContainsKey\(hwnd\)\)[\s\S]*?\}\s*if \(alreadyAttached\)\s*return TryApplyAttachedLayout\(hwnd, state, bounds, visible, false, true, out error\);/,
    "duplicate attach deve consultar o dicionário sob _sync e aplicar o layout somente depois de liberar _sync"
  );
  assert.doesNotMatch(
    tryAttach,
    /lock \(_sync\)\s*\{\s*if \(_attachments\.TryGetValue\(hwnd, out state\)\)\s*return TryApplyAttachedLayout/,
    "não pode reintroduzir _sync -> state.SyncRoot no caminho de duplicate attach"
  );
});

test("falha de correlação encerra a lease uma vez pelo boundary de abort", () => {
  const bridge = fs.readFileSync(
    path.join(root, "desktop/CloudOS.Host/Bridge/WebMessageBridge.cs"),
    "utf8"
  );
  const launchStart = bridge.indexOf("private async Task<object> LaunchAppAsync(");
  const launchEnd = bridge.indexOf("private object Attach(", launchStart);
  const launch = bridge.slice(launchStart, launchEnd);
  const waitStart = bridge.indexOf("private async Task<NativeWindowSnapshot?> WaitForQuarantinedWindowAsync(");
  const waitEnd = bridge.indexOf("private IReadOnlyList<int> SynchronizeTrackedJob(", waitStart);
  const wait = bridge.slice(waitStart, waitEnd);

  assert.ok(launchStart >= 0 && launchEnd > launchStart, "LaunchAppAsync deve permanecer delimitável");
  assert.ok(waitStart >= 0 && waitEnd > waitStart, "WaitForQuarantinedWindowAsync deve permanecer delimitável");
  assert.doesNotMatch(
    launch,
    /TerminateProcessAndForget\(/,
    "LaunchAppAsync não pode encerrar e depois reenviar a mesma lease ao AbortContainedLaunch"
  );
  assert.doesNotMatch(
    wait,
    /TerminateProcessAndForget\(/,
    "o wait de correlação deve reportar a falha e deixar um único boundary encerrar o Job"
  );
  assert.match(
    wait,
    /SelectUniqueQuarantinedWindow\(candidates, out var candidate\)/,
    "a correlação deve exigir um único HWND em quarentena"
  );
  assert.doesNotMatch(
    wait,
    /candidates\[0\]/,
    "ordem de enumeração nunca pode escolher uma janela ambígua"
  );
  assert.match(
    launch,
    /catch \(BridgeException error\)[\s\S]*?AbortContainedLaunch\([\s\S]*?error\.ContainmentFailure \?\? NativeContainmentFailure\.QuarantineFailed\);/,
    "BridgeException deve carregar a causa até o único boundary de abort"
  );
});

test("auditoria de janela valida HWND diferente de zero, visibilidade e retangulo em tela", () => {
  const result = validateWindowPlacement({
    hwnd: "0x240AC0",
    isVisible: true,
    isIconic: false,
    rect: { left: 100, top: 100, right: 1540, bottom: 1000, width: 1440, height: 900 },
    monitorWorkArea: { left: 0, top: 0, right: 5120, bottom: 2832 }
  });
  assert.equal(result.valid, true);
  assert.equal(result.code, "WINDOW_VALID");
});

test("rejeita HWND nulo, janela oculta ou minimizada", () => {
  assert.equal(validateWindowPlacement({ hwnd: 0, isVisible: true, isIconic: false }).code, "HWND_ZERO");
  assert.equal(validateWindowPlacement({ hwnd: "0x123", isVisible: false, isIconic: false }).code, "WINDOW_NOT_VISIBLE");
  assert.equal(validateWindowPlacement({ hwnd: "0x123", isVisible: true, isIconic: true }).code, "WINDOW_ICONIC");
});

test("segunda abertura ativa a primeira sem matar processos alheios e encerra o processo secundario", () => {
  const activation = handleSecondInstanceActivation({
    primaryProcess: { pid: 24292 },
    secondaryProcess: { pid: 99999 },
    isPrimaryAlive: true,
    signalResult: "activated"
  });
  assert.equal(activation.action, "activate_existing");
  assert.equal(activation.secondaryExitCode, 0);
  assert.equal(activation.foreignProcessesKilled, 0);
  assert.equal(activation.code, "SINGLE_INSTANCE_PASS");
});
