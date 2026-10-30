import Foundation
import SwiftUI

enum DiaryCategory: String, CaseIterable, Codable, Identifiable {
    case everyday = "日常", exercise = "运动", reading = "阅读", investment = "投资", food = "饮食"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .everyday: "sun.max.fill"
        case .exercise: "figure.run"
        case .reading: "books.vertical.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .food: "fork.knife"
        }
    }
    var tint: Color {
        switch self {
        case .everyday: .orange
        case .exercise: .mint
        case .reading: .indigo
        case .investment: .teal
        case .food: .pink
        }
    }
}

enum PetID: String, CaseIterable, Codable, Identifiable {
    case danHuang = "蛋黄", liuLiu = "六六"
    var id: String { rawValue }
    var profile: PetProfile {
        switch self {
        case .danHuang: PetProfile(id: self, breed: "短毛金渐层", gender: .female, birthday: .make(2023, 4, 8), symbol: "cat.fill", accent: .orange, caption: "柔软、安静，像一块晒暖的蛋黄。")
        case .liuLiu: PetProfile(id: self, breed: "长毛橘猫", gender: .male, birthday: .make(2024, 6, 6), symbol: "pawprint.fill", accent: .red, caption: "蓬松、好奇，把日子过得热气腾腾。")
        }
    }
}

enum PetGender: Hashable {
    case female
    case male

    var symbol: String { self == .female ? "female.symbol" : "male.symbol" }
    var tint: Color { self == .female ? .pink : .blue }
    var accessibilityLabel: String { self == .female ? "母" : "公" }
}

struct PetProfile: Identifiable, Hashable {
    let id: PetID
    let breed: String
    let gender: PetGender
    let birthday: Date
    let symbol: String
    let accent: Color
    let caption: String
    var ageText: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        return years == 0 ? "\(months) 个月" : (months == 0 ? "\(years) 岁" : "\(years) 岁 \(months) 个月")
    }
    var birthdayText: String { birthday.chineseDate }
}

enum MediaKind: String, Codable { case image, video }

struct MediaAttachment: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: MediaKind
    /// OSS Object Key；数据库持久化的媒体定位字段。
    var filePath: String
    var remoteURL: String?

    init(id: UUID = UUID(), kind: MediaKind, filePath: String, remoteURL: String? = nil) {
        self.id = id
        self.kind = kind
        self.filePath = filePath
        self.remoteURL = remoteURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, filePath, filename, remoteURL = "url"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        kind = try box.decode(MediaKind.self, forKey: .kind)
        // filePath 是 OSS 新契约；filename 仅用于兼容早期本地媒体记录。
        filePath = try box.decodeIfPresent(String.self, forKey: .filePath)
            ?? box.decodeIfPresent(String.self, forKey: .filename)
            ?? ""
        remoteURL = try box.decodeIfPresent(String.self, forKey: .remoteURL)
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(kind, forKey: .kind)
        try box.encode(filePath, forKey: .filePath)
        try box.encodeIfPresent(remoteURL, forKey: .remoteURL)
    }
}

struct DiaryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var category: DiaryCategory
    var date: Date
    var media: [MediaAttachment]
    var isFavorite: Bool
    init(id: UUID = UUID(), title: String, body: String, category: DiaryCategory, date: Date, media: [MediaAttachment] = [], isFavorite: Bool = false) {
        self.id = id; self.title = title; self.body = body; self.category = category; self.date = date; self.media = media; self.isFavorite = isFavorite
    }
    var excerpt: String { body.replacingOccurrences(of: "\n", with: " ") }
    private enum CodingKeys: String, CodingKey { case id, title, body, category, date, media, isFavorite }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try box.decodeIfPresent(String.self, forKey: .body) ?? ""
        category = try box.decodeIfPresent(DiaryCategory.self, forKey: .category) ?? .everyday
        date = try box.decodeIfPresent(Date.self, forKey: .date) ?? .now
        media = try box.decodeIfPresent([MediaAttachment].self, forKey: .media) ?? []
        isFavorite = try box.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct PetAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var petIDs: [PetID]
    var date: Date
    var media: [MediaAttachment]

    init(id: UUID = UUID(), petIDs: [PetID], date: Date, media: [MediaAttachment]) {
        self.id = id
        self.petIDs = petIDs
        self.date = date
        self.media = media
    }

    // 兼容开发期间早期版本的单宠物“动态”本地数据。
    private enum CodingKeys: String, CodingKey { case id, petIDs, petIds, petID, date, media }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let petIDs = try box.decodeIfPresent([PetID].self, forKey: .petIds) ?? box.decodeIfPresent([PetID].self, forKey: .petIDs) {
            self.petIDs = petIDs
        } else if let petID = try box.decodeIfPresent(PetID.self, forKey: .petID) {
            self.petIDs = [petID]
        } else {
            self.petIDs = [.danHuang]
        }
        date = try box.decodeIfPresent(Date.self, forKey: .date) ?? .now
        media = try box.decodeIfPresent([MediaAttachment].self, forKey: .media) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(petIDs, forKey: .petIDs)
        try box.encode(date, forKey: .date)
        try box.encode(media, forKey: .media)
    }
}

enum PetAssetFilter: String, CaseIterable, Identifiable {
    case all = "全部", image = "图片", video = "视频"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .image: "photo.fill"
        case .video: "video.fill"
        }
    }
}

enum ContentLayout: String { case list, waterfall
    var symbol: String { self == .list ? "rectangle.grid.1x2" : "square.grid.2x2" }
    var next: ContentLayout { self == .list ? .waterfall : .list }
}

extension Date {
    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    /// 时间线用相对中文时间；超过三天后回退为完整日期。
    var relativeChineseTime: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        if seconds < 60 { return "刚刚" }
        if seconds < 60 * 60 { return "\(Int(seconds / 60)) 分钟前" }
        if Calendar.current.isDateInToday(self) { return "\(Int(seconds / 3_600)) 小时前" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: self), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        if days <= 3 { return "\(max(1, days)) 天前" }
        return chineseDate
    }

    var chineseDate: String {
        formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day())
    }

    var chineseDateTime: String {
        formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().hour().minute())
    }
}

/// 发布页内的媒体顺序。remote 表示已在服务端保存；draft 仅在本次编辑会话内存在。
struct DraftMedia: Identifiable, Hashable {
    let id: UUID
    let kind: MediaKind
    let data: Data

    init(id: UUID = UUID(), kind: MediaKind, data: Data) {
        self.id = id
        self.kind = kind
        self.data = data
    }
}

enum ComposerMediaSource: Hashable {
    case remote(MediaAttachment)
    case draft(DraftMedia)
}

struct ComposerMedia: Identifiable, Hashable {
    let id: String
    var source: ComposerMediaSource

    init(remote: MediaAttachment) {
        id = "remote-\(remote.id.uuidString)"
        source = .remote(remote)
    }

    init(draft: DraftMedia) {
        id = "draft-\(draft.id.uuidString)"
        source = .draft(draft)
    }

    var kind: MediaKind {
        switch source {
        case let .remote(media): media.kind
        case let .draft(media): media.kind
        }
    }

    var remoteMedia: MediaAttachment? {
        guard case let .remote(media) = source else { return nil }
        return media
    }

    var draftMedia: DraftMedia? {
        guard case let .draft(media) = source else { return nil }
        return media
    }
}

struct DiaryDraft: Codable, Equatable {
    var title: String = ""
    var body: String = ""
    var category: DiaryCategory = .everyday
    var date: Date = .now

    static let storageKey = "danliu.diary.composer-draft.v1"

    static func load() -> DiaryDraft? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DiaryDraft.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: storageKey) }
}
