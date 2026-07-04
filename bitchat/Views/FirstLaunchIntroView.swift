//
// FirstLaunchIntroView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// One-time first-launch screen: says what bitchat is and primes the
/// Bluetooth permission before the OS prompt fires. The main app (and its
/// runtime, whose BLE setup triggers the system dialog) mounts only after
/// [ start ], so the prompt appears in context instead of over an
/// unexplained blank screen.
struct FirstLaunchIntroView: View {
    let onStart: () -> Void

    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            Text(verbatim: "bitchat/")
                .bitchatFont(size: 36, weight: .bold)
                .foregroundColor(palette.primary)

            VStack(alignment: .leading, spacing: 8) {
                taglineLine("first_launch.tagline_mesh")
                taglineLine("first_launch.tagline_infrastructure")
                taglineLine("first_launch.tagline_encryption")
            }

            Text("first_launch.bluetooth_note")
                .bitchatFont(size: 14)
                .foregroundColor(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onStart) {
                Text(verbatim: "[ \(String(localized: "first_launch.start", comment: "Label of the button that leaves the first-launch intro and starts the app")) ]")
                    .bitchatFont(size: 18, weight: .semibold)
                    .foregroundColor(palette.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.primary.opacity(0.6), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(ThemedRootBackground())
    }

    private func taglineLine(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .bitchatFont(size: 15)
            .foregroundColor(palette.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    FirstLaunchIntroView(onStart: {})
}
