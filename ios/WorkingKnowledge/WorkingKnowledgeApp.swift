//
//  WorkingKnowledgeApp.swift
//  WorkingKnowledge
//

import SwiftUI

@main
struct WorkingKnowledgeApp: App {
    @State private var store: PalaceStore
    @State private var models: ModelManager
    @State private var askEngine: AskEngine
    @State private var reporter: DebugReporter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = PalaceStore()
        let models = ModelManager(store: store)
        let reporter = DebugReporter()
        _store = State(initialValue: store)
        _models = State(initialValue: models)
        _askEngine = State(initialValue: AskEngine(store: store, models: models))
        _reporter = State(initialValue: reporter)
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(store)
                .environment(models)
                .environment(askEngine)
                .environment(reporter)
                .onAppear {
                    store.ingestSharedInbox()
                    models.autoloadDownloaded()
                    // Start the remote debug sink — heartbeat telemetry +
                    // previous-launch crash-log scan. No-op if Supabase env
                    // vars aren't injected.
                    let telemetry = DebugTelemetry()
                    models.attachReporter(reporter)
                    reporter.start(telemetry: telemetry, models: models)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.ingestSharedInbox()
                        reporter.report(
                            kind: "lifecycle",
                            severity: .info,
                            source: "app",
                            message: "becameActive"
                        )
                    } else if newPhase == .background {
                        reporter.report(
                            kind: "lifecycle",
                            severity: .info,
                            source: "app",
                            message: "enteredBackground"
                        )
                    }
                }
        }
    }

    /// Applies the Crystal Lattice palette to UIKit-backed navigation and tab bars.
    private static func configureAppearance() {
        let bg = UIColor(Theme.bg)
        let ice = UIColor(Theme.ice)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = bg
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.foregroundColor: ice]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: ice]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.surface)
        tabAppearance.shadowColor = UIColor(Theme.border)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
