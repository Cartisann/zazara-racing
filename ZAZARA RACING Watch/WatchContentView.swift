//
//  WatchContentView.swift
//  ZAZARA RACING Watch
//
//  Two vertical pages: connection (left/up) and live data (right/down).
//  The data page is selected by default.
//

import SwiftUI

enum WatchPage: Hashable {
    case status
    case data
}

struct WatchContentView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @State private var page: WatchPage = .status

    var body: some View {
        TabView(selection: $page) {
            NavigationStack {
                WatchStatusView()
            }
            .tag(WatchPage.status)

            NavigationStack {
                WatchDataView()
            }
            .tag(WatchPage.data)

        }
        .background(WatchTheme.canvas)
    }
}
