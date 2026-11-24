import GantryCore
import Darwin
import Foundation

// This executable is launched by Claude Code as an MCP server. It speaks MCP
// over stdio and forwards tool calls to the Gantry app over a private Unix
// domain socket. Plugin tokens stay inside the app process.

private enum HelperError: Error, LocalizedError {
    case missingEnvironment
    case socketPathTooLong
    case socket(Int32)
    case connect(Int32)
    case write(Int32)
    case read(Int32)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEnvironment:
            return "The Gantry plugin bridge environment is missing."
        case .socketPathTooLong:
            return "The Gantry plugin bridge socket path is too long."
        case .socket(let code):
            return "Couldn't create the plugin bridge socket (\(code))."
        case .connect(let code):
            return "Couldn't connect to the Gantry plugin bridge (\(code))."
        case .write(let code):
            return "Couldn't write to the Gantry plugin bridge (\(code))."
        case .read(let code):
            return "Couldn't read from the Gantry plugin bridge (\(code))."
        case .invalidResponse:
            return "The Gantry plugin bridge returned an invalid response."
        }
    }
}

private func writeMessage(_ value: JSONValue) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func sendResult(id: JSONValue?, result: JSONValue) {
    var payload: [String: JSONValue] = [
        "jsonrpc": .string("2.0"),
        "result": result
    ]
    if let id { payload["id"] = id }
    writeMessage(.object(payload))
}

private func sendError(id: JSONValue?, code: Int, message: String) {
    var payload: [String: JSONValue] = [
        "jsonrpc": .string("2.0"),
        "error": .object([
            "code": .number(Double(code)),
            "message": .string(message)
        ])
    ]
    if let id { payload["id"] = id }
    writeMessage(.object(payload))
}

private func bridgeRequest(
    _ request: PluginToolBridgeRequest,
    socketPath: String
) throws -> PluginToolBridgeResponse {
    guard socketPath.utf8.count < 104 else {
        throw HelperError.socketPathTooLong
    }
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw HelperError.socket(errno)
    }
    defer { close(fileDescriptor) }

    var noSigPipe: Int32 = 1
    _ = setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSigPipe,
        socklen_t(MemoryLayout<Int32>.size)
    )
    var timeout = timeval(tv_sec: 65, tv_usec: 0)
    _ = setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_RCVTIMEO,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
    )
    _ = setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_SNDTIMEO,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
    )

    var address = sockaddr_un()
    let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
    address.sun_len = UInt8(min(addressLength, 255))
    address.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { path in
        _ = strlcpy(
            &address.sun_path.0,
            path,
            MemoryLayout.size(ofValue: address.sun_path)
        )
    }
    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            connect(fileDescriptor, socketAddress, addressLength)
        }
    }
    guard connectResult == 0 else {
        throw HelperError.connect(errno)
    }

    var requestData = try JSONEncoder().encode(request)
    requestData.append(0x0A)
    requestData.withUnsafeBytes { bytes in
        guard var base = bytes.baseAddress else { return }
        var remaining = bytes.count
        while remaining > 0 {
            let written = Darwin.write(fileDescriptor, base, remaining)
            if written > 0 {
                base = base.advanced(by: written)
                remaining -= written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while responseData.count < 8_000_000 {
        let count = buffer.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            return Darwin.read(fileDescriptor, base, bytes.count)
        }
        if count > 0 {
            buffer.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress {
                    responseData.append(
                        base.assumingMemoryBound(to: UInt8.self),
                        count: count
                    )
                }
            }
            if responseData.contains(0x0A) { break }
        } else if count == 0 {
            break
        } else if errno == EINTR {
            continue
        } else {
            throw HelperError.read(errno)
        }
    }
    guard let newline = responseData.firstIndex(of: 0x0A) else {
        throw HelperError.invalidResponse
    }
    let line = responseData.prefix(upTo: newline)
    do {
        return try JSONDecoder().decode(PluginToolBridgeResponse.self, from: line)
    } catch {
        throw HelperError.invalidResponse
    }
}

// MARK: - MCP server

guard let socketPath = ProcessInfo.processInfo.environment["Gantry_PLUGIN_SOCKET"],
      let authToken = ProcessInfo.processInfo.environment["Gantry_PLUGIN_AUTH"],
      !socketPath.isEmpty,
      !authToken.isEmpty else {
    FileHandle.standardError.write(Data(
        "Gantry-plugins: missing Gantry_PLUGIN_SOCKET or Gantry_PLUGIN_AUTH\n".utf8
    ))
    exit(1)
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let message = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)),
          let object = message.objectValue else {
        continue
    }

    let method = object["method"]?.stringValue ?? ""
    let id = object["id"]
    let hasID = id != nil && id != .null
    let params = object["params"]?.objectValue ?? [:]

    switch method {
    case "initialize":
        let requestedVersion = params["protocolVersion"]?.stringValue
        let protocolVersion = requestedVersion?.isEmpty == false
            ? requestedVersion!
            : "2024-11-05"
        sendResult(
            id: id,
            result: .object([
                "protocolVersion": .string(protocolVersion),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("Gantry-plugins"),
                    "version": .string("0.3.5")
                ])
            ])
        )

    case "notifications/initialized", "notifications/cancelled":
        continue

    case "ping":
        if hasID {
            sendResult(id: id, result: .object([:]))
        }

    case "tools/list":
        guard hasID else { continue }
        sendResult(
            id: id,
            result: .object([
                "tools": .array(PluginToolCatalog.all.map(\.mcpValue))
            ])
        )

    case "tools/call":
        guard hasID else { continue }
        guard let toolName = params["name"]?.stringValue, !toolName.isEmpty else {
            sendError(id: id, code: -32602, message: "Missing tool name.")
            continue
        }
        let arguments = params["arguments"] ?? .object([:])
        let request = PluginToolBridgeRequest(
            auth: authToken,
            tool: toolName,
            arguments: arguments
        )
        do {
            let response = try bridgeRequest(request, socketPath: socketPath)
            if response.ok, let result = response.result {
                sendResult(
                    id: id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string(result.prettyJSON)
                            ])
                        ]),
                        "isError": .bool(false)
                    ])
                )
            } else {
                sendResult(
                    id: id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string(response.error ?? "The plugin tool failed.")
                            ])
                        ]),
                        "isError": .bool(true)
                    ])
                )
            }
        } catch {
            sendResult(
                id: id,
                result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(error.localizedDescription)
                        ])
                    ]),
                    "isError": .bool(true)
                ])
            )
        }

    default:
        if hasID {
            sendError(id: id, code: -32601, message: "Unknown method: \(method)")
        }
    }
}
