import Foundation

class StorageManager {
    private let sessionsKey = "chatSessions_gpt41"
    private let latestSessionIdKey = "latestSessionId_gpt41"
    private let apiKeyKey = "openAiApiKey_gpt41" // Key for API Key
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Optional: Register default values if needed
    }

    // Load all sessions
    func loadSessions() -> [ChatSession] {
        guard let data = defaults.data(forKey: sessionsKey) else {
            return []
        }
        do {
            let sessions = try decoder.decode([ChatSession].self, from: data)
            // Sort by last modified date, newest first
            return sessions.sorted { $0.lastModified > $1.lastModified }
        } catch {
            print("Error decoding sessions: \(error)")
            return []
        }
    }

    // Save a single session (adds or updates)
    func saveSession(_ session: ChatSession) {
        var sessions = loadSessions() // Load existing

        // Remove existing session with the same ID if present
        sessions.removeAll { $0.id == session.id }
        // Add the updated/new session
        sessions.append(session)

        do {
            let data = try encoder.encode(sessions)
            defaults.set(data, forKey: sessionsKey)
            // Update the latest session ID
            setLatestSessionId(session.id)
            print("Session \(session.id) saved.")
        } catch {
            print("Error encoding sessions: \(error)")
        }
    }

    // Load a specific session by ID
    func loadSession(withId id: UUID) -> ChatSession? {
        let sessions = loadSessions()
        return sessions.first { $0.id == id }
    }

    // --- Keep track of the last active session --- 

    func setLatestSessionId(_ id: UUID) {
        defaults.set(id.uuidString, forKey: latestSessionIdKey)
    }

    func getLatestSessionId() -> UUID? {
        guard let idString = defaults.string(forKey: latestSessionIdKey) else { return nil }
        return UUID(uuidString: idString)
    }
    
    // Optional: Function to delete a session
    func deleteSession(withId id: UUID) {
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        do {
            let data = try encoder.encode(sessions)
            defaults.set(data, forKey: sessionsKey)
             print("Session \(id) deleted.")
             // If deleting the latest session, update latestSessionId
             if getLatestSessionId() == id {
                 defaults.removeObject(forKey: latestSessionIdKey)
                 // Optional: set latest to the next most recent one
             }
        } catch {
            print("Error encoding sessions after deletion: \(error)")
        }
    }

    // MARK: - API Key Management
    func saveApiKey(_ key: String) {
        defaults.set(key, forKey: apiKeyKey)
        print("API Key saved.")
    }

    func loadApiKey() -> String? {
        return defaults.string(forKey: apiKeyKey)
    }

    func deleteApiKey() {
        defaults.removeObject(forKey: apiKeyKey)
        print("API Key deleted.")
    }

    // Function to delete ALL sessions
    func deleteAllSessions() {
        defaults.removeObject(forKey: sessionsKey)
        defaults.removeObject(forKey: latestSessionIdKey) // Also clear the latest session pointer
        print("All chat history cleared.")
    }

    // Function to delete ALL data (history and API key)
    func deleteAllData() {
        deleteAllSessions()
        deleteApiKey()
        print("All app data (history and API key) deleted.")
    }
} 