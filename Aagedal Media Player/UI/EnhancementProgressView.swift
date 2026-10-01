// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct EnhancementProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 300)
            
            Text("Enhancing video quality... \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding()
    }
}
