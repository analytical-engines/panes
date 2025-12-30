import Foundation
import AppKit
import CryptoKit

/// 入れ子書庫やディレクトリを展開してCompositeImageSourceを構築するビルダー
/// 書庫内に他の書庫ファイルが含まれている場合、それらを自動展開して
/// フラットな画像リストとして表示できるようにする
/// また、複数のディレクトリが含まれる場合もディレクトリごとにセグメント化する
class NestedArchiveBuilder {

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 書庫URLからCompositeImageSourceを構築
    /// 入れ子書庫やディレクトリ構造がない場合はnilを返す（通常のImageSourceを使用すべき）
    static func build(
        from url: URL,
        password: String? = nil,
        onPhaseChange: PhaseCallback? = nil
    ) async -> CompositeImageSource? {
        let ext = url.pathExtension.lowercased()

        // 書庫タイプに応じてリーダーを作成
        if ext == "zip" || ext == "cbz" {
            return await buildFromZip(url: url, password: password, onPhaseChange: onPhaseChange)
        } else if ext == "rar" || ext == "cbr" {
            return await buildFromRar(url: url, password: password, onPhaseChange: onPhaseChange)
        } else if ext == "7z" || ext == "cb7" {
            return await buildFrom7z(url: url, onPhaseChange: onPhaseChange)
        }

        return nil
    }

    // MARK: - Directory Grouping Helper

    /// 画像ファイル名からディレクトリパスを抽出
    private static func extractDirectoryPath(from fileName: String) -> String {
        let nsPath = fileName as NSString
        let directory = nsPath.deletingLastPathComponent
        return directory.isEmpty ? "/" : directory
    }

    /// ディレクトリごとに画像インデックスをグループ化
    /// - Returns: [(ディレクトリ名, インデックス配列)] のソート済み配列、セグメント化不要な場合はnil
    private static func groupImagesByDirectory(
        imageNames: [String],
        imageIndexGetter: (String) -> Int?
    ) -> [(directory: String, indices: [Int])]? {
        // ディレクトリごとにグループ化
        var directoryGroups: [String: [Int]] = [:]

        for name in imageNames {
            guard let index = imageIndexGetter(name) else { continue }
            let directory = extractDirectoryPath(from: name)
            directoryGroups[directory, default: []].append(index)
        }

        // ユニークなディレクトリが1つ以下ならセグメント化不要
        if directoryGroups.count <= 1 {
            return nil
        }

        // ディレクトリ名でソートして配列化
        let sortedGroups = directoryGroups.keys.sorted { dir1, dir2 in
            dir1.localizedStandardCompare(dir2) == .orderedAscending
        }.map { directory in
            (directory: directory, indices: directoryGroups[directory]!)
        }

        return sortedGroups
    }

    // MARK: - ZIP Archive Building

    private static func buildFromZip(
        url: URL,
        password: String?,
        onPhaseChange: PhaseCallback?
    ) async -> CompositeImageSource? {
        guard let reader = await SwiftZipReader.create(url: url, password: password, onPhaseChange: onPhaseChange) else {
            return nil
        }

        // 入れ子書庫がある場合は入れ子書庫を展開
        if reader.nestedArchiveCount > 0 {
            return await buildComposite(
                archiveURL: url,
                allSortedNames: reader.allSortedEntryNames,
                imageGetter: { name in
                    reader.imageIndex(forName: name)
                },
                nestedArchiveGetter: { name in
                    reader.nestedArchiveIndex(forName: name)
                },
                createParentSource: { indices in
                    PartialSwiftZipImageSource(reader: reader, url: url, indices: indices)
                },
                extractNestedArchive: { index in
                    reader.extractNestedArchive(at: index)
                },
                getNestedArchiveName: { index in
                    reader.nestedArchiveName(at: index) ?? "nested"
                },
                onPhaseChange: onPhaseChange
            )
        }

        // 入れ子書庫がない場合、ディレクトリによるセグメント化を試みる
        return buildDirectorySegments(
            archiveURL: url,
            imageNames: reader.allSortedEntryNames,
            imageIndexGetter: { name in reader.imageIndex(forName: name) },
            createPartialSource: { indices in
                PartialSwiftZipImageSource(reader: reader, url: url, indices: indices)
            }
        )
    }

    // MARK: - RAR Archive Building

    private static func buildFromRar(
        url: URL,
        password: String?,
        onPhaseChange: PhaseCallback?
    ) async -> CompositeImageSource? {
        guard let reader = await RarReader.create(url: url, password: password, onPhaseChange: onPhaseChange) else {
            return nil
        }

        // 入れ子書庫がある場合は入れ子書庫を展開
        if reader.nestedArchiveCount > 0 {
            return await buildComposite(
                archiveURL: url,
                allSortedNames: reader.allSortedEntryNames,
                imageGetter: { name in
                    reader.imageIndex(forName: name)
                },
                nestedArchiveGetter: { name in
                    reader.nestedArchiveIndex(forName: name)
                },
                createParentSource: { indices in
                    PartialRarImageSource(reader: reader, url: url, indices: indices)
                },
                extractNestedArchive: { index in
                    reader.extractNestedArchive(at: index)
                },
                getNestedArchiveName: { index in
                    reader.nestedArchiveName(at: index) ?? "nested"
                },
                onPhaseChange: onPhaseChange
            )
        }

        // 入れ子書庫がない場合、ディレクトリによるセグメント化を試みる
        return buildDirectorySegments(
            archiveURL: url,
            imageNames: reader.allSortedEntryNames,
            imageIndexGetter: { name in reader.imageIndex(forName: name) },
            createPartialSource: { indices in
                PartialRarImageSource(reader: reader, url: url, indices: indices)
            }
        )
    }

    // MARK: - 7z Archive Building

    private static func buildFrom7z(
        url: URL,
        onPhaseChange: PhaseCallback?
    ) async -> CompositeImageSource? {
        guard let reader = await SevenZipReader.create(url: url, onPhaseChange: onPhaseChange) else {
            return nil
        }

        // 入れ子書庫がある場合は入れ子書庫を展開
        if reader.nestedArchiveCount > 0 {
            return await buildComposite(
                archiveURL: url,
                allSortedNames: reader.allSortedEntryNames,
                imageGetter: { name in
                    reader.imageIndex(forName: name)
                },
                nestedArchiveGetter: { name in
                    reader.nestedArchiveIndex(forName: name)
                },
                createParentSource: { indices in
                    PartialSevenZipImageSource(reader: reader, url: url, indices: indices)
                },
                extractNestedArchive: { index in
                    reader.extractNestedArchive(at: index)
                },
                getNestedArchiveName: { index in
                    reader.nestedArchiveName(at: index) ?? "nested"
                },
                onPhaseChange: onPhaseChange
            )
        }

        // 入れ子書庫がない場合、ディレクトリによるセグメント化を試みる
        return buildDirectorySegments(
            archiveURL: url,
            imageNames: reader.allSortedEntryNames,
            imageIndexGetter: { name in reader.imageIndex(forName: name) },
            createPartialSource: { indices in
                PartialSevenZipImageSource(reader: reader, url: url, indices: indices)
            }
        )
    }

    // MARK: - Directory Segment Building

    /// ディレクトリごとにセグメント化したCompositeImageSourceを構築
    /// - Returns: 複数ディレクトリがある場合はCompositeImageSource、そうでなければnil
    private static func buildDirectorySegments(
        archiveURL: URL,
        imageNames: [String],
        imageIndexGetter: (String) -> Int?,
        createPartialSource: ([Int]) -> ImageSource
    ) -> CompositeImageSource? {
        // ディレクトリごとにグループ化
        guard let groups = groupImagesByDirectory(
            imageNames: imageNames,
            imageIndexGetter: imageIndexGetter
        ) else {
            // セグメント化不要
            return nil
        }

        let composite = CompositeImageSource(archiveURL: archiveURL)

        DebugLogger.log("📂 NestedArchiveBuilder: Building directory segments from \(groups.count) directories", level: .normal)

        for group in groups {
            // 各ディレクトリをセグメントとして追加
            let source = createPartialSource(group.indices)
            composite.addSegment(source: source, name: group.directory)
            DebugLogger.log("📂 NestedArchiveBuilder: Added directory segment: \(group.directory) (\(group.indices.count) images)", level: .normal)
        }

        DebugLogger.log("📂 NestedArchiveBuilder: Built composite with \(composite.imageCount) total images in \(groups.count) directories", level: .normal)
        return composite
    }

    // MARK: - Generic Composite Building

    /// 汎用的なCompositeImageSource構築ロジック（入れ子書庫用）
    private static func buildComposite(
        archiveURL: URL,
        allSortedNames: [String],
        imageGetter: (String) -> Int?,
        nestedArchiveGetter: (String) -> Int?,
        createParentSource: ([Int]) -> ImageSource,
        extractNestedArchive: (Int) -> URL?,
        getNestedArchiveName: (Int) -> String,
        onPhaseChange: PhaseCallback?
    ) async -> CompositeImageSource {
        let composite = CompositeImageSource(archiveURL: archiveURL)

        DebugLogger.log("📦 NestedArchiveBuilder: Building composite from \(allSortedNames.count) sorted entries", level: .normal)

        var currentImageIndices: [Int] = []

        var entryIndex = 0
        for name in allSortedNames {
            if let imageIndex = imageGetter(name) {
                // 画像エントリ - 収集する
                currentImageIndices.append(imageIndex)
            } else if let archiveIndex = nestedArchiveGetter(name) {
                DebugLogger.log("📦 NestedArchiveBuilder: Found nested archive at position \(entryIndex): '\(name)'", level: .verbose)

                // 書庫エントリ - まず収集した画像をセグメントとして追加
                if !currentImageIndices.isEmpty {
                    DebugLogger.log("📦 NestedArchiveBuilder: Flushing \(currentImageIndices.count) parent images", level: .verbose)
                    let source = createParentSource(currentImageIndices)
                    composite.addSegment(source: source, name: "")
                    currentImageIndices = []
                }

                // 入れ子書庫を展開してセグメントとして追加
                let archiveName = getNestedArchiveName(archiveIndex)
                if let tempURL = extractNestedArchive(archiveIndex) {
                    if let nestedSource = await createImageSource(for: tempURL) {
                        composite.addSegment(
                            source: nestedSource,
                            name: (archiveName as NSString).lastPathComponent,
                            tempFileURL: tempURL
                        )
                        DebugLogger.log("📦 NestedArchiveBuilder: Added nested segment: \((archiveName as NSString).lastPathComponent) (\(nestedSource.imageCount) images)", level: .normal)
                    } else {
                        // 入れ子書庫を開けなかった場合は一時ファイルを削除
                        try? FileManager.default.removeItem(at: tempURL)
                        DebugLogger.log("⚠️ NestedArchiveBuilder: Failed to open nested archive: \(archiveName)", level: .minimal)
                    }
                }
            }
            entryIndex += 1
        }

        // 残りの画像をセグメントとして追加
        if !currentImageIndices.isEmpty {
            DebugLogger.log("📦 NestedArchiveBuilder: Flushing \(currentImageIndices.count) remaining parent images", level: .verbose)
            let source = createParentSource(currentImageIndices)
            composite.addSegment(source: source, name: "")
        }

        DebugLogger.log("📦 NestedArchiveBuilder: Built composite with \(composite.imageCount) total images", level: .normal)
        return composite
    }

    /// URLから適切なImageSourceを作成（入れ子書庫用）
    private static func createImageSource(for url: URL) async -> ImageSource? {
        let ext = url.pathExtension.lowercased()

        if ext == "zip" || ext == "cbz" {
            // 入れ子書庫の場合は再帰的にCompositeを試みるが、1段階のみなので通常のソースを使用
            return await SwiftZipImageSource.create(url: url)
        } else if ext == "rar" || ext == "cbr" {
            return await RarImageSource.create(url: url)
        } else if ext == "7z" || ext == "cb7" {
            return await SevenZipImageSource.create(url: url)
        }

        return nil
    }
}

// MARK: - Partial Image Sources

/// SwiftZipReaderの一部のインデックスのみを公開するImageSource
class PartialSwiftZipImageSource: ImageSource {
    private let reader: SwiftZipReader
    private let archiveURL: URL
    private let indices: [Int]  // 元のリーダーでのインデックス

    init(reader: SwiftZipReader, url: URL, indices: [Int]) {
        self.reader = reader
        self.archiveURL = url
        self.indices = indices
    }

    var sourceName: String { archiveURL.lastPathComponent }
    var imageCount: Int { indices.count }
    var sourceURL: URL? { archiveURL }
    var isStandaloneImageSource: Bool { false }

    func loadImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.loadImage(at: indices[index])
    }

    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileName(at: indices[index])
    }

    func imageSize(at index: Int) -> CGSize? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageSize(at: indices[index])
    }

    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileSize(at: indices[index])
    }

    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageFormat(at: indices[index])
    }

    func fileDate(at index: Int) -> Date? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileDate(at: indices[index])
    }

    func imageRelativePath(at index: Int) -> String? {
        return fileName(at: index)
    }

    func generateImageFileKey(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        guard let imageData = reader.imageData(at: indices[index]) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}

/// RarReaderの一部のインデックスのみを公開するImageSource
class PartialRarImageSource: ImageSource {
    private let reader: RarReader
    private let archiveURL: URL
    private let indices: [Int]

    init(reader: RarReader, url: URL, indices: [Int]) {
        self.reader = reader
        self.archiveURL = url
        self.indices = indices
    }

    var sourceName: String { archiveURL.lastPathComponent }
    var imageCount: Int { indices.count }
    var sourceURL: URL? { archiveURL }
    var isStandaloneImageSource: Bool { false }

    func loadImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.loadImage(at: indices[index])
    }

    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileName(at: indices[index])
    }

    func imageSize(at index: Int) -> CGSize? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageSize(at: indices[index])
    }

    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileSize(at: indices[index])
    }

    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageFormat(at: indices[index])
    }

    func fileDate(at index: Int) -> Date? {
        return nil  // RarReaderは日付を返さない
    }

    func imageRelativePath(at index: Int) -> String? {
        return fileName(at: index)
    }

    func generateImageFileKey(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        guard let imageData = reader.imageData(at: indices[index]) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}

/// SevenZipReaderの一部のインデックスのみを公開するImageSource
class PartialSevenZipImageSource: ImageSource {
    private let reader: SevenZipReader
    private let archiveURL: URL
    private let indices: [Int]

    init(reader: SevenZipReader, url: URL, indices: [Int]) {
        self.reader = reader
        self.archiveURL = url
        self.indices = indices
    }

    var sourceName: String { archiveURL.lastPathComponent }
    var imageCount: Int { indices.count }
    var sourceURL: URL? { archiveURL }
    var isStandaloneImageSource: Bool { false }

    func loadImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.loadImage(at: indices[index])
    }

    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileName(at: indices[index])
    }

    func imageSize(at index: Int) -> CGSize? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageSize(at: indices[index])
    }

    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.fileSize(at: indices[index])
    }

    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        return reader.imageFormat(at: indices[index])
    }

    func fileDate(at index: Int) -> Date? {
        return nil  // SevenZipReaderは日付を返さない
    }

    func imageRelativePath(at index: Int) -> String? {
        return fileName(at: index)
    }

    func generateImageFileKey(at index: Int) -> String? {
        guard index >= 0 && index < indices.count else { return nil }
        guard let imageData = reader.imageData(at: indices[index]) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}
