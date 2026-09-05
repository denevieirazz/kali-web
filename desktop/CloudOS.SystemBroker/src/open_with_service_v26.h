#pragma once

#include "protocol_v21.h"

#include <string>
#include <vector>

namespace CloudOS
{

struct FileAssociationV26 final
{
    std::string extension;
    std::string default_app_id;
    std::string friendly_name;
    std::vector<std::string> candidate_apps;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class OpenWithServiceV26 final
{
public:
    static OpenWithServiceV26& Instance();

    OpenWithServiceV26(const OpenWithServiceV26&) = delete;
    OpenWithServiceV26& operator=(const OpenWithServiceV26&) = delete;

    [[nodiscard]] std::vector<FileAssociationV26> GetAssociations() const;
    [[nodiscard]] std::string GetDefaultApp(const std::string& extension) const;
    bool SetDefaultApp(const std::string& extension, const std::string& app_id);

    bool OpenFile(
        const std::string& path,
        const std::string& preferred_app_id = "",
        std::string* error = nullptr);

    bool ShowOpenWithDialog(const std::string& path, std::string* error = nullptr);

private:
    OpenWithServiceV26();
    ~OpenWithServiceV26() = default;

    void InitDefaultAssociations();

    std::vector<FileAssociationV26> associations_;
};

} // namespace CloudOS
