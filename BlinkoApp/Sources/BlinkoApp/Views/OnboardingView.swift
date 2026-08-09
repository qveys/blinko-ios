import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var serverURLText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var tokenText = ""
    @State private var useToken = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var serverURL: URL? { URL(string: serverURLText) }
    private var canConnect: Bool {
        serverURL != nil && (useToken ? !tokenText.isEmpty : (!username.isEmpty && !password.isEmpty))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "note.text")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)

                    Text("Connect to Blinko")
                        .font(.title)
                        .bold()

                    GroupBox("Server") {
                        TextField("https://blinko.example.com", text: $serverURLText)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    GroupBox("Sign in") {
                        VStack(spacing: 12) {
                            Picker("Method", selection: $useToken) {
                                Text("Username & Password").tag(false)
                                Text("Access Token").tag(true)
                            }
                            .pickerStyle(.segmented)

                            if useToken {
                                SecureField("Personal access token", text: $tokenText)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                TextField("Username", text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.password)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        connect()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConnect || isLoading)
                }
                .padding()
            }
            .navigationTitle("Blinko")
        }
    }

    private func connect() {
        guard let url = serverURL else { return }
        isLoading = true
        errorMessage = nil
        coordinator.configure(serverURL: url)
        Task {
            do {
                if useToken {
                    await coordinator.signIn(withToken: tokenText)
                } else {
                    try await coordinator.signIn(name: username, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
