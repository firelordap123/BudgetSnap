//
//  BudgetSnapApp.swift
//  BudgetSnap
//
//  Created by Alex Parker on 4/30/26.
//

import SwiftUI

@main
struct BudgetSnapApp: App {
    @StateObject private var store = AppStore(
        repository: InMemoryBudgetRepository()
    )

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
        }
    }
}
