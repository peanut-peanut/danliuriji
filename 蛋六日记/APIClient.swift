import Foundation

/// 地址由 Xcode 构建配置注入：Debug 指向本机，Release 使用生产 HTTPS 地址。
enum APIConfiguration {
    static var baseURL: URL {
        let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.host != nil else {
            return URL(string: "http://127.0.0.1:9/api")!
        }
        return url
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case server(message: String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回的数据无效。"
        case let .server(message): message
        }
    }
}

private struct APIEnvelope<Value: Decodable>: Decodable { let data: Value }
private struct APIErrorEnvelope: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }

@MainActor
struct APIClient {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = APIConfiguration.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func diaryEntries(category: DiaryCategory? = nil) async throws -> [DiaryEntry] {
        var components = URLComponents(url: endpoint("diary-entries"), resolvingAgainstBaseURL: false)!
        if let category { components.queryItems = [URLQueryItem(name: "category", value: category.rawValue)] }
        return try await request(url: components.url!, method: "GET")
    }

    func petAssets(filter: PetAssetFilter = .all) async throws -> [PetAsset] {
        var components = URLComponents(url: endpoint("pet-assets"), resolvingAgainstBaseURL: false)!
        if filter == .image { components.queryItems = [URLQueryItem(name: "kind", value: "image")] }
        if filter == .video { components.queryItems = [URLQueryItem(name: "kind", value: "video")] }
        return try await request(url: components.url!, method: "GET")
    }

    func polishDiary(body: String) async throws -> AIPolishResult {
        try await request(path: "ai/polish", method: "POST", body: AIPolishPayload(body: body))
    }

    func createDiary(title: String, body: String, category: DiaryCategory, date: Date, drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> DiaryEntry {
        let media = try await upload(drafts, progress: uploadProgress)
        let payload = DiaryWritePayload(title: title, body: body, category: category.rawValue, date: date.apiTimestamp, isFavorite: false, mediaIds: media.map(\.id))
        return try await request(path: "diary-entries", method: "POST", body: payload)
    }

    func updateDiary(_ entry: DiaryEntry, drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> DiaryEntry {
        let newlyUploaded = try await upload(drafts, progress: uploadProgress)
        let payload = DiaryWritePayload(title: entry.title, body: entry.body, category: entry.category.rawValue, date: entry.date.apiTimestamp, isFavorite: entry.isFavorite, mediaIds: (entry.media + newlyUploaded).map(\.id))
        return try await request(path: "diary-entries/\(entry.id.uuidString)", method: "PATCH", body: payload)
    }

    func deleteDiary(id: UUID) async throws { try await delete(path: "diary-entries/\(id.uuidString)") }
    func setDiaryFavorite(_ entry: DiaryEntry) async throws -> DiaryEntry { try await request(path: "diary-entries/\(entry.id.uuidString)", method: "PATCH", body: ["isFavorite": entry.isFavorite]) }

    func createPetAsset(petIDs: [PetID], drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> PetAsset {
        let media = try await upload(drafts, progress: uploadProgress)
        return try await request(path: "pet-assets", method: "POST", body: PetAssetWritePayload(petIds: petIDs.map(\.rawValue), mediaIds: media.map(\.id)))
    }

    func deletePetAsset(id: UUID) async throws { try await delete(path: "pet-assets/\(id.uuidString)") }

    private func upload(_ drafts: [DraftMedia], progress: @escaping (Int, Int) -> Void) async throws -> [MediaAttachment] {
        var uploaded: [MediaAttachment] = []
        for (index, draft) in drafts.enumerated() {
            try Task.checkCancellation()
            progress(index, drafts.count)
            var request = URLRequest(url: endpoint("media"))
            request.httpMethod = "POST"
            request.setValue(draft.kind == .image ? "image/jpeg" : "video/quicktime", forHTTPHeaderField: "Content-Type")
            request.setValue(draft.kind == .image ? "image.jpg" : "video.mov", forHTTPHeaderField: "X-Filename")
            request.httpBody = draft.data
            let (data, response) = try await perform(request, binaryBody: true)
            uploaded.append(try decodeEnvelope(data: data, response: response))
            progress(index + 1, drafts.count)
        }
        return uploaded
    }

    private func request<Value: Decodable>(path: String, method: String, body: (some Encodable)? = nil) async throws -> Value {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, response) = try await perform(request)
        return try decodeEnvelope(data: data, response: response)
    }

    private func request<Value: Decodable>(url: URL, method: String) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let (data, response) = try await perform(request)
        return try decodeEnvelope(data: data, response: response)
    }

    private func delete(path: String) async throws {
        var request = URLRequest(url: endpoint(path)); request.httpMethod = "DELETE"
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw responseError(data: data, status: http.statusCode) }
    }

    private func perform(_ request: URLRequest, binaryBody: Bool = false) async throws -> (Data, URLResponse) {
        DebugNetworkLogger.logRequest(request, binaryBody: binaryBody)
        do {
            let result = try await session.data(for: request)
            DebugNetworkLogger.logResponse(result.0, response: result.1)
            return result
        } catch {
            DebugNetworkLogger.logTransportError(error, request: request)
            throw error
        }
    }

    private func decodeEnvelope<Value: Decodable>(data: Data, response: URLResponse) throws -> Value {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw responseError(data: data, status: http.statusCode) }
        do { return try decoder.decode(APIEnvelope<Value>.self, from: data).data }
        catch { throw APIError.invalidResponse }
    }

    private func responseError(data: Data, status: Int) -> APIError {
        let message = (try? decoder.decode(APIErrorEnvelope.self, from: data))?.error.message ?? "请求失败（HTTP \(status)）。"
        return .server(message: message)
    }

    private func endpoint(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}

struct AIPolishResult: Decodable { let body: String }
private struct AIPolishPayload: Encodable { let body: String }
private struct DiaryWritePayload: Encodable { let title: String; let body: String; let category: String; let date: String; let isFavorite: Bool; let mediaIds: [UUID] }
private struct PetAssetWritePayload: Encodable { let petIds: [String]; let mediaIds: [UUID] }
private struct AnyEncodable: Encodable { private let encodeClosure: (Encoder) throws -> Void; init(_ value: some Encodable) { encodeClosure = value.encode }; func encode(to encoder: Encoder) throws { try encodeClosure(encoder) } }
private extension Date { var apiTimestamp: String { ISO8601DateFormatter().string(from: self) } }

private enum DebugNetworkLogger {
    static func logRequest(_ request: URLRequest, binaryBody: Bool) {
        #if DEBUG
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        let headerCurl = headers.sorted { $0.key < $1.key }.map { "  -H '\($0.key): \(escape($0.value))'" }.joined(separator: " \\\n")
        let body: String
        if binaryBody { body = request.httpBody.map { "  --data-binary '<\($0.count) bytes binary omitted>'" } ?? "" }
        else if let data = request.httpBody, let value = String(data: data, encoding: .utf8) { body = "  --data-raw '\(escape(value))'" }
        else { body = "" }
        print("\n🌐 [API Request] \(method) \(request.url?.absoluteString ?? "")\nHeaders: \(headers)\nBody: \(body.isEmpty ? "<empty>" : binaryBody ? "<binary omitted>" : body.dropFirst(13))\nCURL:\ncurl -i -X \(method) \\\n\(headerCurl)\(headerCurl.isEmpty ? "" : " \\\n")\(body)\(body.isEmpty ? "" : " \\\n")  '\(request.url?.absoluteString ?? "")'\n")
        #endif
    }

    static func logResponse(_ data: Data, response: URLResponse) {
        #if DEBUG
        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
        print("✅ [API Response] HTTP \(http?.statusCode ?? 0) \(response.url?.absoluteString ?? "")\nHeaders: \(http?.allHeaderFields ?? [:])\nBody: \(body)\n")
        #endif
    }

    static func logTransportError(_ error: Error, request: URLRequest) {
        #if DEBUG
        print("❌ [API Transport Error] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")\n\(error.localizedDescription)\n")
        #endif
    }

    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") }
}
