import SwiftUI

@MainActor
private final class NovaAccountForm: ObservableObject {
    @Published var email: String
    @Published var password = ""
    @Published var ownerCode = ""
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
    @State private var showsExistingAccountOptions = false

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
                    Text("Sign-in is optional · guests get 25 messages a day")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if store.hasSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.isGuest ? "GUEST PROFILE" : "SIGNED IN")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Text(store.isGuest ? "This device’s guest profile" : (store.email ?? "NOVA account"))
                        .font(.system(size: 13, weight: .medium))
                    Label(
                        store.isOwner ? "Owner profile · unlimited messages" : "25 messages per UTC day",
                        systemImage: store.isOwner ? "star.circle.fill" : "checkmark.seal.fill"
                    )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.77))
                    Text("Your daily allowance resets at 00:00 UTC.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                if !store.isOwner {
                    ownerCodeSection
                    if store.isGuest {
                        DisclosureGroup("Sign in to an existing account", isExpanded: $showsExistingAccountOptions) {
                            existingAccountSection
                                .padding(.top, 8)
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                }

                if let message = store.statusMessage {
                    Label(message, systemImage: store.isOwner ? "checkmark.seal.fill" : "info.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(store.isOwner ? Color.blue : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage = form.errorMessage {
                    Text(errorMessage).font(.system(size: 10)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    if !store.isGuest {
                        Button("Sign out", role: .destructive) {
                            Task { await store.signOut(); dismiss() }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use NOVA as a guest without creating an account. Your guest profile is created automatically when you chat.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ownerCodeSection
                    Divider()
                    existingAccountSection
                }

                if let errorMessage = form.errorMessage {
                    Text(errorMessage).font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
        .task { await store.refreshOwnerStatus() }
        .onChange(of: store.hasSession) { signedIn in
            if signedIn && !store.isGuest { dismiss() }
        }
        .onChange(of: store.isGuest) { isGuest in
            if store.hasSession && !isGuest { dismiss() }
        }
    }

    private var existingAccountSection: some View {
        VStack(alignment: .leading, spacing: 9) {
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

            Text("Sign in with Google or your existing email and password.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("Email address", text: $form.email)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            SecureField("Password", text: $form.password)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Sign in") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isWorking || store.isGoogleSignInInProgress || form.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.password.isEmpty)
            }
        }
    }

    private var ownerCodeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("OWNER PROFILE")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            SecureField("One-time owner access code", text: $form.ownerCode)
                .textFieldStyle(.roundedBorder)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
            Button {
                Task { await redeemOwnerCode() }
            } label: {
                Label("Activate owner profile", systemImage: "star.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isWorking || form.ownerCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    @MainActor
    private func redeemOwnerCode() async {
        form.errorMessage = nil
        do {
            try await store.redeemOwnerCode(form.ownerCode)
            form.ownerCode = ""
            await store.refreshOwnerStatus()
        } catch {
            form.errorMessage = error.localizedDescription
        }
    }
}
