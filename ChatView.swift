import SwiftUI
import PhotosUI // Import PhotosUI

// Define a struct to represent a chat message
struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let text: String
    let isFromUser: Bool
    let timestamp: Date
}

// Define a struct for a chat session
struct ChatSession: Identifiable, Codable {
    var id = UUID()
    var messages: [ChatMessage]
    var lastModified: Date {
        messages.last?.timestamp ?? Date.distantPast
    }
    var previewText: String {
        messages.first?.text ?? "New Chat"
    }
}

struct ChatView: View {
    @State private var messageText: String = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var currentSessionId: UUID?
    @State private var showHistory = false
    @State private var showingAttachmentOptions = false
    
    // State for image picking
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var showingCameraPicker = false // Separate state for camera sheet
    @State private var isLoading = false // State for loading indicator

    let storageManager: StorageManager
    let onChangeApiKeyRequested: () -> Void
    private let openAIService = OpenAIService() // Add service instance

    // Add initializer
    init(storageManager: StorageManager, onChangeApiKeyRequested: @escaping () -> Void) {
        self.storageManager = storageManager
        self.onChangeApiKeyRequested = onChangeApiKeyRequested
        // Initialize state based on latest session *here* instead of onAppear?
        // Or keep using onAppear. Let's stick with onAppear for now.
    }

    var body: some View {
        VStack {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(chatMessages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                         // Optional: Show typing indicator when loading
                         if isLoading {
                             HStack {
                                 ProgressView() // Simple loading spinner
                                     .padding(.leading)
                                 Text("GPT is thinking...")
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                                 Spacer()
                             }
                             .padding(.horizontal)
                         }
                    }
                    .padding(.horizontal)
                    .onChange(of: chatMessages.count) { _, _ in
                        scrollToBottom(proxy: scrollViewProxy)
                    }
                }
                .onTapGesture { hideKeyboard() }
            }

            // --- Image Preview Area --- 
            if let image = selectedImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation { selectedImage = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .background(Color.white.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(4)
                        }
                    Spacer() // Push preview to left
                }
                .padding(.horizontal)
                .transition(.scale.combined(with: .opacity)) // Add animation
            }
            // --- End Image Preview Area --- 

            // Input area
            HStack(spacing: 10) {
                 Button(action: {
                     hideKeyboard() // Dismiss keyboard before showing options
                     showingAttachmentOptions = true
                 }) {
                     Image(systemName: "plus.circle.fill")
                         .resizable()
                         .frame(width: 30, height: 30)
                 }
                 .disabled(isLoading) // Disable while loading

                // Rounded TextField
                 HStack {
                    TextField("Type your message...", text: $messageText, onCommit: { sendMessage() })
                         .padding(.horizontal, 10)
                         .padding(.vertical, 8)
                 }
                 .background(Color(.systemGray6))
                 .clipShape(Capsule())

                // Send button
                 Button(action: { sendMessage() }) {
                     Image(systemName: "paperplane.fill")
                         .resizable()
                         .frame(width: 20, height: 20)
                         .padding(8)
                 }
                 .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil || isLoading)
             }
             .padding(.horizontal)
             .padding(.vertical, 8)
             .opacity(isLoading ? 0.5 : 1.0) // Dim input while loading
        }
        .contentShape(Rectangle()) // Ensure the VStack receives gestures in empty areas
        .gesture(
            DragGesture()
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = value.translation.height
                    // startX is no longer needed for this logic
                    // let startX = value.startLocation.x 
                    
                    // Define thresholds
                    // edgeThreshold is no longer needed
                    let distanceThreshold: CGFloat = 100.0 // How far left drag must go
                    let maxVerticalDrag: CGFloat = 50.0 // Limit vertical movement

                    // Check conditions: Swipe LEFT anywhere
                    if horizontalAmount < -distanceThreshold && // Check for swipe left
                       abs(verticalAmount) < maxVerticalDrag {
                        print("Swipe left gesture detected, opening history.")
                        withAnimation { 
                            showHistory = true
                        }
                    }
                }
        )
        .navigationTitle("GPT 4.1")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { // Add toolbar items
             ToolbarItem(placement: .navigationBarLeading) { // Hamburger Button
                 Button {
                     showHistory = true
                 } label: {
                     Image(systemName: "line.3.horizontal")
                 }
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Button(action: startNewChat) {
                     Image(systemName: "plus") // New chat icon
                 }
             }
         }
         .sheet(isPresented: $showHistory) { // Present History View
             // Explicitly label both closure parameters
             HistoryView(storageManager: storageManager, 
                         onChangeApiKeyRequested: onChangeApiKeyRequested, 
                         onSessionSelected: { selectedSessionId in
                 loadSession(sessionId: selectedSessionId)
                 showHistory = false // Dismiss sheet after selection
             })
         }
         .sheet(isPresented: $showingCameraPicker) { // Sheet for Camera
             ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                 .ignoresSafeArea() // Allow camera full screen
         }
         .photosPicker( // Modifier for Photo Library selection
             isPresented: .constant(selectedPhotoItem != nil), // Use constant binding derived from item state
             selection: $selectedPhotoItem,
             matching: .images // Only allow images
         )
         .onChange(of: selectedPhotoItem) { _, newItem in // Handle selection from PhotosPicker
             Task { @MainActor in // Use Task for async loading
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImage = UIImage(data: data)
                    selectedPhotoItem = nil // Clear the item state after loading
                } else {
                    print("Failed to load image data")
                    selectedPhotoItem = nil // Clear item state even on failure
                }
             }
         }
         .confirmationDialog("Attach Content", isPresented: $showingAttachmentOptions, titleVisibility: .visible) {
             Button {
                 // Trigger Photos Picker by setting the item state (indirectly via binding)
                 // We need a way to signal the .photosPicker modifier. 
                 // A simple trick is to just set the item state variable, but PhotoPicker 
                 // requires a binding for isPresented. Let's slightly change the .photosPicker binding.
                 // Reverted: Setting selectedPhotoItem *will* trigger the picker IF the binding is set up correctly.
                 // Let's try setting the state that controls the binding
                 selectedPhotoItem = PhotosPickerItem(itemIdentifier: "placeholder") // Set dummy item to trigger picker
             } label: {
                 Label("Photos", systemImage: "photo.on.rectangle")
             }

             Button {
                 // Check if camera is available before presenting
                 if UIImagePickerController.isSourceTypeAvailable(.camera) {
                     showingCameraPicker = true
                 } else {
                     print("Camera not available")
                     // Optionally show an alert to the user
                 }
             } label: {
                 Label("Camera", systemImage: "camera")
             }
         } message: {
             Text("Select source")
         }
         .onAppear(perform: startNewChat) // Always start a new chat when the view appears
    }

    // Main function to trigger sending
    func sendMessage() {
        let textToSend = messageText // Capture text
        // Prevent sending empty messages unless an image is attached
        guard !textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil else { return }
        
        // Dismiss keyboard
        hideKeyboard()
        
        // Start async task
        Task {
            await appendAndSend(text: textToSend)
        }
    }

    // Async function to handle message sending and API call
    @MainActor // Ensure UI updates happen on the main thread
    func appendAndSend(text: String) async {
        let imageToSend = selectedImage
        if imageToSend != nil {
             withAnimation { selectedImage = nil }
        }
        messageText = "" 

        let userMessage = ChatMessage(text: text, isFromUser: true, timestamp: Date())
        // Create a temporary history including the new user message BEFORE the API call
        var currentChatHistory = chatMessages
        currentChatHistory.append(userMessage)
        
        // Update the main messages list for UI immediately
        chatMessages = currentChatHistory
        
        isLoading = true
        defer { isLoading = false }

        guard let apiKey = storageManager.loadApiKey(), !apiKey.isEmpty else {
            appendErrorMessage("API Key not found. Please set it in History -> Change API Key.")
            return
        }
        
        do {
            print("Calling API. History length: \(currentChatHistory.count), Image present: \(imageToSend != nil)")
            // Pass the temporary history and the image to the service
            let responseText = try await openAIService.generateResponse(currentHistory: currentChatHistory, 
                                                                  apiKey: apiKey, 
                                                                  newImage: imageToSend)
            appendModelMessage(responseText)
        } catch {
            print("API Error: \(error.localizedDescription)")
            appendErrorMessage("Error: \(error.localizedDescription)")
        }
    }
    
    // Helper to append model message and save
    @MainActor
    private func appendModelMessage(_ content: String) {
         let modelMessage = ChatMessage(text: content, isFromUser: false, timestamp: Date())
         // Append the new message to the existing chatMessages state
         chatMessages.append(modelMessage) 
         saveCurrentSession() // Save session including the model response
    }
    
    // Helper to append error message and save
    @MainActor
    private func appendErrorMessage(_ message: String) {
        let errorMessage = ChatMessage(text: message, isFromUser: false, timestamp: Date())
        // Append the error message to the existing chatMessages state
        chatMessages.append(errorMessage)
        saveCurrentSession() // Save session including the error message
    }

    func startNewChat() {
        currentSessionId = UUID() // Assign a new ID for the new chat
        chatMessages.removeAll()
        print("Started new chat with ID: \(currentSessionId!)")
        // Session is saved when the first message is sent.
    }

    func saveCurrentSession() {
        guard let sessionId = currentSessionId else {
            print("Error: Cannot save session, currentSessionId is nil.")
            return
        }
        // Make sure there are messages to save, or decide if empty sessions should be saved
        // guard !chatMessages.isEmpty else { return }

        print("Saving session: \(sessionId)")
        let session = ChatSession(id: sessionId, messages: chatMessages)
        storageManager.saveSession(session)
    }

    func loadSession(sessionId: UUID) {
        print("Loading session: \(sessionId)")
        if let session = storageManager.loadSession(withId: sessionId) {
            currentSessionId = session.id
            // Sort messages just in case they aren't stored chronologically (they should be)
            chatMessages = session.messages.sorted { $0.timestamp < $1.timestamp }
            storageManager.setLatestSessionId(session.id) // Mark this as the latest viewed
        } else {
            print("Failed to load session \(sessionId), starting new chat.")
            startNewChat() // Fallback to new chat if load fails
        }
    }

    // loadLatestSession is no longer called by onAppear, but keep it for potential future use
    func loadLatestSession() {
         if let latestId = storageManager.getLatestSessionId() {
             print("Loading latest session ID: \(latestId)")
             loadSession(sessionId: latestId)
         } else {
             print("No latest session found, starting new chat.")
             startNewChat()
         }
    }

    // Helper to scroll to the bottom
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessageId = chatMessages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
        }
    }
    
    // Helper to hide keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Separate View for displaying a single message
struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer() // Push user message to the right
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule()) // Rounded bubble
            } else {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // No background for model messages
                    .foregroundColor(Color(.label)) // Ensure text is visible in light/dark mode
                Spacer() // Keep model message to the left
            }
        }
    }
}

#Preview {
     // Preview ContentView as it handles the setup flow
     ContentView()
     // Direct ChatView preview needs dummy data/closures:
     /*
     ChatView(storageManager: StorageManager(), onChangeApiKeyRequested: {})
         .onAppear {
             // Inject dummy data if needed for direct preview
         }
     */
} 