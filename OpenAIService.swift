import Foundation
import UIKit // Needed for UIImage conversion

// MARK: - OpenAI Request Structures

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    // Add other parameters like max_tokens if needed
}

struct OpenAIMessage: Codable {
    let role: String
    let content: MessageContent // Can be String or Array
    
    // Custom coding keys/logic to handle flexible content type
    enum CodingKeys: String, CodingKey {
        case role, content
    }
    
    // Allow simple initialization with just text
    init(role: String, text: String) {
        self.role = role
        self.content = .text(text)
    }
    
    // Allow initialization with text and image
    init(role: String, text: String, base64Image: String, mimeType: String = "image/jpeg") {
        self.role = role
        self.content = .contentArray([
            .textItem(TextContent(text: text)),
            .imageItem(ImageContent(imageUrl: ImageURL(url: "data:\(mimeType);base64,\(base64Image)")))
        ])
    }
    
    // Encode based on content type
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        
        switch content {
        case .text(let textContent):
            try container.encode(textContent, forKey: .content)
        case .contentArray(let contentArray):
            try container.encode(contentArray, forKey: .content)
        }
    }
    
    // Decoder (if needed, less likely for sending requests)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        // Try decoding as String first, then as Array
        if let textContent = try? container.decode(String.self, forKey: .content) {
            content = .text(textContent)
        } else {
             let contentArray = try container.decode([MessageContentItem].self, forKey: .content)
             content = .contentArray(contentArray)
        }
    }
}

// Enum to handle flexible content (String or Array)
enum MessageContent: Codable {
    case text(String)
    case contentArray([MessageContentItem])
}

// Enum for items within the content array
enum MessageContentItem: Codable {
    case textItem(TextContent)
    case imageItem(ImageContent)
    
    // Custom coding keys/logic if structure differs significantly
    enum CodingKeys: String, CodingKey {
         case type, text, imageUrl = "image_url"
     }
     
     // Manual encoding
     func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         switch self {
         case .textItem(let textContent):
             try container.encode("text", forKey: .type)
             try container.encode(textContent.text, forKey: .text)
         case .imageItem(let imageContent):
             try container.encode("image_url", forKey: .type)
             try container.encode(imageContent.imageUrl, forKey: .imageUrl)
         }
     }
     
    // Manual decoding
     init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         let type = try container.decode(String.self, forKey: .type)
         
         switch type {
         case "text":
             let text = try container.decode(String.self, forKey: .text)
             self = .textItem(TextContent(text: text))
         case "image_url":
             let imageUrl = try container.decode(ImageURL.self, forKey: .imageUrl)
             self = .imageItem(ImageContent(imageUrl: imageUrl))
         default:
             throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid content type")
         }
     }
}

struct TextContent: Codable {
    let type: String = "text"
    let text: String
}

struct ImageContent: Codable {
    let type: String = "image_url"
    let imageUrl: ImageURL
    
    enum CodingKeys: String, CodingKey {
        case type, imageUrl = "image_url"
    }
}

struct ImageURL: Codable {
    let url: String
    // Add detail field if needed: let detail: String = "high"
}

// MARK: - OpenAI Response Structures

struct OpenAIResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let usage: Usage?
    let error: OpenAIError? // Handle potential API errors
}

struct Choice: Codable {
    let index: Int?
    let message: ResponseMessage?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct ResponseMessage: Codable {
    let role: String?
    let content: String?
}

struct Usage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAIError: Codable {
    let message: String?
    let type: String?
    let param: String?
    let code: String?
}

// MARK: - OpenAI Service Class

class OpenAIService {
    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let modelName = "gpt-4.1" // Using the desired model

    // Update signature to accept history and optional new image for the *last* message
    func generateResponse(currentHistory: [ChatMessage], apiKey: String, newImage: UIImage?) async throws -> String {
        
        // Map ChatMessage history to OpenAIMessage history
        var apiMessages: [OpenAIMessage] = []
        
        for (index, message) in currentHistory.enumerated() {
            let role = message.isFromUser ? "user" : "assistant"
            
            // For the last user message, include the image if provided
            if index == currentHistory.count - 1 && message.isFromUser && newImage != nil {
                guard let image = newImage else {
                    apiMessages.append(OpenAIMessage(role: role, text: message.text))
                    continue
                }
                
                // Convert image to data with proper compression and quality handling
                guard let imageData = image.jpegData(compressionQuality: 0.7) ?? image.pngData() else {
                    print("Failed to convert image to data")
                    throw ServiceError.imageConversionFailed
                }
                
                // Limit size for API constraints (less than 20MB for OpenAI)
                if imageData.count > 10_000_000 { // 10MB limit for safety
                    // Try with higher compression if too large
                    guard let compressedData = image.jpegData(compressionQuality: 0.5) else {
                        print("Failed to compress image")
                        throw ServiceError.imageConversionFailed
                    }
                    
                    if compressedData.count > 10_000_000 {
                        print("Image too large even after compression")
                        throw ServiceError.imageConversionFailed
                    }
                    
                    let base64Image = compressedData.base64EncodedString()
                    print("Compressed image included for last user message, base64 size: \(base64Image.count)")
                    apiMessages.append(OpenAIMessage(role: role, text: message.text, base64Image: base64Image, mimeType: "image/jpeg"))
                } else {
                    // Use original data if size is acceptable
                    let mimeType = (imageData == image.jpegData(compressionQuality: 0.7)) ? "image/jpeg" : "image/png"
                    let base64Image = imageData.base64EncodedString()
                    print("Image included for last user message, base64 size: \(base64Image.count), mime type: \(mimeType)")
                    apiMessages.append(OpenAIMessage(role: role, text: message.text, base64Image: base64Image, mimeType: mimeType))
                }
            } else {
                // For all other messages (or if no new image for the last one), send text only
                apiMessages.append(OpenAIMessage(role: role, text: message.text))
            }
        }
        
        // Ensure we actually have messages to send
        guard !apiMessages.isEmpty else {
            print("Error: No messages constructed for API call.")
            throw ServiceError.invalidResponseStructure // Or a more specific error
        }

        let requestBody = OpenAIRequest(model: modelName, messages: apiMessages)
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            print("Sending request with \(apiMessages.count) messages...")
        } catch {
            print("Error encoding request: \(error)")
            throw ServiceError.requestEncodingFailed(error)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debugging response
            if let httpResponse = response as? HTTPURLResponse {
                print("Response status code: \(httpResponse.statusCode)")
            }
            // print("Response data: \(String(data: data, encoding: .utf8) ?? "Invalid data")")
             
            let decoder = JSONDecoder()
            let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
            
            if let apiError = openAIResponse.error {
                 print("API Error: \(apiError.message ?? "Unknown API error")")
                 throw ServiceError.apiError(apiError.message ?? "Unknown API error")
            }
            
            guard let content = openAIResponse.choices?.first?.message?.content else {
                print("Invalid response structure or empty content")
                throw ServiceError.invalidResponseStructure
            }
            
            print("Received response successfully.")
            return content
            
        } catch let error as URLError {
            print("URL Error: \(error)")
            throw ServiceError.networkError(error)
        } catch let error as DecodingError {
            print("Decoding Error: \(error)")
            throw ServiceError.responseDecodingFailed(error)
        } catch {
            print("Unknown Error: \(error)")
            throw ServiceError.unknownError(error)
        }
    }
}

// MARK: - Service Errors

enum ServiceError: Error, LocalizedError {
    case apiKeyMissing
    case imageConversionFailed
    case requestEncodingFailed(Error)
    case networkError(URLError)
    case apiError(String)
    case responseDecodingFailed(Error)
    case invalidResponseStructure
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "API Key is missing."
        case .imageConversionFailed: return "Failed to convert image to data."
        case .requestEncodingFailed(let error): return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let message): return "API error: \(message)"
        case .responseDecodingFailed(let error): return "Failed to decode response: \(error.localizedDescription)"
        case .invalidResponseStructure: return "Received invalid response structure from API."
        case .unknownError(let error): return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
} 