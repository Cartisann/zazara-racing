//
//  DesignSystem.swift
//  ZAZARA RACING
//
//  Light, iOS-native visual language with ZAZARA red accents.
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

    static let zzCanvas = Color(zzHex: 0xF4F4F6)
    static let zzSurface = Color.white
    static let zzMutedSurface = Color(zzHex: 0xEDEDF0)
    static let zzInk = Color(zzHex: 0x141416)
    static let zzSecondary = Color(zzHex: 0x77777F)
    static let zzTertiary = Color(zzHex: 0xA5A5AD)
    static let zzLine = Color(zzHex: 0xE4E4E8)
    static let zzRed = Color(zzHex: 0xE21E2B)
    static let zzRedSoft = Color(zzHex: 0xFBEAEC)
    static let zzGreen = Color(zzHex: 0x1E9D55)
    static let zzGreenSoft = Color(zzHex: 0xE9F6EF)
    static let zzAmber = Color(zzHex: 0xC98200)
    static let zzAmberSoft = Color(zzHex: 0xFFF4E1)
}

// MARK: - Type

extension Font {
    static func zzMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Device metrics

enum ZZDeviceMetrics {
    static var screenSize: CGSize {
        #if os(iOS)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return scene.screen.bounds.size
        }
        return UIScreen.main.bounds.size
        #else
        return .zero
        #endif
    }

    /// iPhone Duo outer display: 466 x 678 points (either orientation).
    static var isDuoOuterDisplay: Bool {
        #if os(iOS)
        let size = screenSize
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        return shortSide >= 420
            && shortSide <= 500
            && longSide >= 620
            && longSide <= 760
        #else
        return false
        #endif
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

    func body(content: Content) -> some View {
        content
            .background(
                (muted ? Color.zzMutedSurface : Color.zzSurface),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.zzLine.opacity(muted ? 0.5 : 0.9), lineWidth: 0.8)
            )
            .shadow(
                color: Color.black.opacity(muted ? 0 : 0.035),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func zzCard(cornerRadius: CGFloat = 18, muted: Bool = false) -> some View {
        modifier(ZZCardModifier(cornerRadius: cornerRadius, muted: muted))
    }
}

// MARK: - Liquid Glass

struct ZZLiquidGlassBackground: View {
    var cornerRadius: CGFloat = 30
    var tint: Color = .white

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.055)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.16),
                            Color.zzRed.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
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
                    .stroke(Color.zzRed.opacity(0.25), lineWidth: 1)
                    .frame(width: 46, height: 46)
            }

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.zzRed)
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
            .stroke(Color.zzRed.opacity(0.4), lineWidth: 1)
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
            Color.black.opacity(0.22)
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

        var path = Path()
        path.move(to: point(0.06, 0.68))
        path.addCurve(
            to: point(0.23, 0.32),
            control1: point(0.07, 0.5),
            control2: point(0.12, 0.35)
        )
        path.addCurve(
            to: point(0.48, 0.28),
            control1: point(0.32, 0.29),
            control2: point(0.38, 0.26)
        )
        path.addCurve(
            to: point(0.68, 0.18),
            control1: point(0.56, 0.3),
            control2: point(0.6, 0.18)
        )
        path.addCurve(
            to: point(0.9, 0.32),
            control1: point(0.78, 0.18),
            control2: point(0.88, 0.24)
        )
        path.addCurve(
            to: point(0.84, 0.58),
            control1: point(0.92, 0.41),
            control2: point(0.91, 0.5)
        )
        path.addCurve(
            to: point(0.65, 0.64),
            control1: point(0.77, 0.66),
            control2: point(0.72, 0.61)
        )
        path.addCurve(
            to: point(0.5, 0.8),
            control1: point(0.58, 0.66),
            control2: point(0.56, 0.76)
        )
        path.addCurve(
            to: point(0.3, 0.78),
            control1: point(0.44, 0.84),
            control2: point(0.37, 0.82)
        )
        path.addCurve(
            to: point(0.06, 0.68),
            control1: point(0.2, 0.74),
            control2: point(0.12, 0.72)
        )
        path.closeSubpath()
        return path
    }
}
