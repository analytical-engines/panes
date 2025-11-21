import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @State private var isFilePickerPresented = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            // 背景（クリック可能にして全体でフォーカスを受け取る）
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // タップでフォーカスを確保
                }

            if let image = viewModel.currentImage {
                // 画像表示
                VStack(spacing: 0) {
                    // 画像エリア
                    ImageDisplayView(image: image)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 画像タップでもフォーカスを確保
                        }

                    // ステータスバー
                    HStack {
                        Text(viewModel.archiveFileName)
                            .foregroundColor(.white)
                        Spacer()
                        Text(viewModel.currentFileName)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(viewModel.pageInfo)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                }
            } else {
                // ファイル未選択時の表示
                VStack(spacing: 20) {
                    Text("ImageViewer")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    } else {
                        Text("zipファイルまたは画像ファイルをドロップ")
                            .foregroundColor(.gray)
                    }

                    Button("ファイルを開く") {
                        openFilePicker()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusable()  // フォーカス可能にする
        .focusEffectDisabled()  // フォーカスリングを非表示
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onKeyPress(.leftArrow) {
            viewModel.nextPage()  // 右→左なので、左矢印で次ページ
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.previousPage()  // 右→左なので、右矢印で前ページ
            return .handled
        }
        .onKeyPress(keys: [.space]) { press in
            // Shift+Spaceなら前ページ、通常Spaceなら次ページ
            if press.modifiers.contains(.shift) {
                viewModel.previousPage()
            } else {
                viewModel.nextPage()
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { press in
            // Command+Control+Fでフルスクリーン切り替え
            if press.modifiers.contains(.command) && press.modifiers.contains(.control) {
                toggleFullScreen()
                return .handled
            }
            return .ignored
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true  // 複数選択可能に
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .jpeg, .png]
        panel.message = "zipファイルまたは画像ファイルを選択してください"

        if panel.runModal() == .OK {
            let urls = panel.urls
            viewModel.openFiles(urls: urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: "public.file-url")
                        if let data = item as? Data,
                           let path = String(data: data, encoding: .utf8),
                           let url = URL(string: path) {
                            urls.append(url)
                        } else if let url = item as? URL {
                            urls.append(url)
                        }
                    } catch {
                        print("Failed to load item: \(error)")
                    }
                }
            }

            // メインスレッドでファイルを開く
            await MainActor.run {
                if !urls.isEmpty {
                    self.viewModel.openFiles(urls: urls)
                }
            }
        }
    }
}
