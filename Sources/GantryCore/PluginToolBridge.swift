import Darwin
import Foundation

/// A loopback-only tool bridge over a Unix domain socket. The MCP helper runs
/// as a child of Claude Code and can call only the handler scoped to one
/// project and plugin; plugin tokens never leave the app process.
public final class PluginToolBridge: @unchecked Sendable {
    public let socketPath: String
    public let authToken: String

    private let handler: @Sendable (PluginToolBridgeRequest) async throws -> JSONValue
    private let stateLock = NSLock()
    private var listenFileDescriptor: Int32 = -1
    private var stopped = false

    public init(
        handler: @escaping @Sendable (PluginToolBridgeRequest) async throws -> JSONValue
    ) throws {
        self.handler = handler
        self.authToken = UUID().uuidString
        self.socketPath = Self.makeSocketPath()

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw PluginToolBridgeError.socket(errno)
        }
        _ = fcntl(fileDescriptor, F_SETFD, FD_CLOEXEC)
        _ = unlink(socketPath)

        var address = sockaddr_un()
        let addressLength = socklen_t(
            MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1
        )
        address.sun_len = UInt8(min(addressLength, 255))
        address.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { path in
            _ = strlcpy(
                &address.sun_path.0,
                path,
                MemoryLayout.size(ofValue: address.sun_path)
            )
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fileDescriptor, socketAddress, addressLength)
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fileDescriptor)
            _ = unlink(socketPath)
            throw PluginToolBridgeError.bind(code)
        }

        _ = chmod(socketPath, S_IRUSR | S_IWUSR)

        guard listen(fileDescriptor, 8) == 0 else {
            let code = errno
            close(fileDescriptor)
            _ = unlink(socketPath)
            throw PluginToolBridgeError.listen(code)
        }

        listenFileDescriptor = fileDescriptor
        let thread = Thread { [self] in
            acceptLoop(fileDescriptor: fileDescriptor)
        }
        thread.name = "GantryPluginToolBridge"
        thread.start()
    }

    deinit {
        stop()
    }

    public func stop() {
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            return
        }
        stopped = true
        let fileDescriptor = listenFileDescriptor
        listenFileDescriptor = -1
        stateLock.unlock()

        if fileDescriptor >= 0 {
            _ = shutdown(fileDescriptor, SHUT_RDWR)
            close(fileDescriptor)
        }
        _ = unlink(socketPath)
    }

    // MARK: - Server loop

    private func acceptLoop(fileDescriptor: Int32) {
        while true {
            var clientAddress = sockaddr_storage()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    accept(fileDescriptor, socketAddress, &clientAddressLength)
                }
            }
            guard client >= 0 else {
                if errno == EINTR { continue }
                break
            }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            var noSigPipe: Int32 = 1
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            let thread = Thread { [self] in
                receiveAndHandle(fileDescriptor: client)
            }
            thread.name = "GantryPluginToolClient"
            thread.start()
        }
    }

    private func receiveAndHandle(fileDescriptor: Int32) {
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

        let requestData: Data
        do {
            requestData = try readLine(fileDescriptor: fileDescriptor)
        } catch {
            respond(
                .init(ok: false, error: "Couldn't read the bridge request."),
                fileDescriptor: fileDescriptor
            )
            return
        }

        let request: PluginToolBridgeRequest
        do {
            request = try JSONDecoder().decode(PluginToolBridgeRequest.self, from: requestData)
        } catch {
            respond(
                .init(ok: false, error: "The bridge request wasn't valid JSON."),
                fileDescriptor: fileDescriptor
            )
            return
        }

        guard request.auth == authToken else {
            respond(
                .init(ok: false, error: "The bridge request wasn't authorized."),
                fileDescriptor: fileDescriptor
            )
            return
        }

        Task { [handler] in
            let response: PluginToolBridgeResponse
            do {
                let result = try await handler(request)
                response = PluginToolBridgeResponse(ok: true, result: result)
            } catch {
                response = PluginToolBridgeResponse(
                    ok: false,
                    error: error.localizedDescription
                )
            }
            respond(response, fileDescriptor: fileDescriptor)
        }
    }

    private func readLine(fileDescriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count < 1_000_000 {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(fileDescriptor, base, bytes.count)
            }
            if count > 0 {
                buffer.withUnsafeBytes { bytes in
                    if let base = bytes.baseAddress {
                        data.append(
                            base.assumingMemoryBound(to: UInt8.self),
                            count: count
                        )
                    }
                }
                if data.contains(0x0A) { break }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw PluginToolBridgeError.read(errno)
            }
        }
        guard let newline = data.firstIndex(of: 0x0A) else {
            throw PluginToolBridgeError.incompleteRequest
        }
        return data.prefix(upTo: newline)
    }

    private func respond(
        _ response: PluginToolBridgeResponse,
        fileDescriptor: Int32
    ) {
        defer {
            _ = shutdown(fileDescriptor, SHUT_WR)
            close(fileDescriptor)
        }
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
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
                    break
                }
            }
        }
    }

    private static func makeSocketPath() -> String {
        let filename = "Gantry-plugin-\(UUID().uuidString.prefix(8)).sock"
        let preferred = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .path
        if preferred.utf8.count < 100 {
            return preferred
        }
        return "/tmp/\(filename)"
    }
}

public enum PluginToolBridgeError: Error, LocalizedError, Sendable {
    case socket(Int32)
    case bind(Int32)
    case listen(Int32)
    case read(Int32)
    case incompleteRequest

    public var errorDescription: String? {
        switch self {
        case .socket(let code):
            return "Couldn't create the plugin tool socket (\(code))."
        case .bind(let code):
            return "Couldn't bind the plugin tool socket (\(code))."
        case .listen(let code):
            return "Couldn't listen on the plugin tool socket (\(code))."
        case .read(let code):
            return "Couldn't read a plugin tool request (\(code))."
        case .incompleteRequest:
            return "The plugin tool request was incomplete."
        }
    }
}
