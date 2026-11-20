import Foundation
import Network

/// The loopback listener the OAuth redirect lands on. macOS 26 has the Swift-native Network
/// listener; below it the same job runs on `NWListener`, whose callbacks are wrapped here.
@MainActor
final class MCPOAuthListener {
    nonisolated static let redirectURI = "http://127.0.0.1:4962/callback"
    nonisolated private static let queue = DispatchQueue(label: "com.tinycast.mcp-oauth")

    private var task: Task<Void, Never>?
    private var listener: NWListener?
    private var ready: CheckedContinuation<Void, Error>?
    private var reply: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var accepted = false

    isolated deinit {
        task?.cancel()
        listener?.cancel()
    }

    func start(
        state: String, issuer: String, requiresIssuer: Bool, timeout: Duration = .seconds(300)
    ) async throws {
        guard result == nil else { throw CancellationError() }
        guard let listener = try? Self.makeListener() else {
            throw MCPOAuth.Failure.listenerUnavailable
        }
        self.listener = listener
        listener.newConnectionLimit = 16
        listener.stateUpdateHandler = { [weak self] status in
            Task { @MainActor in self?.listenerChanged(status) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                await self?.receive(
                    connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
            }
        }

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.start(queue: Self.queue)
                task = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        throw MCPOAuth.Failure.timedOut
                    } catch {
                        self?.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func code() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { reply = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private static func makeListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: 4962)!)
        return try NWListener(using: parameters)
    }

    private func listenerChanged(_ status: NWListener.State) {
        switch status {
        case .ready:
            ready?.resume()
            ready = nil
        case .waiting, .failed:
            finish(.failure(MCPOAuth.Failure.listenerUnavailable))
        default:
            break
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        ready?.resume(throwing: result.failure ?? CancellationError())
        ready = nil
        reply?.resume(with: result)
        reply = nil
        task?.cancel()
        task = nil
        listener?.cancel()
        listener = nil
    }

    private func receive(
        _ connection: NWConnection, state: String, issuer: String, requiresIssuer: Bool
    ) async {
        connection.start(queue: Self.queue)
        defer { connection.cancel() }
        do {
            try await read(
                connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        } catch {
            return
        }
    }

    private func read(
        _ connection: NWConnection, state: String, issuer: String, requiresIssuer: Bool
    ) async throws {
        var bytes = Data()
        while bytes.count < 8192 {
            let (chunk, isComplete) = try await receiveSome(connection, atMost: 8192 - bytes.count)
            bytes.append(chunk)
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if isComplete { return }
            if chunk.isEmpty { return }
        }
        guard !accepted else { return }
        guard let request = String(bytes: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
            return
        }
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        var outcome: Result<String, Error>?
        if parts.count == 3, parts[0] == "GET" {
            do {
                let code = try MCPOAuth.callback(
                    String(parts[1]), state: state, issuer: issuer,
                    requiresIssuer: requiresIssuer)
                outcome = .success(code)
            } catch MCPOAuth.Failure.denied {
                outcome = .failure(MCPOAuth.Failure.denied)
            } catch { outcome = nil }
        }
        let status = outcome == nil ? "400 Bad Request" : "200 OK"
        let page =
            outcome == nil
            ? String(localized: "Invalid sign-in response.")
            : String(localized: "Return to Tinycast. You can close this tab.")
        let response =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Cache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\n"
            + "Connection: close\r\nContent-Length: \(page.utf8.count)\r\n\r\n\(page)"
        if outcome != nil { self.accepted = true }
        do {
            try await sendAll(Data(response.utf8), on: connection)
        } catch {
            if let outcome { self.finish(outcome) }
            throw error
        }
        if let outcome { self.finish(outcome) }
    }

    private func receiveSome(_ connection: NWConnection, atMost: Int) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: atMost) {
                data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), isComplete))
                }
            }
        }
    }

    private func sendAll(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data, contentContext: .defaultMessage, isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
        }
    }
}

private extension Result where Success == String, Failure == Error {
    var failure: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
