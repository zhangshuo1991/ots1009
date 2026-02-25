import Foundation

enum CodexProtocolSignal: Equatable, Sendable {
    case sessionMeta(cwd: String)
    case event(type: String)
}

enum CodexProtocolLineParser {
    static func parse(line: String) -> CodexProtocolSignal? {
        guard let data = line.data(using: .utf8),
              let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any]
        else {
            return nil
        }

        if object["jsonrpc"] != nil {
            return parseJSONRPC(object: object)
        }

        guard let envelopeType = object["type"] as? String else {
            return nil
        }

        switch envelopeType {
        case "event_msg":
            guard let payload = object["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String,
                  !eventType.isEmpty
            else {
                return nil
            }
            return .event(type: eventType)

        case "session_meta":
            guard let payload = object["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String,
                  !cwd.isEmpty
            else {
                return nil
            }
            return .sessionMeta(cwd: cwd)

        default:
            return nil
        }
    }

    private static func parseJSONRPC(object: [String: Any]) -> CodexProtocolSignal? {
        guard let method = object["method"] as? String, !method.isEmpty else {
            return nil
        }

        if method == "codex/event" {
            guard let params = object["params"] as? [String: Any],
                  let msg = params["msg"] as? [String: Any],
                  let eventType = msg["type"] as? String,
                  !eventType.isEmpty
            else {
                return nil
            }
            return .event(type: eventType)
        }

        // App-server v2 style notifications use the method name itself as event type.
        if method.contains("/") {
            return .event(type: method)
        }

        return nil
    }
}
