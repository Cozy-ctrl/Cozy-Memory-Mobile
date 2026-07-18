//
//  ContentView.swift
//  WorkingKnowledge
//

import SwiftUI

struct ContentView: View {
    var body: some View {
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
