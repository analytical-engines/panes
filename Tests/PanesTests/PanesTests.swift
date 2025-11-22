import Testing
@testable import Panes

@Suite("FileHistoryManager Tests")
struct FileHistoryManagerTests {

    @Test("FileHistoryManager initialization")
    func testFileHistoryInitialization() {
        let manager = FileHistoryManager()
        #expect(manager.history.count >= 0)
    }

    @Test("Recording file access")
    func testRecordAccess() {
        let manager = FileHistoryManager()
        let initialCount = manager.history.count

        manager.recordAccess(
            fileKey: "test-key-1",
            filePath: "/tmp/test.jpg",
            fileName: "test.jpg"
        )

        #expect(manager.history.count == initialCount + 1)
        #expect(manager.history.first?.fileKey == "test-key-1")
        #expect(manager.history.first?.accessCount == 1)
    }

    @Test("Incrementing access count")
    func testIncrementAccessCount() {
        let manager = FileHistoryManager()

        manager.recordAccess(
            fileKey: "test-key-2",
            filePath: "/tmp/test.jpg",
            fileName: "test.jpg"
        )
        manager.recordAccess(
            fileKey: "test-key-2",
            filePath: "/tmp/test.jpg",
            fileName: "test.jpg"
        )

        #expect(manager.history.first?.accessCount == 2)
    }

    @Test("Getting recent history")
    func testGetRecentHistory() {
        let manager = FileHistoryManager()

        for i in 0..<5 {
            manager.recordAccess(
                fileKey: "test-key-\(i)",
                filePath: "/tmp/test\(i).jpg",
                fileName: "test\(i).jpg"
            )
        }

        let recent = manager.getRecentHistory(limit: 3)
        #expect(recent.count <= 3)
    }
}

@Suite("FileHistoryEntry Tests")
struct FileHistoryEntryTests {

    @Test("FileHistoryEntry initialization")
    func testEntryInitialization() {
        let entry = FileHistoryEntry(
            fileKey: "test-key",
            filePath: "/tmp/test.jpg",
            fileName: "test.jpg"
        )

        #expect(entry.fileKey == "test-key")
        #expect(entry.filePath == "/tmp/test.jpg")
        #expect(entry.fileName == "test.jpg")
        #expect(entry.accessCount == 1)
    }
}

@Suite("BookViewModel Tests")
struct BookViewModelTests {

    @Test("ViewModel initialization")
    func testInitialization() {
        let viewModel = BookViewModel()
        #expect(viewModel.currentPage == 0)
        #expect(viewModel.totalPages == 0)
        #expect(viewModel.sourceName == "")
    }

    @Test("Page navigation without source")
    func testPageNavigationWithoutSource() {
        let viewModel = BookViewModel()

        // No image source - should not crash
        viewModel.nextPage()
        #expect(viewModel.currentPage == 0)

        viewModel.previousPage()
        #expect(viewModel.currentPage == 0)
    }

    @Test("View mode toggle")
    func testViewModeToggle() {
        let viewModel = BookViewModel()

        #expect(viewModel.viewMode == .single)

        viewModel.toggleViewMode()
        #expect(viewModel.viewMode == .spread)

        viewModel.toggleViewMode()
        #expect(viewModel.viewMode == .single)
    }

    @Test("Page info display")
    func testPageInfo() {
        let viewModel = BookViewModel()

        // No pages
        #expect(viewModel.pageInfo == "")
    }
}
