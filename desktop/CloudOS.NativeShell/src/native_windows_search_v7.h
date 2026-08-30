#pragma once

#include <windows.h>
#include <msdasc.h>
#include <oledb.h>
#include <searchapi.h>

#include <algorithm>
#include <cstddef>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "SearchSDK.lib")
#pragma comment(lib, "uuid.lib")

namespace CloudOS
{
struct NativeSearchIndexResultV7 final
{
    std::wstring name;
    std::wstring path;
    std::wstring url;
};

class NativeWindowsSearchV7 final
{
public:
    // Queries the Windows Search SystemIndex instead of recursively walking
    // disks. The service is intentionally synchronous at this boundary; Start
    // invokes it from a worker so its UI thread remains latency-safe.
    static std::vector<NativeSearchIndexResultV7> Query(
        const std::wstring& user_query,
        std::size_t maximum_results = 80u)
    {
        std::vector<NativeSearchIndexResultV7> results;
        if (user_query.empty() || maximum_results == 0u) return results;
        maximum_results = std::min<std::size_t>(maximum_results, 256u);

        ISearchManager* search_manager = nullptr;
        HRESULT hr = CoCreateInstance(
            CLSID_CSearchManager,
            nullptr,
            CLSCTX_LOCAL_SERVER,
            IID_PPV_ARGS(&search_manager));
        if (FAILED(hr) || search_manager == nullptr) return results;

        ISearchCatalogManager* catalog = nullptr;
        hr = search_manager->GetCatalog(L"SystemIndex", &catalog);
        search_manager->Release();
        if (FAILED(hr) || catalog == nullptr) return results;

        ISearchQueryHelper* helper = nullptr;
        hr = catalog->GetQueryHelper(&helper);
        catalog->Release();
        if (FAILED(hr) || helper == nullptr) return results;

        (void)helper->put_QuerySelectColumns(
            L"System.ItemName,System.ItemPathDisplay,System.ItemUrl");
        (void)helper->put_QueryMaxResults(static_cast<LONG>(maximum_results));

        LPWSTR sql = nullptr;
        LPWSTR connection_string = nullptr;
        hr = helper->GenerateSQLFromUserQuery(user_query.c_str(), &sql);
        if (SUCCEEDED(hr)) hr = helper->get_ConnectionString(&connection_string);
        helper->Release();
        if (FAILED(hr) || sql == nullptr || connection_string == nullptr)
        {
            if (sql != nullptr) CoTaskMemFree(sql);
            if (connection_string != nullptr) CoTaskMemFree(connection_string);
            return results;
        }

        // IDataInitialize and the OLE DB interfaces are COM contracts. They are
        // activated through CoCreateInstance; no separate OLE DB import library is
        // required (and current Windows SDK runners do not ship OLE DB stub libs).
        IDataInitialize* data_initialize = nullptr;
        hr = CoCreateInstance(
            CLSID_MSDAINITIALIZE,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&data_initialize));
        if (FAILED(hr) || data_initialize == nullptr)
        {
            CoTaskMemFree(sql);
            CoTaskMemFree(connection_string);
            return results;
        }

        IDBInitialize* database = nullptr;
        hr = data_initialize->GetDataSource(
            nullptr,
            CLSCTX_INPROC_SERVER,
            connection_string,
            IID_IDBInitialize,
            reinterpret_cast<IUnknown**>(&database));
        data_initialize->Release();
        CoTaskMemFree(connection_string);
        if (FAILED(hr) || database == nullptr)
        {
            CoTaskMemFree(sql);
            return results;
        }

        hr = database->Initialize();
        if (FAILED(hr))
        {
            database->Release();
            CoTaskMemFree(sql);
            return results;
        }

        IDBCreateSession* session_factory = nullptr;
        hr = database->QueryInterface(IID_PPV_ARGS(&session_factory));
        if (FAILED(hr) || session_factory == nullptr)
        {
            database->Uninitialize();
            database->Release();
            CoTaskMemFree(sql);
            return results;
        }

        IDBCreateCommand* command_factory = nullptr;
        hr = session_factory->CreateSession(
            nullptr,
            IID_IDBCreateCommand,
            reinterpret_cast<IUnknown**>(&command_factory));
        session_factory->Release();
        if (FAILED(hr) || command_factory == nullptr)
        {
            database->Uninitialize();
            database->Release();
            CoTaskMemFree(sql);
            return results;
        }

        ICommandText* command = nullptr;
        hr = command_factory->CreateCommand(
            nullptr,
            IID_ICommandText,
            reinterpret_cast<IUnknown**>(&command));
        command_factory->Release();
        if (FAILED(hr) || command == nullptr)
        {
            database->Uninitialize();
            database->Release();
            CoTaskMemFree(sql);
            return results;
        }

        hr = command->SetCommandText(DBGUID_DEFAULT, sql);
        CoTaskMemFree(sql);
        if (FAILED(hr))
        {
            command->Release();
            database->Uninitialize();
            database->Release();
            return results;
        }

        IRowset* rowset = nullptr;
        DBROWCOUNT affected_rows = 0;
        hr = command->Execute(
            nullptr,
            IID_IRowset,
            nullptr,
            &affected_rows,
            reinterpret_cast<IUnknown**>(&rowset));
        command->Release();
        if (FAILED(hr) || rowset == nullptr)
        {
            database->Uninitialize();
            database->Release();
            return results;
        }

        ReadRows(rowset, maximum_results, &results);
        rowset->Release();
        database->Uninitialize();
        database->Release();
        return results;
    }

private:
    struct BoundRow final
    {
        DBSTATUS name_status{};
        DBLENGTH name_length{};
        wchar_t name[512]{};
        DBSTATUS path_status{};
        DBLENGTH path_length{};
        wchar_t path[2048]{};
        DBSTATUS url_status{};
        DBLENGTH url_length{};
        wchar_t url[2048]{};
    };

    static bool StatusHasValue(DBSTATUS status) noexcept
    {
        return status == DBSTATUS_S_OK || status == DBSTATUS_S_TRUNCATED;
    }

    static void ConfigureBinding(
        DBBINDING* binding,
        DBORDINAL ordinal,
        DBBYTEOFFSET status_offset,
        DBBYTEOFFSET length_offset,
        DBBYTEOFFSET value_offset,
        DBLENGTH maximum_bytes)
    {
        if (binding == nullptr) return;
        *binding = {};
        binding->iOrdinal = ordinal;
        binding->obStatus = status_offset;
        binding->obLength = length_offset;
        binding->obValue = value_offset;
        binding->dwPart = DBPART_STATUS | DBPART_LENGTH | DBPART_VALUE;
        binding->dwMemOwner = DBMEMOWNER_CLIENTOWNED;
        binding->eParamIO = DBPARAMIO_NOTPARAM;
        binding->cbMaxLen = maximum_bytes;
        binding->wType = DBTYPE_WSTR;
    }

    static void ReadRows(
        IRowset* rowset,
        std::size_t maximum_results,
        std::vector<NativeSearchIndexResultV7>* output)
    {
        if (rowset == nullptr || output == nullptr) return;
        IAccessor* accessor = nullptr;
        if (FAILED(rowset->QueryInterface(IID_PPV_ARGS(&accessor))) || accessor == nullptr) return;

        DBBINDING bindings[3]{};
        ConfigureBinding(
            &bindings[0], 1,
            offsetof(BoundRow, name_status),
            offsetof(BoundRow, name_length),
            offsetof(BoundRow, name),
            sizeof(BoundRow::name));
        ConfigureBinding(
            &bindings[1], 2,
            offsetof(BoundRow, path_status),
            offsetof(BoundRow, path_length),
            offsetof(BoundRow, path),
            sizeof(BoundRow::path));
        ConfigureBinding(
            &bindings[2], 3,
            offsetof(BoundRow, url_status),
            offsetof(BoundRow, url_length),
            offsetof(BoundRow, url),
            sizeof(BoundRow::url));

        HACCESSOR row_accessor = DB_NULL_HACCESSOR;
        DBBINDSTATUS bind_status[3]{};
        const HRESULT create_result = accessor->CreateAccessor(
            DBACCESSOR_ROWDATA,
            3,
            bindings,
            sizeof(BoundRow),
            &row_accessor,
            bind_status);
        if (FAILED(create_result))
        {
            accessor->Release();
            return;
        }

        while (output->size() < maximum_results)
        {
            DBCOUNTITEM obtained = 0;
            HROW* rows = nullptr;
            const HRESULT next = rowset->GetNextRows(
                DB_NULL_HCHAPTER,
                0,
                1,
                &obtained,
                &rows);
            if (FAILED(next) || obtained == 0 || rows == nullptr)
            {
                if (rows != nullptr) CoTaskMemFree(rows);
                break;
            }

            BoundRow row{};
            if (SUCCEEDED(rowset->GetData(rows[0], row_accessor, &row)))
            {
                NativeSearchIndexResultV7 item{};
                if (StatusHasValue(row.name_status)) item.name = row.name;
                if (StatusHasValue(row.path_status)) item.path = row.path;
                if (StatusHasValue(row.url_status)) item.url = row.url;
                if (!item.name.empty() || !item.path.empty() || !item.url.empty())
                    output->push_back(std::move(item));
            }

            (void)rowset->ReleaseRows(obtained, rows, nullptr, nullptr, nullptr);
            CoTaskMemFree(rows);
        }

        (void)accessor->ReleaseAccessor(row_accessor, nullptr);
        accessor->Release();
    }
};
} // namespace CloudOS
