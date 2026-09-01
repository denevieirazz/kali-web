#include "protocol_v21.h"

#include <cerrno>
#include <charconv>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <limits>
#include <sstream>

namespace CloudOS
{

namespace
{
constexpr size_t kMaxJsonDepth = 64;
constexpr size_t kMaxJsonContainerItems = 65536;
constexpr size_t kMaxRequestIdLength = 256;
constexpr size_t kMaxMethodLength = 128;
constexpr size_t kMaxEventNameLength = 128;

void EscapeString(const std::string& str, std::string& out)
{
    out.push_back('"');
    for (char c : str)
    {
        switch (c)
        {
        case '"': out.append("\\\""); break;
        case '\\': out.append("\\\\"); break;
        case '\b': out.append("\\b"); break;
        case '\f': out.append("\\f"); break;
        case '\n': out.append("\\n"); break;
        case '\r': out.append("\\r"); break;
        case '\t': out.append("\\t"); break;
        default:
            if (static_cast<unsigned char>(c) < 0x20)
            {
                char hex[8];
                snprintf(hex, sizeof(hex), "\\u%04x", static_cast<unsigned char>(c));
                out.append(hex);
            }
            else
            {
                out.push_back(c);
            }
            break;
        }
    }
    out.push_back('"');
}

void SerializeValue(const JsonValue& val, std::string& out)
{
    if (val.IsNull())
    {
        out.append("null");
    }
    else if (val.IsBool())
    {
        out.append(val.AsBool() ? "true" : "false");
    }
    else if (val.IsInt())
    {
        out.append(std::to_string(val.AsInt()));
    }
    else if (val.IsDouble())
    {
        const double value = val.AsDouble();
        if (!std::isfinite(value))
        {
            out.append("null");
            return;
        }
        std::ostringstream ss;
        ss << std::setprecision(std::numeric_limits<double>::max_digits10) << value;
        out.append(ss.str());
    }
    else if (val.IsString())
    {
        EscapeString(val.AsString(), out);
    }
    else if (val.IsArray())
    {
        out.push_back('[');
        const auto& arr = val.AsArray();
        for (size_t i = 0; i < arr.size(); ++i)
        {
            if (i > 0) out.push_back(',');
            SerializeValue(arr[i], out);
        }
        out.push_back(']');
    }
    else if (val.IsObject())
    {
        out.push_back('{');
        const auto& obj = val.AsObject();
        size_t idx = 0;
        for (const auto& [k, v] : obj)
        {
            if (idx++ > 0) out.push_back(',');
            EscapeString(k, out);
            out.push_back(':');
            SerializeValue(v, out);
        }
        out.push_back('}');
    }
}

bool AppendUtf8CodePoint(uint32_t code_point, std::string& out)
{
    if (code_point > 0x10FFFF || (code_point >= 0xD800 && code_point <= 0xDFFF)) return false;
    if (code_point <= 0x7F)
    {
        out.push_back(static_cast<char>(code_point));
    }
    else if (code_point <= 0x7FF)
    {
        out.push_back(static_cast<char>(0xC0 | (code_point >> 6)));
        out.push_back(static_cast<char>(0x80 | (code_point & 0x3F)));
    }
    else if (code_point <= 0xFFFF)
    {
        out.push_back(static_cast<char>(0xE0 | (code_point >> 12)));
        out.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (code_point & 0x3F)));
    }
    else
    {
        out.push_back(static_cast<char>(0xF0 | (code_point >> 18)));
        out.push_back(static_cast<char>(0x80 | ((code_point >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (code_point & 0x3F)));
    }
    return true;
}

int HexDigit(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + c - 'a';
    if (c >= 'A' && c <= 'F') return 10 + c - 'A';
    return -1;
}

class JsonParser final
{
public:
    explicit JsonParser(const std::string& input) : src_(input), pos_(0) {}

    bool Parse(JsonValue& root)
    {
        SkipWhitespace();
        if (pos_ >= src_.size()) return false;
        if (!ParseValue(root, 0)) return false;
        SkipWhitespace();
        return pos_ == src_.size();
    }

private:
    void SkipWhitespace()
    {
        while (pos_ < src_.size() && (std::isspace(static_cast<unsigned char>(src_[pos_])) != 0))
        {
            pos_++;
        }
    }

    char Peek() const { return pos_ < src_.size() ? src_[pos_] : '\0'; }
    char Get() { return pos_ < src_.size() ? src_[pos_++] : '\0'; }

    bool ParseValue(JsonValue& val, size_t depth)
    {
        if (depth > kMaxJsonDepth) return false;
        SkipWhitespace();
        const char c = Peek();
        if (c == '"')
        {
            std::string s;
            if (!ParseString(s)) return false;
            val = JsonValue(std::move(s));
            return true;
        }
        if (c == '{')
        {
            JsonObject obj;
            if (!ParseObject(obj, depth)) return false;
            val = JsonValue(std::move(obj));
            return true;
        }
        if (c == '[')
        {
            JsonArray arr;
            if (!ParseArray(arr, depth)) return false;
            val = JsonValue(std::move(arr));
            return true;
        }
        if (c == 't' || c == 'f')
        {
            bool b = false;
            if (!ParseBool(b)) return false;
            val = JsonValue(b);
            return true;
        }
        if (c == 'n') return ParseNull(val);
        if (c == '-' || std::isdigit(static_cast<unsigned char>(c))) return ParseNumber(val);
        return false;
    }

    bool ParseHexUnit(uint32_t& unit)
    {
        if (pos_ + 4 > src_.size()) return false;
        unit = 0;
        for (size_t i = 0; i < 4; ++i)
        {
            const int value = HexDigit(src_[pos_++]);
            if (value < 0) return false;
            unit = (unit << 4) | static_cast<uint32_t>(value);
        }
        return true;
    }

    bool ParseString(std::string& out)
    {
        if (Get() != '"') return false;
        out.clear();
        while (pos_ < src_.size())
        {
            const char c = Get();
            if (c == '"') return true;
            if (static_cast<unsigned char>(c) < 0x20) return false;
            if (c != '\\')
            {
                out.push_back(c);
                continue;
            }

            if (pos_ >= src_.size()) return false;
            const char esc = Get();
            switch (esc)
            {
            case '"': out.push_back('"'); break;
            case '\\': out.push_back('\\'); break;
            case '/': out.push_back('/'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            case 'u':
            {
                uint32_t first = 0;
                if (!ParseHexUnit(first)) return false;
                uint32_t code_point = first;
                if (first >= 0xD800 && first <= 0xDBFF)
                {
                    if (pos_ + 2 > src_.size() || src_[pos_] != '\\' || src_[pos_ + 1] != 'u') return false;
                    pos_ += 2;
                    uint32_t second = 0;
                    if (!ParseHexUnit(second) || second < 0xDC00 || second > 0xDFFF) return false;
                    code_point = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
                }
                else if (first >= 0xDC00 && first <= 0xDFFF)
                {
                    return false;
                }
                if (!AppendUtf8CodePoint(code_point, out)) return false;
                break;
            }
            default:
                return false;
            }
        }
        return false;
    }

    bool ParseObject(JsonObject& obj, size_t depth)
    {
        if (Get() != '{') return false;
        SkipWhitespace();
        if (Peek() == '}')
        {
            Get();
            return true;
        }
        while (pos_ < src_.size())
        {
            if (obj.size() >= kMaxJsonContainerItems) return false;
            SkipWhitespace();
            if (Peek() != '"') return false;
            std::string key;
            if (!ParseString(key)) return false;
            if (obj.find(key) != obj.end()) return false;
            SkipWhitespace();
            if (Get() != ':') return false;
            JsonValue val;
            if (!ParseValue(val, depth + 1)) return false;
            obj.emplace(std::move(key), std::move(val));
            SkipWhitespace();
            const char c = Get();
            if (c == '}') return true;
            if (c != ',') return false;
        }
        return false;
    }

    bool ParseArray(JsonArray& arr, size_t depth)
    {
        if (Get() != '[') return false;
        SkipWhitespace();
        if (Peek() == ']')
        {
            Get();
            return true;
        }
        while (pos_ < src_.size())
        {
            if (arr.size() >= kMaxJsonContainerItems) return false;
            JsonValue val;
            if (!ParseValue(val, depth + 1)) return false;
            arr.push_back(std::move(val));
            SkipWhitespace();
            const char c = Get();
            if (c == ']') return true;
            if (c != ',') return false;
        }
        return false;
    }

    bool ParseBool(bool& b)
    {
        if (src_.compare(pos_, 4, "true") == 0)
        {
            pos_ += 4;
            b = true;
            return true;
        }
        if (src_.compare(pos_, 5, "false") == 0)
        {
            pos_ += 5;
            b = false;
            return true;
        }
        return false;
    }

    bool ParseNull(JsonValue& val)
    {
        if (src_.compare(pos_, 4, "null") != 0) return false;
        pos_ += 4;
        val = JsonValue(nullptr);
        return true;
    }

    bool ParseNumber(JsonValue& val)
    {
        const size_t start = pos_;
        bool is_float = false;

        if (Peek() == '-')
        {
            ++pos_;
            if (pos_ >= src_.size()) return false;
        }

        if (Peek() == '0')
        {
            ++pos_;
            if (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek()))) return false;
        }
        else
        {
            if (Peek() < '1' || Peek() > '9') return false;
            while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek()))) ++pos_;
        }

        if (pos_ < src_.size() && Peek() == '.')
        {
            is_float = true;
            ++pos_;
            if (pos_ >= src_.size() || !std::isdigit(static_cast<unsigned char>(Peek()))) return false;
            while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek()))) ++pos_;
        }

        if (pos_ < src_.size() && (Peek() == 'e' || Peek() == 'E'))
        {
            is_float = true;
            ++pos_;
            if (pos_ < src_.size() && (Peek() == '+' || Peek() == '-')) ++pos_;
            if (pos_ >= src_.size() || !std::isdigit(static_cast<unsigned char>(Peek()))) return false;
            while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek()))) ++pos_;
        }

        const std::string number = src_.substr(start, pos_ - start);
        if (!is_float)
        {
            int64_t parsed = 0;
            const auto result = std::from_chars(number.data(), number.data() + number.size(), parsed, 10);
            if (result.ec != std::errc{} || result.ptr != number.data() + number.size()) return false;
            val = JsonValue(parsed);
            return true;
        }

        errno = 0;
        char* end = nullptr;
        const double parsed = std::strtod(number.c_str(), &end);
        if (errno == ERANGE || end != number.c_str() + number.size() || !std::isfinite(parsed)) return false;
        val = JsonValue(parsed);
        return true;
    }

    const std::string& src_;
    size_t pos_;
};

} // namespace

std::string SerializeJson(const JsonValue& val)
{
    std::string out;
    out.reserve(256);
    SerializeValue(val, out);
    return out;
}

bool ParseJson(const std::string& input, JsonValue& output)
{
    if (input.empty() || input.size() > kMaxPayloadBytes) return false;
    try
    {
        JsonParser parser(input);
        return parser.Parse(output);
    }
    catch (...)
    {
        return false;
    }
}

std::string SerializeRequest(const BrokerRequest& req)
{
    JsonObject obj;
    obj["protocol"] = JsonValue(req.protocol);
    obj["type"] = JsonValue("request");
    obj["id"] = JsonValue(req.id);
    obj["method"] = JsonValue(req.method);
    obj["payload"] = JsonValue(req.payload);
    return SerializeJson(JsonValue(std::move(obj)));
}

std::string SerializeResponse(const BrokerResponse& res)
{
    JsonObject obj;
    obj["protocol"] = JsonValue(res.protocol);
    obj["type"] = JsonValue("response");
    obj["id"] = JsonValue(res.id);
    obj["ok"] = JsonValue(res.ok);
    obj["payload"] = JsonValue(res.payload);
    if (!res.ok)
    {
        JsonObject err;
        err["code"] = JsonValue(res.error_code);
        err["message"] = JsonValue(res.error_message);
        obj["error"] = JsonValue(std::move(err));
    }
    return SerializeJson(JsonValue(std::move(obj)));
}

std::string SerializeEvent(const BrokerEvent& ev)
{
    JsonObject obj;
    obj["protocol"] = JsonValue(ev.protocol);
    obj["type"] = JsonValue("event");
    obj["event"] = JsonValue(ev.event);
    obj["payload"] = JsonValue(ev.payload);
    obj["timestamp"] = JsonValue(static_cast<int64_t>(ev.timestamp_ms));
    return SerializeJson(JsonValue(std::move(obj)));
}

bool ParseRequest(const std::string& json_str, BrokerRequest& req, std::string& err)
{
    req = BrokerRequest{};
    err.clear();
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    const auto it_proto = obj.find("protocol");
    if (it_proto == obj.end() || !it_proto->second.IsInt() || it_proto->second.AsInt() != kProtocolVersion)
    {
        err = "Unsupported protocol version";
        return false;
    }
    const auto it_type = obj.find("type");
    if (it_type == obj.end() || !it_type->second.IsString() || it_type->second.AsString() != "request")
    {
        err = "Invalid message type; expected 'request'";
        return false;
    }
    const auto it_id = obj.find("id");
    if (it_id == obj.end() || !it_id->second.IsString() || it_id->second.AsString().empty() ||
        it_id->second.AsString().size() > kMaxRequestIdLength)
    {
        err = "Missing or invalid request 'id'";
        return false;
    }
    const auto it_method = obj.find("method");
    if (it_method == obj.end() || !it_method->second.IsString() || it_method->second.AsString().empty() ||
        it_method->second.AsString().size() > kMaxMethodLength)
    {
        err = "Missing or invalid 'method'";
        return false;
    }

    req.protocol = static_cast<int>(it_proto->second.AsInt());
    req.id = it_id->second.AsString();
    req.method = it_method->second.AsString();

    const auto it_payload = obj.find("payload");
    if (it_payload == obj.end())
    {
        req.payload.clear();
    }
    else if (it_payload->second.IsObject())
    {
        req.payload = it_payload->second.AsObject();
    }
    else
    {
        err = "Invalid request 'payload'; expected an object";
        return false;
    }
    return true;
}

bool ParseResponse(const std::string& json_str, BrokerResponse& res, std::string& err)
{
    res = BrokerResponse{};
    err.clear();
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    const auto it_proto = obj.find("protocol");
    if (it_proto == obj.end() || !it_proto->second.IsInt() || it_proto->second.AsInt() != kProtocolVersion)
    {
        err = "Unsupported protocol version";
        return false;
    }
    const auto it_type = obj.find("type");
    if (it_type == obj.end() || !it_type->second.IsString() || it_type->second.AsString() != "response")
    {
        err = "Invalid message type; expected 'response'";
        return false;
    }
    const auto it_id = obj.find("id");
    if (it_id == obj.end() || !it_id->second.IsString() || it_id->second.AsString().empty() ||
        it_id->second.AsString().size() > kMaxRequestIdLength)
    {
        err = "Missing or invalid response id";
        return false;
    }
    const auto it_ok = obj.find("ok");
    if (it_ok == obj.end() || !it_ok->second.IsBool())
    {
        err = "Missing ok flag";
        return false;
    }

    res.protocol = static_cast<int>(it_proto->second.AsInt());
    res.id = it_id->second.AsString();
    res.ok = it_ok->second.AsBool();

    const auto it_payload = obj.find("payload");
    if (it_payload == obj.end())
    {
        res.payload.clear();
    }
    else if (it_payload->second.IsObject())
    {
        res.payload = it_payload->second.AsObject();
    }
    else
    {
        err = "Invalid response payload";
        return false;
    }

    if (!res.ok)
    {
        const auto it_error = obj.find("error");
        if (it_error == obj.end() || !it_error->second.IsObject())
        {
            err = "Missing response error object";
            return false;
        }
        const auto& error_obj = it_error->second.AsObject();
        const auto it_code = error_obj.find("code");
        const auto it_message = error_obj.find("message");
        if (it_code == error_obj.end() || !it_code->second.IsString() ||
            it_message == error_obj.end() || !it_message->second.IsString())
        {
            err = "Invalid response error object";
            return false;
        }
        res.error_code = it_code->second.AsString();
        res.error_message = it_message->second.AsString();
    }
    return true;
}

bool ParseEvent(const std::string& json_str, BrokerEvent& ev, std::string& err)
{
    ev = BrokerEvent{};
    err.clear();
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    const auto it_proto = obj.find("protocol");
    if (it_proto == obj.end() || !it_proto->second.IsInt() || it_proto->second.AsInt() != kProtocolVersion)
    {
        err = "Unsupported protocol version";
        return false;
    }
    const auto it_type = obj.find("type");
    if (it_type == obj.end() || !it_type->second.IsString() || it_type->second.AsString() != "event")
    {
        err = "Invalid message type; expected 'event'";
        return false;
    }
    const auto it_event = obj.find("event");
    if (it_event == obj.end() || !it_event->second.IsString() || it_event->second.AsString().empty() ||
        it_event->second.AsString().size() > kMaxEventNameLength)
    {
        err = "Missing or invalid event name";
        return false;
    }
    ev.protocol = static_cast<int>(it_proto->second.AsInt());
    ev.event = it_event->second.AsString();

    const auto it_payload = obj.find("payload");
    if (it_payload == obj.end())
    {
        ev.payload.clear();
    }
    else if (it_payload->second.IsObject())
    {
        ev.payload = it_payload->second.AsObject();
    }
    else
    {
        err = "Invalid event payload";
        return false;
    }

    const auto it_ts = obj.find("timestamp");
    if (it_ts != obj.end())
    {
        if (!it_ts->second.IsInt() || it_ts->second.AsInt() < 0)
        {
            err = "Invalid event timestamp";
            return false;
        }
        ev.timestamp_ms = static_cast<uint64_t>(it_ts->second.AsInt());
    }
    else
    {
        ev.timestamp_ms = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
    }
    return true;
}

} // namespace CloudOS
