import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var serverURLText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "note.text")
                    .font(.system(size: 64))
                    .foregroundStyle(.accent)

                Text("Connect to Blinko")
                    .font(.title)
                    .bold()

                TextField("Server URL (e.g. https://blinko.example.com)", text: $serverURLText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Connect") {
                    guard let url = URL(string: serverURLText) else { return }
                    coordinator.configure(serverURL: url)
                    coordinator.isAuthenticated = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverURLText.isEmpty)
            }
            .padding()
            .navigationTitle("Blinko")
        }
    }
}
