import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var serverURLText = ""
    @State private var tokenText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "note.text")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text("Connect to Blinko")
                    .font(.title)
                    .bold()

                TextField("Server URL (e.g. https://blinko.example.com)", text: $serverURLText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Personal access token", text: $tokenText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Connect") {
                    guard let url = URL(string: serverURLText) else { return }
                    coordinator.configure(serverURL: url)
                    Task { await coordinator.signIn(withToken: tokenText) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverURLText.isEmpty || tokenText.isEmpty)
            }
            .padding()
            .navigationTitle("Blinko")
        }
    }
}
