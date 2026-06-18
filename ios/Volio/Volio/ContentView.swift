import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
    @State private var selectedTab: MainTab = .gallery
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                GalleryView()
                    .tag(MainTab.gallery)

                TimelineView()
                    .tag(MainTab.timeline)

                SearchView()
                    .tag(MainTab.search)
            }
            .tint(VolioTheme.accent)
            .toolbar(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !session.isShowingDetail {
                HStack(alignment: .center, spacing: 16) {
                    NativeTabCluster(selectedTab: $selectedTab)
                        .frame(width: 250, height: 68)
                    Spacer(minLength: 16)
                    FloatingCaptureButton {
                        showCamera = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .tint(VolioTheme.accent)
        .fullScreenCover(isPresented: $showCamera) {
            StackCameraView(
                onCapture: { data in
                    session.createWork(data: data, workType: "visual", createdAround: .capturedDate)
                },
                onImportPhotos: {
                    showCamera = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPhotoPicker = true
                    }
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

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var loadedJPEGs: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.86) {
                loadedJPEGs.append(jpeg)
            }
        }
        for jpeg in loadedJPEGs {
            session.createWork(data: jpeg, workType: "visual", createdAround: .capturedDate)
        }
        photoPickerItems.removeAll()
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
        case .capture: "camera.fill"
        }
    }
}

private struct NativeTabCluster: UIViewRepresentable {
    @Binding var selectedTab: MainTab
    private static let tabs: [MainTab] = [.gallery, .timeline, .search]

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedTab: $selectedTab)
    }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar()
        tabBar.delegate = context.coordinator
        tabBar.items = Self.tabs.enumerated().map { index, tab in
            UITabBarItem(title: tab.title, image: UIImage(systemName: tab.icon), tag: index)
        }
        tabBar.itemPositioning = .fill
        tabBar.tintColor = UIColor(red: 0.94, green: 0.33, blue: 0.20, alpha: 1)
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.clipsToBounds = true
        tabBar.layer.cornerRadius = 24
        tabBar.layer.cornerCurve = .continuous

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance.selected.iconColor = tabBar.tintColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: tabBar.tintColor as Any]
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        updateSelection(tabBar)
        return tabBar
    }

    func updateUIView(_ uiView: UITabBar, context: Context) {
        updateSelection(uiView)
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
}

private struct FloatingCaptureButton: View {
    var onCapture: () -> Void

    var body: some View {
        Button(action: onCapture) {
            Image(systemName: MainTab.capture.icon)
                .font(.system(size: 25, weight: .bold))
                .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .modifier(CaptureButtonChrome())
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

extension View {
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
