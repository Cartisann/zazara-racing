//
//  LinkedView.swift
//  ZAZARA RACING
//
//  Connection confirmation, in the light ZAZARA style.
//

import SwiftUI

struct LinkedView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var moduleName: String {
        manager.connectedModule?.name ?? "GPS Module"
    }

    var body: some View {
        ZStack {
            Color.zzCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 18) {
                        successHeader
                        deviceCard
                        holdTheSignalCard
                        actions
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(Color.zzCanvas)
            }
        }
        .background(Color.zzCanvas)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .zzOnChange(of: manager.linkState) { state in
            if state != .connected {
                dismiss()
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            ZZWordmark()
            Spacer(minLength: 8)
            ZZStatusPill(text: settings.t("Connected"), color: .zzGreen)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.zzSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.zzMutedSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Back to devices"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(Color.zzSurface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)
        }
    }

    // MARK: - Header

    private var successHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.zzRedSoft)
                    .frame(width: 92, height: 92)

                Circle()
                    .stroke(Color.zzRed.opacity(0.14), lineWidth: 1)
                    .frame(width: 106, height: 106)

                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.zzRed)
            }

            VStack(spacing: 6) {
                (
                    Text(settings.t("Signal locked"))
                        .foregroundColor(Color.zzInk)
                    + Text(".")
                        .foregroundColor(Color.zzRed)
                )
                .font(.system(size: 31, weight: .bold))
                .accessibilityLabel(settings.t("Signal locked"))

                Text(settings.t("%@ is connected and ready.", moduleName))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var deviceCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZZModuleGlyph(active: true, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(moduleName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.zzGreen)
                            .frame(width: 6, height: 6)

                        Text(settings.t("Connected"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.zzGreen)
                    }
                }

                Spacer(minLength: 8)
                ZZSignalBars(level: manager.connectedSignalLevel, tint: .zzGreen)
            }
            .padding(16)

            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)

            HStack(spacing: 0) {
                metric(
                    title: settings.t("Signal"),
                    value: settings.signalLabel(level: manager.connectedSignalLevel).uppercased(),
                    footnote: rssiText
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                verticalDivider

                metric(
                    title: settings.t("Battery"),
                    value: manager.batteryLevel.map { "\($0)%" } ?? "—",
                    footnote: settings.t("Percent")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

                verticalDivider

                metric(
                    title: settings.t("Link"),
                    value: "BLE",
                    footnote: settings.t("Active")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let module = manager.connectedModule {
                Rectangle()
                    .fill(Color.zzLine)
                    .frame(height: 0.5)

                HStack {
                    Text(settings.linkedText(module.lastLinkedAt))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Color.zzTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(settings.t("LIVE"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.zzGreen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        .zzCard(cornerRadius: 20)
    }

    private func metric(title: String, value: String, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.zzTertiary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(footnote)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.zzLine)
            .frame(width: 0.5, height: 42)
    }

    private var holdTheSignalCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.zzRed)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.zzRedSoft))

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("Hold the signal"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.zzInk)

                Text(settings.t("Keep the receiver powered and within 3 m. Link health refreshes every few seconds."))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
        }
        .padding(14)
        .zzCard(cornerRadius: 16)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Text(settings.t("Back to Devices"))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(ZZPrimaryButtonStyle())
            .accessibilityHint(settings.t("Returns to the devices list and keeps the link active"))

            Button {
                manager.disconnect()
                dismiss()
            } label: {
                Text(settings.t("Disconnect"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.zzRedSoft))
            }
            .buttonStyle(.plain)
            .accessibilityHint(settings.t("Disconnects the GPS module"))
        }
        .padding(.top, 4)
    }

    private var rssiText: String {
        guard let rssi = manager.connectedRSSI else { return "— dBm" }
        return "\(rssi) dBm"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Signal locked") {
    LinkedView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            bluetoothState: .poweredOn,
            connectedModule: ZZPreviewData.connectedModule,
            connectedRSSI: -58,
            batteryLevel: 87
        )
    )
    .environmentObject(AppSettings(language: .english))
}

#Preview("Signal locked — no battery service") {
    LinkedView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            bluetoothState: .poweredOn,
            connectedModule: ZZPreviewData.savedModules[1],
            connectedRSSI: -81
        )
    )
    .environmentObject(AppSettings(language: .english))
}
#endif
