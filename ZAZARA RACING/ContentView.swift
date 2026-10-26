//
//  ContentView.swift
//  ZAZARA RACING
//
//  Created by Yufan Wang on 10/17/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gpsLinkManager: GPSLinkManager

    var body: some View {
        AppShellView(manager: gpsLinkManager)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(
            GPSLinkManager.preview(
                savedModules: ZZPreviewData.savedModules,
                bluetoothState: .poweredOn
            )
        )
        .environmentObject(AppSettings(language: .english))
        .preferredColorScheme(.light)
}
#endif
