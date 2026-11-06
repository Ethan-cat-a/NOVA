import SwiftUI

@MainActor
private final class NovaAccountForm: ObservableObject {
    @Published var email: String
    @Published var password = ""
    @Published var errorMessage: String?

    init(email: String) {
        self.email = email
    }
}

@MainActor
struct NovaAccountView: View {
    @ObservedObject var store: NovaAccountStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form: NovaAccountForm

    init(store: NovaAccountStore) {
        self.store = store
        _form = StateObject(wrappedValue: NovaAccountForm(email: store.email ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: store.hasSession ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.77))
                VStack(alignment: .leading, spacing: 3) {
                    Text("NOVA Account").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Sign in to use NOVA Copilot").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let signedInEmail = store.email {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SIGNED IN").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Text(signedInEmail).font(.system(size: 13, weight: .medium))
                    Label("Verified account · usage limits enforced by NOVA", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.77))
                    Text("Your daily allowance resets at 00:00 UTC.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Sign out", role: .destructive) {
                        Task { await store.signOut(); dismiss() }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        form.errorMessage = nil
                        do {
                            try store.beginGoogleSignIn()
                        } catch {
                            form.errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Continue with Google", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isWorking || store.isGoogleSignInInProgress)

                    Text("Sign in with the Google account linked to your existing NOVA account.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()

                    TextField("Email address", text: $form.email)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $form.password)
                        .textFieldStyle(.roundedBorder)

                    Text("Email and password are for signing in to an existing account.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                if let message = store.statusMessage {
                    Label(message, systemImage: "envelope.badge")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage = form.errorMessage {
                    Text(errorMessage).font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Sign in") {
                        Task { await submit() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isWorking || store.isGoogleSignInInProgress || form.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.password.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
        .onChange(of: store.hasSession) { signedIn in
            if signedIn { dismiss() }
        }
    }

    @MainActor
    private func submit() async {
        form.errorMessage = nil
        do {
            try await store.signIn(email: form.email, password: form.password)
            dismiss()
        } catch {
            form.errorMessage = error.localizedDescription
        }
    }
}
