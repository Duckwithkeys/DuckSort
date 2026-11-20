//
//  PhotoLibraryViewModel.swift
//  PhotomatorSort
//
//  Main-actor state container. Owns the photo library, tag store, export
//  rule store, and the routed copy/move/export workflow. File-system work
//  runs through actors so scans and transfers never block SwiftUI updates.
//

import Combine
import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    
    // MARK: - Stores
    
    let tagStore: TagStore
    let ruleStore: ExportRuleStore
    let packLibrary: TagPackLibrary
    
    private var isInitializing = true
    
    // MARK: - Published state
    
    @Published private(set) var sourceDirectories: [URL] = []
    /// Individually imported files (via drag-and-drop or Import…) that live
    /// outside of a scanned source directory.
    @Published private(set) var looseFiles: [URL] = []
    @Published private(set) var failedSources: Set<URL> = []
    @Published private(set) var destinationDirectory: URL?
    private var isMutatingSelectionOnly = false

    @Published var photoSets: [PhotoSet] = [] {
        didSet {
            guard !isMutatingSelectionOnly else { return }
            rebuildPhotoSetIndex()
            updateGlobalCounts()
            setNeedsDerivedUpdate()
        }
    }

    /// O(1) lookup of a photo set's index in `photoSets` by its ID. Rebuilt
    /// inside the `photoSets` didSet so it stays in sync with the published
    /// array. Every method that previously did `photoSets.firstIndex(where:)`
    /// should go through this index instead.
    private var photoSetIndex: [UUID: Int] = [:]
    private var suppressDerivedUpdates = false
    private var derivedStateDirty = false

    private func setNeedsDerivedUpdate() {
        guard !suppressDerivedUpdates else { return }
        guard !derivedStateDirty else { return }
        derivedStateDirty = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.derivedStateDirty = false
            self.updateDerivedState()
        }
    }

    func batchUpdate(_ body: () -> Void) {
        suppressDerivedUpdates = true
        body()
        suppressDerivedUpdates = false
        updateDerivedState()
    }

    private func rebuildPhotoSetIndex() {
        photoSetIndex = Dictionary(uniqueKeysWithValues: photoSets.enumerated().map { ($1.id, $0) })
    }
    @Published private(set) var photoMetadata: [UUID: MetadataSnapshot] = [:]
    @Published private(set) var exifLoadProgress: (completed: Int, total: Int)? = nil
    private var lastFolderIndexKey: (count: Int, sources: [URL], firstID: UUID?, lastID: UUID?) = (-1, [], nil, nil)

    func setPhotoMetadata(for id: UUID, metadata: MetadataSnapshot) {
        photoMetadata[id] = metadata
        photoDateCache.removeValue(forKey: id)
        setNeedsDerivedUpdate()
    }
    @Published private(set) var photoCaptions: [UUID: String] = [:]
    @Published private(set) var visionSuggestionsCache: [UUID: [AutoTagSuggestion]] = [:]
    @Published var filterRule: PhotoFilterRule = .allPhotos {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.lastFilterRule = filterRule
            UserPreferences.shared.save()
            setNeedsDerivedUpdate()
        }
    }
    @Published var selectedTagFilters: Set<UUID> = [] {
        didSet {
            setNeedsDerivedUpdate()
        }
    }
    @Published var selectedFlags: Set<Int> = [] {
        didSet {
            setNeedsDerivedUpdate()
        }
    }
    @Published var selectedRatings: Set<Int> = [] {
        didSet {
            setNeedsDerivedUpdate()
        }
    }


    @Published var isInspectorOpen: Bool = false {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.isInspectorOpen = isInspectorOpen
            UserPreferences.shared.save()
        }
    }

    @Published var speedCullingEnabled: Bool = false {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.speedCullingEnabled = speedCullingEnabled
            UserPreferences.shared.save()
        }
    }

    // MARK: - Sorting and Filtering State

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Date Descending (Newest First)"
        case dateAscending = "Date Ascending (Oldest First)"
        case nameAscending = "Name (A–Z)"
        case nameDescending = "Name (Z–A)"
        case fileSizeDescending = "File Size (Largest / Smallest)"
        case fileSizeAscending = "File Size (Smallest / Largest)"

        var id: String { rawValue }
    }
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case date = "Date"
        case size = "File Size"
    }

    enum SortDirection: String, CaseIterable {
        case ascending = "Ascending"
        case descending = "Descending"
    }

    enum BinaryFilter: String, CaseIterable {
        case include = "Include"
        case exclude = "Exclude"
    }

    enum RatingCondition: String, CaseIterable {
        case equalTo = "Equal to"
        case greaterThanOrEqualTo = "Greater than or equal to"
        case lessThanOrEqualTo = "Less than or equal to"
    }

    enum FlagFilter: String, CaseIterable {
        case all = "All Flags"
        case flagged = "Flagged"
        case rejected = "Rejected"
        case unflagged = "Unflagged"
    }

    enum NameCondition: String, CaseIterable {
        case contains = "Contains"
        case matches = "Matches"
        case startsWith = "Starts with"
        case endsWith = "Ends with"
    }

    private var isSyncingSort = false

    @Published var sortOption: SortOption = .dateDescending {
        didSet {
            guard !isSyncingSort else { return }
            isSyncingSort = true
            defer { isSyncingSort = false }
            switch sortOption {
            case .dateDescending:
                sortOrder = .date
                sortDirection = .descending
            case .dateAscending:
                sortOrder = .date
                sortDirection = .ascending
            case .nameAscending:
                sortOrder = .name
                sortDirection = .ascending
            case .nameDescending:
                sortOrder = .name
                sortDirection = .descending
            case .fileSizeDescending:
                sortOrder = .size
                sortDirection = .descending
            case .fileSizeAscending:
                sortOrder = .size
                sortDirection = .ascending
            }
            setNeedsDerivedUpdate()
        }
    }

    @Published var sortOrder: SortOrder = .date {
        didSet {
            guard !isSyncingSort else { return }
            isSyncingSort = true
            defer { isSyncingSort = false }
            syncSortOption()
            setNeedsDerivedUpdate()
        }
    }
    @Published var sortDirection: SortDirection = .descending {
        didSet {
            guard !isSyncingSort else { return }
            isSyncingSort = true
            defer { isSyncingSort = false }
            syncSortOption()
            setNeedsDerivedUpdate()
        }
    }

    private func syncSortOption() {
        switch (sortOrder, sortDirection) {
        case (.date, .descending):
            if sortOption != .dateDescending { sortOption = .dateDescending }
        case (.date, .ascending):
            if sortOption != .dateAscending { sortOption = .dateAscending }
        case (.name, .ascending):
            if sortOption != .nameAscending { sortOption = .nameAscending }
        case (.name, .descending):
            if sortOption != .nameDescending { sortOption = .nameDescending }
        case (.size, .descending):
            if sortOption != .fileSizeDescending { sortOption = .fileSizeDescending }
        case (.size, .ascending):
            if sortOption != .fileSizeAscending { sortOption = .fileSizeAscending }
        }
    }
    @Published var isFilterPopoverEnabled: Bool = true {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterEditedActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterEdited: BinaryFilter = .include {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterRawActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterRaw: BinaryFilter = .include {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterRatingActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterRatingValue: Int = 0 {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterRatingCondition: RatingCondition = .equalTo {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterFlagActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterFlag: FlagFilter = .all {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterNameActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var nameFilterQuery: String = "" {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var nameFilterCondition: NameCondition = .contains {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterDateActive: Bool = false {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterStartDate: Date = Date() {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published var filterEndDate: Date = Date() {
        didSet { setNeedsDerivedUpdate() }
    }
    @Published private(set) var isScanning = false
    @Published private(set) var isTransferring = false
    @Published private(set) var operationProgress: FileOperationProgress?
    @Published private(set) var statusMessage = "Choose a photoshoot folder to begin."
    @Published var errorMessage: String?
    
    /// Dismissed auto-tag suggestions: (photoSetID, tagName) pairs.
    /// Ephemeral — cleared when the photo changes.
    @Published private var dismissedSuggestions: Set<DismissedSuggestionKey> = []
    
    /// Large image viewer state
    @Published var focusedPhotoIndex: Int = 0 {
        didSet {
            // Clear dismissed suggestions when the photo changes
            // (ephemeral per-session, per-photo).
            dismissedSuggestions.removeAll()
            preloadNeighbors(around: focusedPhotoIndex)
        }
    }
    @Published var isLargeImageViewerOpen: Bool = false
    @Published var currentTagCategoryID: UUID? = nil
    
    @Published var singleZoomState = SynchronizedZoomState()
    @Published var sharedZoomState = SynchronizedZoomState()

    /// Memoized counts & UI state
    @Published var searchText = ""
    @Published var nearFocusedIds: Set<UUID> = []
    
    @Published var selectedSubfolderFilter: URL? = nil {
        didSet {
            updateDerivedState()
        }
    }
    @Published var pendingRoutedPlan: RoutedPlan? = nil

    // MARK: - Culling Undo/Redo State
    @Published private var undoManager = CullingUndoManager()
    private var pendingTagStoreRefresh = false

    @Published var cachedSubfolders: [URL: [URL]] = [:]
    @Published var cachedSubfolderCounts: [URL: Int] = [:]

    // Folder tree index for the recursive sidebar. Built once when
    // photoSets changes (not on every read), so the sidebar can render
    // any node in O(1). Both maps are keyed by the standardized URL
    // path string so lookups don't allocate.
    //
    //   childSubfoldersIndex[parentPath]  -> sorted immediate children paths
    //   recursivePhotoCountIndex[folderPath] -> photo set count anywhere at or below folder
    //
    // Invalidated by `rebuildFolderIndex()`, which is called from the
    // photoSets didSet (after updateGlobalCounts + updateDerivedState).
    @Published private(set) var childSubfoldersIndex: [String: [String]] = [:]
    @Published private(set) var recursivePhotoCountIndex: [String: Int] = [:]
    @Published private(set) var childFolderURLs: [String: [URL]] = [:]

    // Memoized sidebar counts
    var cachedAllPhotosCount: Int = 0
    var cachedEditedCount: Int = 0
    var cachedUneditedCount: Int = 0
    var cachedTagCounts: [UUID: Int] = [:]
    var cachedFlagCounts: [Int: Int] = [:]
    var cachedRatingCounts: [Int: Int] = [:]

    var countFlagged: Int { cachedFlagCounts[1] ?? 0 }
    var countRejected: Int { cachedFlagCounts[-1] ?? 0 }
    var countUnflagged: Int { cachedFlagCounts[0] ?? 0 }
    var countFiveStars: Int { cachedRatingCounts[5] ?? 0 }
    var countFourStars: Int { cachedRatingCounts[4] ?? 0 }
    var countThreeStars: Int { cachedRatingCounts[3] ?? 0 }
    var countTwoStars: Int { cachedRatingCounts[2] ?? 0 }
    var countOneStar: Int { cachedRatingCounts[1] ?? 0 }
    var countFourPlusStars: Int { (cachedRatingCounts[4] ?? 0) + (cachedRatingCounts[5] ?? 0) }
    var countThreePlusStars: Int { (cachedRatingCounts[3] ?? 0) + (cachedRatingCounts[4] ?? 0) + (cachedRatingCounts[5] ?? 0) }
    var countRated: Int { (1...5).reduce(0) { $0 + (cachedRatingCounts[$1] ?? 0) } }
    var countUnrated: Int { cachedRatingCounts[0] ?? 0 }

    /// Number of columns the photo grid is currently rendering. Kept in sync by
    /// PhotoGridView so arrow-key navigation matches the visible layout.
    var gridColumnCount: Int = 1
    
    // MARK: - Services

    private let scanner = FileScanner()
    private let xmpTagging = XMPTaggingService()         // new custom tag keywords
    private let transferService = FileTransferService()
    private let routedTransfer = RoutedTransferService()
    private let metadataReader = MetadataReader()
    private var scanTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var tagTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Performance constants

    /// Number of photos loaded per metadata batch. First batch is always shown
    /// immediately; subsequent batches of this size are loaded and applied
    /// progressively so very large libraries populate the UI incrementally.
    /// Tunable range: 100–250 items.
    static let metadataBatchSize: Int = 150

    // MARK: - Memory pressure

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Init
    
    init(
        tagStore: TagStore? = nil,
        ruleStore: ExportRuleStore? = nil,
        packLibrary: TagPackLibrary? = nil
    ) {
        self.tagStore = tagStore ?? TagStore()
        self.ruleStore = ruleStore ?? ExportRuleStore()
        self.packLibrary = packLibrary ?? TagPackLibrary()
        
        UserPreferences.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.speedCullingEnabled != UserPreferences.shared.speedCullingEnabled {
                        self.speedCullingEnabled = UserPreferences.shared.speedCullingEnabled
                    }
                    self.updateDerivedState()
                }
            }
            .store(in: &cancellables)
        
        self.tagStore.objectWillChange
            // Coalesce multiple `objectWillChange` fires from a batch tag
            // operation into a single MainActor pass per runloop cycle.
            .sink { [weak self] _ in
                guard let self, !self.pendingTagStoreRefresh else { return }
                self.pendingTagStoreRefresh = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingTagStoreRefresh = false
                    self.updateGlobalCounts()
                    self.updateDerivedState()
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        // Every change to the live tag/category lists should snapshot back
        // into the active pack's saved state so the user's edits survive
        // switching packs and relaunching the app.
        self.tagStore.$tags
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivePackFromStore()
            }
            .store(in: &cancellables)
        self.tagStore.$categories
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivePackFromStore()
            }
            .store(in: &cancellables)
        
        $searchText
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDerivedState()
            }
            .store(in: &cancellables)
        
        let isRunningTests = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        if !isRunningTests {
            self.filterRule = UserPreferences.shared.lastFilterRule
            self.isInspectorOpen = UserPreferences.shared.isInspectorOpen
            self.speedCullingEnabled = UserPreferences.shared.speedCullingEnabled

            let urls = UserPreferences.shared.lastSourceDirectoryIDs.map { URL(fileURLWithPath: $0) }
            self.sourceDirectories = urls
            self.looseFiles = UserPreferences.shared.lastLooseFilePaths.map { URL(fileURLWithPath: $0) }

            if let destID = UserPreferences.shared.lastDestinationDirectoryID {
                self.destinationDirectory = URL(fileURLWithPath: destID)
            }
        }

        self.tagManagerHotkey = UserPreferences.shared.tagManagerHotkey
        self.ruleEditorHotkey = UserPreferences.shared.ruleEditorHotkey
        self.openSourceHotkey = UserPreferences.shared.openSourceHotkey
        self.photomatorHotkey = UserPreferences.shared.photomatorHotkey

        self.isInitializing = false

        updateGlobalCounts()
        updateDerivedState()

        if !isRunningTests && (!sourceDirectories.isEmpty || !looseFiles.isEmpty) {
            let urls = self.sourceDirectories
            Task { [weak self] in
                self?.scanSourceDirectories(urls)
            }
        }

        // Register for OS memory pressure events and evict the thumbnail
        // cache on warning/critical to prevent the app from being jettisoned.
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard self != nil else { return }
            let event = source.data
            if event.contains(.warning) || event.contains(.critical) {
                ThumbnailCache.global.evictAll()
                Task { await DiskThumbnailCache.shared.evictAll() }
                AppLogger.ui.warning("Memory pressure event received — thumbnail cache evicted")
            }
        }
        source.resume()
        self.memoryPressureSource = source
    }
    
    deinit {
        scanTask?.cancel()
        transferTask?.cancel()
        tagTask?.cancel()
        metadataTask?.cancel()
        memoryPressureSource?.cancel()
        
        // Clean up keyboard monitor if registered
        if let keyboardMonitor = keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        // Clean up scroll monitor if registered
        if let scrollMonitor = scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }
    
    // MARK: - Derived state
    
    @Published private(set) var filteredPhotoSets: [PhotoSet] = []
    
    var selectedPhotoSets: [PhotoSet] {
        photoSets.filter(\.isSelected)
    }

    /// O(1) read of the cached selection count. Updated inside
    /// `updateGlobalCounts()` so the per-frame toolbar and footer don't
    /// trigger an O(n) filter every body re-evaluation.
    var selectedCount: Int { cachedSelectedCount }

    /// O(1) read of the cached selected file count. Same caching strategy as
    /// `selectedCount`.
    var selectedFileCount: Int { cachedSelectedFileCount }

    private var cachedSelectedCount: Int = 0
    private var cachedSelectedFileCount: Int = 0

    var editedCount: Int { cachedEditedCount }
    var uneditedCount: Int { cachedUneditedCount }
    
    var canTransfer: Bool {
        destinationDirectory != nil && cachedSelectedCount > 0 && !isTransferring
    }
    
    var currentFocusedPhotoSet: PhotoSet? {
        let list = filteredPhotoSets
        guard !list.isEmpty else { return nil }
        let safe = max(0, min(focusedPhotoIndex, list.count - 1))
        return list[safe]
    }
    
    func metadata(for photoSet: PhotoSet) -> MetadataSnapshot {
        var snapshot = photoMetadata[photoSet.id] ?? MetadataSnapshot()
        if let caption = photoCaptions[photoSet.id] {
            snapshot.caption = caption
        }
        return snapshot
    }

    func caption(for photoSet: PhotoSet) -> String? {
        photoCaptions[photoSet.id]
    }

    /// Write a caption (description) to the photo set's XMP sidecars and update
    /// the in-memory cache. Pass an empty/whitespace-only string to clear it.
    func setCaption(_ caption: String?, for photoSetID: UUID) {
        guard let idx = photoSetIndex[photoSetID] else { return }
        let photo = photoSets[idx]
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let previous = photoCaptions[photoSetID]
        if previous == normalized { return }

        if normalized == nil {
            photoCaptions.removeValue(forKey: photoSetID)
        } else {
            photoCaptions[photoSetID] = normalized
        }

        let tagNames = Set(tagStore.assignedTags(for: photo.id).map(\.name))
        let existingSnapshot = photoMetadata[photo.id]
        let reader = metadataReader
        let previousTask = tagTask
        tagTask = Task { @MainActor [weak self, xmpTagging] in
            _ = await previousTask?.result
            let result: Result<Void, Error> = await Task.detached(priority: .utility) {
                let snapshot = existingSnapshot ?? (photo.preferredPreviewURL.map { reader.metadata(for: $0) } ?? MetadataSnapshot())
                return Result { try xmpTagging.updateCaption(normalized, for: photo, tagNames: tagNames, metadata: snapshot) }
            }.value
            if case .failure(let error) = result {
                self?.errorMessage = error.localizedDescription
            }
        }

        updateDerivedState()
    }
    
    func assignedTags(for photoSet: PhotoSet) -> [CustomTag] {
        tagStore.assignedTags(for: photoSet.id)
    }
    
    func tags(in categoryID: UUID) -> [CustomTag] {
        tagStore.tags(in: categoryID)
    }
    
    // MARK: - Directory selection
    
    func addSourceDirectory() {
        guard let url = FolderPanel.chooseDirectory(title: "Add Source Folder") else { return }
        let standardized = url.standardizedFileURL
        if !sourceDirectories.contains(standardized) {
            var updated = sourceDirectories
            updated.append(standardized)
            sourceDirectories = updated
            persistSources()
            scanSourceDirectories(updated)
        }
    }

    /// Open a panel that accepts both files and folders, then import the result.
    func importItems() {
        let urls = FolderPanel.chooseItems(title: "Import Photos")
        guard !urls.isEmpty else { return }
        importURLs(urls)
    }

    /// Import a mix of dropped/selected files and folders. Folders become source
    /// directories (scanned recursively); files are grouped directly into sets.
    func importURLs(_ urls: [URL]) {
        let fm = FileManager.default
        var newDirs: [URL] = []
        var newFiles: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                newDirs.append(standardized)
            } else {
                newFiles.append(standardized)
            }
        }

        var dirs = sourceDirectories
        var files = looseFiles
        var changed = false

        for dir in newDirs where !dirs.contains(dir) {
            dirs.append(dir)
            changed = true
        }
        for file in newFiles where !files.contains(file) {
            files.append(file)
            changed = true
        }

        guard changed else { return }

        sourceDirectories = dirs
        looseFiles = files
        persistSources()
        scanSourceDirectories(dirs)
    }

    private func persistSources() {
        UserPreferences.shared.lastSourceDirectoryIDs = sourceDirectories.map(\.path)
        UserPreferences.shared.lastLooseFilePaths = looseFiles.map(\.path)
        UserPreferences.shared.save()
    }
    
    func removeSourceDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        var updated = sourceDirectories
        updated.removeAll { $0.standardizedFileURL == standardized }
        sourceDirectories = updated
        persistSources()
        scanSourceDirectories(updated)
    }

    func removeLooseFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        var updated = looseFiles
        updated.removeAll { $0.standardizedFileURL == standardized }
        looseFiles = updated
        persistSources()
        scanSourceDirectories(sourceDirectories)
    }

    func clearSourceDirectories() {
        scanTask?.cancel()
        metadataTask?.cancel()
        tagTask?.cancel()
        sourceDirectories = []
        looseFiles = []
        photoSets = []
        photoMetadata = [:]
        photoCaptions = [:]
        visionSuggestionsCache = [:]
        photoDateCache = [:]
        photoFileSizeCache = [:]
        selectedSubfolderFilter = nil
        exifLoadProgress = nil
        undoManager.clear()
        isScanning = false
        persistSources()
        statusMessage = "Choose a photoshoot folder to begin."
    }
    
    func chooseDestinationDirectory() {
        guard let url = FolderPanel.chooseDirectory(title: "Choose Destination Folder") else { return }
        UserPreferences.shared.lastDestinationDirectoryID = url.standardizedFileURL.path
        UserPreferences.shared.save()
        destinationDirectory = url
        statusMessage = "Destination set to \(url.lastPathComponent)."
    }
    
    // MARK: - Scan
    
    func scanSourceDirectories(_ urls: [URL]) {
        scanTask?.cancel()
        metadataTask?.cancel()
        undoManager.clear()
        sourceDirectories = urls
        photoSets = []
        photoMetadata = [:]
        photoCaptions = [:]
        failedSources = []
        errorMessage = nil
        isScanning = true
        
        let looseFiles = self.looseFiles

        if urls.isEmpty && looseFiles.isEmpty {
            self.statusMessage = "No sources selected."
            self.isScanning = false
            return
        }

        let foldersText = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) folders"
        statusMessage = urls.isEmpty
            ? "Scanning \(looseFiles.count) imported files..."
            : "Scanning \(foldersText) and subfolders..."

        scanTask = Task { @MainActor [weak self, scanner] in
            var photoSets: [PhotoSet] = []
            var scannedFileCount = 0
            var failed: Set<URL> = []

            if !urls.isEmpty {
                let dirResult = await scanner.scanDirectories(urls)
                guard !Task.isCancelled else { return }
                photoSets.append(contentsOf: dirResult.photoSets)
                scannedFileCount += dirResult.scannedFileCount
                failed.formUnion(dirResult.failedDirectories)
            }

            if !looseFiles.isEmpty {
                let fileResult = await scanner.scanFiles(looseFiles)
                guard !Task.isCancelled else { return }
                photoSets.append(contentsOf: fileResult.photoSets)
                scannedFileCount += fileResult.scannedFileCount
                failed.formUnion(fileResult.failedDirectories)
            }

            guard !Task.isCancelled, let self else { return }

            photoSets.sort {
                $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
            }

            self.photoSets = photoSets
            self.failedSources = failed
            let sourceLabel = urls.map(\.lastPathComponent).joined(separator: ", ")
            let scope = looseFiles.isEmpty ? sourceLabel
                : (urls.isEmpty ? "imported files" : "\(sourceLabel) + imported files")
            
            if failed.isEmpty {
                self.statusMessage = "Found \(photoSets.count) photo sets across [\(scope)], \(scannedFileCount) matching files."
            } else {
                self.statusMessage = "Found \(photoSets.count) photo sets, \(scannedFileCount) matching files. Warning: \(failed.count) source(s) failed to load."
                self.errorMessage = "Failed to scan \(failed.count) source folder(s): \(failed.map(\.lastPathComponent).joined(separator: ", "))"
            }
            
            self.loadMetadataAndTags(for: photoSets)
            self.isScanning = false
        }
    }
    
    private func loadMetadata(for photoSets: [PhotoSet]) {
        // Replaced by loadMetadataAndTags. Kept as an internal entry point so
        // other call sites still compile while we transition.
        metadataTask?.cancel()
        tagTask?.cancel()
        loadMetadataAndTags(for: photoSets)
    }

    /// Two-pass metadata loader optimized for thousands of photos:
    /// - **Pass 1 (Instant XMP Sidecars):** Reads only lightweight `.xmp` sidecar
    ///   files across the entire library in parallel so all pick/reject flags,
    ///   star ratings, saved tags, and captions appear immediately.
    /// - **Pass 2 (Background EXIF Trickle):** Quietly streams full ImageIO EXIF
    ///   (camera, lens, ISO, aperture, shutter, capture date) in batches at
    ///   `.utility` priority while reporting progress via `exifLoadProgress`.
    private func loadMetadataAndTags(for photoSets: [PhotoSet]) {
        metadataTask?.cancel()
        tagTask?.cancel()

        let sets = photoSets
        guard !sets.isEmpty else {
            exifLoadProgress = nil
            return
        }

        let batchSize = Self.metadataBatchSize
        let allTags = tagStore.tags
        let nameToID: [String: UUID] = Dictionary(
            allTags.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        AppLogger.metadata.info("Starting two-pass metadata load: \(sets.count) sets, batch size \(batchSize)")

        metadataTask = Task { @MainActor [weak self, metadataReader, xmpTagging] in
            // Pass 1: Instant XMP sidecars (flags, stars, tags, captions) across all sets.
            let sidecarResults = await Task.detached(priority: .userInitiated) {
                await Self.loadSidecarsOnly(sets, xmpTagging: xmpTagging)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applySidecarOnlyResults(sidecarResults)

            // Pass 2: Quietly trickle-load full ImageIO EXIF in background batches.
            self.exifLoadProgress = (completed: 0, total: sets.count)
            var offset = 0
            while offset < sets.count {
                if Task.isCancelled {
                    self.exifLoadProgress = nil
                    return
                }
                let upper = min(offset + batchSize, sets.count)
                let batch = Array(sets[offset..<upper])
                let results = await Task.detached(priority: .utility) {
                    await Self.loadBatchMetadataAndTags(
                        batch,
                        metadataReader: metadataReader,
                        xmpTagging: xmpTagging
                    )
                }.value
                guard !Task.isCancelled else {
                    self.exifLoadProgress = nil
                    return
                }
                self.applyMetadataAndTagResults(results, nameToID: nameToID)
                offset = upper
                self.exifLoadProgress = (completed: offset, total: sets.count)
                AppLogger.metadata.debug("Applied EXIF batch: \(offset)/\(sets.count) sets")
            }
            self.exifLoadProgress = nil
            AppLogger.metadata.info("Two-pass metadata load complete: \(sets.count) sets processed")
        }
    }

    private struct SidecarOnlyInfo: Sendable {
        let id: UUID
        let tags: Set<String>
        let rating: Int?
        let pick: Int?
        let description: String?
    }

    /// Pass 1: Fast parallel `.xmp` sidecar reader (no ImageIO/RAW opens).
    private static func loadSidecarsOnly(
        _ sets: [PhotoSet],
        xmpTagging: XMPTaggingService
    ) async -> [SidecarOnlyInfo] {
        let maxConcurrency = 32
        return await withTaskGroup(of: SidecarOnlyInfo?.self) { group in
            var inFlight = 0
            var out: [SidecarOnlyInfo] = []
            for photo in sets {
                if inFlight >= maxConcurrency {
                    if let item = await group.next(), let unwrapped = item {
                        out.append(unwrapped)
                    }
                    inFlight -= 1
                }
                inFlight += 1
                group.addTask {
                    let sidecar = xmpTagging.readSidecarData(from: photo)
                    if sidecar.tags.isEmpty && sidecar.rating == nil && sidecar.pick == nil && sidecar.description == nil {
                        return nil
                    }
                    return SidecarOnlyInfo(
                        id: photo.id,
                        tags: sidecar.tags,
                        rating: sidecar.rating,
                        pick: sidecar.pick,
                        description: sidecar.description
                    )
                }
            }
            for await item in group {
                if let unwrapped = item { out.append(unwrapped) }
            }
            return out
        }
    }

    private func applySidecarOnlyResults(_ results: [SidecarOnlyInfo]) {
        guard !results.isEmpty else { return }

        var allDiscoveredNames = Set<String>()
        for info in results {
            allDiscoveredNames.formUnion(info.tags)
        }
        if !allDiscoveredNames.isEmpty {
            tagStore.ensureTags(named: allDiscoveredNames)
        }
        let activeNameToID = Dictionary(
            tagStore.tags.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        suppressDerivedUpdates = true
        var batchTags: [UUID: Set<UUID>] = [:]
        var updatedCaptions = self.photoCaptions
        var captionsChanged = false
        var updatedSets = self.photoSets
        var setsChanged = false

        for info in results {
            if !info.tags.isEmpty {
                let tagIDs = Set(info.tags.compactMap { activeNameToID[$0.lowercased()] })
                if !tagIDs.isEmpty {
                    batchTags[info.id] = tagIDs
                }
            }
            if let description = info.description, !description.isEmpty {
                updatedCaptions[info.id] = description
                captionsChanged = true
            }
            if let idx = photoSetIndex[info.id] {
                if updatedSets[idx].rating == nil, let rating = info.rating {
                    updatedSets[idx].rating = rating
                    setsChanged = true
                }
                if updatedSets[idx].pick == nil, let pick = info.pick {
                    updatedSets[idx].pick = pick
                    setsChanged = true
                }
            }
        }

        if !batchTags.isEmpty {
            tagStore.setTagsBatch(batchTags)
        }
        if captionsChanged {
            self.photoCaptions = updatedCaptions
        }
        if setsChanged {
            self.photoSets = updatedSets
        }
        suppressDerivedUpdates = false
        updateGlobalCounts()
        updateDerivedState()
    }

    /// Read EXIF metadata + XMP sidecar for every photo in `batch` in parallel.
    /// One task per photo so each set's I/O runs concurrently.
    /// Concurrency is capped at 16 concurrent in-flight tasks to avoid
    /// saturating the disk I/O scheduler on low-IOPS storage.
    private static func loadBatchMetadataAndTags(
        _ batch: [PhotoSet],
        metadataReader: MetadataReader,
        xmpTagging: XMPTaggingService
    ) async -> [LoadedPhotoInfo] {
        let maxConcurrency = 16
        AppLogger.metadata.debug("Loading metadata batch: \(batch.count) sets, concurrency cap: \(maxConcurrency)")
        return await withTaskGroup(of: LoadedPhotoInfo.self) { group in
            var inFlight = 0
            var out: [LoadedPhotoInfo] = []
            out.reserveCapacity(batch.count)
            for photo in batch {
                if inFlight >= maxConcurrency {
                    if let result = await group.next() {
                        out.append(result)
                        inFlight -= 1
                    }
                }
                inFlight += 1
                group.addTask {
                    let metadata: MetadataSnapshot
                    if let url = photo.preferredPreviewURL {
                        metadata = metadataReader.metadata(for: url)
                    } else {
                        metadata = MetadataSnapshot()
                    }
                    let sidecar = xmpTagging.readSidecarData(from: photo)

                    var combinedTags = sidecar.tags
                    combinedTags.formUnion(metadata.keywords)

                    if metadata.keywords.isEmpty {
                        for file in photo.mediaFiles where file != photo.preferredPreviewURL {
                            let ext = file.pathExtension.lowercased()
                            if ext == "jpg" || ext == "jpeg" || FileExtension.heifLikeExtensions.contains(ext) {
                                let extra = metadataReader.metadata(for: file)
                                if !extra.keywords.isEmpty {
                                    combinedTags.formUnion(extra.keywords)
                                    break
                                }
                            }
                        }
                    }

                    let combinedDescription = sidecar.description ?? metadata.caption

                    return LoadedPhotoInfo(
                        id: photo.id,
                        metadata: metadata,
                        sidecarTags: combinedTags,
                        sidecarRating: sidecar.rating,
                        sidecarPick: sidecar.pick,
                        sidecarDescription: combinedDescription
                    )
                }
            }
            for await result in group { out.append(result) }
            return out
        }
    }

    private func applyMetadataAndTagResults(
        _ results: [LoadedPhotoInfo],
        nameToID: [String: UUID]
    ) {
        guard !results.isEmpty else { return }
        
        // Ensure all discovered tag names from metadata and sidecars are registered in TagStore
        var allDiscoveredNames = Set<String>()
        for info in results {
            allDiscoveredNames.formUnion(info.sidecarTags)
        }
        
        tagStore.ensureTags(named: allDiscoveredNames)
        let activeNameToID = Dictionary(
            tagStore.tags.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        suppressDerivedUpdates = true
        var metadataCache = self.photoMetadata
        metadataCache.reserveCapacity(metadataCache.count + results.count)
        var batchTags: [UUID: Set<UUID>] = [:]
        var batchCaptions: [UUID: String] = [:]

        var updatedSets = self.photoSets

        for info in results {
            metadataCache[info.id] = info.metadata
            photoDateCache.removeValue(forKey: info.id)

            if !info.sidecarTags.isEmpty {
                let tagIDs = Set(info.sidecarTags.compactMap { activeNameToID[$0.lowercased()] })
                if !tagIDs.isEmpty {
                    batchTags[info.id] = tagIDs
                }
            }

            if let description = info.sidecarDescription, !description.isEmpty {
                batchCaptions[info.id] = description
            }

            if let idx = photoSetIndex[info.id] {
                let rating = info.sidecarRating ?? info.metadata.rating
                let pick = info.sidecarPick ?? info.metadata.pick
                if updatedSets[idx].rating == nil, let rating {
                    updatedSets[idx].rating = rating
                }
                if updatedSets[idx].pick == nil, let pick {
                    updatedSets[idx].pick = pick
                }
            }
        }

        self.photoMetadata = metadataCache
        if !batchTags.isEmpty {
            tagStore.setTagsBatch(batchTags)
        }
        if !batchCaptions.isEmpty {
            var mergedCaptions = self.photoCaptions
            for (id, caption) in batchCaptions {
                mergedCaptions[id] = caption
            }
            self.photoCaptions = mergedCaptions
        }
        self.photoSets = updatedSets
        suppressDerivedUpdates = false
        updateGlobalCounts()
        updateDerivedState()
    }

    /// Compact value type used by `loadMetadataAndTags` to ferry per-photo
    /// results out of the task group without depending on the sidecar tuple
    /// type alias.
    fileprivate struct LoadedPhotoInfo: Sendable {
        let id: UUID
        let metadata: MetadataSnapshot
        let sidecarTags: Set<String>
        let sidecarRating: Int?
        let sidecarPick: Int?
        let sidecarDescription: String?
    }
    
    func toggleFlagFilter(_ flag: Int) {
        if selectedFlags.contains(flag) {
            selectedFlags.remove(flag)
        } else {
            selectedFlags.insert(flag)
        }
    }

    func toggleRatingFilter(_ rating: Int) {
        if selectedRatings.contains(rating) {
            selectedRatings.remove(rating)
        } else {
            selectedRatings.insert(rating)
        }
    }

    // MARK: - Selection
    
    /// The photo set that the user last single-clicked (without shift). This
    /// is the anchor used for shift-click range selection and for showing the
    /// "active focus" highlight ring distinct from the broader selection.
    @Published var selectionAnchorID: PhotoSet.ID? = nil

    private func fileCount(for photoSet: PhotoSet) -> Int {
        photoSet.mediaFiles.count + (photoSet.editPath != nil ? 1 : 0)
    }

    private func setSingleSelectionState(_ newValue: Bool, at index: Int, id: PhotoSet.ID) {
        let oldValue = photoSets[index].isSelected
        guard oldValue != newValue else { return }
        isMutatingSelectionOnly = true
        photoSets[index].isSelected = newValue
        isMutatingSelectionOnly = false

        let deltaFiles = fileCount(for: photoSets[index])
        if newValue {
            cachedSelectedCount += 1
            cachedSelectedFileCount += deltaFiles
        } else {
            cachedSelectedCount = max(0, cachedSelectedCount - 1)
            cachedSelectedFileCount = max(0, cachedSelectedFileCount - deltaFiles)
        }

        if let filteredIndex = filteredPhotoSets.firstIndex(where: { $0.id == id }) {
            filteredPhotoSets[filteredIndex].isSelected = newValue
        }
    }

    private func applyBatchSelection(_ shouldSelect: (PhotoSet) -> Bool) {
        var updated = photoSets
        var selectedCount = 0
        var selectedFiles = 0
        var selectedIDs = Set<UUID>()
        for i in updated.indices {
            let sel = shouldSelect(updated[i])
            updated[i].isSelected = sel
            if sel {
                selectedCount += 1
                selectedFiles += fileCount(for: updated[i])
                selectedIDs.insert(updated[i].id)
            }
        }
        isMutatingSelectionOnly = true
        photoSets = updated
        isMutatingSelectionOnly = false
        cachedSelectedCount = selectedCount
        cachedSelectedFileCount = selectedFiles

        var updatedFiltered = filteredPhotoSets
        for i in updatedFiltered.indices {
            updatedFiltered[i].isSelected = selectedIDs.contains(updatedFiltered[i].id)
        }
        filteredPhotoSets = updatedFiltered
    }

    func toggleSelection(for id: PhotoSet.ID) {
        guard let index = photoSetIndex[id] else { return }
        setSingleSelectionState(!photoSets[index].isSelected, at: index, id: id)
        // Every toggle updates the anchor to this cell so a subsequent
        // shift-click extends from it.
        selectionAnchorID = id
    }

    func setSelection(_ isSelected: Bool, for id: PhotoSet.ID) {
        guard let index = photoSetIndex[id] else { return }
        setSingleSelectionState(isSelected, at: index, id: id)
    }

    /// Select every visible photo set between the anchor (or ``id`` if no
    /// anchor exists) and ``id``, inclusive. If the anchor is missing, the
    /// anchor is set to ``id`` and only that cell is selected.
    func selectRange(to id: PhotoSet.ID, additive: Bool = false) {
        let visibleIDs = filteredPhotoSets.map(\.id)
        guard let endIndex = visibleIDs.firstIndex(of: id) else {
            statusMessage = "Shift-click target not found in current view."
            return
        }

        let anchorID = selectionAnchorID ?? id
        guard let startIndex = visibleIDs.firstIndex(of: anchorID) else {
            // Anchor was lost (e.g., the anchor photo is filtered out).
            // Treat the current click as the new anchor.
            setSelection(true, for: id)
            selectionAnchorID = id
            statusMessage = "Set new selection anchor at \(filteredPhotoSets[endIndex].baseName)."
            return
        }

        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = Set(visibleIDs[lower...upper])

        if additive {
            applyBatchSelection { photoSet in
                photoSet.isSelected || rangeIDs.contains(photoSet.id)
            }
        } else {
            applyBatchSelection { photoSet in
                rangeIDs.contains(photoSet.id)
            }
        }

        let direction = startIndex < endIndex ? "forward" : "backward"
        statusMessage = "Selected \(rangeIDs.count) photo set\(rangeIDs.count == 1 ? "" : "s") in range (\(direction))."
    }

    /// Replace the entire selection with the given IDs in one batch update.
    func replaceSelection(with ids: [PhotoSet.ID]) {
        let idSet = Set(ids)
        applyBatchSelection { photoSet in
            idSet.contains(photoSet.id)
        }
    }

    /// Target photo sets for batch metadata operations: the current selection
    /// if non-empty, otherwise just the focused photo. Used so that pressing
    /// "1-5 / X / tag hotkey" applies to the user's selection automatically.
    var batchTargetPhotoSets: [PhotoSet] {
        let selected = selectedPhotoSets
        return selected.isEmpty ? (currentFocusedPhotoSet.map { [$0] } ?? []) : selected
    }
    
    // MARK: - Permanent Tags (Rating & Pick)

    func setRating(_ rating: Int?, for id: PhotoSet.ID) {
        setRating(rating, forIDs: [id])
    }

    /// Apply the same rating to every photo in ``ids``. Pass an empty array
    /// to no-op (used when no photo is in scope).
    func setRating(_ rating: Int?, forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        let before = captureState(for: ids)
        var updated = photoSets
        var targetItems: [(photo: PhotoSet, tags: Set<String>, metadata: MetadataSnapshot?)] = []
        for id in ids {
            if let index = photoSetIndex[id] {
                updated[index].rating = rating
                let photo = updated[index]
                let tags = Set(tagStore.assignedTags(for: id).map(\.name))
                targetItems.append((photo, tags, photoMetadata[id]))
            }
        }
        photoSets = updated

        if let rating {
            statusMessage = "Rated \(ids.count) photo set\(ids.count == 1 ? "" : "s") ★\(rating)."
        } else {
            statusMessage = "Cleared rating on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        }

        registerUndo(beforeStates: before, actionName: "Rating")

        let itemsToWrite = targetItems
        let reader = metadataReader
        let previousTask = tagTask
        tagTask = Task { @MainActor [weak self, xmpTagging] in
            _ = await previousTask?.result
            let errorText: String? = await Task.detached(priority: .utility) {
                for item in itemsToWrite {
                    let snapshot = item.metadata ?? (item.photo.preferredPreviewURL.map { reader.metadata(for: $0) } ?? MetadataSnapshot())
                    do {
                        try xmpTagging.updatePermanentTags(
                            rating: rating,
                            pick: item.photo.pick,
                            for: item.photo,
                            tagNames: item.tags,
                            metadata: snapshot
                        )
                    } catch {
                        return "Failed to write rating: \(error.localizedDescription)"
                    }
                }
                return nil
            }.value
            if let errorText {
                self?.errorMessage = errorText
            }
        }
    }

    func setPick(_ pick: Int?, for id: PhotoSet.ID) {
        setPick(pick, forIDs: [id])
    }

    /// Apply the same pick flag to every photo in ``ids``.
    func setPick(_ pick: Int?, forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        let before = captureState(for: ids)
        var updated = photoSets
        var targetItems: [(photo: PhotoSet, tags: Set<String>, metadata: MetadataSnapshot?)] = []
        for id in ids {
            if let index = photoSetIndex[id] {
                updated[index].pick = pick
                let photo = updated[index]
                let tags = Set(tagStore.assignedTags(for: id).map(\.name))
                targetItems.append((photo, tags, photoMetadata[id]))
            }
        }
        photoSets = updated

        if let pick {
            statusMessage = "Set pick flag (\(pick)) on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        } else {
            statusMessage = "Cleared pick flag on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        }

        registerUndo(beforeStates: before, actionName: "Pick Flag")

        let itemsToWrite = targetItems
        let reader = metadataReader
        let previousTask = tagTask
        tagTask = Task { @MainActor [weak self, xmpTagging] in
            _ = await previousTask?.result
            let errorText: String? = await Task.detached(priority: .utility) {
                for item in itemsToWrite {
                    let snapshot = item.metadata ?? (item.photo.preferredPreviewURL.map { reader.metadata(for: $0) } ?? MetadataSnapshot())
                    do {
                        try xmpTagging.updatePermanentTags(
                            rating: item.photo.rating,
                            pick: pick,
                            for: item.photo,
                            tagNames: item.tags,
                            metadata: snapshot
                        )
                    } catch {
                        return "Failed to write pick flag: \(error.localizedDescription)"
                    }
                }
                return nil
            }.value
            if let errorText {
                self?.errorMessage = errorText
            }
        }
    }

    // MARK: - Undo/Redo Helper Functions

    private func captureState(for ids: [PhotoSet.ID]) -> [CullingState] {
        return ids.compactMap { id -> CullingState? in
            guard let index = photoSetIndex[id] else { return nil }
            let photo = photoSets[index]
            let tagIDs = tagStore.assignedTagIDs(for: id)
            return CullingState(photoSetID: id, rating: photo.rating, pick: photo.pick, tagIDs: tagIDs)
        }
    }

    private func registerUndo(beforeStates: [CullingState], actionName: String) {
        undoManager.registerUndo(beforeStates: beforeStates)
    }

    private func restoreState(_ states: [CullingState]) {
        var updated = photoSets
        for state in states {
            if let index = photoSetIndex[state.photoSetID] {
                updated[index].rating = state.rating
                updated[index].pick = state.pick
                tagStore.setTags(state.tagIDs, for: state.photoSetID)
            }
        }
        photoSets = updated

        let targets = states.compactMap { state -> (photo: PhotoSet, tagIDs: Set<UUID>, metadata: MetadataSnapshot)? in
            guard let index = photoSetIndex[state.photoSetID] else { return nil }
            let photo = photoSets[index]
            let snapshot = photoMetadata[photo.id] ?? (photo.preferredPreviewURL != nil ? metadataReader.metadata(for: photo.preferredPreviewURL!) : MetadataSnapshot())
            return (photo, state.tagIDs, snapshot)
        }

        let previousTask = tagTask
        tagTask = Task { @MainActor [xmpTagging, tagStore] in
            _ = await previousTask?.result
            for target in targets {
                do {
                    let names = Set(target.tagIDs.compactMap { tagStore.tag(id: $0)?.name })
                    try xmpTagging.updatePermanentTags(
                        rating: target.photo.rating,
                        pick: target.photo.pick,
                        for: target.photo,
                        tagNames: names,
                        metadata: target.metadata
                    )
                    if target.tagIDs.isEmpty {
                        try xmpTagging.clear(for: target.photo)
                    } else {
                        try xmpTagging.applyTagNames(names, to: target.photo, metadata: target.metadata)
                    }
                } catch {
                    self.errorMessage = "Failed to sync XMP on undo/redo: \(error.localizedDescription)"
                }
            }
        }
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func undo() {
        guard let before = undoManager.popUndo(pushingRedo: { ids in captureState(for: ids) }) else {
            statusMessage = "Nothing to undo."
            return
        }
        restoreState(before)
        statusMessage = "Undid last culling change."
        triggerHapticFeedback(for: .flag)
    }

    func redo() {
        guard let after = undoManager.popRedo(pushingUndo: { ids in captureState(for: ids) }) else {
            statusMessage = "Nothing to redo."
            return
        }
        restoreState(after)
        statusMessage = "Redid last culling change."
        triggerHapticFeedback(for: .flag)
    }

    enum CullingAction {
        case flag, reject, rating
    }

    func triggerHapticFeedback(for action: CullingAction = .flag) {
        let prefs = UserPreferences.shared
        #if os(macOS)
        let profile: HapticProfile
        switch action {
        case .flag: profile = prefs.hapticProfileFlag
        case .reject: profile = prefs.hapticProfileReject
        case .rating: profile = prefs.hapticProfileRating
        }
        HapticFeedbackManager.shared.performHaptic(profile)

        if prefs.autoAdvanceSoundEnabled {
            NSSound.beep()
        }
        #endif
    }

    func setStatusMessage(_ message: String) {
        self.statusMessage = message
    }

    func advanceToNext() {
        guard focusedPhotoIndex < filteredPhotoSets.count - 1 else { return }
        focusedPhotoIndex += 1
    }

    /// Clear pick flag on every photo in the current selection (or focused
    /// photo if nothing is selected). Bound to the "U" hotkey.
    func clearPickFlagOnSelection() {
        let ids = batchTargetPhotoSets.map(\.id)
        guard !ids.isEmpty else { return }
        setPick(0, forIDs: ids)
    }

    /// Reject the given photo and, if it is the currently focused one,
    /// advance ``focusedPhotoIndex`` to the next visible photo so culling
    /// flows continue smoothly. Rejected photos are filtered out of the
    /// default view (see ``updateDerivedState``) and only reappear when
    /// the user selects the "Rejected" filter in the sidebar.
    func rejectAndAdvance(for id: PhotoSet.ID) {
        // Snapshot the visible position *before* mutating pick, because
        // setPick triggers updateDerivedState, which removes rejected
        // photos from filteredPhotoSets.
        let priorIndex = filteredPhotoSets.firstIndex(where: { $0.id == id })
 
        setPick(-1, for: id)
        // Synchronously refresh filteredPhotoSets so the rejected photo is removed
        // immediately before advancing focusedPhotoIndex (instead of waiting for
        // the async coalesced derived update).
        updateDerivedState()
        triggerHapticFeedback()

        guard speedCullingEnabled else { return }

        guard !filteredPhotoSets.isEmpty else { return }
        guard let currentIndex = priorIndex else { return }
        // The rejected photo is now hidden, so the photo at the same
        // index in the refreshed list is the next visible one.
        if currentIndex < filteredPhotoSets.count {
            focusedPhotoIndex = currentIndex
        } else {
            focusedPhotoIndex = filteredPhotoSets.count - 1
        }
    }
    
    func selectVisiblePhotoSets() {
        let visibleIDs = Set(filteredPhotoSets.map(\.id))
        applyBatchSelection { photoSet in
            photoSet.isSelected || visibleIDs.contains(photoSet.id)
        }
    }
    
    func clearSelection() {
        applyBatchSelection { _ in false }
        self.selectionAnchorID = nil
    }

    // MARK: - Tag pack management

    /// Snapshot the currently-active tags into the outgoing pack's saved
    /// state, then load the incoming pack's state into the live tag
    /// store. Each pack has its own persistent state, so the user can
    /// edit Wedding, switch to Cars, then come back to Wedding and find
    /// their edits.
    func switchTagPack(id: String) {
        let incomingID = id
        let outgoingID = packLibrary.activePackID

        if incomingID == outgoingID { return }

        if let outgoing = packLibrary.state(for: outgoingID) {
            packLibrary.snapshotActivePack(from: tagStore, packID: outgoing.id)
            _ = outgoing
        }

        packLibrary.activePackID = incomingID
        packLibrary.applyPack(incomingID, to: tagStore)

        if let pack = packLibrary.state(for: incomingID) {
            statusMessage = "Switched to \(pack.name) tag pack."
        }
    }

    func switchTagPack(_ template: TagPackTemplate) {
        switchTagPack(id: template.id)
    }

    /// The currently active tag pack state. Falls back to the default
    /// template's factory state if the persisted id is unknown.
    var activeTagPack: TagPackState {
        packLibrary.activePack
    }

    // MARK: - Custom pack management (UI-facing wrappers)

    /// Create a new user pack. If `basedOnTemplateID` is provided, the
    /// new pack starts with that template's categories and tags. Otherwise
    /// it starts empty.
    @discardableResult
    func createPack(named name: String,
                    basedOnTemplateID: String? = nil,
                    copyFromPackID: String? = nil,
                    systemImage: String? = nil,
                    accentColor: String? = nil) -> TagPackState? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let newID = makeUniquePackID(basedOn: trimmed)

        var state: TagPackState
        if let fromID = copyFromPackID, let original = packLibrary.state(for: fromID) {
            state = TagPackState(
                id: newID,
                name: trimmed,
                tagline: original.tagline,
                systemImage: systemImage ?? original.systemImage,
                accentColor: accentColor ?? original.accentColor,
                isBuiltIn: false,
                categories: original.categories,
                tags: original.tags
            )
        } else if let templateID = basedOnTemplateID,
                  let template = TagPackTemplate.template(id: templateID) {
            state = TagPackState(
                id: newID,
                name: trimmed,
                tagline: template.tagline,
                systemImage: systemImage ?? template.systemImage,
                accentColor: accentColor ?? template.accentColor,
                isBuiltIn: false,
                categories: template.categories.map { TagPackState.CategoryEntry(name: $0) },
                tags: template.tags.map {
                    TagPackState.TagEntry(category: $0.category, name: $0.name,
                                          hotkey: $0.hotkey, colorHex: $0.colorHex)
                }
            )
        } else {
            state = TagPackState.empty(id: newID, name: trimmed)
            if systemImage != nil || accentColor != nil {
                state.systemImage = systemImage ?? state.systemImage
                state.accentColor = accentColor ?? state.accentColor
            }
        }
        packLibrary.upsert(state)
        return state
    }

    func renamePack(id: String, to newName: String) {
        packLibrary.renamePack(id: id, to: newName)
    }

    func restylePack(id: String, systemImage: String, accentColor: String) {
        packLibrary.restylePack(id: id, systemImage: systemImage, accentColor: accentColor)
    }

    func resetPack(id: String) {
        // Snapshot the current edits first so the user doesn't lose work
        // for the *other* packs they might want to revisit.
        if id == packLibrary.activePackID {
            packLibrary.snapshotActivePack(from: tagStore, packID: id)
        }
        packLibrary.resetPack(id: id)
        if id == packLibrary.activePackID {
            packLibrary.applyPack(id, to: tagStore)
        }
        statusMessage = "Reset \(packLibrary.state(for: id)?.name ?? id)."
    }

    func duplicatePack(id: String, newName: String) -> TagPackState? {
        packLibrary.duplicatePack(id: id, newName: newName)
    }

    func deletePack(id: String) {
        guard !packLibrary.isBuiltIn(id) else { return }
        // If the user deletes the active pack, switch to the default first
        // so we always have something loaded.
        if id == packLibrary.activePackID {
            let fallback = TagPackTemplate.defaultTemplateID
            packLibrary.snapshotActivePack(from: tagStore, packID: id)
            packLibrary.activePackID = fallback
            packLibrary.applyPack(fallback, to: tagStore)
        }
        packLibrary.deletePack(id: id)
    }

    /// Persist the user's current edits to the tags into the active pack's
    /// saved state. Called automatically after tag/category mutations when
    /// the live tags differ from the last snapshot.
    func syncActivePackFromStore() {
        let id = packLibrary.activePackID
        packLibrary.snapshotActivePack(from: tagStore, packID: id)
    }

    // MARK: - Import / Export

    /// Prompt the user for a destination file and write the pack as a
    /// JSON document the user can share or back up.
    func exportPack(id: String) {
        guard let state = packLibrary.state(for: id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.tagPack]
        panel.nameFieldStringValue = "\(state.name).tagpack.json"
        panel.canCreateDirectories = true
        panel.title = "Export Tag Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.encodedForExport().write(to: url, options: .atomic)
            statusMessage = "Exported \(state.name) to \(url.lastPathComponent)."
        } catch {
            self.errorMessage = "Couldn't export pack: \(error.localizedDescription)"
        }
    }

    /// Prompt the user for a `.tagpack.json` file and add it as a new
    /// user pack.
    func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.tagPack]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Tag Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let incoming = try TagPackState.decodedFromImport(data)
            let stored = packLibrary.importPack(incoming)
            statusMessage = "Imported \(stored.name)."
        } catch {
            self.errorMessage = "Couldn't import pack: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func makeUniquePackID(basedOn name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = slug.isEmpty ? "pack" : slug
        var candidate = "user-" + base
        var counter = 2
        while packLibrary.packs.contains(where: { $0.id == candidate }) {
            candidate = "user-\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    // MARK: - Sidebar filter state

    @Published var isSidebarHidden: Bool = false

    var activeFilterCount: Int {
        var count = selectedTagFilters.count
            + (selectedSubfolderFilter == nil ? 0 : 1)
        
        if isFilterPopoverEnabled {
            if filterEditedActive { count += 1 }
            if filterRawActive { count += 1 }
            if filterRatingActive { count += 1 }
            if filterFlagActive { count += 1 }
            if filterNameActive && !nameFilterQuery.isEmpty { count += 1 }
            if filterDateActive { count += 1 }
        }
        return count
    }

    func resetFilterPopover() {
        filterEditedActive = false
        filterEdited = .include
        filterRawActive = false
        filterRaw = .include
        filterRatingActive = false
        filterRatingValue = 0
        filterRatingCondition = .equalTo
        filterFlagActive = false
        filterFlag = .all
        filterNameActive = false
        nameFilterQuery = ""
        nameFilterCondition = .contains
        filterDateActive = false
        filterStartDate = Date()
        filterEndDate = Date()
    }

    func clearAllFilters() {
        selectedTagFilters.removeAll()
        selectedSubfolderFilter = nil
        searchText = ""
        resetFilterPopover()
    }


    // MARK: - Large image viewer navigation
    
    func openLargeImageViewer() {
        guard !filteredPhotoSets.isEmpty else {
            errorMessage = "Load a photoshoot before opening the viewer."
            return
        }
        let count = filteredPhotoSets.count
        if focusedPhotoIndex < 0 || focusedPhotoIndex >= count {
            focusedPhotoIndex = 0
        }
        isLargeImageViewerOpen = true
        currentTagCategoryID = tagStore.categories.first?.id
        statusMessage = "Viewer mode — use ←/→ to navigate, hotkeys to tag, Esc to close."
        preloadNeighbors(around: focusedPhotoIndex)
    }
    
    func closeLargeImageViewer() {
        isLargeImageViewerOpen = false
        statusMessage = "Exited viewer mode."
    }
    
    func navigateFocusedPhoto(delta: Int) {
        let count = filteredPhotoSets.count
        guard count > 0 else { return }
        focusedPhotoIndex = max(0, min(count - 1, focusedPhotoIndex + delta))
    }
    
    func preloadNeighbors(around index: Int) {
        // Skip preloading during active scroll so decode tasks don't
        // compete with the currently-visible cells for I/O bandwidth.
        guard !ScrollStateObserver.shared.isScrolling else { return }
        let sets = filteredPhotoSets
        guard !sets.isEmpty else { return }

        let neighbors = [index - 1, index + 1, index + 2]
        for neighborIndex in neighbors {
            if neighborIndex >= 0 && neighborIndex < sets.count {
                let neighborSet = sets[neighborIndex]
                if let url = neighborSet.preferredPreviewURL {
                    LargeImageLoader.preload(url: url)
                    if visionSuggestionsCache[neighborSet.id] == nil && UserPreferences.shared.autoTaggingEnabled {
                        Task { @MainActor in
                            if self.visionSuggestionsCache[neighborSet.id] == nil {
                                let mlSuggestions = await AutoTagEngine.shared.visionSuggestions(for: url)
                                self.visionSuggestionsCache[neighborSet.id] = mlSuggestions
                            }
                        }
                    }
                }
            }
        }
    }
    
    func cycleCurrentCategory(direction: Int) {
        guard !tagStore.categories.isEmpty else { return }
        
        let cats = tagStore.categories
        guard let index = cats.firstIndex(where: { $0.id == (currentTagCategoryID ?? UUID()) }) else {
            currentTagCategoryID = cats.first?.id
            return
        }
        let next = (index + direction + cats.count) % cats.count
        currentTagCategoryID = cats[next].id
    }
    
    // MARK: - Tag application (focused photo, no auto-advance)
    
    func applyTagToFocusedPhoto(_ tag: CustomTag) {
        guard let photo = currentFocusedPhotoSet else { return }
        applyTag(tag, toPhotoSets: [photo])
    }

    /// Apply a tag to one or more photo sets with selection-aware toggle
    /// semantics: if any photo in ``photos`` lacks the tag, it is added to
    /// every photo that lacks it; if all photos already have the tag, it is
    /// removed from every photo.
    func applyTag(_ tag: CustomTag, toPhotoSets photos: [PhotoSet]) {
        guard !photos.isEmpty else { return }
        let ids = photos.map(\.id)
        let before = captureState(for: ids)
        let tagID = tag.id

        // Snapshot whether each target already has the tag, then mutate the
        // store synchronously in one pass so we don't repeatedly hit
        // tagStore.assignedTagIDs(for:) inside a hot loop.
        var targets: [(photo: PhotoSet, hasTag: Bool)] = []
        targets.reserveCapacity(photos.count)
        var anyMissing = false
        for photo in photos {
            let hasTag = tagStore.assignedTagIDs(for: photo.id).contains(tagID)
            if !hasTag { anyMissing = true }
            targets.append((photo, hasTag))
        }

        if anyMissing {
            for entry in targets where !entry.hasTag {
                let current = tagStore.assignedTagIDs(for: entry.photo.id)
                commitTagChange(current.union([tagID]),
                                for: entry.photo,
                                remove: false)
            }
            statusMessage = "Applied \(tag.name) to \(photos.count) photo set\(photos.count == 1 ? "" : "s")."
        } else {
            for entry in targets {
                let current = tagStore.assignedTagIDs(for: entry.photo.id).subtracting([tagID])
                commitTagChange(current,
                                for: entry.photo,
                                remove: current.isEmpty)
            }
            if photos.count == 1 {
                statusMessage = "Removed \(tag.name) from \(photos[0].baseName)."
            } else {
                statusMessage = "Removed \(tag.name) from \(photos.count) photo sets."
            }
        }

        registerUndo(beforeStates: before, actionName: "Apply Tag")
    }

    /// Apply a tag to every photo in the current selection (or focused photo
    /// if nothing is selected). Used by tag hotkeys.
    func applyTagToSelection(_ tag: CustomTag) {
        let targets = batchTargetPhotoSets
        applyTag(tag, toPhotoSets: targets)
    }
    
    @discardableResult
    func createAndApplyTag(named name: String, categoryID: UUID? = nil, to photoSetID: UUID) -> CustomTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tag: CustomTag
        if let existing = tagStore.tags.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            tag = existing
        } else {
            let catID = categoryID ?? tagStore.categories.first?.id ?? tagStore.addCategory(name: "Custom").id
            tag = tagStore.addTag(name: trimmed, categoryID: catID)
        }
        applyTag(tag, to: photoSetID)
        return tag
    }

    func moveTag(_ tag: CustomTag, to categoryID: UUID) {
        var updated = tag
        updated.categoryID = categoryID
        tagStore.updateTag(updated)
        updateDerivedState()
    }

    func applyTag(_ tag: CustomTag, to photoSetID: UUID) {
        guard let idx = photoSetIndex[photoSetID] else { return }
        let before = captureState(for: [photoSetID])
        let photo = photoSets[idx]
        var current = tagStore.assignedTagIDs(for: photoSetID)
        let alreadyApplied = current.contains(tag.id)
        if !alreadyApplied { current.insert(tag.id) }
        commitTagChange(current, for: photo, remove: false)
        registerUndo(beforeStates: before, actionName: "Apply Tag")
    }
    
    func removeTag(_ tag: CustomTag, from photoSetID: UUID) {
        guard let idx = photoSetIndex[photoSetID] else { return }
        let before = captureState(for: [photoSetID])
        let photo = photoSets[idx]
        var current = tagStore.assignedTagIDs(for: photoSetID)
        current.remove(tag.id)
        commitTagChange(current, for: photo, remove: current.isEmpty)
        registerUndo(beforeStates: before, actionName: "Remove Tag")
    }
    
    // MARK: - Auto-tagging
    
    /// Returns auto-tag suggestions for the given photo set, based on
    /// the user's enabled rules, EXIF metadata, and Vision ML classifications.
    func suggestedTags(for photoSet: PhotoSet) -> [AutoTagSuggestion] {
        guard UserPreferences.shared.autoTaggingEnabled else { return [] }
        
        // Trigger background Vision ML classification if not already cached
        if visionSuggestionsCache[photoSet.id] == nil, let previewURL = photoSet.preferredPreviewURL {
            Task { @MainActor in
                if self.visionSuggestionsCache[photoSet.id] == nil {
                    let mlSuggestions = await AutoTagEngine.shared.visionSuggestions(for: previewURL)
                    self.visionSuggestionsCache[photoSet.id] = mlSuggestions
                }
            }
        }

        var combined: [AutoTagSuggestion] = []

        if let visionML = visionSuggestionsCache[photoSet.id] {
            combined.append(contentsOf: visionML)
        }

        // Get currently assigned tags to exclude them from suggestions
        let assignedNames = Set(assignedTags(for: photoSet).map { $0.name.lowercased() })

        // Filter out dismissed suggestions and already assigned tags, with deduplication
        var deduplicated: [AutoTagSuggestion] = []
        var seenTagNames = Set<String>()

        for suggestion in combined {
            let lowerName = suggestion.tagName.lowercased()
            guard !assignedNames.contains(lowerName) else { continue }
            guard !seenTagNames.contains(lowerName) else { continue }
            guard !dismissedSuggestions.contains(DismissedSuggestionKey(photoSetID: photoSet.id, tagName: suggestion.tagName)) else { continue }

            seenTagNames.insert(lowerName)
            deduplicated.append(suggestion)
        }

        return deduplicated
    }
    
    /// Accepts a suggestion: applies the tag to the photo (or creates it
    /// if it doesn't exist) and writes to the XMP sidecar.
    func acceptSuggestion(_ suggestion: AutoTagSuggestion) {
        guard let photo = currentFocusedPhotoSet else { return }
        let tagName = suggestion.tagName
        
        // 1. Check if a tag with that name already exists (case-insensitive).
        if let existingTag = tagStore.tags.first(where: {
            $0.name.lowercased() == tagName.lowercased()
        }) {
            applyTag(existingTag, toPhotoSets: [photo])
            statusMessage = "Applied \(tagName) to \(photo.baseName)."
        } else {
            // 2. Tag doesn't exist — create it.
            let newTag: CustomTag
            if let categoryID = suggestion.categoryID {
                // Create in existing category.
                newTag = tagStore.addTag(name: tagName, categoryID: categoryID)
            } else {
                // Create a new "Auto-Tagged" category.
                let autoCategory: TagCategory
                if let existingCategory = tagStore.categories.first(where: {
                    $0.name.lowercased() == "auto-tagged"
                }) {
                    autoCategory = existingCategory
                } else {
                    autoCategory = tagStore.addCategory(name: "Auto-Tagged")
                }
                newTag = tagStore.addTag(name: tagName, categoryID: autoCategory.id)
            }
            applyTag(newTag, toPhotoSets: [photo])
            statusMessage = "Created and applied \(tagName) to \(photo.baseName)."
        }
        
        // Clear from dismissed set so it won't reappear.
        dismissedSuggestions.remove(DismissedSuggestionKey(photoSetID: photo.id, tagName: tagName))
    }
    
    /// Dismisses a suggestion. Ephemeral — not persisted.
    func dismissSuggestion(_ suggestion: AutoTagSuggestion) {
        guard let photo = currentFocusedPhotoSet else { return }
        dismissedSuggestions.insert(DismissedSuggestionKey(photoSetID: photo.id, tagName: suggestion.tagName))
    }
    
    func clearTags(for photoSetID: UUID) {
        clearTags(forIDs: [photoSetID])
    }

    /// Clear custom tags for every photo in ``ids``. Used by the "0" hotkey
    /// so users can reset all tags on the selection in a single action.
    func clearTags(forIDs ids: [PhotoSet.ID]) {
        guard !ids.isEmpty else { return }
        let before = captureState(for: ids)
        let targets: [PhotoSet] = ids.compactMap { photoSetIndex[$0].map { photoSets[$0] } }
        for photo in targets {
            commitTagChange([], for: photo, remove: true)
        }
        statusMessage = "Cleared tags on \(ids.count) photo set\(ids.count == 1 ? "" : "s")."
        registerUndo(beforeStates: before, actionName: "Clear Tags")
    }
    
    private func commitTagChange(_ tagIDs: Set<UUID>, for photo: PhotoSet, remove: Bool) {
        tagStore.setTags(tagIDs, for: photo.id)
        
        let names = tagIDs.compactMap { tagStore.tag(id: $0)?.name }
        let nameSet = Set(names)
        let existingSnapshot = photoMetadata[photo.id]
        let reader = metadataReader
        let previousTask = tagTask
        tagTask = Task { @MainActor [weak self, xmpTagging] in
            _ = await previousTask?.result
            let result: Result<Void, Error> = await Task.detached(priority: .utility) {
                if remove {
                    return Result { try xmpTagging.clear(for: photo) }
                } else {
                    let snapshot = existingSnapshot ?? (photo.preferredPreviewURL.map { reader.metadata(for: $0) } ?? MetadataSnapshot())
                    return Result { try xmpTagging.applyTagNames(nameSet, to: photo, metadata: snapshot) }
                }
            }.value
            if case .failure(let error) = result {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func clearTagsForSelection() {
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = "Select at least one photo set before clearing tags."
            return
        }
        let ids = selected.map(\.id)
        let before = captureState(for: ids)
        let previousTask = tagTask
        // Update in-memory tagStore + undo immediately so rapid edits remain ordered.
        for photo in selected {
            tagStore.clearTags(for: photo.id)
        }
        registerUndo(beforeStates: before, actionName: "Clear Tags")
        statusMessage = "Clearing tags for \(selected.count) selected photo sets..."
        tagTask = Task { @MainActor [weak self, xmpTagging] in
            _ = await previousTask?.result
            let result: Result<Void, Error> = await Task.detached(priority: .utility) {
                for photo in selected {
                    try Task.checkCancellation()
                    try xmpTagging.clear(for: photo)
                }
            }.result
            guard let self else { return }
            switch result {
            case .success:
                self.statusMessage = "Cleared tags for \(selected.count) photo sets."
            case .failure(is CancellationError):
                self.statusMessage = "Tag clearing cancelled."
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Could not clear tags."
            }
        }
    }
    
    // MARK: - Plain transfer (no routing)
    
    func transferSelectedPhotoSets(operation: TransferOperation) {
        guard let destinationDirectory else { return }
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = TransferError.noSelection.localizedDescription
            return
        }
        transferTask?.cancel()
        isTransferring = true
        operationProgress = nil
        errorMessage = nil
        statusMessage = "\(operation.progressTitle) \(selected.count) selected photo sets (\(selectedFileCount) files)..."
        let tagNameMap: [UUID: Set<String>] = Dictionary(
            uniqueKeysWithValues: selected.map { set in
                (set.id, Set(tagStore.assignedTags(for: set.id).map(\.name)))
            }
        )
        let plan = TransferPlan(
            operation: operation,
            destinationDirectory: destinationDirectory,
            photoSets: selected,
            tagNames: tagNameMap,
            metadata: photoMetadata
        )
        let currentSources = sourceDirectories
        transferTask = Task { @MainActor [transferService, currentSources] in
            do {
                let summary = try await transferService.execute(plan) { progress in
                    Task { @MainActor in
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                self.statusMessage = "\(summary.operation.rawValue) complete: \(summary.fileCount) files to \(summary.destinationDirectory.lastPathComponent)."
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
                self.clearSelection()
                if operation == .move {
                    self.scanSourceDirectories(currentSources)
                }
            } catch is CancellationError {
                self.statusMessage = "Transfer cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Transfer failed."
            }
            self.operationProgress = nil
            self.isTransferring = false
        }
    }
    
    // MARK: - Routed transfer (copy / move / export JPEG with rule)
    
    func performRoutedOperation(_ operation: RoutedOperation) {
        guard let destinationDirectory else {
            errorMessage = "Choose a destination folder first."
            return
        }
        let selected = selectedPhotoSets
        guard !selected.isEmpty else {
            errorMessage = TransferError.noSelection.localizedDescription
            return
        }
        guard let rule = ruleStore.selectedRule else {
            errorMessage = "Create an export routing rule first."
            return
        }
        
        let routedPhotos: [RoutedPhoto] = selected.map { photo in
            RoutedPhoto(
                photoSet: photo,
                metadata: photoMetadata[photo.id] ?? MetadataSnapshot(),
                tags: tagStore.assignedTags(for: photo.id)
            )
        }
        
        let plan = RoutedPlan(
            operation: operation,
            baseDestination: destinationDirectory,
            rule: rule.components,
            photos: routedPhotos
        )
        
        self.pendingRoutedPlan = plan
    }

    func executeRoutedPlan(_ plan: RoutedPlan) {
        let categoryNames = Dictionary(
            uniqueKeysWithValues: tagStore.categories.map { ($0.id, $0.name) }
        )
        let categoryNameProvider: @Sendable (UUID) -> String? = { id in
            categoryNames[id]
        }
        
        let operation = plan.operation
        let selectedCount = plan.photos.count
        
        transferTask?.cancel()
        isTransferring = true
        operationProgress = nil
        errorMessage = nil
        statusMessage = "\(operation.progressTitle) \(selectedCount) photo sets into routed folders..."
        
        let currentSources = sourceDirectories
        transferTask = Task { @MainActor [routedTransfer, currentSources] in
            do {
                let summary = try await routedTransfer.execute(
                    plan,
                    categoryNameProvider: categoryNameProvider
                ) { progress in
                    Task { @MainActor in
                        self.operationProgress = progress
                        self.statusMessage = "\(operation.progressTitle) \(progress.displayText)"
                    }
                }
                let foldersText = summary.foldersCreated == 1 ? "1 folder" : "\(summary.foldersCreated) folders"
                self.statusMessage = "\(operation.displayName) complete: \(summary.fileCount) files across \(foldersText) under \(summary.baseDestination.lastPathComponent)."
                if summary.sidecarFailures > 0 {
                    self.statusMessage += " (\(summary.sidecarFailures) sidecar(s) could not be written)"
                }
                if summary.filesLeftInPlace > 0 {
                    self.statusMessage += " (\(summary.filesLeftInPlace) file(s) left in place, already present at destination)"
                }
                self.clearSelection()
                if operation == .moveOriginals {
                    self.scanSourceDirectories(currentSources)
                }
            } catch is CancellationError {
                self.statusMessage = "Operation cancelled."
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusMessage = "Routed operation failed."
            }
            self.operationProgress = nil
            self.isTransferring = false
        }
    }
    
    // MARK: - Tag loading (now merged into loadMetadataAndTags)

    // MARK: - Keyboard Monitor Retention
    nonisolated(unsafe) private var keyboardMonitor: Any? = nil

    func registerKeyboardMonitor(_ handler: @escaping (NSEvent) -> Bool) {
        if let existing = keyboardMonitor {
            NSEvent.removeMonitor(existing)
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handler(event) {
                return nil
            }
            return event
        }
    }

    nonisolated(unsafe) private var scrollMonitor: Any? = nil

    func registerScrollMonitor(_ handler: @escaping (NSEvent) -> Bool) {
        if let existing = scrollMonitor {
            NSEvent.removeMonitor(existing)
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if handler(event) {
                return nil
            }
            return event
        }
    }

    @Published var tagManagerHotkey: String? = "cmd+t" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.tagManagerHotkey = tagManagerHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var ruleEditorHotkey: String? = "cmd+r" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.ruleEditorHotkey = ruleEditorHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var openSourceHotkey: String? = "cmd+o" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.openSourceHotkey = openSourceHotkey ?? ""
            UserPreferences.shared.save()
        }
    }

    @Published var photomatorHotkey: String? = "e" {
        didSet {
            guard !isInitializing else { return }
            UserPreferences.shared.photomatorHotkey = photomatorHotkey ?? ""
            UserPreferences.shared.save()
        }
    }



    var tagManagerShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = tagManagerHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }

    var ruleEditorShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = ruleEditorHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }

    var openSourceShortcutInfo: KeyboardShortcutInfo? {
        guard let hotkey = openSourceHotkey, !hotkey.isEmpty else { return nil }
        return KeyboardShortcutInfo.parse(hotkey)
    }



    // MARK: - Count Memoization & Index Clamping
    
    private var photoDateCache: [UUID: Date] = [:]
    private var photoFileSizeCache: [UUID: Int64] = [:]

    func photoDate(for photoSet: PhotoSet) -> Date {
        if let cached = photoDateCache[photoSet.id] {
            return cached
        }
        if let captureDate = photoMetadata[photoSet.id]?.captureDate {
            photoDateCache[photoSet.id] = captureDate
            return captureDate
        }
        if let modDate = photoSet.modificationDate {
            photoDateCache[photoSet.id] = modDate
            return modDate
        }
        if let fileURL = photoSet.mediaFiles.first,
           let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modDate = values.contentModificationDate {
            photoDateCache[photoSet.id] = modDate
            return modDate
        }
        let fallback = Date.distantPast
        photoDateCache[photoSet.id] = fallback
        return fallback
    }

    func photoFileSize(for photoSet: PhotoSet) -> Int64 {
        if let precomputed = photoSet.totalFileSize {
            return precomputed
        }
        if let cached = photoFileSizeCache[photoSet.id] {
            return cached
        }
        var total: Int64 = 0
        for file in photoSet.allFiles {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                total += Int64(size)
            }
        }
        photoFileSizeCache[photoSet.id] = total
        return total
    }

    func updateDerivedState() {
        guard !suppressDerivedUpdates else { return }

        let hasTagFilter = !selectedTagFilters.isEmpty
        let subfolderPath = selectedSubfolderFilter?.standardizedFileURL.path
        let textQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasSearchQuery = !textQuery.isEmpty

        // Header Name filter
        let nameQuery = nameFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasNameFilter = !nameQuery.isEmpty

        // Date range boundaries
        let startOfDay: Date
        let endOfDay: Date
        if isFilterPopoverEnabled && filterDateActive {
            startOfDay = Calendar.current.startOfDay(for: filterStartDate)
            endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: filterEndDate)
                .map { Calendar.current.startOfDay(for: $0) } ?? filterEndDate
        } else {
            startOfDay = .distantPast
            endOfDay = .distantFuture
        }

        var list: [PhotoSet] = []
        list.reserveCapacity(photoSets.count)

        for photoSet in photoSets {
            // Hide rejected photos by default, unless the user specifically filters by Rejected flag
            let isFilteringRejected = isFilterPopoverEnabled && filterFlagActive && filterFlag == .rejected
            if !isFilteringRejected && photoSet.pick == -1 {
                continue
            }

            // Library sidebar filter rule (All / Edited / Unedited)
            if !filterRule.matches(photoSet) {
                continue
            }

            // 1. Sidebar subfolder filter (if selected)
            if let subfolderPath {
                let subfolderPrefix = subfolderPath.hasSuffix("/") ? subfolderPath : subfolderPath + "/"
                var matches = false
                for fileURL in photoSet.mediaFiles {
                    let filePath = fileURL.standardizedFileURL.path
                    if filePath == subfolderPath || filePath.hasPrefix(subfolderPrefix) {
                        matches = true
                        break
                    }
                }
                if !matches { continue }
            }

            // 2. Sidebar Tag Filter (stacks with everything)
            if hasTagFilter {
                let assigned = tagStore.assignedTagIDs(for: photoSet.id)
                if selectedTagFilters.isDisjoint(with: assigned) { continue }
            }

            // 3. Header: Edited Filter (Include/Exclude)
            if isFilterPopoverEnabled && filterEditedActive {
                if filterEdited == .exclude && photoSet.hasEdit {
                    continue
                }
                if filterEdited == .include && !photoSet.hasEdit {
                    continue
                }
            }

            // 4. Header: RAW Filter (Include/Exclude)
            if isFilterPopoverEnabled && filterRawActive {
                if filterRaw == .exclude && photoSet.mediaFormats.isRaw {
                    continue
                }
                if filterRaw == .include && !photoSet.mediaFormats.isRaw {
                    continue
                }
            }

            // 5. Header: Rating Filter with condition modifier
            if isFilterPopoverEnabled && filterRatingActive {
                let ratingVal = photoSet.rating ?? 0
                let filterVal = filterRatingValue // 0 is Unrated, 1-5 is stars
                switch filterRatingCondition {
                case .equalTo:
                    if ratingVal != filterVal { continue }
                case .greaterThanOrEqualTo:
                    if ratingVal < filterVal { continue }
                case .lessThanOrEqualTo:
                    if ratingVal > filterVal { continue }
                }
            }

            // 6. Header: Flag Filter
            if isFilterPopoverEnabled && filterFlagActive {
                switch filterFlag {
                case .flagged:
                    if photoSet.pick != 1 { continue }
                case .rejected:
                    if photoSet.pick != -1 { continue }
                case .unflagged:
                    if (photoSet.pick ?? 0) != 0 { continue }
                case .all:
                    break
                }
            }

            // 7. Header: File Name search with conditions
            if isFilterPopoverEnabled && filterNameActive && hasNameFilter {
                let baseName = photoSet.baseName.lowercased()
                switch nameFilterCondition {
                case .contains:
                    if !baseName.contains(nameQuery) { continue }
                case .matches:
                    if baseName != nameQuery { continue }
                case .startsWith:
                    if !baseName.hasPrefix(nameQuery) { continue }
                case .endsWith:
                    if !baseName.hasSuffix(nameQuery) { continue }
                }
            }

            // 8. Header: Date Range Filter
            if isFilterPopoverEnabled && filterDateActive {
                let captureDate = photoDate(for: photoSet)
                if captureDate < startOfDay || captureDate >= endOfDay {
                    continue
                }
            }

            // 9. Standard search bar filter (caption / baseName)
            if hasSearchQuery {
                if !photoSet.baseName.lowercased().contains(textQuery),
                   !(photoCaptions[photoSet.id]?.lowercased().contains(textQuery) ?? false) {
                    continue
                }
            }

            list.append(photoSet)
        }

        // Apply Sorting dynamically based on Top Header rules
        list.sort { lhs, rhs in
            let ascending = (sortDirection == .ascending)
            switch sortOrder {
            case .name:
                let result = lhs.baseName.localizedStandardCompare(rhs.baseName)
                return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
            case .date:
                let d1 = photoDate(for: lhs)
                let d2 = photoDate(for: rhs)
                if d1 == d2 {
                    return lhs.baseName.localizedStandardCompare(rhs.baseName) == .orderedAscending
                }
                return ascending ? (d1 < d2) : (d1 > d2)
            case .size:
                let s1 = photoFileSize(for: lhs)
                let s2 = photoFileSize(for: rhs)
                if s1 == s2 {
                    return lhs.baseName.localizedStandardCompare(rhs.baseName) == .orderedAscending
                }
                return ascending ? (s1 < s2) : (s1 > s2)
            }
        }

        // Skip-if-equal: avoid the SwiftUI diffing pass when the filtered
        // result is identical to what's already displayed. This commonly
        // occurs when a non-filter property (e.g. inspector state) changes.
        if list != self.filteredPhotoSets {
            // Reshuffle grid animates automatically via SwiftUI spring transition
            withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                self.filteredPhotoSets = list
            }
        }

        // Clamp focusedPhotoIndex first to valid range of filteredPhotoSets
        let clamped: Int
        if !list.isEmpty {
            clamped = max(0, min(focusedPhotoIndex, list.count - 1))
        } else {
            clamped = 0
        }

        if focusedPhotoIndex != clamped {
            focusedPhotoIndex = clamped
        }

        let index = clamped
        let start = max(0, index - 10)
        let end = min(list.count - 1, index + 10)
        var newSet = Set<UUID>()
        newSet.reserveCapacity(end - start + 1)
        if !list.isEmpty && start <= end {
            for i in start...end {
                newSet.insert(list[i].id)
            }
        }
        if newSet != self.nearFocusedIds {
            self.nearFocusedIds = newSet
        }
    }

    func updateGlobalCounts() {
        let totalPhotos = photoSets.count
        self.cachedAllPhotosCount = totalPhotos

        var editedCount = 0
        var pick1Count = 0
        var pickMinus1Count = 0
        var pick0Count = 0
        var ratingCounts = [Int: Int]()
        for r in 0...5 { ratingCounts[r] = 0 }

        var tagHistogram = [UUID: Int]()
        for tag in tagStore.tags { tagHistogram[tag.id] = 0 }

        let currentFolderKey = (photoSets.count, sourceDirectories, photoSets.first?.id, photoSets.last?.id)
        let needsFolderRebuild = currentFolderKey.0 != lastFolderIndexKey.count
            || currentFolderKey.1 != lastFolderIndexKey.sources
            || currentFolderKey.2 != lastFolderIndexKey.firstID
            || currentFolderKey.3 != lastFolderIndexKey.lastID

        var photoSetsBySubfolder = [URL: Set<UUID>]()

        // Reset selection counters before the loop so they stay consistent
        // with `photoSets` even when individual sets flip isSelected mid-loop
        // (which they don't, but the invariant is easier to reason about).
        cachedSelectedCount = 0
        cachedSelectedFileCount = 0

        for photoSet in photoSets {
            if photoSet.hasEdit {
                editedCount += 1
            }

            if photoSet.isSelected {
                cachedSelectedCount += 1
                cachedSelectedFileCount += photoSet.mediaFiles.count + (photoSet.editPath != nil ? 1 : 0)
            }
            
            let pick = photoSet.pick ?? 0
            if pick == 1 {
                pick1Count += 1
            } else if pick == -1 {
                pickMinus1Count += 1
            } else {
                pick0Count += 1
            }
            
            let rating = photoSet.rating ?? 0
            if rating >= 0 && rating <= 5 {
                ratingCounts[rating, default: 0] += 1
            }
            
            let assignedIDs = tagStore.assignedTagIDs(for: photoSet.id)
            for tagID in assignedIDs {
                tagHistogram[tagID, default: 0] += 1
            }
            
            if needsFolderRebuild {
                for file in photoSet.mediaFiles {
                    let parentDir = file.deletingLastPathComponent().standardizedFileURL
                    photoSetsBySubfolder[parentDir, default: []].insert(photoSet.id)
                }
            }
        }
        
        self.cachedEditedCount = editedCount
        self.cachedUneditedCount = totalPhotos - editedCount
        
        self.cachedTagCounts = tagHistogram
        self.cachedFlagCounts = [1: pick1Count, -1: pickMinus1Count, 0: pick0Count]
        self.cachedRatingCounts = ratingCounts

        if needsFolderRebuild {
            lastFolderIndexKey = currentFolderKey
            let folderIndex = FolderTreeIndex.build(
                from: photoSetsBySubfolder,
                sourceDirectories: sourceDirectories
            )
            self.cachedSubfolders = folderIndex.cachedSubfolders
            self.cachedSubfolderCounts = folderIndex.cachedSubfolderCounts
            self.childSubfoldersIndex = folderIndex.childSubfoldersIndex
            self.recursivePhotoCountIndex = folderIndex.recursivePhotoCountIndex
            self.childFolderURLs = folderIndex.childFolderURLs
        }
    }

    func relativePath(of subfolderURL: URL, relativeTo sourceURL: URL) -> String {
        FolderTreeIndex.relativePath(of: subfolderURL, relativeTo: sourceURL)
    }

    // MARK: - Recursive folder tree (O(1) lookups against the index)

    /// Returns the immediate child subfolders of `folder` that contain
    /// at least one photo set in the loaded library. Returns `[]` for
    /// folders with no photo-bearing children or for the library root.
    ///
    /// Backed by `childFolderURLs`, populated inside `updateGlobalCounts`
    /// every time `photoSets` changes. O(1) per call.
    func childSubfolders(of folder: URL) -> [URL] {
        let path = folder.standardizedFileURL.path
        guard path != "/" else { return [] }
        return childFolderURLs[path] ?? []
    }

    /// Total photo sets that live anywhere at or below `folder`. Includes
    /// the folder itself, its direct children, and all deeper
    /// descendants. O(1) per call.
    func recursivePhotoCount(in folder: URL) -> Int {
        let path = folder.standardizedFileURL.path
        guard path != "/" else { return photoSets.count }
        return recursivePhotoCountIndex[path] ?? 0
    }

    /// True if `folder` is known to contain any photo sets anywhere in
    /// its subtree. Used by the tree row to decide whether to show the
    /// expand chevron. O(1) per call.
    func hasAnyPhotos(in folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        return (recursivePhotoCountIndex[path] ?? 0) > 0
    }

    /// True if `folder` contains any photo set directly (the photo set's
    /// parent directory equals `folder`). O(n) but typically only called
    /// once per row when first expanding; cheap because the typical
    /// sub-tree size is small.
    func hasPhotosDirectly(in folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        for set in photoSets {
            for file in set.mediaFiles {
                if file.deletingLastPathComponent().standardizedFileURL.path == folderPath {
                    return true
                }
            }
        }
        return false
    }

    /// Returns photo sets whose media files are directly inside `folder`
    /// (not inside a subfolder of `folder`). Used by the file-level tree
    /// leaf nodes so users can drill down to individual photos.
    ///
    /// When a folder is expanded in the sidebar, this method is called once
    /// and the result is cached in `@State` so expanding/collapsing doesn't
    /// re-scan on every render.
    func photoSetsDirectlyIn(folder: URL) -> [PhotoSet] {
        let folderPath = folder.standardizedFileURL.path
        return photoSets.filter { set in
            set.mediaFiles.contains { file in
                file.deletingLastPathComponent().standardizedFileURL.path == folderPath
            }
        }
    }

    // MARK: - Insights

    func computeInsights() -> InsightReport {
        InsightsCalculator.compute(
            photoMetadata: photoMetadata,
            photoSets: photoSets,
            photoSetIndex: photoSetIndex
        )
    }

    // MARK: - External Editor Handoff

    func openFocusedPhotoInPhotomator() {
        guard focusedPhotoIndex >= 0 && focusedPhotoIndex < filteredPhotoSets.count else { return }
        let photo = filteredPhotoSets[focusedPhotoIndex]
        
        // Choose the raw file if present (Photomator prefers editing RAWs), otherwise fallback to JPEG/HEIF
        let rawExtensions: Set<String> = ["raf", "arw", "cr2", "cr3", "nef", "dng", "orf", "rw2", "pef"]
        guard let targetURL = photo.mediaFiles.first(where: { rawExtensions.contains($0.pathExtension.lowercased()) })
               ?? photo.preferredPreviewURL else { return }

        let workspace = NSWorkspace.shared
        
        // Attempt to launch Photomator explicitly
        if let photomatorURL = workspace.urlForApplication(withBundleIdentifier: "com.pixelmatorteam.pixelmator.touch.x.photo") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            workspace.open([targetURL], withApplicationAt: photomatorURL, configuration: configuration) { _, error in
                if let error {
                    print("Failed to launch Photomator: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback: Open with default application
            workspace.open(targetURL)
        }
    }

}

/// Key for tracking dismissed auto-tag suggestions.
private struct DismissedSuggestionKey: Hashable {
    let photoSetID: UUID
    let tagName: String
}
