import Foundation
import SwiftUI

@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var entries: [DiaryEntry] = []
    @Published private(set) var petAssets: [PetAsset] = []
    @Published private(set) var syncError: String?
    @Published var hasEnabledFaceID: Bool { didSet { UserDefaults.standard.set(hasEnabledFaceID, forKey: faceIDKey) } }

    private let client = APIClient()
    private let faceIDKey = "xiaowang.diary.faceid.v1"

    init() {
        hasEnabledFaceID = UserDefaults.standard.bool(forKey: faceIDKey)
        Task { await refresh() }
    }

    func refresh() async {
        do {
            async let diary = client.diaryEntries()
            async let assets = client.petAssets()
            entries = try await diary.sorted { $0.date > $1.date }
            petAssets = try await assets.sorted { $0.date > $1.date }
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    func refreshPetAssets(filter: PetAssetFilter) async -> [PetAsset] {
        do { return try await client.petAssets(filter: filter).sorted { $0.date > $1.date } }
        catch { syncError = error.localizedDescription; return [] }
    }

    func createDiary(title: String, body: String, category: DiaryCategory, date: Date, drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws {
        let entry = try await client.createDiary(title: title, body: body, category: category, date: date, drafts: drafts, uploadProgress: uploadProgress)
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
    }

    func updateDiary(_ entry: DiaryEntry, drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws {
        let updated = try await client.updateDiary(entry, drafts: drafts, uploadProgress: uploadProgress)
        replace(updated, in: &entries)
    }

    func delete(_ entry: DiaryEntry) async throws {
        try await client.deleteDiary(id: entry.id)
        entries.removeAll { $0.id == entry.id }
    }

    func toggleFavorite(_ entry: DiaryEntry) async throws {
        var pending = entry
        pending.isFavorite.toggle()
        let updated = try await client.setDiaryFavorite(pending)
        replace(updated, in: &entries)
    }

    func createPetAsset(petIDs: [PetID], drafts: [DraftMedia], uploadProgress: @escaping (Int, Int) -> Void = { _, _ in }) async throws {
        let asset = try await client.createPetAsset(petIDs: petIDs, drafts: drafts, uploadProgress: uploadProgress)
        petAssets.insert(asset, at: 0)
        petAssets.sort { $0.date > $1.date }
    }

    func delete(_ asset: PetAsset) async throws {
        try await client.deletePetAsset(id: asset.id)
        petAssets.removeAll { $0.id == asset.id }
    }

    func mediaURL(for item: MediaAttachment) -> URL? {
        guard let remoteURL = item.remoteURL else { return nil }
        return URL(string: remoteURL)
    }

    private func replace(_ value: DiaryEntry, in collection: inout [DiaryEntry]) {
        guard let index = collection.firstIndex(where: { $0.id == value.id }) else { return }
        collection[index] = value
        collection.sort { $0.date > $1.date }
    }
}
