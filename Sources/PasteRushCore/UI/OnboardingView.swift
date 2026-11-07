import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var step = 0
    @State private var accessibilityOK = AccessibilityPermissionManager().isTrusted
    @State private var testResult: String?
    @State private var celebrating = false
    @State private var celebrateScale: CGFloat = 0.4
    @State private var celebrateOpacity: Double = 0
    var onFinished: () -> Void

    private let lastStep = 4

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("onboarding.welcome")).font(.largeTitle.bold())
                TabView(selection: $step) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("onboarding.step1_title")).font(.title2.bold())
                        Text(L10n.tr("onboarding.step1_body"))
                    }.tag(0)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("onboarding.step2_title")).font(.title2.bold())
                        Text(L10n.tr("onboarding.step2_body"))
                        Text(L10n.tr("onboarding.step2_current", GlobalHotkeyManager.displayString(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers)))
                            .font(.system(.body, design: .monospaced))
                    }.tag(1)

                    if Distribution.isAppStore {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("onboarding.step3_title_store")).font(.title2.bold())
                            Text(L10n.tr("onboarding.step3_body_store"))
                        }.tag(2)
                    } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("onboarding.step3_title")).font(.title2.bold())
                        Text(L10n.tr("onboarding.step3_body"))
                        HStack {
                            Button(L10n.tr("onboarding.open_accessibility")) {
                                AccessibilityPermissionManager().openSystemSettings()
                            }
                            Button(L10n.tr("onboarding.check_again")) {
                                accessibilityOK = AccessibilityPermissionManager().isTrusted
                            }
                            Button(L10n.tr("onboarding.run_paste_test")) {
                                testResult = PasteCoordinator.shared.runPasteTest()
                            }
                        }
                        Text(accessibilityOK ? L10n.tr("onboarding.accessibility_ok") : L10n.tr("onboarding.accessibility_missing"))
                            .foregroundStyle(accessibilityOK ? .green : .orange)
                        if let testResult {
                            Text(L10n.tr("onboarding.paste_test_hint", testResult))
                                .font(.caption)
                        }
                    }.tag(2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("onboarding.step4_title")).font(.title2.bold())
                        Toggle(L10n.tr("onboarding.launch_toggle"), isOn: $settings.launchAtLogin)
                            .onChange(of: settings.launchAtLogin) { _, value in
                                try? LaunchAtLoginService().setEnabled(value)
                            }
                        Text(Distribution.tr("onboarding.step4_hint"))
                            .foregroundStyle(.secondary)
                    }.tag(3)

                    shortcutsStep.tag(4)
                }
                .tabViewStyle(.automatic)
                .frame(height: 300)

                HStack {
                    if step > 0 {
                        Button(L10n.tr("onboarding.back")) { step -= 1 }
                            .disabled(celebrating)
                    }
                    Spacer()
                    if step < lastStep {
                        Button(L10n.tr("onboarding.next")) { step += 1 }
                            .keyboardShortcut(.defaultAction)
                            .disabled(celebrating)
                    } else {
                        Button(L10n.tr("onboarding.finish")) { finishWithFlourish() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(celebrating)
                    }
                }
            }
            .padding(24)
            .blur(radius: celebrating ? 6 : 0)
            .opacity(celebrating ? 0.35 : 1)

            if celebrating {
                celebrationOverlay
                    .transition(.opacity)
            }
        }
        .frame(width: 580, height: 480)
        .animation(.easeInOut(duration: 0.35), value: celebrating)
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("onboarding.step5_title")).font(.title2.bold())
            Text(L10n.tr("onboarding.open_label", GlobalHotkeyManager.displayString(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers)))
                .font(.system(.callout, design: .monospaced))

            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("↵", Distribution.tr("onboarding.sc_paste"))
                shortcutRow("⇧↵", L10n.tr("onboarding.sc_plain"))
                shortcutRow("⌘↵", L10n.tr("onboarding.sc_copy"))
                shortcutRow("⌥↵", L10n.tr("onboarding.sc_props"))
                shortcutRow("␣ / ⌥␣", L10n.tr("onboarding.sc_preview"))
                shortcutRow("↑↓←→", L10n.tr("onboarding.sc_nav"))
                shortcutRow("Esc", L10n.tr("onboarding.sc_esc"))
                shortcutRow("⌘P", L10n.tr("onboarding.sc_pin"))
                shortcutRow("⌘E", L10n.tr("onboarding.sc_edit"))
                shortcutRow("⌘G", L10n.tr("onboarding.sc_groups"))
                shortcutRow("⌘⌫", L10n.tr("onboarding.sc_delete"))
                shortcutRow("⌘,", L10n.tr("onboarding.sc_settings"))
            }
            .font(.caption)

            Text(L10n.tr("onboarding.config_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            BuyMeACoffeeButton()
                .padding(.top, 6)
            Text(Distribution.tr("onboarding.support"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 72, alignment: .leading)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var celebrationOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .scaleEffect(celebrateScale)
                .opacity(celebrateOpacity)
            Text(L10n.tr("onboarding.done"))
                .font(.title.bold())
                .opacity(celebrateOpacity)
            Text(L10n.tr("onboarding.ready"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(celebrateOpacity)
        }
    }

    private func finishWithFlourish() {
        guard !celebrating else { return }
        celebrating = true
        WelcomeSound.play()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            celebrateScale = 1
            celebrateOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            settings.hasCompletedOnboarding = true
            onFinished()
        }
    }
}
