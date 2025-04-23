//
//  ContentView.swift
//  gpt4.1_app
//
//  Created by Sagar Varma on 4/23/25.
//

import SwiftUI

struct ContentView: View {
    // State to track if the API key is set and valid (or just present)
    @State private var isApiKeySet: Bool = false
    // State for the input field, only used when setting the key initially
    @State private var apiKeyInput: String = ""

    // Use a single instance of StorageManager
    private let storageManager = StorageManager()

    var body: some View {
        // Use a Group to apply onAppear to the conditional content
        Group {
            if isApiKeySet {
                // Wrap ChatView in its own NavigationView
                NavigationView {
                    ChatView(storageManager: storageManager) {
                        storageManager.deleteApiKey()
                        isApiKeySet = false
                        apiKeyInput = ""
                    }
                }
                // Prevent multiple stacked NavigationViews if ChatView had its own
                .navigationViewStyle(.stack)
            } else {
                // API Key Setup View
                SetupView(apiKeyInput: $apiKeyInput) { enteredKey in
                    // This closure is called when the 'Continue' button is tapped in SetupView
                    storageManager.saveApiKey(enteredKey)
                    isApiKeySet = true
                }
            }
        }
        .onAppear { // Apply onAppear to the Group
            if let existingKey = storageManager.loadApiKey(), !existingKey.isEmpty {
                isApiKeySet = true
                print("Existing API key found.")
            } else {
                isApiKeySet = false
                print("No API key found, showing setup.")
            }
        }
    }
}

// Extracted Setup View Logic
struct SetupView: View {
    @Binding var apiKeyInput: String
    let onApiKeySet: (String) -> Void // Closure to call when key is submitted

    var body: some View {
        NavigationView { // Added NavigationView for title consistency if needed
            VStack {
                Text("Add Your Open AI API Key to Talk to GPT 4.1")
                    .font(.headline)
                    .padding(.bottom)
                    .multilineTextAlignment(.center)


                // Use SecureField for API keys
                SecureField("Enter API Key", text: $apiKeyInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                Button("Continue") {
                    let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedKey.isEmpty {
                        onApiKeySet(trimmedKey) // Call the closure with the entered key
                    } else {
                        print("API Key cannot be empty")
                        // Optionally show an alert
                    }
                }
                .padding(.top)
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("API Key Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
