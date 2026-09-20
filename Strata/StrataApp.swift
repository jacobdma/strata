//
//  StrataApp.swift
//  Strata
//
//  Created by Jacob Ma on 9/19/26.
//

import SwiftUI

@main
struct StrataApp: App {
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
