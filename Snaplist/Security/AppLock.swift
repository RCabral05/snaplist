import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Face ID (or Touch ID, or the iPhone passcode as a fallback) in front of the
/// archive. Locked at launch and after more than `gracePeriod` in the
/// background, so answering a text and coming straight back doesn't ask again.
///
/// This gates the screens. The files underneath are separately protected by
/// iOS Data Protection, which keeps them encrypted while the phone is locked.
@MainActor @Observable
final class AppLock {
    static let gracePeriod: TimeInterval = 30
    private static let enabledKey = "appLockEnabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var errorMessage: String?

    private var backgroundedAt: Date?

    init() {
        // On by default wherever the phone has a passcode to check against.
        var enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? Self.isAvailable
        #if DEBUG
        if DemoData.isEnabled { enabled = false }
        #endif
        isEnabled = enabled
        isLocked = enabled && Self.isAvailable
    }

    /// False when the iPhone has no passcode: there is nothing to verify, and
    /// locking anyway would lock the owner out.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode".
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func sceneChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = .now }
        case .active:
            if let backgroundedAt, isEnabled, Date.now.timeIntervalSince(backgroundedAt) > Self.gracePeriod {
                isLocked = true
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        guard Self.isAvailable else {
            // The passcode was removed since the lock was turned on.
            isLocked = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            _ = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                                                     localizedReason: "Unlock your Snaplist archive")
            isLocked = false
            errorMessage = nil
        } catch let error as LAError where Self.quietCodes.contains(error.code) {
            // Cancelled, or asked before the app was on screen: the Unlock
            // button is there, and prompting again on our own would loop.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turning the lock on is free; turning it off asks first, so a borrowed
    /// unlocked phone can't quietly switch it off.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        if !enabled {
            do {
                _ = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                                                         localizedReason: "Turn off the lock for Snaplist")
            } catch {
                return
            }
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    private static let quietCodes: Set<LAError.Code> = [.userCancel, .systemCancel, .appCancel, .notInteractive]
}

/// What shows instead of the archive while it is locked.
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: .circle)
            Text("Snaplist is locked")
                .font(Theme.display(.title, weight: .bold))
            Text("Your archive stays private until you unlock it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(AppLock.methodName)", systemImage: AppLock.methodName == "Face ID" ? "faceid" : "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)

            if let message = lock.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task { await lock.unlock() }
    }
}

/// Covers the screen whenever the app isn't frontmost, so the app switcher's
/// snapshot shows this rather than a receipt.
struct PrivacyCover: View {
    var body: some View {
        Rectangle()
            .fill(Color(.systemGroupedBackground))
            .overlay {
                Text("Snaplist")
                    .font(Theme.display(.largeTitle, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .ignoresSafeArea()
    }
}
