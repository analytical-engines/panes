import SwiftUI

/// サードパーティライブラリのライセンス情報
struct LibraryLicense: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let license: String
    let copyright: String
}

/// ライセンス一覧表示ビュー
struct AcknowledgementsView: View {
    private let libraries: [LibraryLicense] = [
        LibraryLicense(
            name: "ZIPFoundation",
            url: "https://github.com/weichsel/ZIPFoundation",
            license: "MIT",
            copyright: "Copyright (c) 2017-2024 Thomas Zoechling"
        ),
        LibraryLicense(
            name: "SWCompression",
            url: "https://github.com/tsolomko/SWCompression",
            license: "MIT",
            copyright: "Copyright (c) 2016-2024 Timofey Solomko"
        ),
        LibraryLicense(
            name: "BitByteData",
            url: "https://github.com/tsolomko/BitByteData",
            license: "MIT",
            copyright: "Copyright (c) 2018-2024 Timofey Solomko"
        ),
        LibraryLicense(
            name: "Unrar.swift",
            url: "https://github.com/mtgto/Unrar.swift",
            license: "MIT",
            copyright: "Copyright (c) 2021 mtgto"
        ),
        LibraryLicense(
            name: "swift-system",
            url: "https://github.com/apple/swift-system",
            license: "Apache 2.0",
            copyright: "Copyright (c) 2020 Apple Inc."
        ),
        LibraryLicense(
            name: "ZipArchive (swift-zip-archive)",
            url: "https://github.com/adam-fowler/swift-zip-archive",
            license: "Apache 2.0",
            copyright: "Copyright 2025 Adam Fowler"
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("acknowledgements_title"))
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(libraries) { library in
                        LibraryRow(library: library)
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 400)
    }
}

/// ライブラリ情報の行
private struct LibraryRow: View {
    let library: LibraryLicense

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(library.name)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Text(library.license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            Text(library.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(library.url)
                .font(.caption)
                .foregroundStyle(.link)
                .onTapGesture {
                    if let url = URL(string: library.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AcknowledgementsView()
}
