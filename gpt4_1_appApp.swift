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
        UITextView.appearance().backgroundColor = .clear
        print("Configured UITextView appearance: Background set to clear.")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
