import SwiftUI
import UIKit
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import Vision
import ImageIO


struct ContentView: View {
    @State private var selectedTab = 0
    @State private var composer: ComposerKind?
    enum ComposerKind: Identifiable { case diary, pet; var id: Int { self == .diary ? 0 : 1 } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DiaryTimelineView().tag(0).tabItem { Label("记录", systemImage: "rectangle.stack.fill") }
                PetWallView().tag(1).tabItem { Label("宠物", systemImage: "pawprint.fill") }
                LifeMuseumView().tag(2).tabItem { Label("展览", systemImage: "photo.on.rectangle.angled") }
            }
            if selectedTab < 2 {
                Button { composer = selectedTab == 0 ? .diary : .pet } label: {
                    Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white).frame(width: 54, height: 54).background(.orange.gradient, in: Circle()).shadow(color: .orange.opacity(0.28), radius: 12, y: 6)
                }
                .accessibilityLabel(selectedTab == 0 ? "发布记录" : "发布宠物动态")
                .padding(.trailing, 20).padding(.bottom, 66)
            }
        }
        .sheet(item: $composer) { kind in
            switch kind { case .diary: DiaryEditorView(); case .pet: PetPostEditorView() }
        }
    }
}

struct DiaryTimelineView: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var category: DiaryCategory?
    @AppStorage("danliu.diary.layout") private var layoutRawValue = ContentLayout.list.rawValue
    @State private var selectedEntry: DiaryEntry?
    private var layout: ContentLayout { ContentLayout(rawValue: layoutRawValue) ?? .list }
    private var entries: [DiaryEntry] { store.entries.filter { category == nil || $0.category == category } }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = max(0, geometry.size.width - 40)
                let columnWidth = max(0, (contentWidth - 12) / 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            categoryPicker
                            layoutToggle
                        }
                        if let syncError = store.syncError {
                            BackendStatusNotice(message: syncError)
                        }
                        if entries.isEmpty { ContentUnavailableView("还没有记录", systemImage: "square.and.pencil", description: Text("点击右下角加号，写下今天的片刻。")).padding(.top, 64) }
                        else if layout == .list { LazyVStack(spacing: 14) { ForEach(entries) { entryButton($0) } } }
                        else { WaterfallGrid(items: entries, columnWidth: columnWidth) { entry in entryButton(entry) } }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 104)
                    // A vertical ScrollView otherwise accepts a child's ideal width. Lock it to
                    // the visible viewport so a loaded AsyncImage cannot expand it horizontally.
                    .frame(width: geometry.size.width, alignment: .leading)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(item: $selectedEntry) { DiaryDetailView(entry: $0) }
        }
    }
    private func entryButton(_ entry: DiaryEntry) -> some View {
        Button { selectedEntry = entry } label: { layout == .list ? AnyView(DiaryCard(entry: entry)) : AnyView(DiaryWaterfallCard(entry: entry)) }
            .buttonStyle(.plain).contextMenu {
                Button(entry.isFavorite ? "取消收藏" : "收藏", systemImage: entry.isFavorite ? "heart.slash" : "heart") { Task { try? await store.toggleFavorite(entry) } }
                Button("删除", systemImage: "trash", role: .destructive) { Task { try? await store.delete(entry) } }
            }
    }
    private var layoutToggle: some View {
        Button { layoutRawValue = layout.next.rawValue } label: {
            Image(systemName: layout.next.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.background, in: Circle())
        }
        .accessibilityLabel("切换为\(layout.next == .list ? "列表" : "瀑布流")")
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) {
            CategoryCapsule(title: "全部", symbol: "square.grid.2x2.fill", tint: .primary, selected: category == nil) { category = nil }
            ForEach(DiaryCategory.allCases) { item in CategoryCapsule(title: item.rawValue, symbol: item.symbol, tint: item.tint, selected: category == item) { category = item } }
        } }
    }
}

struct BackendStatusNotice: View {
    let message: String
    var body: some View {
        Label("暂时无法连接后端：\(message)", systemImage: "wifi.exclamationmark")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CategoryCapsule: View {
    let title: String; let symbol: String; let tint: Color; let selected: Bool; let action: () -> Void
    var body: some View { Button(action: action) { Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(selected ? .white : tint).padding(.horizontal, 11).padding(.vertical, 8).background(selected ? tint : tint.opacity(0.12), in: Capsule()) }.buttonStyle(.plain) }
}

struct WaterfallGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var columnWidth: CGFloat?
    @ViewBuilder let cell: (Item) -> Cell

    private var columns: [GridItem] {
        let size: GridItem.Size = columnWidth.map { .fixed($0) } ?? .flexible(minimum: 0)
        return [
            GridItem(size, spacing: 12, alignment: .top),
            GridItem(size, spacing: 12, alignment: .top)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
            ForEach(items) { item in
                cell(item)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(
            width: columnWidth.map { $0 * 2 + 12 },
            alignment: .top
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct DiaryCard: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            DiaryListThumbnail(
                media: entry.media.first,
                fallbackSymbol: entry.category.symbol,
                tint: entry.category.tint
            )
            .frame(width: 108, height: 108)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title.isEmpty ? "无标题记录" : entry.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    CategoryTag(category: entry.category)
                }

                Spacer(minLength: 10)

                Text(entry.excerpt.isEmpty ? "图片记录" : entry.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(entry.date.relativeChineseTime)
                    if entry.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

struct CategoryTag: View {
    let category: DiaryCategory

    var body: some View {
        Label(category.rawValue, systemImage: category.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(category.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(category.tint.opacity(0.12), in: Capsule())
    }
}

struct DiaryListThumbnail: View {
    @EnvironmentObject private var store: DiaryStore
    let media: MediaAttachment?
    let fallbackSymbol: String
    let tint: Color
    private let side: CGFloat = 108

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.17).gradient)

            if let media, media.kind == .image, let url = store.mediaURL(for: media) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                    case .failure:
                        fallback
                    default:
                        ProgressView().tint(tint)
                    }
                }
                .frame(width: side, height: side)
                .clipped()
            } else {
                fallback
            }

            if media?.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: media?.kind == .video ? "play.rectangle.fill" : fallbackSymbol)
            .font(.title2)
            .foregroundStyle(tint)
    }
}

struct DiaryWaterfallCard: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WaterfallMediaTile(media: entry.media.first, fallbackSymbol: entry.category.symbol, tint: entry.category.tint)

            Text(entry.title.isEmpty ? (entry.excerpt.isEmpty ? "图片记录" : entry.excerpt) : entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Label(entry.category.rawValue, systemImage: entry.category.symbol)
                Text("·")
                Text(entry.date.relativeChineseTime)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

/// A waterfall tile always uses the width proposed by its grid column. Its height is
/// derived from the downloaded image's aspect ratio, so it cannot widen its parent card.
struct WaterfallMediaTile: View {
    @EnvironmentObject private var store: DiaryStore
    let media: MediaAttachment?
    let fallbackSymbol: String
    let tint: Color

    var body: some View {
        ZStack {
            mediaContent

            if media?.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.17).gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let media, media.kind == .image, let url = store.mediaURL(for: media) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                case .failure:
                    fallback
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                default:
                    ProgressView()
                        .tint(tint)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        } else {
            fallback
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var fallback: some View {
        Image(systemName: media?.kind == .video ? "play.rectangle.fill" : fallbackSymbol)
            .font(.title2)
            .foregroundStyle(tint)
    }
}

struct MediaTile: View {
    @EnvironmentObject private var store: DiaryStore
    let media: MediaAttachment?
    let fallbackSymbol: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.17).gradient)

            if let media, media.kind == .image, let url = store.mediaURL(for: media) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        fallback
                    default:
                        ProgressView().tint(tint)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                fallback
            }

            if media?.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: media?.kind == .video ? "play.rectangle.fill" : fallbackSymbol)
            .font(.title2)
            .foregroundStyle(tint)
    }
}

struct DiaryDetailView: View {
    @EnvironmentObject private var store: DiaryStore
    let entry: DiaryEntry; @State private var editing = false
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) {
        MediaGallery(media: entry.media, fallbackSymbol: entry.category.symbol, tint: entry.category.tint)
        Text(entry.title.isEmpty ? "无标题记录" : entry.title).font(.largeTitle.weight(.bold))
        HStack { Label(entry.category.rawValue, systemImage: entry.category.symbol); Text(entry.date.chineseDateTime) }.font(.subheadline).foregroundStyle(.secondary)
        Text(entry.body).font(.body).lineSpacing(7)
    }.padding(20) }.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button { Task { try? await store.toggleFavorite(entry) } } label: { Image(systemName: entry.isFavorite ? "heart.fill" : "heart") }; Button("编辑") { editing = true } } }.sheet(isPresented: $editing) { DiaryEditorView(entry: entry) } }
}

struct MediaGallery: View {
    let media: [MediaAttachment]
    let fallbackSymbol: String
    let tint: Color
    @State private var selectedMedia: MediaAttachment?

    var body: some View {
        if media.isEmpty {
            MediaTile(media: nil, fallbackSymbol: fallbackSymbol, tint: tint).frame(height: 220)
        } else {
            TabView {
                ForEach(media) { item in
                    Button { selectedMedia = item } label: {
                        MediaViewer(item: item, fallbackSymbol: fallbackSymbol, tint: tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 280)
            .tabViewStyle(.page)
            .fullScreenCover(item: $selectedMedia) { item in
                FullScreenMediaViewer(media: media, initialID: item.id, fallbackSymbol: fallbackSymbol, tint: tint)
            }
        }
    }
}

struct MediaViewer: View {
    @EnvironmentObject private var store: DiaryStore
    let item: MediaAttachment
    let fallbackSymbol: String
    let tint: Color

    var body: some View {
        if item.kind == .video, let url = store.mediaURL(for: item) {
            VideoPlayer(player: AVPlayer(url: url))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            MediaTile(media: item, fallbackSymbol: fallbackSymbol, tint: tint)
        }
    }
}

struct FullScreenMediaViewer: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let media: [MediaAttachment]
    let initialID: UUID
    let fallbackSymbol: String
    let tint: Color
    @State private var selection: UUID

    init(media: [MediaAttachment], initialID: UUID, fallbackSymbol: String, tint: Color) {
        self.media = media
        self.initialID = initialID
        self.fallbackSymbol = fallbackSymbol
        self.tint = tint
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(media) { item in
                    Group {
                        if item.kind == .video, let url = store.mediaURL(for: item) {
                            VideoPlayer(player: AVPlayer(url: url))
                        } else if let url = store.mediaURL(for: item) {
                            ZoomableRemoteImage(url: url, fallbackSymbol: fallbackSymbol, tint: tint)
                        } else {
                            Image(systemName: fallbackSymbol).font(.largeTitle).foregroundStyle(tint)
                        }
                    }
                    .tag(item.id)
                    .padding(.vertical, 50)
                }
            }
            .tabViewStyle(.page)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.top, 14)
            .padding(.trailing, 18)
        }
    }
}

struct ZoomableRemoteImage: View {
    let url: URL
    let fallbackSymbol: String
    let tint: Color
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFit()
            case .failure:
                Image(systemName: fallbackSymbol).font(.largeTitle).foregroundStyle(tint)
            default:
                ProgressView().tint(.white)
            }
        }
        .scaleEffect(scale * gestureScale)
        .offset(x: offset.width + gestureOffset.width, y: offset.height + gestureOffset.height)
        .gesture(MagnificationGesture().updating($gestureScale) { value, state, _ in state = value }.onEnded { value in scale = min(max(scale * value, 1), 4) })
        .simultaneousGesture(DragGesture().updating($gestureOffset) { value, state, _ in state = value.translation }.onEnded { value in offset = CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height) })
        .onTapGesture(count: 2) { withAnimation(.snappy) { scale = scale == 1 ? 2 : 1; offset = .zero } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ComposerMediaStrip: View {
    @Binding var selection: [PhotosPickerItem]
    @Binding var media: [ComposerMedia]
    let disabled: Bool
    let onImageAdded: (Data) -> Void

    init(selection: Binding<[PhotosPickerItem]>, media: Binding<[ComposerMedia]>, disabled: Bool, onImageAdded: @escaping (Data) -> Void = { _ in }) {
        _selection = selection
        _media = media
        self.disabled = disabled
        self.onImageAdded = onImageAdded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $selection, maxSelectionCount: max(0, 9 - media.count), matching: .any(of: [.images, .videos])) {
                Label("添加图片或视频", systemImage: "photo.badge.plus")
            }
            .disabled(disabled || media.count >= 9)

            if !media.isEmpty {
                Text("长按左右按钮可调整顺序，删除后不会上传该媒体。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                            ComposerMediaCell(item: item, canMoveLeft: index > 0, canMoveRight: index < media.count - 1, disabled: disabled,
                                              remove: { media.remove(at: index) },
                                              move: { direction in media.move(fromOffsets: IndexSet(integer: index), toOffset: direction < 0 ? index - 1 : index + 2) })
                        }
                    }
                }
            }
        }
        .onChange(of: selection) { _, items in
            Task {
                for item in items {
                    let kind: MediaKind = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) ? .video : .image
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            media.append(ComposerMedia(draft: DraftMedia(kind: kind, data: data)))
                            if kind == .image { onImageAdded(data) }
                        }
                    }
                }
                await MainActor.run { selection = [] }
            }
        }
    }
}

struct ComposerMediaCell: View {
    let item: ComposerMedia
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let disabled: Bool
    let remove: () -> Void
    let move: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            preview
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .black)
            }
            .disabled(disabled)
            .offset(x: 6, y: -6)

            HStack(spacing: 4) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(disabled || !canMoveLeft)
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(disabled || !canMoveRight)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .offset(y: 31)
        }
    }

    @ViewBuilder private var preview: some View {
        switch item.source {
        case let .draft(draft):
            if draft.kind == .image, let image = UIImage(data: draft.data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Color.secondary.opacity(0.15).overlay { Image(systemName: "video.fill").foregroundStyle(.secondary) } }
        case let .remote(media):
            if media.kind == .image, let url = URL(string: media.remoteURL ?? "") {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
            } else { Color.secondary.opacity(0.15).overlay { Image(systemName: "video.fill").foregroundStyle(.secondary) } }
        }
    }
}

struct UploadProgressBanner: View {
    let completed: Int
    let total: Int
    let cancel: () -> Void

    var body: some View {
        if total > 0 {
            HStack(spacing: 10) {
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.orange)
                Text("正在上传 \(min(completed + 1, total)) / \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel, action: cancel).font(.caption.weight(.semibold))
            }
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(.orange)
                Text("正在发布…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel, action: cancel).font(.caption.weight(.semibold))
            }
        }
    }
}

struct DiaryEditorView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let existingEntry: DiaryEntry?
    @State private var title: String
    @State private var bodyText: String
    @State private var category: DiaryCategory
    @State private var date: Date
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var media: [ComposerMedia]
    @State private var isSaving = false
    @State private var isPolishing = false
    @State private var shouldExtractImageInfo = false
    @State private var uploadCompleted = 0
    @State private var uploadTotal = 0
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    init(entry: DiaryEntry? = nil) {
        existingEntry = entry
        let draft = entry == nil ? DiaryDraft.load() : nil
        _title = State(initialValue: entry?.title ?? draft?.title ?? "")
        _bodyText = State(initialValue: entry?.body ?? draft?.body ?? "")
        _category = State(initialValue: entry?.category ?? draft?.category ?? .everyday)
        _date = State(initialValue: entry?.date ?? draft?.date ?? .now)
        _media = State(initialValue: entry?.media.map(ComposerMedia.init(remote:)) ?? [])
    }

    private var drafts: [DraftMedia] { media.compactMap(\.draftMedia) }
    private var remoteMedia: [MediaAttachment] { media.compactMap(\.remoteMedia) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（选填）", text: $title).font(.title3.weight(.semibold))
                    TextEditor(text: $bodyText).frame(minHeight: 150)
                        .overlay(alignment: .topLeading) { if bodyText.isEmpty { Text("写下此刻的心情、遇见的人或值得记住的事…").foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false) } }
                    Button(action: polish) {
                        Label(isPolishing ? "正在润色…" : "AI 润色", systemImage: "sparkles")
                    }
                    .disabled(isSaving || isPolishing || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("图文视频") {
                    ComposerMediaStrip(selection: $pickerItems, media: $media, disabled: isSaving) { imageData in
                        recognizeImageInfo(imageData)
                    }
                    Toggle("识别新图片信息", isOn: $shouldExtractImageInfo)
                    Text("开启后仅在本机提取图片中的文字、拍摄时间和 GPS 坐标（如有），确认上传前会追加至正文；不会把图片发给 AI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("分类") { Picker("分类", selection: $category) { ForEach(DiaryCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }.pickerStyle(.navigationLink) }
                Section("记录时间") { DatePicker("时间", selection: $date) }
                if isSaving { Section { UploadProgressBanner(completed: uploadCompleted, total: uploadTotal, cancel: cancelUpload) } }
                if existingEntry == nil && !title.isEmpty || !bodyText.isEmpty { Section { Label("文字内容已自动保存为草稿", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle(existingEntry == nil ? "发布记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { persistDraft(); dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { isSaving ? AnyView(ProgressView().controlSize(.small)) : AnyView(Text(existingEntry == nil ? "发布" : "完成")) }.fontWeight(.semibold).disabled(isSaving || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && media.isEmpty)) }
            }
            .onChange(of: title) { _, _ in persistDraft() }
            .onChange(of: bodyText) { _, _ in persistDraft() }
            .onChange(of: category) { _, _ in persistDraft() }
            .onChange(of: date) { _, _ in persistDraft() }
            .alert("发布失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func persistDraft() {
        guard existingEntry == nil else { return }
        DiaryDraft(title: title, body: bodyText, category: category, date: date).save()
    }

    private func polish() {
        isPolishing = true
        Task {
            defer { isPolishing = false }
            do {
                let result = try await APIClient().polishDiary(body: bodyText)
                bodyText = result.body
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recognizeImageInfo(_ imageData: Data) {
        guard shouldExtractImageInfo else { return }
        Task {
            guard let info = await ImageInfoExtractor.extract(from: imageData) else { return }
            let separator = bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            bodyText += "\(separator)\(info)"
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        uploadCompleted = 0
        uploadTotal = drafts.count
        saveTask = Task {
            defer { isSaving = false; saveTask = nil }
            do {
                if var entry = existingEntry {
                    entry.title = cleanTitle; entry.body = cleanBody; entry.category = category; entry.date = date; entry.media = remoteMedia
                    try await store.updateDiary(entry, drafts: drafts, uploadProgress: updateProgress)
                } else {
                    try await store.createDiary(title: cleanTitle, body: cleanBody, category: category, date: date, drafts: drafts, uploadProgress: updateProgress)
                    DiaryDraft.clear()
                }
                dismiss()
            } catch is CancellationError {
                errorMessage = "已取消上传，已保留当前编辑内容。"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func updateProgress(_ completed: Int, _ total: Int) { uploadCompleted = completed; uploadTotal = total }
    private func cancelUpload() { saveTask?.cancel() }
}

struct PetWallView: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var selectedPet: PetID?
    @AppStorage("danliu.pet.layout") private var layoutRawValue = ContentLayout.waterfall.rawValue
    @State private var filter: PetAssetFilter = .all
    private var layout: ContentLayout { ContentLayout(rawValue: layoutRawValue) ?? .waterfall }

    private var assets: [PetAsset] {
        store.petAssets.filter { asset in
            switch filter {
            case .all: true
            case .image: asset.media.contains { $0.kind == .image }
            case .video: asset.media.contains { $0.kind == .video }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let syncError = store.syncError {
                        BackendStatusNotice(message: syncError)
                    }
                    HStack(spacing: 12) {
                        ForEach(PetID.allCases) { pet in
                            Button { selectedPet = pet } label: {
                                CompactPetCard(profile: pet.profile, assetCount: store.petAssets.filter { $0.petIDs.contains(pet) }.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        filterPicker
                        Spacer(minLength: 0)
                        layoutToggle
                    }

                    if assets.isEmpty {
                        ContentUnavailableView("还没有资源", systemImage: "photo.on.rectangle.angled", description: Text("点击右下角加号，从相册添加照片或视频。"))
                            .padding(.top, 48)
                    } else if layout == .list {
                        LazyVStack(spacing: 12) { ForEach(assets) { PetAssetListCard(asset: $0) } }
                    } else {
                        WaterfallGrid(items: assets) { PetAssetWaterfallCard(asset: $0) }
                    }
                }
                .padding(20)
                .padding(.bottom, 104)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(item: $selectedPet) { PetDetailView(pet: $0) }
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PetAssetFilter.allCases) { item in
                    Button { filter = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == item ? .white : .secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(filter == item ? Color.orange : Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var layoutToggle: some View {
        Button { layoutRawValue = layout.next.rawValue } label: {
            Image(systemName: layout.next.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.background, in: Circle())
        }
        .accessibilityLabel("切换为\(layout.next == .list ? "列表" : "瀑布流")")
    }
}

struct CompactPetCard: View {
    let profile: PetProfile
    let assetCount: Int

    var body: some View {
        HStack(spacing: 9) {
            PetAvatar(pet: profile.id, profile: profile, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.id.rawValue).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                Text("\(assetCount) 个资源").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct PetAvatar: View {
    let pet: PetID
    let profile: PetProfile
    let size: CGFloat
    let isEditable: Bool
    @State private var avatarData: Data?
    @State private var pickerItem: PhotosPickerItem?

    init(pet: PetID, profile: PetProfile, size: CGFloat, isEditable: Bool = false) {
        self.pet = pet
        self.profile = profile
        self.size = size
        self.isEditable = isEditable
        _avatarData = State(initialValue: UserDefaults.standard.data(forKey: Self.avatarKey(for: pet)))
    }

    private static func avatarKey(for pet: PetID) -> String {
        "danliu.pet.avatar.\(pet.rawValue)"
    }

    var body: some View {
        Group {
            if isEditable {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改\(pet.rawValue)头像")
            } else {
                avatar
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                let thumbnail = image.preparingThumbnail(of: CGSize(width: 800, height: 800)) ?? image
                guard let compressedData = thumbnail.jpegData(compressionQuality: 0.82) else { return }
                await MainActor.run {
                    avatarData = compressedData
                    UserDefaults.standard.set(compressedData, forKey: Self.avatarKey(for: pet))
                    pickerItem = nil
                }
            }
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(profile.accent.opacity(0.16))
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: profile.symbol)
                    .font(size >= 60 ? .title : .headline)
                    .foregroundStyle(profile.accent)
            }
            if isEditable {
                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(profile.accent, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct PetAssetListCard: View {
    let asset: PetAsset
    var body: some View {
        HStack(spacing: 13) {
            MediaTile(media: asset.media.first, fallbackSymbol: "photo.fill", tint: .orange).frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 7) {
                PetBadges(pets: asset.petIDs)
                Text(asset.date.relativeChineseTime).font(.caption).foregroundStyle(.secondary)
                Text("\(asset.media.count) 个媒体").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

struct PetAssetWaterfallCard: View {
    let asset: PetAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MediaTile(media: asset.media.first, fallbackSymbol: "photo.fill", tint: .orange)
                .frame(maxWidth: .infinity)
                .frame(height: asset.id.uuidString.hashValue.isMultiple(of: 2) ? 182 : 138)
            PetBadges(pets: asset.petIDs)
            Text(asset.date.relativeChineseTime).font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct PetBadges: View {
    let pets: [PetID]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(pets) { pet in
                Text(pet.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pet.profile.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(pet.profile.accent.opacity(0.13), in: Capsule())
            }
        }
    }
}

struct PetDetailView: View {
    @EnvironmentObject private var store: DiaryStore
    let pet: PetID
    private var profile: PetProfile { pet.profile }
    private var assets: [PetAsset] { store.petAssets.filter { $0.petIDs.contains(pet) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    PetAvatar(pet: pet, profile: profile, size: 70, isEditable: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pet.rawValue).font(.title2.weight(.bold))
                        HStack(spacing: 6) {
                            Text(profile.breed)
                            Text("·")
                            Image(systemName: profile.gender.symbol)
                                .foregroundStyle(profile.gender.tint)
                                .accessibilityLabel(profile.gender.accessibilityLabel)
                            Text("·")
                            Text(profile.ageText)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) { FactTile(label: "品种", value: profile.breed); FactTile(label: "生日", value: profile.birthdayText) }
                Text("资源").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                WaterfallGrid(items: assets) { PetAssetWaterfallCard(asset: $0) }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(pet.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FactTile: View { let label: String; let value: String; var body: some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous)) } }

struct PetPostEditorView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPets: Set<PetID> = [.danHuang]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var media: [ComposerMedia] = []
    @State private var isSaving = false
    @State private var uploadCompleted = 0
    @State private var uploadTotal = 0
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    private var drafts: [DraftMedia] { media.compactMap(\.draftMedia) }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择照片或视频") { ComposerMediaStrip(selection: $pickerItems, media: $media, disabled: isSaving) }
                Section("标记宠物") {
                    ForEach(PetID.allCases) { pet in
                        Button {
                            if selectedPets.contains(pet) { selectedPets.remove(pet) } else { selectedPets.insert(pet) }
                        } label: {
                            HStack {
                                Image(systemName: pet.profile.symbol).foregroundStyle(pet.profile.accent).frame(width: 26)
                                Text(pet.rawValue)
                                Spacer()
                                if selectedPets.contains(pet) { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(isSaving)
                    }
                }
                if isSaving { Section { UploadProgressBanner(completed: uploadCompleted, total: uploadTotal, cancel: cancelUpload) } }
            }
            .navigationTitle("添加宠物资源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { isSaving ? AnyView(ProgressView().controlSize(.small)) : AnyView(Text("添加")) }
                        .fontWeight(.semibold)
                        .disabled(isSaving || drafts.isEmpty || selectedPets.isEmpty)
                }
            }
            .alert("添加失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        isSaving = true
        uploadCompleted = 0
        uploadTotal = drafts.count
        saveTask = Task {
            defer { isSaving = false; saveTask = nil }
            do {
                try await store.createPetAsset(petIDs: PetID.allCases.filter { selectedPets.contains($0) }, drafts: drafts, uploadProgress: updateProgress)
                dismiss()
            } catch is CancellationError { errorMessage = "已取消上传，媒体仍保留在当前页面。" }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func updateProgress(_ completed: Int, _ total: Int) { uploadCompleted = completed; uploadTotal = total }
    private func cancelUpload() { saveTask?.cancel() }
}

struct LifeMuseumView: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var selectedMedia: MediaAttachment?

    private var items: [GalleryPhoto] {
        let diaryPhotos = store.entries.flatMap { entry in
            entry.media
                .filter { $0.kind == .image }
                .map { GalleryPhoto(id: "diary-\(entry.id.uuidString)-\($0.id.uuidString)", media: $0, date: entry.date) }
        }
        let petPhotos = store.petAssets.flatMap { asset in
            asset.media
                .filter { $0.kind == .image }
                .map { GalleryPhoto(id: "pet-\(asset.id.uuidString)-\($0.id.uuidString)", media: $0, date: asset.date) }
        }
        return (diaryPhotos + petPhotos).sorted { $0.date > $1.date }
    }

    private var months: [GalleryMonth] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: items) { item in
            calendar.date(from: calendar.dateComponents([.year, .month], from: item.date)) ?? item.date
        }
        return grouped
            .map { GalleryMonth(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    private var images: [MediaAttachment] { items.map(\.media) }

    var body: some View {
        NavigationStack {
            Group {
                if months.isEmpty {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                } else {
                    GeometryReader { proxy in
                        let contentWidth = max(0, proxy.size.width - 36)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 34) {
                                ForEach(months) { month in
                                    GalleryMonthSection(month: month, contentWidth: contentWidth) { media in
                                        selectedMedia = media
                                    }
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                            .padding(.top, 22)
                            .padding(.bottom, 36)
                        }
                        .frame(width: proxy.size.width)
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.965, green: 0.957, blue: 0.937))
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedMedia) { media in
                FullScreenMediaViewer(
                    media: images,
                    initialID: media.id,
                    fallbackSymbol: "photo.fill",
                    tint: .orange
                )
            }
        }
    }
}

private struct GalleryPhoto: Identifiable {
    let id: String
    let media: MediaAttachment
    let date: Date
}

private struct GalleryMonth: Identifiable {
    let date: Date
    let items: [GalleryPhoto]
    var id: Date { date }

    var title: String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month())
    }
}

private struct GalleryMonthSection: View {
    let month: GalleryMonth
    let contentWidth: CGFloat
    let select: (MediaAttachment) -> Void
    @State private var aspectRatios: [String: CGFloat] = [:]

    private var rows: [[GalleryPhoto]] {
        var result: [[GalleryPhoto]] = []
        var current: [GalleryPhoto] = []
        var totalAspect: CGFloat = 0
        let targetAspect: CGFloat = contentWidth > 390 ? 2.7 : 2.35

        for item in month.items {
            let aspect = aspectRatios[item.id] ?? 1
            current.append(item)
            totalAspect += aspect
            if totalAspect >= targetAspect {
                result.append(current)
                current = []
                totalAspect = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(month.title)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(Color(red: 0.56, green: 0.55, blue: 0.52))
                .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GalleryPhotoRow(
                        items: row,
                        availableWidth: contentWidth,
                        isLastRow: rowIndex == rows.indices.last,
                        aspectRatios: aspectRatios,
                        select: select,
                        updateAspectRatio: updateAspectRatio
                    )
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: aspectRatios)
    }

    private func updateAspectRatio(_ ratio: CGFloat, for id: String) {
        guard ratio.isFinite, ratio > 0, aspectRatios[id] != ratio else { return }
        aspectRatios[id] = ratio
    }
}

private struct GalleryPhotoRow: View {
    let items: [GalleryPhoto]
    let availableWidth: CGFloat
    let isLastRow: Bool
    let aspectRatios: [String: CGFloat]
    let select: (MediaAttachment) -> Void
    let updateAspectRatio: (CGFloat, String) -> Void
    private let spacing: CGFloat = 10

    private var totalAspect: CGFloat { items.reduce(0) { $0 + (aspectRatios[$1.id] ?? 1) } }
    private var rowHeight: CGFloat {
        let fullWidthHeight = max(76, (availableWidth - CGFloat(max(0, items.count - 1)) * spacing) / max(totalAspect, 0.1))
        return isLastRow ? min(fullWidthHeight, 156) : min(fullWidthHeight, 190)
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items) { item in
                let ratio = aspectRatios[item.id] ?? 1
                let width = max(56, rowHeight * ratio)
                Button { select(item.media) } label: {
                    PinnedPhoto(
                        media: item.media,
                        date: item.date,
                        width: width,
                        imageHeight: rowHeight,
                        rotation: paperRotation(for: item.id),
                        verticalOffset: paperOffset(for: item.id),
                        onAspectRatio: { updateAspectRatio($0, item.id) }
                    )
                }
                .buttonStyle(.plain)
                .frame(width: width)
            }
        }
        .frame(width: availableWidth, alignment: .leading)
    }

    private func paperRotation(for id: String) -> Angle {
        let values: [Double] = [-1.45, 0.9, -0.65, 1.2, -1.0, 0.55]
        return .degrees(values[stableIndex(for: id, count: values.count)])
    }

    private func paperOffset(for id: String) -> CGFloat {
        let values: [CGFloat] = [2, -1, 1, -2, 0, 1]
        return values[stableIndex(for: id, count: values.count)]
    }

    private func stableIndex(for id: String, count: Int) -> Int {
        abs(id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % count
    }
}

private struct PinnedPhoto: View {
    let media: MediaAttachment
    let date: Date
    let width: CGFloat
    let imageHeight: CGFloat
    let rotation: Angle
    let verticalOffset: CGFloat
    let onAspectRatio: (CGFloat) -> Void

    private var dateText: String {
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            GalleryRemoteImage(media: media, onAspectRatio: onAspectRatio)
                .frame(width: width - 12, height: imageHeight)
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .background(.white)

            Text(dateText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.54, green: 0.53, blue: 0.50))
                .frame(width: width, height: 28)
                .background(.white)
        }
        .rotationEffect(rotation)
        .offset(y: verticalOffset)
        .shadow(color: .black.opacity(0.045), radius: 2, y: 1)
        .accessibilityLabel("打开 \(dateText) 的照片")
    }
}

private struct GalleryRemoteImage: View {
    let media: MediaAttachment
    let onAspectRatio: (CGFloat) -> Void
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if didFail || media.remoteURL == nil {
                Image(systemName: "photo.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else {
                ProgressView()
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .task(id: media.remoteURL) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard image == nil, !didFail, let url = media.remoteURL.flatMap(URL.init(string:)) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let downloadedImage = UIImage(data: data), downloadedImage.size.height > 0 else {
                didFail = true
                return
            }
            image = downloadedImage
            onAspectRatio(downloadedImage.size.width / downloadedImage.size.height)
        } catch {
            didFail = true
        }
    }
}

#Preview { ContentView().environmentObject(DiaryStore()) }
