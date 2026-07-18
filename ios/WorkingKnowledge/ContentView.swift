//
//  ContentView.swift
//  WorkingKnowledge
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            DebugTopBar()
            TabView {
                SubjectsView()
                    .tabItem { Label("Palace", systemImage: "building.columns.fill") }

                AskView()
                    .tabItem { Label("Ask", systemImage: "sparkles") }

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }

                ToolsView()
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
            }
            .tint(Theme.cyan)
        }
    }
}
