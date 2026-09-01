#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace CloudOS
{

constexpr int kProtocolVersion = 21;
constexpr uint32_t kMaxPayloadBytes = 1048576; // 1 MiB

// Minimal typed JSON value
struct JsonValue;
using JsonObject = std::map<std::string, JsonValue>;
using JsonArray = std::vector<JsonValue>;

struct JsonValue final
{
    using ValueType = std::variant<
        std::nullptr_t,
        bool,
        int64_t,
        double,
        std::string,
        JsonObject,
        JsonArray>;

    ValueType value;

    JsonValue() : value(nullptr) {}
    JsonValue(std::nullptr_t) : value(nullptr) {}
    JsonValue(bool b) : value(b) {}
    JsonValue(int i) : value(static_cast<int64_t>(i)) {}
    JsonValue(int64_t i) : value(i) {}
    JsonValue(double d) : value(d) {}
    JsonValue(const char* s) : value(std::string(s ? s : "")) {}
    JsonValue(std::string s) : value(std::move(s)) {}
    JsonValue(JsonObject o) : value(std::move(o)) {}
    JsonValue(JsonArray a) : value(std::move(a)) {}

    [[nodiscard]] bool IsNull() const noexcept { return std::holds_alternative<std::nullptr_t>(value); }
    [[nodiscard]] bool IsBool() const noexcept { return std::holds_alternative<bool>(value); }
    [[nodiscard]] bool IsInt() const noexcept { return std::holds_alternative<int64_t>(value); }
    [[nodiscard]] bool IsDouble() const noexcept { return std::holds_alternative<double>(value) || std::holds_alternative<int64_t>(value); }
    [[nodiscard]] bool IsString() const noexcept { return std::holds_alternative<std::string>(value); }
    [[nodiscard]] bool IsObject() const noexcept { return std::holds_alternative<JsonObject>(value); }
    [[nodiscard]] bool IsArray() const noexcept { return std::holds_alternative<JsonArray>(value); }

    [[nodiscard]] bool AsBool(bool def = false) const noexcept {
        return IsBool() ? std::get<bool>(value) : def;
    }
    [[nodiscard]] int64_t AsInt(int64_t def = 0) const noexcept {
        return IsInt() ? std::get<int64_t>(value) : def;
    }
    [[nodiscard]] double AsDouble(double def = 0.0) const noexcept {
        if (std::holds_alternative<double>(value)) return std::get<double>(value);
        if (std::holds_alternative<int64_t>(value)) return static_cast<double>(std::get<int64_t>(value));
        return def;
    }
    [[nodiscard]] const std::string& AsString() const {
        static const std::string empty;
        return IsString() ? std::get<std::string>(value) : empty;
    }
    [[nodiscard]] const JsonObject& AsObject() const {
        static const JsonObject empty;
        return IsObject() ? std::get<JsonObject>(value) : empty;
    }
    [[nodiscard]] const JsonArray& AsArray() const {
        static const JsonArray empty;
        return IsArray() ? std::get<JsonArray>(value) : empty;
    }
};

std::string SerializeJson(const JsonValue& val);
bool ParseJson(const std::string& input, JsonValue& output);

struct BrokerRequest final
{
    int protocol{kProtocolVersion};
    std::string id;
    std::string method;
    JsonObject payload;
};

struct BrokerResponse final
{
    int protocol{kProtocolVersion};
    std::string id;
    bool ok{true};
    JsonObject payload;
    std::string error_code;
    std::string error_message;
};

struct BrokerEvent final
{
    int protocol{kProtocolVersion};
    std::string event;
    JsonObject payload;
    uint64_t timestamp_ms{0};
};

std::string SerializeRequest(const BrokerRequest& req);
std::string SerializeResponse(const BrokerResponse& res);
std::string SerializeEvent(const BrokerEvent& ev);

bool ParseRequest(const std::string& json_str, BrokerRequest& req, std::string& err);
bool ParseResponse(const std::string& json_str, BrokerResponse& res, std::string& err);
bool ParseEvent(const std::string& json_str, BrokerEvent& ev, std::string& err);

} // namespace CloudOS
