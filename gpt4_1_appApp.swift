//
//  gpt4_1_appApp.swift
//  gpt4.1_app
//
//  Created by Sagar Varma on 4/23/25.
//

import SwiftUI
import UIKit

@main
struct gpt4_1_appApp: App {
    
    init() {
        // Configure global UIKit appearance settings
        UITextView.appearance().backgroundColor = .clear
        
        // Additional iPad-specific settings
        #if targetEnvironment(macCatalyst)
        // macOS settings if needed
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Force full-screen on iPad
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.forEach { windowScene in
                windowScene.windows.forEach { window in
                    window.overrideUserInterfaceStyle = .light // Force light mode for consistency
                    // Force the window to use the full screen
                    if let window = window as? UIWindow {
                        window.frame = UIScreen.main.bounds
                    }
                }
            }
        }
        #endif
        
        print("Configured app appearance settings for \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Force light mode for consistency
                .onAppear {
                    // Configure window on appearance
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        configureWindowForIPad()
                    }
                }
        }
    }
    
    // Helper function to configure windows for iPad
    private func configureWindowForIPad() {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.forEach { windowScene in
                windowScene.windows.forEach { window in
                    // Ensure the window uses the entire screen space
                    if let window = window as? UIWindow {
                        window.frame = UIScreen.main.bounds
                    }
                }
            }
        }
    }
}
