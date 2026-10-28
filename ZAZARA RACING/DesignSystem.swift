//
//  DesignSystem.swift
//  ZAZARA RACING
//
//  Black and graphite visual language with ZAZARA red accents.
//

import SwiftUI
import CoreBluetooth

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Palette

extension Color {
    init(zzHex hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static let zzCanvas = Color(zzHex: 0x08080A)
    static let zzSurface = Color(zzHex: 0x16161A)
    static let zzMutedSurface = Color(zzHex: 0x222228)
    static let zzInk = Color(zzHex: 0xF2F2F5)
    static let zzSecondary = Color(zzHex: 0xA2A2AC)
    static let zzTertiary = Color(zzHex: 0x73737D)
    static let zzLine = Color(zzHex: 0x2D2D34)
    static let zzRed = Color(zzHex: 0xFF3B45)
    static let zzRedSoft = Color(zzHex: 0x3A181D)
    static let zzGreen = Color(zzHex: 0x35D07F)
    static let zzGreenSoft = Color(zzHex: 0x102B1E)
    static let zzAmber = Color(zzHex: 0xF0B44A)
    static let zzAmberSoft = Color(zzHex: 0x30250F)
}

// MARK: - Type

extension Font {
    static func zzMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Platform helpers

enum ZZPlatform {
    static func openBluetoothSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Compat

extension View {
    @ViewBuilder
    func zzOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
        #else
        onChange(of: value, perform: action)
        #endif
    }

    @ViewBuilder
    func zzScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

// MARK: - Brand

struct ZZWordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 2) {
                Rectangle()
                    .fill(Color.zzRed.opacity(0.35))
                    .frame(width: 2.5, height: 7)
                Rectangle()
                    .fill(Color.zzRed.opacity(0.6))
                    .frame(width: 2.5, height: 11)
                Rectangle()
                    .fill(Color.zzRed)
                    .frame(width: 2.5, height: 15)
            }
            .rotationEffect(.degrees(-17))
            .frame(width: 14, height: 18)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("ZAZARA")
                    .font(.system(size: 15, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(Color.zzInk)

                Text("RACING")
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.zzRed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ZAZARA Racing")
    }
}

struct ZZStatusPill: View {
    let text: String
    var color: Color = .zzGreen

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.zzMutedSurface))
    }
}

// MARK: - Header

struct ZZScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let statusText: String
    let statusColor: Color
    private let trailingContent: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        statusText: String,
        statusColor: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusColor = statusColor
        self.trailingContent = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZZWordmark()
                Spacer(minLength: 8)
                ZZStatusPill(text: statusText, color: statusColor)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(Color.zzInk)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.zzSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
                trailingContent
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 980)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 15)
        .background(Color.zzSurface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)
        }
    }
}

extension ZZScreenHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        statusText: String,
        statusColor: Color
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            statusText: statusText,
            statusColor: statusColor
        ) {
            EmptyView()
        }
    }
}

// MARK: - Section header

struct ZZSectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.zzInk)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Card

private struct ZZCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var muted: Bool
    var squareTrailing: Bool = false

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: squareTrailing ? 0 : cornerRadius,
            topTrailingRadius: squareTrailing ? 0 : cornerRadius,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background(
                (muted ? Color.zzMutedSurface : Color.zzSurface),
                in: cardShape
            )
            .overlay(
                cardShape
                    .stroke(Color.zzLine.opacity(muted ? 0.5 : 0.9), lineWidth: 0.8)
            )
            .shadow(
                color: Color.black.opacity(muted ? 0 : 0.28),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func zzCard(
        cornerRadius: CGFloat = 18,
        muted: Bool = false,
        squareTrailing: Bool = false
    ) -> some View {
        modifier(
            ZZCardModifier(
                cornerRadius: cornerRadius,
                muted: muted,
                squareTrailing: squareTrailing
            )
        )
    }
}

// MARK: - Button styles

struct ZZPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Capsule().fill(Color.zzRed))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ZZSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.zzInk)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Capsule().fill(Color.zzMutedSurface))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ZZCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Signal

struct ZZSignalBars: View {
    let level: Int
    var tint: Color = .zzInk
    var inactive: Color = Color.zzLine
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(index < level ? tint : inactive)
                    .frame(width: 3, height: 4 + CGFloat(index) * 3)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.t("Signal strength %d of 4", level))
    }
}

struct ZZPulseDot: View {
    var color: Color = .zzGreen
    var size: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1)
                    .frame(width: size * 1.9, height: size * 1.9)
            } else {
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 1)
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(expanded ? 1 : 0.25)
                    .opacity(expanded ? 0 : 0.8)
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.8, height: size * 2.8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct ZZAnimatedDots: View {
    var color: Color = .zzRed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .opacity(active ? 1 : (reduceMotion ? 1 : 0.2))
                    .animation(
                        reduceMotion
                            ? .easeInOut(duration: 0.01)
                            : .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                        value: active
                    )
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            active = true
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Module glyph

struct ZZModuleGlyph: View {
    var active = false
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? Color.zzRedSoft : Color.zzMutedSurface)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.31, weight: .semibold))
                .foregroundStyle(active ? Color.zzRed : Color.zzInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Radar

struct ZZScanRadar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.zzRedSoft)
                .frame(width: 46, height: 46)

            if !reduceMotion {
                ZZRadarRing(delay: 0)
                ZZRadarRing(delay: 0.85)
            } else {
                Circle()
                    .stroke(Color.zzInk.opacity(0.3), lineWidth: 1)
                    .frame(width: 46, height: 46)
            }

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.zzInk)
                .rotationEffect(.degrees(spinning ? 8 : -8))
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: spinning)
        }
        .frame(width: 46, height: 46)
        .onAppear {
            guard !reduceMotion else { return }
            spinning = true
        }
        .accessibilityHidden(true)
    }
}

private struct ZZRadarRing: View {
    let delay: Double
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(Color.zzInk.opacity(0.4), lineWidth: 1)
            .frame(width: 40, height: 40)
            .scaleEffect(animate ? 1.35 : 0.6)
            .opacity(animate ? 0 : 0.5)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(delay)) {
                    animate = true
                }
            }
    }
}

// MARK: - Notice

enum ZZNoticeTone {
    case warning
    case error
    case info

    var tint: Color {
        switch self {
        case .warning: return .zzAmber
        case .error: return .zzRed
        case .info: return .zzSecondary
        }
    }

    var soft: Color {
        switch self {
        case .warning: return .zzAmberSoft
        case .error: return .zzRedSoft
        case .info: return .zzMutedSurface
        }
    }
}

struct ZZNoticeCard: View {
    let tone: ZZNoticeTone
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tone.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tone.soft))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.tint)

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(actionTitle)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(tone.tint)
                        .padding(.top, 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.zzTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(13)
        .zzCard(cornerRadius: 14)
    }
}

// MARK: - Connecting overlay

struct ZZConnectingOverlay: View {
    let name: String
    let onCancel: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Color.zzLine, lineWidth: 1)
                        .frame(width: 94, height: 94)

                    Circle()
                        .trim(from: 0, to: 0.2)
                        .stroke(
                            Color.zzRed,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 94, height: 94)
                        .rotationEffect(.degrees(rotating ? 360 : 0))

                    ZZModuleGlyph(active: true, size: 48)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                        rotating = true
                    }
                }

                VStack(spacing: 6) {
                    Text(settings.t("Connecting"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.zzInk)

                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.zzSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(settings.t("Keep the module close to your phone."))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.zzTertiary)
                        .padding(.top, 2)
                }

                Button(action: onCancel) {
                    Text(settings.t("Cancel"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.zzSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .frame(maxWidth: 320)
            .zzCard(cornerRadius: 24)
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - Status

extension GPSLinkManager {
    func zzStatus(language: AppLanguage) -> (text: String, color: Color) {
        AppSettings.localizedStatus(for: self, language: language)
    }
}

// MARK: - Track shape

struct ZZTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        // Closed Catmull-Rom spline. Every segment is a cubic curve with
        // matching tangents at its neighbours, so the outline has no sharp
        // corners or cusps at any scale.
        // Simplified Monza silhouette: long left straight, Curva Grande,
        // Lesmo, the inner Serraglio/Ascari return and Parabolica.
        let points = [
            point(0.18, 0.78),
            point(0.22, 0.55),
            point(0.28, 0.35),
            point(0.30, 0.25),
            point(0.43, 0.12),
            point(0.62, 0.12),
            point(0.80, 0.18),
            point(0.88, 0.28),
            point(0.85, 0.42),
            point(0.70, 0.48),
            point(0.50, 0.58),
            point(0.44, 0.66),
            point(0.34, 0.82)
        ]

        var path = Path()
        path.move(to: points[0])

        for index in 0..<points.count {
            let p0 = points[(index - 1 + points.count) % points.count]
            let p1 = points[index]
            let p2 = points[(index + 1) % points.count]
            let p3 = points[(index + 2) % points.count]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        path.closeSubpath()
        return path
    }
}
