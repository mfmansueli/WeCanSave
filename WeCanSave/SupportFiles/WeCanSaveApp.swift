//
//  WeCanSaveApp.swift
//  WeCanSave
//
//  Created by Mateus Mansuelli on 24/02/25.
//

import SwiftUI
import SwiftData

@main
struct WeCanSaveApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TripsListView()
//                .environment(\.modelContext, sharedModelContainer.mainContext)
//                .environmentObject(UserManager(modelContext: sharedModelContainer.mainContext))
        }
        .modelContainer(sharedModelContainer)
    }
}
