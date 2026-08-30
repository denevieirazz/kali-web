# CloudOS Visual Platform V7 — integration checkpoint

This checkpoint intentionally advances the PR head after the first Windows/MSVC integration pass so GitHub regenerates the pull-request merge ref from the corrected tree.

## Corrections already present in the branch

- Bluetooth C++/WinRT enumeration uses `IVectorView::Size()` + `GetAt()` instead of relying on range-for iterator definitions.
- Shell context invocation uses `CMIC_MASK_UNICODE | CMIC_MASK_PTINVOKE` with `CMINVOKECOMMANDINFOEX`.
- Quick Settings media metadata uses the Win32 `SS_ENDELLIPSIS` static-control style.
- Visual Platform V7 contracts run before the Release x64 compile.

## Gate

Do not promote V7 until both CloudOS Native Full-System CI and CloudOS CI Baseline are green on the same head commit.
