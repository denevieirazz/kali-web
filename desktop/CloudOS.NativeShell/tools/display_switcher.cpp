#include <windows.h>
#include <iostream>
#include <string>
#include <vector>

int wmain(int argc, wchar_t* argv[]) {
    if (argc < 2) {
        std::wcout << L"Usage: display_switcher <query|set|restore> [args...]\n";
        return 1;
    }

    std::wstring cmd = argv[1];
    if (cmd == L"ccd") {
        UINT32 numPaths = 0, numModes = 0;
        LONG hr = GetDisplayConfigBufferSizes(QDC_ALL_PATHS, &numPaths, &numModes);
        if (hr != ERROR_SUCCESS) {
            std::wcerr << L"GetDisplayConfigBufferSizes failed: " << hr << L"\n";
            return 1;
        }
        std::vector<DISPLAYCONFIG_PATH_INFO> paths(numPaths);
        std::vector<DISPLAYCONFIG_MODE_INFO> modes(numModes);
        hr = QueryDisplayConfig(QDC_ALL_PATHS, &numPaths, paths.data(), &numModes, modes.data(), NULL);
        if (hr != ERROR_SUCCESS) {
            std::wcerr << L"QueryDisplayConfig failed: " << hr << L"\n";
            return 2;
        }
        std::wcout << L"CCD Paths: " << numPaths << L", Modes: " << numModes << L"\n";
        for (UINT32 i = 0; i < numPaths; ++i) {
            if (paths[i].flags & DISPLAYCONFIG_PATH_ACTIVE) {
                int sIdx = paths[i].sourceInfo.modeInfoIdx;
                std::wcout << L"Active Path " << i << L": sourceModeIdx=" << sIdx;
                if (sIdx >= 0 && sIdx < (int)numModes && modes[sIdx].infoType == DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE) {
                    std::wcout << L" " << modes[sIdx].sourceMode.width << L"x" << modes[sIdx].sourceMode.height;
                }
                std::wcout << L"\n";
            }
        }
        return 0;
    }

    if (cmd == L"ccd-set") {
        if (argc < 4) {
            std::wcout << L"Usage: display_switcher ccd-set <width> <height> [pathIndex=0]\n";
            return 1;
        }
        DWORD targetW = std::stoul(argv[2]);
        DWORD targetH = std::stoul(argv[3]);
        UINT32 targetPath = (argc >= 5) ? std::stoul(argv[4]) : 0;

        UINT32 numPaths = 0, numModes = 0;
        LONG hr = GetDisplayConfigBufferSizes(QDC_ALL_PATHS, &numPaths, &numModes);
        if (hr != ERROR_SUCCESS) return 1;
        std::vector<DISPLAYCONFIG_PATH_INFO> paths(numPaths);
        std::vector<DISPLAYCONFIG_MODE_INFO> modes(numModes);
        hr = QueryDisplayConfig(QDC_ALL_PATHS, &numPaths, paths.data(), &numModes, modes.data(), NULL);
        if (hr != ERROR_SUCCESS) return 2;

        UINT32 activeCount = 0;
        int foundSourceIdx = -1;
        for (UINT32 i = 0; i < numPaths; ++i) {
            if (paths[i].flags & DISPLAYCONFIG_PATH_ACTIVE) {
                if (activeCount == targetPath) {
                    foundSourceIdx = paths[i].sourceInfo.modeInfoIdx;
                    break;
                }
                activeCount++;
            }
        }

        if (foundSourceIdx < 0 || foundSourceIdx >= (int)numModes) {
            std::wcerr << L"Active path " << targetPath << L" not found\n";
            return 3;
        }

        modes[foundSourceIdx].sourceMode.width = targetW;
        modes[foundSourceIdx].sourceMode.height = targetH;

        hr = SetDisplayConfig(numPaths, paths.data(), numModes, modes.data(),
                              SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES);
        std::wcout << L"SET_DISPLAY_CONFIG_RESULT " << hr << L"\n";
        return (hr == ERROR_SUCCESS) ? 0 : 4;
    }

    if (cmd == L"query") {
        std::wstring device = (argc >= 3) ? argv[2] : L"\\\\.\\DISPLAY6";
        DEVMODEW dm = {};
        dm.dmSize = sizeof(dm);
        if (EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &dm)) {
            std::wcout << L"CURRENT " << device << L" " << dm.dmPelsWidth << L"x" << dm.dmPelsHeight 
                       << L"@" << dm.dmDisplayFrequency << L"Hz (pos: " << dm.dmPosition.x << L"," << dm.dmPosition.y << L")\n";
            return 0;
        } else {
            std::wcerr << L"EnumDisplaySettings failed for " << device << L"\n";
            return 2;
        }
    }

    if (cmd == L"set") {
        if (argc < 5) {
            std::wcout << L"Usage: display_switcher set <device> <width> <height> [freq]\n";
            return 1;
        }
        std::wstring device = argv[2];
        DWORD width = std::stoul(argv[3]);
        DWORD height = std::stoul(argv[4]);
        DWORD freq = (argc >= 6) ? std::stoul(argv[5]) : 0;

        DEVMODEW currentDm = {};
        currentDm.dmSize = sizeof(currentDm);
        EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &currentDm);

        DEVMODEW dm = {};
        dm.dmSize = sizeof(dm);
        int modeIndex = -1;
        for (int i = 0; EnumDisplaySettingsW(device.c_str(), i, &dm); ++i) {
            if (dm.dmPelsWidth == width && dm.dmPelsHeight == height && (freq == 0 || dm.dmDisplayFrequency == freq)) {
                modeIndex = i;
                break;
            }
        }

        if (modeIndex == -1) {
            std::wcerr << L"Mode " << width << L"x" << height << L" not supported by driver on " << device << L"\n";
            return 2;
        }

        // Preserve monitor position in multi-monitor virtual desktop
        dm.dmPosition = currentDm.dmPosition;
        dm.dmFields |= DM_POSITION;

        // Step 1: Update registry for specific display device with CDS_NORESET
        LONG res1 = ChangeDisplaySettingsExW(device.c_str(), &dm, NULL, CDS_UPDATEREGISTRY | CDS_NORESET, NULL);
        if (res1 != DISP_CHANGE_SUCCESSFUL) {
            std::wcerr << L"Step 1 failed: " << res1 << L"\n";
            return 3;
        }
        // Step 2: Apply to all displays
        LONG res2 = ChangeDisplaySettingsExW(NULL, NULL, NULL, 0, NULL);
        std::wcout << L"CHANGE_RESULT " << res2 << L"\n";
        return (res2 == DISP_CHANGE_SUCCESSFUL) ? 0 : 4;
    }

    if (cmd == L"restore") {
        std::wstring device = (argc >= 3) ? argv[2] : L"\\\\.\\DISPLAY6";
        LONG res = ChangeDisplaySettingsExW(device.c_str(), NULL, NULL, 0, NULL);
        if (res != DISP_CHANGE_SUCCESSFUL) {
            res = ChangeDisplaySettingsExW(NULL, NULL, NULL, 0, NULL);
        }
        std::wcout << L"RESTORE_RESULT " << res << L"\n";
        return (res == DISP_CHANGE_SUCCESSFUL) ? 0 : 5;
    }

    return 0;
}
