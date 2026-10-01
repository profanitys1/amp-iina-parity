// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct EnhancementSuggestionView: View {
    let suggestion: EnhancementSuggestion.Suggestion
    let onEnhance: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Enhancement Available")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Text(suggestion.reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Enhance Now", action: onEnhance)
                    .buttonStyle(.borderedProminent)
                
                Button("Later") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding()
    }
}
