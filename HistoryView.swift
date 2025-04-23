import SwiftUI

struct HistoryView: View {
    let storageManager: StorageManager
    let onChangeApiKeyRequested: () -> Void // Closure to request API key change
    let onSessionSelected: (UUID) -> Void // Closure to call when a session is tapped

    @State private var sessions: [ChatSession] = []
    @State private var showingClearHistoryAlert = false
    @State private var showingDeleteAllAlert = false // State for delete all alert
    @Environment(\.dismiss) var dismiss // To dismiss the sheet

    // Static date formatter for consistent formatting
    private static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long // e.g., April 23, 2025
        formatter.timeStyle = .none
        return formatter
    }()

    // Explicit initializer
    init(storageManager: StorageManager, 
         onChangeApiKeyRequested: @escaping () -> Void, 
         onSessionSelected: @escaping (UUID) -> Void) {
        self.storageManager = storageManager
        self.onChangeApiKeyRequested = onChangeApiKeyRequested
        self.onSessionSelected = onSessionSelected
    }

    var body: some View {
        NavigationView { // Embed in NavigationView for title and toolbar
            VStack {
                if sessions.isEmpty {
                    Spacer() // Push text to center
                    Text("No past chats found.")
                        .foregroundColor(.secondary)
                    Spacer() // Push text to center
                } else {
                    List {
                        ForEach(sessions) { session in
                            Button { // Make the whole row tappable
                                onSessionSelected(session.id)
                                // dismiss() // Dismiss is now handled in ChatView's sheet binding
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(session.previewText) // Show first message as preview
                                        .font(.headline)
                                        .lineLimit(1)
                                    // Format the date using the date formatter
                                    Text(session.lastModified, formatter: HistoryView.dateFormatter)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(Color(.label)) // Ensure text color adapts
                        }
                        .onDelete(perform: deleteSession) // Add swipe-to-delete
                    }
                    .listStyle(.plain)
                }

                // --- Buttons Section at the bottom --- 
                VStack(spacing: 15) {
                   Divider()

                   Button("Change API Key") {
                       // Call the closure provided by ContentView via ChatView
                       onChangeApiKeyRequested()
                       // Dismiss the sheet after triggering the change
                       dismiss()
                   }
                   .padding(.top) // Add some padding above the first button

                   Button("Clear History", role: .destructive) { // Destructive role for red text
                       showingClearHistoryAlert = true // Trigger the alert
                   }
                   
                   // --- Add Delete All Data Button ---
                   Button("Delete All Data", role: .destructive) {
                        showingDeleteAllAlert = true // Trigger the new alert
                   }
                   // --- End Add Button ---
                }
                .padding(.horizontal)
                .padding(.bottom) // Add padding below buttons
                // --- End Buttons Section --- 
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                 ToolbarItem(placement: .navigationBarLeading) { // Add EditButton for delete
                     EditButton()
                 }
            }
            .alert("Clear History?", isPresented: $showingClearHistoryAlert) { // Alert modifier
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { 
                    clearAllHistory()
                }
            } message: {
                Text("This action cannot be reversed.")
            }
            // --- Add Alert for Delete All Data --- 
            .alert("Delete All Data?", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAllAppData()
                }
            } message: {
                Text("This will permanently delete all chat history and your saved API key. The app will reset.")
            }
            // --- End Add Alert --- 
            .onAppear {
                // Load sessions when the view appears
                sessions = storageManager.loadSessions()
            }
        }
    }
    
    // Function to handle deletion from the list
    private func deleteSession(at offsets: IndexSet) {
        let sessionsToDelete = offsets.map { sessions[$0] }
        sessions.remove(atOffsets: offsets) // Update UI immediately
        // Perform deletion in storage
        for session in sessionsToDelete {
            storageManager.deleteSession(withId: session.id)
            print("Deleted session from history view: \(session.id)")
        }
    }

    // --- Add Function to clear all history --- 
    private func clearAllHistory() {
        print("Clearing all history...")
        storageManager.deleteAllSessions() // Call manager function
        sessions.removeAll() // Update the local state to refresh the list
        // Optionally dismiss after clearing, or stay on the (now empty) history view
        // dismiss()
    }
    // --- End Add Function ---

    // --- Add Function to delete all app data ---
    private func deleteAllAppData() {
        print("Deleting all app data...")
        storageManager.deleteAllData() // Call the new manager function
        sessions.removeAll() // Clear local session state
        // Trigger the navigation back to SetupView via the closure
        onChangeApiKeyRequested() 
        dismiss() // Dismiss the history sheet
    }
    // --- End Add Function --- 
}

// Preview provider (optional, might need to mock StorageManager)
/*
 #Preview {
     // Need a way to provide a StorageManager and a closure for preview
     // Example:
     let manager = StorageManager()
     // Add some dummy data to manager for preview if needed
     
     return HistoryView(storageManager: manager) { sessionId in
         print("Session selected: \(sessionId)")
     }
 }
*/ 