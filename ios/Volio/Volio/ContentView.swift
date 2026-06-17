import SwiftUI

struct ContentView: View {
    @Environment(VolioSession.self) private var session

    var body: some View {
        Group {
            if session.isPaired {
                if session.children.isEmpty && session.isLoading {
                    ProgressView("Loading Volio Desktop...")
                } else if session.children.isEmpty {
                    OnboardingChildView()
                } else {
                    RootTabsView()
                }
            } else {
                PairingView()
            }
        }
        .task {
            if session.isPaired {
                await session.refresh()
            }
        }
        .onOpenURL { url in
            session.pair(with: url)
            Task { await session.refresh() }
        }
    }
}

struct RootTabsView: View {
    @Environment(VolioSession.self) private var session

    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera.fill")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "rectangle.grid.2x2")
                }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.red, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

struct OnboardingChildView: View {
    @Environment(VolioSession.self) private var session
    @State private var name = ""
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 6
    @State private var birthMonth = 6
    @State private var onlyYear = false
    @State private var isSaving = false

    private var birthDateValue: String {
        onlyYear ? String(birthYear) : String(format: "%04d-%02d", birthYear, birthMonth)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("Start with one child")
                            .font(.largeTitle.bold())
                        Text("Volio uses birth month to place old artwork into the right age on the timeline.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Nickname", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        Toggle("I only know the birth year", isOn: $onlyYear)

                        Picker("Birth year", selection: $birthYear) {
                            ForEach((2005...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 118)

                        if !onlyYear {
                            Picker("Birth month", selection: $birthMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 118)
                        }
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

                    Button {
                        Task { await save() }
                    } label: {
                        Label(isSaving ? "Creating..." : "Create Timeline", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
                .padding(22)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Volio")
            .toolbar {
                Button("Forget Mac") {
                    session.forgetPairing()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func save() async {
        guard let client = session.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let child = try await client.addChild(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                birthDate: birthDateValue
            )
            session.children = [child]
            session.selectedChildId = child.id
            await session.refresh()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environment(VolioSession())
}
