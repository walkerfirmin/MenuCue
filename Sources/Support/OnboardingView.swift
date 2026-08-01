import SwiftUI
import AppKit

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var trusted = AccessibilityPermission.isTrusted
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable Accessibility")
                .font(.title2.bold())
            Text("MenuCue reads each app’s menu bar through macOS Accessibility so you can search and run commands from the keyboard. Grant access in System Settings, then return here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? "Accessibility is enabled" : "Waiting for permission…")
            }

            HStack {
                Button("Open System Settings…") {
                    AccessibilityPermission.promptIfNeeded()
                    AccessibilityPermission.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button(trusted ? "Continue" : "Quit") {
                    if trusted {
                        onDone()
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { startPolling() }
        .onDisappear { timer?.invalidate() }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let now = AccessibilityPermission.isTrusted
            if now != trusted {
                trusted = now
            }
        }
    }
}
