# CloudOS Files & Storage V5 — Native architecture research

## Mission

Files V5 turns `Arquivos` into a first-party CloudOS native application without pretending that CloudOS should reimplement every Windows Shell namespace feature.

The architectural split is deliberate:

- **CloudOS owns the application chrome**: tabs, Quick Access, search, preview, operation orchestration, CloudOS Drive safety policy, persistence and status.
- **Windows Shell owns Windows namespace rendering** through `IExplorerBrowser` / `IFolderView2` when that is the platform-correct integration.
- **CloudOS Drive owns its private filesystem policy** and never treats arbitrary reparse points as trusted directories.
- **External applications remain normal Windows top-level processes**; Files does not reparent them.

## Existing baseline

Before V5 the repository already contains:

- `CloudOSNativeFilesWindow` with Windows, CloudOS Drive and fallback filesystem modes;
- `NativeShellViewHost` built on `IExplorerBrowser`;
- `IFileOperationProgressSink` based copy/move operations;
- ZIP create/extract support through the Windows `tar.exe` implementation;
- CloudOS Drive trash and reparse-point guards;
- desktop OLE `IDropTarget` support.

However the public application id `files` still launches `explorer.exe`, so the native Files implementation is not the primary user path. V5 changes that first.

## Official Windows API findings

### IExplorerBrowser

`IExplorerBrowser::Initialize` hosts the Windows Shell browser inside a caller-owned HWND. The caller must eventually invoke `Destroy`.

`IExplorerBrowser::Advise` connects an `IExplorerBrowserEvents` listener before navigation. Navigation callbacks provide a clean boundary for CloudOS to update its own address bar, tab state, persistence and preview state.

V5 keeps this model for ordinary Windows namespace paths. It is more compatible than implementing a fake Explorer view and preserves Shell context menus, providers, icons and namespace extensions.

### Shell selection

The current browser view can be queried as `IFolderView2`. V5 will expose selected `IShellItem` filesystem/parsing paths to CloudOS chrome so preview/details/actions can work while Windows still owns the view itself.

### Context menus

The Windows Shell exposes `IContextMenu::QueryContextMenu` and `IContextMenu::InvokeCommand` for Shell items. Embedded `IExplorerBrowser` already owns the normal Shell view context menu. CloudOS only needs a dedicated context menu for its custom CloudOS Drive/fallback view and for CloudOS-specific commands outside the Shell surface.

### OLE drag and drop

`DoDragDrop` requires an `IDataObject` and `IDropSource`; `RegisterDragDrop` registers one HWND with an `IDropTarget`. OLE must be initialized with `OleInitialize` on the message-pumping thread.

The V5 custom view may add its own source/target layer, but the embedded Shell view must not be wrapped with a fake drag implementation because ExplorerBrowser already implements standard Shell drag/drop.

### Windows Imaging Component

WIC provides `IWICImagingFactory::CreateDecoderFromFilename` and frame decoding without loading arbitrary codec logic into CloudOS itself. The V5 first-party preview pane will use WIC for image formats supported by installed Windows codecs, with bounded decode dimensions.

Text preview is bounded by byte count and never executes content.

### IPreviewHandler

Windows preview handlers expose `SetWindow`, `SetRect`, `DoPreview` and `Unload`. They can provide richer previews but they are extension code with a more complex lifecycle. V5 does not make arbitrary third-party preview handlers a requirement for the first cut; first-party WIC/text/metadata previews are the safe baseline.

### Windows Search

`ISearchQueryHelper::GenerateSQLFromUserQuery` converts AQS/NQS input to Windows Search SQL and can obtain the SystemIndex connection string. This is suitable for a later indexed-search provider.

The first V5 cut uses a bounded, cancelable filesystem search provider for predictable behavior across CloudOS Drive and non-indexed locations. It skips reparse-point recursion and caps results/depth. An indexed provider can be added without changing the search-window contract.

## V5 pillars

### 1. First-party launcher cutover

`NativeAppLauncher::LaunchById(L"files")` opens `CloudOSNativeFilesWindow`.

Windows Explorer remains a valid external application and Windows namespace provider, but it is no longer the CloudOS Files application implementation.

### 2. Tabs

A Files HWND owns multiple path tabs.

Each tab stores only safe navigation state:

- path;
- display title;
- back stack;
- forward stack.

Tabs do not persist process handles or arbitrary executable state.

### 3. Quick Access

Quick Access stores user-pinned directories alongside built-in known folders. Persistence is under `%LOCALAPPDATA%\CloudOS\FilesV5` using an atomic temporary-file replacement.

Invalid or missing paths are displayed conservatively or pruned only when explicitly requested; Files never silently follows a reparse point in CloudOS Drive.

### 4. Search

A dedicated native search window owns a worker thread and cancellation flag.

Safety rules:

- bounded maximum results;
- bounded recursion depth;
- skip directory reparse-point recursion;
- no execution while indexing/searching;
- worker joined during teardown;
- result delivery is by owned message payload, never borrowed stack pointers.

### 5. Preview/details

The preview pane is CloudOS-owned.

First-party providers:

- directories: folder metadata;
- images: WIC decode, scaled to a bounded surface;
- text/code/log/config: bounded read-only Unicode/UTF-8 preview;
- other files: icon, size, timestamps, extension and canonical path metadata.

Selecting a Shell item queries the current `IFolderView2`; selecting a custom item uses the existing `Entry` model.

### 6. Operations integration

Files V5 surfaces the existing operations engine from the main toolbar/context menu with selected sources pre-populated.

Copy/move remain `IFileOperation` based. ZIP/extract remain explicit external `tar.exe` child operations with progress/cancel UI; the Shell never claims an archive succeeded until the child reports success.

### 7. CloudOS Drive safety

CloudOS Drive custom operations continue to reject unsafe leaf names and reparse-point traversal.

Search and preview may read canonical ordinary files, but must not recursively traverse a CloudOS Drive reparse directory.

### 8. Persistence

Only declarative UX state is persisted:

- favorite paths;
- last tabs;
- active tab;
- preview pane visibility.

Writes are versioned, size-bounded and atomic.

## Explicit non-goals

V5 does not:

- replace the Windows filesystem driver;
- emulate Explorer shell extensions with HTML;
- capture or reparent arbitrary external windows;
- execute previewed content;
- traverse CloudOS Drive junctions/symlinks as trusted folders;
- require Windows Search indexing to function;
- enable Shell Launcher/WESL.

## Validation gates

Before promotion:

1. `files` launcher is first-party and contract-protected;
2. tabs and persisted state are bounded/versioned;
3. Shell mode remains `IExplorerBrowser` backed;
4. search cancellation and reparse guards are contract-protected;
5. preview has bounded read/decode paths;
6. CloudOS Drive safety rules remain intact;
7. no new universal `SetParent` or remote-process injection path appears;
8. MSVC Release x64 builds with `/W4 /WX`;
9. CloudOS native provenance/package pipeline passes;
10. repository baseline remains green.
