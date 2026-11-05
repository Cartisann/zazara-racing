//
//  WatchContentView.swift
//  ZAZARA RACING Watch
//
//  Two vertical pages: connection (left/up) and live data (right/down).
//  The data page is selected by default.
//

import SwiftUI

enum WatchPage: Hashable {
    case timing
    case connection
    case data
}

struct WatchContentView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @State private var page: WatchPage = .timing

    var body: some View {
        TabView(selection: $page) {
            NavigationStack {
                WatchTimingView()
            }
            .tag(WatchPage.timing)

            NavigationStack {
                WatchConnectionView()
            }
            .tag(WatchPage.connection)

            NavigationStack {
                WatchDataView()
            }
            .tag(WatchPage.data)
        }
        .background(WatchTheme.canvas)
    }
}
