import SwiftUI
import PhotosUI // Import PhotosUI
import UniformTypeIdentifiers // Import UniformTypeIdentifiers for UTType
import Photos

// Define a struct to represent a chat message
struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let text: String
    let isFromUser: Bool
    let timestamp: Date
    var imageData: Data? // Store image as Data for Codable compatibility
    
    enum CodingKeys: String, CodingKey {
        case id, text, isFromUser, timestamp, imageData
    }
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
    @State private var selectedImage: UIImage? = nil
    @State private var showingCameraPicker = false // Separate state for camera sheet
    @State private var showingPhotosPicker = false // Separate state for Photos picker
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

    // --- Main Body --- 
    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 to avoid extra gaps
            messageListView // Extracted ScrollView
            
            // Conditionally show preview *above* input area
            if selectedImage != nil {
                imagePreview
                    .padding(.bottom, 4) // Add padding below preview
            }

            inputArea // Extracted input HStack
        }
        .contentShape(Rectangle()) // Apply to VStack
        .gesture(swipeGesture) // Apply gesture to VStack
        .navigationTitle("GPT 4.1")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(content: toolbarContent)
        .sheet(isPresented: $showHistory, content: historySheet)
        .sheet(isPresented: $showingCameraPicker, content: cameraSheet)
        .sheet(isPresented: $showingPhotosPicker) {
            PHPickerRepresentable(image: $selectedImage)
        }
        .confirmationDialog("Attach Content", isPresented: $showingAttachmentOptions, titleVisibility: .visible, actions: attachmentDialogActions, message: attachmentDialogMessage)
        .onAppear(perform: startNewChat)
    }
    
    // --- Extracted View Components --- 
    
    // Computed property for the message list ScrollView
    private var messageListView: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chatMessages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }
                    if isLoading {
                        loadingIndicator
                    }
                }
                .padding(.top, 10) // Add padding at the top of messages
                .padding(.horizontal)
            }
            .onChange(of: chatMessages.count) { _, _ in
                scrollToBottom(proxy: scrollViewProxy)
            }
            .onTapGesture { hideKeyboard() }
        }
    }
    
    // Computed property for the image preview
    @ViewBuilder // Use ViewBuilder for conditional content
    private var imagePreview: some View {
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
                Spacer()
            }
            .padding(.horizontal)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    // Computed property for the input area HStack
    private var inputArea: some View {
        HStack(spacing: 10) {
             Button(action: {
                 hideKeyboard()
                 showingAttachmentOptions = true
             }) {
                 Image(systemName: "plus.circle.fill")
                     .resizable()
                     .frame(width: 30, height: 30)
             }
             .disabled(isLoading)

             ZStack(alignment: .leading) {
                 if messageText.isEmpty {
                     Text("Ask Anything...")
                         .foregroundColor(Color(.placeholderText))
                         .padding(.horizontal, 5)
                         .padding(.vertical, 8)
                 }
                 TextEditor(text: $messageText)
                     .frame(maxHeight: 100)
                     .fixedSize(horizontal: false, vertical: true)
                     .padding(.vertical, 4)
                     .padding(.horizontal, 1)
                     .scrollContentBackground(.hidden)
                     .background(Color.clear)
             }
             .padding(.horizontal, 10)
             .padding(.vertical, 4)
             .background(Color(.systemGray6))
             .clipShape(RoundedRectangle(cornerRadius: 20))

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
         .opacity(isLoading ? 0.5 : 1.0)
         .background(.thinMaterial) // Add material background to input bar
    }
    
    // Computed property for the loading indicator
    private var loadingIndicator: some View {
         HStack {
             ProgressView()
                 .padding(.leading)
             Text("GPT is thinking...")
                 .font(.caption)
                 .foregroundColor(.secondary)
             Spacer()
         }
         .padding(.horizontal)
    }
    
    // Computed property for the swipe gesture
    private var swipeGesture: some Gesture {
         DragGesture()
             .onEnded { value in
                 let horizontalAmount = value.translation.width
                 let verticalAmount = value.translation.height
                 let distanceThreshold: CGFloat = 100.0
                 let maxVerticalDrag: CGFloat = 50.0

                 if horizontalAmount < -distanceThreshold && abs(verticalAmount) < maxVerticalDrag {
                     withAnimation { showHistory = true }
                 }
             }
    }
    
    // --- Extracted Modifier Content --- 
    
    // Function returning ToolbarContent
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
         ToolbarItem(placement: .navigationBarLeading) {
             Button {
                 showHistory = true
             } label: {
                 Image(systemName: "line.3.horizontal")
             }
         }
         ToolbarItem(placement: .navigationBarTrailing) {
             Button(action: startNewChat) {
                 Image(systemName: "plus")
             }
         }
    }
    
    // Function returning Sheet content for History
    @ViewBuilder
    private func historySheet() -> some View {
        HistoryView(storageManager: storageManager, 
                    onChangeApiKeyRequested: onChangeApiKeyRequested, 
                    onSessionSelected: { selectedSessionId in
            loadSession(sessionId: selectedSessionId)
            showHistory = false
        })
    }
    
    // Function returning Sheet content for Camera
    @ViewBuilder
    private func cameraSheet() -> some View {
        ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
            .ignoresSafeArea()
    }
    
    // Function returning actions for ConfirmationDialog
    @ViewBuilder
    private func attachmentDialogActions() -> some View {
        Button {
            showingPhotosPicker = true 
        } label: {
            Label("Photos", systemImage: "photo.on.rectangle")
        }

        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showingCameraPicker = true
            } else {
                print("Camera not available")
            }
        } label: {
            Label("Camera", systemImage: "camera")
        }
    }
    
    // Function returning message for ConfirmationDialog
    @ViewBuilder
    private func attachmentDialogMessage() -> some View {
        Text("Select source")
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
        var imageData: Data? = nil
        
        // Convert UIImage to Data if available
        if let image = imageToSend {
            // Compress to JPEG format with good quality
            imageData = image.jpegData(compressionQuality: 0.7)
            withAnimation { selectedImage = nil }
        }
        
        messageText = "" 

        // Create message with image data if available
        let userMessage = ChatMessage(
            text: text, 
            isFromUser: true, 
            timestamp: Date(),
            imageData: imageData
        )
        
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
         let modelMessage = ChatMessage(
             text: content, 
             isFromUser: false, 
             timestamp: Date(),
             imageData: nil
         )
         // Append the new message to the existing chatMessages state
         chatMessages.append(modelMessage) 
         saveCurrentSession() // Save session including the model response
    }
    
    // Helper to append error message
    @MainActor
    private func appendErrorMessage(_ errorText: String) {
         let errorMessage = ChatMessage(
             text: errorText, 
             isFromUser: false, 
             timestamp: Date(),
             imageData: nil
         )
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

    // Computed property to safely create AttributedString from Markdown
    private var attributedString: AttributedString {
        do {
            // Attempt to initialize AttributedString from Markdown
            return try AttributedString(markdown: message.text)
        } catch {
            // If Markdown parsing fails, return a plain AttributedString
            print("Error parsing Markdown: \(error)")
            return AttributedString(message.text)
        }
    }
    
    // Convert Data to UIImage if available
    private var messageImage: UIImage? {
        if let imageData = message.imageData {
            return UIImage(data: imageData)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
            // Display image above the bubble if available
            if let image = messageImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .frame(maxWidth: 240, maxHeight: 240)
            }
            
            // Message bubble
            HStack {
                if message.isFromUser {
                    Spacer() 
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .textSelection(.enabled)
                } else {
                    // Display the AttributedString
                    Text(attributedString)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(Color(.label))
                        .textSelection(.enabled)
                    Spacer() 
                }
            }
        }
        .padding(.horizontal, 4) // Add some horizontal padding to the whole message container
    }
}

// New struct for PHPickerViewController
struct PHPickerRepresentable: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // Not needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerRepresentable

        init(_ parent: PHPickerRepresentable) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else {
                print("No image selected")
                return
            }
            
            // Clear any existing image while loading
            DispatchQueue.main.async {
                self.parent.image = nil
            }
            
            // Try multiple UTTypes for better compatibility
            let supportedTypes = [UTType.image, UTType.jpeg, UTType.png, UTType.heic, UTType.tiff]
            
            // First approach: Try loading as UIImage directly
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    if let error = error {
                        print("Error loading image: \(error.localizedDescription)")
                        // Don't return here - we'll try other approaches
                    } else if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self?.parent.image = image
                            print("Successfully loaded image via UIImage")
                        }
                        return // Success!
                    }
                    
                    // If we get here, the direct approach failed, try data approach
                    self?.tryLoadingAsData(result: result)
                }
            } else {
                // Direct UIImage loading not supported, try data approach
                tryLoadingAsData(result: result)
            }
        }
        
        private func tryLoadingAsData(result: PHPickerResult) {
            // Second approach: Try loading as data with multiple types
            for type in [UTType.jpeg, UTType.png, UTType.heic] {
                if result.itemProvider.hasItemConformingToTypeIdentifier(type.identifier) {
                    result.itemProvider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] (data, error) in
                        if let error = error {
                            print("Error loading image data: \(error.localizedDescription)")
                            return
                        }
                        
                        guard let data = data else {
                            print("No data loaded for type: \(type.identifier)")
                            return
                        }
                        
                        // Create UIImage from data
                        if let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self?.parent.image = image
                                print("Successfully loaded image via data for type: \(type.identifier)")
                            }
                        } else {
                            print("Failed to create UIImage from data for type: \(type.identifier)")
                        }
                    }
                    return // Started loading attempt, don't try other types in parallel
                }
            }
            
            // Generic approach as last resort
            result.itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] (item, error) in
                if let error = error {
                    print("Error loading item: \(error.localizedDescription)")
                    return
                }
                
                // Handle different returned item types
                if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.parent.image = image
                        print("Successfully loaded image via URL")
                    }
                } else if let data = item as? Data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.parent.image = image
                        print("Successfully loaded image via generic data")
                    }
                } else {
                    print("Failed to load image from item type: \(String(describing: type(of: item)))")
                }
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