import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation

struct ContentView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RootTabsView()
            .onAppear {
                session.setup(context: modelContext)
            }
    }
}

struct RootTabsView: View {
    @Environment(VolioSession.self) private var session
    @State private var selectedTab: MainTab = .timeline
    @State private var lastContentTab: MainTab = .timeline
    @State private var showCamera = false
    @State private var showAddMenu = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    var body: some View {
        rootShell
        .tint(VolioTheme.accent)
        .environment(\.dismissVolioTransientOverlays, dismissTransientOverlays)
        .fullScreenCover(isPresented: $showCamera) {
            StackCameraView(
                onCapture: { payload in
                    Task {
                        await session.createWorkAsync(
                            data: payload.originalData,
                            previewData: payload.previewData,
                            workType: "visual",
                            createdAround: .unknown
                        )
                    }
                },
                onDone: { _ in
                    selectedTab = .gallery
                    lastContentTab = .gallery
                },
                onCancel: {
                    selectedTab = lastContentTab
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 30, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await importPhotos(items) }
        }
        .overlay(alignment: .top) {
            if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(VolioTheme.accent, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if session.errorMessage == message {
                            session.errorMessage = nil
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: session.errorMessage != nil)
    }

    @ViewBuilder
    private var rootShell: some View {
        if #available(iOS 18.0, *) {
            SystemRootTabsView(
                selectedTab: $selectedTab,
                lastContentTab: $lastContentTab,
                showCamera: $showCamera,
                showAddMenu: $showAddMenu,
                showPhotoPicker: $showPhotoPicker
            )
        } else {
            LegacyRootTabsView(
                selectedTab: $selectedTab,
                showAddMenu: $showAddMenu,
                showCamera: $showCamera,
                showPhotoPicker: $showPhotoPicker,
                onAdd: toggleAddMenu
            )
        }
    }

    private func toggleAddMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            showAddMenu.toggle()
        }
        if showAddMenu {
            prewarmCameraAccess()
        }
    }

    private func prewarmCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
            break
        }
    }

    private func dismissTransientOverlays() {
        guard showAddMenu else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showAddMenu = false
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await session.createWorkAsync(data: data, workType: "visual", createdAround: .unknown)
            }
        }
        photoPickerItems.removeAll()
        selectedTab = .gallery
        lastContentTab = .gallery
    }
}

private struct DismissVolioTransientOverlaysKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dismissVolioTransientOverlays: () -> Void {
        get { self[DismissVolioTransientOverlaysKey.self] }
        set { self[DismissVolioTransientOverlaysKey.self] = newValue }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case gallery
    case timeline
    case search
    case capture

    var id: String { rawValue }
    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .timeline: "Timeline"
        case .search: "Search"
        case .capture: "Capture"
        }
    }

    var icon: String {
        switch self {
        case .gallery: "square.grid.2x2"
        case .timeline: "clock"
        case .search: "magnifyingglass"
        case .capture: "plus"
        }
    }

    static var contentTabs: [MainTab] { [.timeline, .gallery, .search] }
}

@available(iOS 18.0, *)
private struct SystemRootTabsView: View {
    @Environment(VolioSession.self) private var session
    @Binding var selectedTab: MainTab
    @Binding var lastContentTab: MainTab
    @Binding var showCamera: Bool
    @Binding var showAddMenu: Bool
    @Binding var showPhotoPicker: Bool

    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .capture {
                    toggleAddMenu()
                    selectedTab = lastContentTab
                } else {
                    showAddMenu = false
                    selectedTab = newValue
                    lastContentTab = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(MainTab.timeline.title, systemImage: MainTab.timeline.icon, value: MainTab.timeline) {
                TimelineView()
            }

            Tab(MainTab.gallery.title, systemImage: MainTab.gallery.icon, value: MainTab.gallery) {
                GalleryView()
            }

            Tab(MainTab.search.title, systemImage: MainTab.search.icon, value: MainTab.search) {
                SearchView()
            }

            cameraTab
        }
        .toolbar(session.isShowingDetail ? .hidden : .visible, for: .tabBar)
        .volioStableSystemTabBar()
        .overlay(alignment: .bottomTrailing) {
            if !session.isShowingDetail {
                AddTabTouchShield(onAdd: toggleAddMenu)
                    .padding(.trailing, 0)
                    .padding(.bottom, 0)
                    .zIndex(45)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showAddMenu, !session.isShowingDetail {
                AddWorkMenu(
                    onTakePhoto: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            showAddMenu = false
                        }
                        showCamera = true
                    },
                    onChoosePhoto: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            showAddMenu = false
                        }
                        showPhotoPicker = true
                    }
                )
                .padding(.trailing, 18)
                .padding(.bottom, 82)
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                .zIndex(60)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showAddMenu)
    }

    @TabContentBuilder<MainTab>
    private var cameraTab: some TabContent<MainTab> {
        if #available(iOS 27.0, *) {
            Tab("Add", systemImage: MainTab.capture.icon, value: MainTab.capture, role: .prominent) {
                Color.clear
            }
        } else {
            Tab("Add", systemImage: MainTab.capture.icon, value: MainTab.capture, role: .search) {
                Color.clear
            }
        }
    }

    private func toggleAddMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            showAddMenu.toggle()
        }
        if showAddMenu {
            prewarmCameraAccess()
        }
    }

    private func prewarmCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
            break
        }
    }
}

private struct AddTabTouchShield: View {
    var onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            Color.clear
                .frame(width: 76, height: 76)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add work")
    }
}

private struct AddWorkMenu: View {
    var onTakePhoto: () -> Void
    var onChoosePhoto: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            AddWorkMenuRow(icon: "camera.fill", title: "Take Photo", action: onTakePhoto)
            Divider()
                .padding(.leading, 44)
            AddWorkMenuRow(icon: "photo.on.rectangle", title: "Choose Photo", action: onChoosePhoto)
        }
        .padding(.vertical, 8)
        .frame(width: 214)
        .modifier(AddWorkMenuChrome())
    }
}

private struct AddWorkMenuRow: View {
    var icon: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(VolioTheme.ink)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

private struct AddWorkMenuChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.5)).interactive(), in: .rect(cornerRadius: 28))
                .shadow(color: VolioTheme.ink.opacity(0.16), radius: 18, y: 10)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: VolioTheme.ink.opacity(0.16), radius: 18, y: 10)
        }
    }
}

private struct LegacyRootTabsView: View {
    @Environment(VolioSession.self) private var session
    @Binding var selectedTab: MainTab
    @Binding var showAddMenu: Bool
    @Binding var showCamera: Bool
    @Binding var showPhotoPicker: Bool
    var onAdd: () -> Void

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case .gallery:
                    GalleryView()
                case .timeline:
                    TimelineView()
                case .search:
                    SearchView()
                case .capture:
                    GalleryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if !session.isShowingDetail {
                FloatingBottomControls(selectedTab: $selectedTab, showAddMenu: showAddMenu, onAdd: onAdd)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showAddMenu, !session.isShowingDetail {
                AddWorkMenu(
                    onTakePhoto: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            showAddMenu = false
                        }
                        showCamera = true
                    },
                    onChoosePhoto: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                            showAddMenu = false
                        }
                        showPhotoPicker = true
                    }
                )
                .padding(.trailing, 18)
                .padding(.bottom, 82)
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                .zIndex(60)
            }
        }
    }
}

private struct NativeTabCluster: UIViewRepresentable {
    @Binding var selectedTab: MainTab
    private static let tabs = MainTab.contentTabs
    private let horizontalPressOverflow: CGFloat = 18

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedTab: $selectedTab)
    }

    func makeUIView(context: Context) -> TabBarContainerView {
        let container = TabBarContainerView(
            horizontalPressOverflow: horizontalPressOverflow
        )
        let tabBar = container.tabBar
        tabBar.delegate = context.coordinator
        tabBar.items = Self.tabs.enumerated().map { index, tab in
            UITabBarItem(title: tab.title, image: UIImage(systemName: tab.icon), tag: index)
        }
        tabBar.itemPositioning = .fill
        tabBar.tintColor = UIColor(red: 0.94, green: 0.33, blue: 0.20, alpha: 1)
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.clipsToBounds = false

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance.selected.iconColor = tabBar.tintColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: tabBar.tintColor as Any]
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        updateSelection(tabBar)
        return container
    }

    func updateUIView(_ uiView: TabBarContainerView, context: Context) {
        uiView.horizontalPressOverflow = horizontalPressOverflow
        uiView.setNeedsLayout()
        updateSelection(uiView.tabBar)
    }

    private func updateSelection(_ tabBar: UITabBar) {
        guard let index = Self.tabs.firstIndex(of: selectedTab),
              let item = tabBar.items?.first(where: { $0.tag == index }) else { return }
        if tabBar.selectedItem !== item {
            tabBar.selectedItem = item
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selectedTab: Binding<MainTab>

        init(selectedTab: Binding<MainTab>) {
            self.selectedTab = selectedTab
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard item.tag >= 0, item.tag < NativeTabCluster.tabs.count else { return }
            selectedTab.wrappedValue = NativeTabCluster.tabs[item.tag]
        }
    }

    final class TabBarContainerView: UIView {
        let tabBar = UITabBar()
        var horizontalPressOverflow: CGFloat

        init(horizontalPressOverflow: CGFloat) {
            self.horizontalPressOverflow = horizontalPressOverflow
            super.init(frame: .zero)
            clipsToBounds = false
            backgroundColor = .clear
            addSubview(tabBar)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            clipsToBounds = false
            layer.masksToBounds = false

            tabBar.frame = CGRect(
                x: horizontalPressOverflow,
                y: 0,
                width: max(1, bounds.width - horizontalPressOverflow * 2),
                height: bounds.height
            )
            tabBar.clipsToBounds = false
            tabBar.layer.masksToBounds = false
        }
    }
}

private struct FloatingCaptureButton: View {
    var isOpen: Bool
    var onAdd: () -> Void
    private let buttonSize: CGFloat = 68

    var body: some View {
        ZStack {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: buttonSize, height: buttonSize)
                    .rotationEffect(.degrees(isOpen ? 45 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Close add menu" : "Add work")
            .modifier(CaptureButtonChrome())
        }
        .frame(width: buttonSize, height: buttonSize, alignment: .center)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
    }
}

private struct CaptureButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(VolioTheme.accent)
                .glassEffect(.regular.tint(Color.white.opacity(0.46)).interactive(), in: .circle)
                .shadow(color: VolioTheme.ink.opacity(0.16), radius: 16, y: 8)
        } else {
            content
                .foregroundStyle(.white)
                .background(VolioTheme.accent, in: Circle())
                .shadow(color: VolioTheme.accent.opacity(0.28), radius: 16, y: 8)
        }
    }
}

// MARK: - Bottom Controls

private struct FloatingBottomControls: View {
    @Binding var selectedTab: MainTab
    var showAddMenu: Bool
    var onAdd: () -> Void

    private let horizontalInset: CGFloat = 20
    private let controlHeight: CGFloat = 92
    private let tabWidth: CGFloat = 268
    private let tabPressOverflow: CGFloat = 18
    private let cameraSize: CGFloat = 68
    private let bottomPadding: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let tabVisualLeft = horizontalInset - 2
            let tabCenterX = tabVisualLeft + tabWidth / 2
            let tabFrameWidth = tabWidth + 2 * tabPressOverflow
            let cameraCenterX = proxy.size.width - horizontalInset - cameraSize / 2
            let centerY = controlHeight / 2

            NativeTabCluster(selectedTab: $selectedTab)
                .frame(width: tabFrameWidth, height: controlHeight)
                .position(x: tabCenterX, y: centerY)

            FloatingCaptureButton(isOpen: showAddMenu, onAdd: onAdd)
            .frame(width: cameraSize, height: cameraSize)
            .position(x: cameraCenterX, y: centerY)
        }
        .frame(height: controlHeight)
        .padding(.bottom, bottomPadding)
        .allowsHitTesting(true)
    }
}

extension View {
    @ViewBuilder
    func volioStableSystemTabBar() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }

    @ViewBuilder
    func volioGlass(cornerRadius: CGFloat, tint: Color = VolioTheme.glassTint, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.52), lineWidth: 1)
                }
        }
    }
}

// MARK: - Settings Tab

struct SettingsLinkView: View {
    var body: some View {
        NavigationStack {
            SettingsContent()
        }
    }
}

struct SettingsContent: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @State private var showPairing = false
    @State private var name = ""
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 6
    @State private var birthMonth = 6
    @State private var hasProfile = false

    private let accentColor = VolioTheme.accent

    var body: some View {
        List {
            Section {
                Toggle("Profile", isOn: $hasProfile)
                    .tint(accentColor)
                if hasProfile {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Birth year", selection: $birthYear) {
                        ForEach((2005...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Birth month", selection: $birthMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                        }
                    }
                }
            } header: {
                Label("Creator", systemImage: "person.fill")
            }

            Section {
                if session.isMacPaired {
                    HStack {
                        Label("Paired", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(session.macHostName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Forget Mac", role: .destructive) {
                        session.forgetMac()
                    }
                } else {
                    Button("Connect to Mac") {
                        showPairing = true
                    }
                    Text("Pair with Volio Desktop on your Mac for AI analysis and backup.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Mac Assist", systemImage: "desktopcomputer")
            }

            Section {
                Text("\(session.works.count) works")
                    .foregroundStyle(.secondary)
                Text("Volio stores everything on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Label("Storage", systemImage: "internaldrive")
            }
        }
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $showPairing) {
            PairingView()
        }
        .onAppear { loadProfile() }
        .onChange(of: hasProfile) { _, newValue in
            if !newValue { clearProfile() }
            else { saveProfile() }
        }
        .onChange(of: name) { _, _ in saveProfile() }
        .onChange(of: birthYear) { _, _ in saveProfile() }
        .onChange(of: birthMonth) { _, _ in saveProfile() }
    }

    private func loadProfile() {
        let descriptor = FetchDescriptor<LocalProfile>()
        if let existing = try? modelContext.fetch(descriptor).first {
            hasProfile = true
            name = existing.name ?? ""
            birthYear = existing.birthYear ?? Calendar.current.component(.year, from: Date()) - 6
            birthMonth = existing.birthMonth ?? 6
            session.profile = existing
        }
    }

    private func saveProfile() {
        guard hasProfile else { return }
        let descriptor = FetchDescriptor<LocalProfile>()
        let existing = try? modelContext.fetch(descriptor).first
        let profile = existing ?? LocalProfile()
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        profile.birthYear = birthYear
        profile.birthMonth = birthMonth
        if existing == nil {
            modelContext.insert(profile)
        }
        session.profile = profile
        try? modelContext.save()
    }

    private func clearProfile() {
        let descriptor = FetchDescriptor<LocalProfile>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = nil
            existing.birthYear = nil
            existing.birthMonth = nil
            try? modelContext.save()
        }
    }
}
