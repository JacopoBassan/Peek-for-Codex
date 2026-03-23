import Foundation

actor CodexAppServerClient {
    private enum Limits {
        static let requestTimeout: Duration = .seconds(15)
        static let maxStdoutBufferBytes = 256 * 1024
        static let maxStderrBufferBytes = 64 * 1024
    }

    enum ClientError: LocalizedError {
        case codexNotFound
        case appServerUnavailable(String)
        case requestFailed(String)
        case requestTimedOut
        case outputOverflow(String)
        case invalidResponse
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .codexNotFound:
                return "The `codex` CLI was not found in PATH."
            case .appServerUnavailable(let message):
                return message
            case .requestFailed(let message):
                return message
            case .requestTimedOut:
                return "The Codex app-server did not respond in time."
            case .outputOverflow(let message):
                return message
            case .invalidResponse:
                return "The Codex app-server returned an invalid response."
            case .decodeFailed(let payload):
                return "The rate-limit payload could not be decoded.\n\(payload)"
            }
        }
    }

    private struct JSONRPCRequest<Params: Encodable>: Encodable {
        let id: String
        let method: String
        let params: Params?
    }

    private struct InitializeParams: Encodable {
        struct ClientInfo: Encodable {
            let name: String
            let title: String?
            let version: String
        }

        struct Capabilities: Encodable {
            let experimentalApi: Bool
        }

        let clientInfo: ClientInfo
        let capabilities: Capabilities?
    }

    private struct JSONRPCResponse: Decodable {
        let id: JSONValue?
        let result: JSONValue?
        let error: JSONRPCErrorPayload?
        let method: String?
        let params: JSONValue?
    }

    private struct JSONRPCErrorPayload: Decodable {
        let code: Int
        let message: String
    }

    private enum JSONValue: Codable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .object(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }

        var stringValue: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pendingContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var notificationHandler: (@Sendable (RateLimitSnapshot) -> Void)?
    private var nextRequestID = 0
    private var initialized = false

    func setNotificationHandler(_ handler: (@Sendable (RateLimitSnapshot) -> Void)?) {
        notificationHandler = handler
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        try await ensureStarted()
        let data = try await sendRequestData(
            method: "account/rateLimits/read",
            params: Optional<String>.none
        )

        if let response = try? decoder.decode(GetAccountRateLimitsResponse.self, from: data) {
            return response.rateLimits
        }

        if let response = try? decoder.decode(LegacyGetAccountRateLimitsResponse.self, from: data) {
            return response.rate_limits
        }

        if let snapshot = try? decoder.decode(RateLimitSnapshot.self, from: data) {
            return snapshot
        }

        let payload = String(data: data, encoding: .utf8) ?? "<non-utf8 payload>"
        throw ClientError.decodeFailed(payload)
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true, initialized {
            return
        }

        guard let codexURL = CodexLocator.cliURL() else {
            throw ClientError.codexNotFound
        }

        let task = Process()
        task.executableURL = codexURL
        task.arguments = ["app-server"]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStdout(data)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStderr(data)
            }
        }

        task.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(process)
            }
        }

        do {
            try task.run()
        } catch {
            throw ClientError.codexNotFound
        }

        process = task
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        stdoutBuffer = Data()
        stderrBuffer = Data()
        pendingContinuations = [:]
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks = [:]
        initialized = false

        let params = InitializeParams(
            clientInfo: .init(name: "PeekForCodex", title: "Peek for Codex", version: "0.1.0"),
            capabilities: .init(experimentalApi: true)
        )

        struct InitializeResponse: Decodable {
            let userAgent: String
        }

        _ = try await sendRequest(method: "initialize", params: params) as InitializeResponse
        initialized = true
    }

    private func sendRequest<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params?
    ) async throws -> Response {
        let data = try await sendRequestData(method: method, params: params)
        return try data.decoded(as: Response.self, using: decoder)
    }

    private func sendRequestData<Params: Encodable>(
        method: String,
        params: Params?
    ) async throws -> Data {
        guard process?.isRunning == true, let stdin = stdinPipe else {
            throw ClientError.appServerUnavailable("The Codex app-server is not running.")
        }

        nextRequestID += 1
        let requestID = String(nextRequestID)
        let request = JSONRPCRequest(id: requestID, method: method, params: params)
        let payload = try encoder.encode(request)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingContinuations[requestID] = continuation
            timeoutTasks[requestID] = Task { [weak self] in
                try? await Task.sleep(for: Limits.requestTimeout)
                await self?.handleRequestTimeout(id: requestID)
            }

            do {
                var line = payload
                line.append(0x0A)
                try stdin.fileHandleForWriting.write(contentsOf: line)
            } catch {
                pendingContinuations.removeValue(forKey: requestID)
                cancelTimeout(for: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    private func consumeStdout(_ data: Data) async {
        guard !data.isEmpty else { return }
        stdoutBuffer.append(data)

        if stdoutBuffer.count > Limits.maxStdoutBufferBytes {
            await failProcess(
                with: ClientError.outputOverflow("The Codex app-server produced too much output without a complete response.")
            )
            return
        }

        await drainStdoutLines()
    }

    private func consumeStderr(_ data: Data) async {
        guard !data.isEmpty else { return }
        stderrBuffer.append(data)

        if stderrBuffer.count > Limits.maxStderrBufferBytes {
            await failProcess(
                with: ClientError.outputOverflow("The Codex app-server produced too much error output without a newline.")
            )
            return
        }

        drainStderrLines()
    }

    private func drainStdoutLines() async {
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.prefix(upTo: newline)
            stdoutBuffer.removeSubrange(...newline)

            guard !lineData.isEmpty else { continue }
            await handleStdoutLine(Data(lineData))
        }
    }

    private func drainStderrLines() {
        while let newline = stderrBuffer.firstIndex(of: 0x0A) {
            stderrBuffer.removeSubrange(...newline)
        }
    }

    private func handleStdoutLine(_ data: Data) async {
        guard let response = try? decoder.decode(JSONRPCResponse.self, from: data) else {
            return
        }

        if let method = response.method, method == "account/rateLimits/updated", let params = response.params {
            if let snapshot = try? decodeValue(params, as: GetAccountRateLimitsResponse.self) {
                notificationHandler?(snapshot.rateLimits)
            } else if let snapshot = try? decodeValue(params, as: RateLimitSnapshot.self) {
                notificationHandler?(snapshot)
            }
            return
        }

        guard let id = response.id?.stringValue else {
            return
        }

        guard let continuation = pendingContinuations.removeValue(forKey: id) else {
            return
        }

        cancelTimeout(for: id)

        if let error = response.error {
            continuation.resume(throwing: ClientError.requestFailed(error.message))
            return
        }

        guard let result = response.result else {
            continuation.resume(throwing: ClientError.invalidResponse)
            return
        }

        do {
            let encoded = try encoder.encode(result)
            continuation.resume(returning: encoded)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func decodeValue<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private func handleRequestTimeout(id: String) async {
        guard let continuation = pendingContinuations.removeValue(forKey: id) else {
            return
        }

        cancelTimeout(for: id)
        continuation.resume(throwing: ClientError.requestTimedOut)
        await stopProcess()
    }

    private func handleTermination(_ process: Process) async {
        let stderr = String(data: stderrBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr?.isEmpty == false ? stderr! : "The Codex app-server exited unexpectedly."

        for continuation in pendingContinuations.values {
            continuation.resume(throwing: ClientError.appServerUnavailable(message))
        }

        clearPendingRequests()
        resetProcessState()
    }

    private func failProcess(with error: ClientError) async {
        for continuation in pendingContinuations.values {
            continuation.resume(throwing: error)
        }

        clearPendingRequests()
        await stopProcess()
    }

    private func cancelTimeout(for requestID: String) {
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
    }

    private func clearPendingRequests() {
        pendingContinuations.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
    }

    private func resetProcessState() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer = Data()
        stderrBuffer = Data()
        process = nil
        initialized = false
    }

    private func stopProcess() async {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil

        if process?.isRunning == true {
            process?.terminate()
        }

        resetProcessState()
    }
}

extension CodexAppServerClient: UsageProviding {}

private extension Data {
    func decoded<T: Decodable>(as type: T.Type, using decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(T.self, from: self)
        } catch {
            let payload = String(data: self, encoding: .utf8) ?? "<non-utf8 payload>"
            throw CodexAppServerClient.ClientError.decodeFailed(payload)
        }
    }
}
