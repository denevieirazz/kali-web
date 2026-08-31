#include "protocol_v21.h"

#include <cctype>
#include <chrono>
#include <iomanip>
#include <sstream>

namespace CloudOS
{

namespace
{

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
        std::ostringstream ss;
        ss << std::setprecision(6) << val.AsDouble();
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

class JsonParser final
{
public:
    explicit JsonParser(const std::string& input) : src_(input), pos_(0) {}

    bool Parse(JsonValue& root)
    {
        SkipWhitespace();
        if (pos_ >= src_.size()) return false;
        if (!ParseValue(root)) return false;
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

    bool ParseValue(JsonValue& val)
    {
        SkipWhitespace();
        char c = Peek();
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
            if (!ParseObject(obj)) return false;
            val = JsonValue(std::move(obj));
            return true;
        }
        if (c == '[')
        {
            JsonArray arr;
            if (!ParseArray(arr)) return false;
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
        if (c == 'n')
        {
            return ParseNull(val);
        }
        if (c == '-' || std::isdigit(static_cast<unsigned char>(c)))
        {
            return ParseNumber(val);
        }
        return false;
    }

    bool ParseString(std::string& out)
    {
        if (Get() != '"') return false;
        out.clear();
        while (pos_ < src_.size())
        {
            char c = Get();
            if (c == '"') return true;
            if (c == '\\')
            {
                if (pos_ >= src_.size()) return false;
                char esc = Get();
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
                    if (pos_ + 4 > src_.size()) return false;
                    pos_ += 4;
                    out.push_back('?');
                    break;
                default:
                    out.push_back(esc);
                    break;
                }
            }
            else
            {
                out.push_back(c);
            }
        }
        return false;
    }

    bool ParseObject(JsonObject& obj)
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
            SkipWhitespace();
            if (Peek() != '"') return false;
            std::string key;
            if (!ParseString(key)) return false;
            SkipWhitespace();
            if (Get() != ':') return false;
            JsonValue val;
            if (!ParseValue(val)) return false;
            obj[key] = std::move(val);
            SkipWhitespace();
            char c = Get();
            if (c == '}') return true;
            if (c != ',') return false;
        }
        return false;
    }

    bool ParseArray(JsonArray& arr)
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
            JsonValue val;
            if (!ParseValue(val)) return false;
            arr.push_back(std::move(val));
            SkipWhitespace();
            char c = Get();
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
        if (src_.compare(pos_, 4, "null") == 0)
        {
            pos_ += 4;
            val = JsonValue(nullptr);
            return true;
        }
        return false;
    }

    bool ParseNumber(JsonValue& val)
    {
        size_t start = pos_;
        bool is_float = false;
        if (Peek() == '-') pos_++;
        while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek())))
        {
            pos_++;
        }
        if (pos_ < src_.size() && Peek() == '.')
        {
            is_float = true;
            pos_++;
            while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek())))
            {
                pos_++;
            }
        }
        if (pos_ < src_.size() && (Peek() == 'e' || Peek() == 'E'))
        {
            is_float = true;
            pos_++;
            if (pos_ < src_.size() && (Peek() == '+' || Peek() == '-')) pos_++;
            while (pos_ < src_.size() && std::isdigit(static_cast<unsigned char>(Peek())))
            {
                pos_++;
            }
        }
        std::string num_str = src_.substr(start, pos_ - start);
        if (is_float)
        {
            val = JsonValue(std::stod(num_str));
        }
        else
        {
            val = JsonValue(std::stoll(num_str));
        }
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
    JsonParser parser(input);
    return parser.Parse(output);
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
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    auto it_proto = obj.find("protocol");
    if (it_proto == obj.end() || !it_proto->second.IsInt() || it_proto->second.AsInt() != kProtocolVersion)
    {
        err = "Unsupported protocol version";
        return false;
    }
    auto it_type = obj.find("type");
    if (it_type == obj.end() || !it_type->second.IsString() || it_type->second.AsString() != "request")
    {
        err = "Invalid message type; expected 'request'";
        return false;
    }
    auto it_id = obj.find("id");
    if (it_id == obj.end() || !it_id->second.IsString() || it_id->second.AsString().empty())
    {
        err = "Missing or invalid request 'id'";
        return false;
    }
    auto it_method = obj.find("method");
    if (it_method == obj.end() || !it_method->second.IsString() || it_method->second.AsString().empty())
    {
        err = "Missing or invalid 'method'";
        return false;
    }

    req.protocol = static_cast<int>(it_proto->second.AsInt());
    req.id = it_id->second.AsString();
    req.method = it_method->second.AsString();

    auto it_payload = obj.find("payload");
    if (it_payload != obj.end() && it_payload->second.IsObject())
    {
        req.payload = it_payload->second.AsObject();
    }
    else
    {
        req.payload.clear();
    }
    return true;
}

bool ParseResponse(const std::string& json_str, BrokerResponse& res, std::string& err)
{
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    auto it_proto = obj.find("protocol");
    if (it_proto == obj.end() || !it_proto->second.IsInt())
    {
        err = "Missing protocol";
        return false;
    }
    auto it_id = obj.find("id");
    if (it_id == obj.end() || !it_id->second.IsString())
    {
        err = "Missing response id";
        return false;
    }
    auto it_ok = obj.find("ok");
    if (it_ok == obj.end() || !it_ok->second.IsBool())
    {
        err = "Missing ok flag";
        return false;
    }

    res.protocol = static_cast<int>(it_proto->second.AsInt());
    res.id = it_id->second.AsString();
    res.ok = it_ok->second.AsBool();

    auto it_payload = obj.find("payload");
    if (it_payload != obj.end() && it_payload->second.IsObject())
    {
        res.payload = it_payload->second.AsObject();
    }
    else
    {
        res.payload.clear();
    }

    if (!res.ok)
    {
        auto it_err = obj.find("error");
        if (it_err != obj.end() && it_err->second.IsObject())
        {
            const auto& err_obj = it_err->second.AsObject();
            auto it_code = err_obj.find("code");
            if (it_code != err_obj.end()) res.error_code = it_code->second.AsString();
            auto it_msg = err_obj.find("message");
            if (it_msg != err_obj.end()) res.error_message = it_msg->second.AsString();
        }
    }
    return true;
}

bool ParseEvent(const std::string& json_str, BrokerEvent& ev, std::string& err)
{
    JsonValue root;
    if (!ParseJson(json_str, root) || !root.IsObject())
    {
        err = "Malformed JSON or root is not an object";
        return false;
    }
    const auto& obj = root.AsObject();
    auto it_event = obj.find("event");
    if (it_event == obj.end() || !it_event->second.IsString())
    {
        err = "Missing event name";
        return false;
    }
    ev.protocol = kProtocolVersion;
    ev.event = it_event->second.AsString();

    auto it_payload = obj.find("payload");
    if (it_payload != obj.end() && it_payload->second.IsObject())
    {
        ev.payload = it_payload->second.AsObject();
    }
    else
    {
        ev.payload.clear();
    }

    auto it_ts = obj.find("timestamp");
    if (it_ts != obj.end() && it_ts->second.IsInt())
    {
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
