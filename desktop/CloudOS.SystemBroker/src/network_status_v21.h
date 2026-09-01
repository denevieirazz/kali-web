#pragma once

#include <string>

namespace CloudOS
{

struct NetworkStatusV21 final
{
    bool available{};
    std::string name;
    std::string transport;
};

class NetworkStatusServiceV21 final
{
public:
    static NetworkStatusV21 Query();
};

} // namespace CloudOS
