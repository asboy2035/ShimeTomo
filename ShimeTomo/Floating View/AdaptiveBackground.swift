//
//  AdaptiveBackground.swift
//  ShimeTomo
//
//  Created by ash on 8/28/25.
//

import SwiftUI

struct AdaptiveBackground: View {
    @State var isHovered: Bool
    
    var body: some View {
        if isHovered {
            RoundedRectangle(cornerRadius: 18)
                .background(.ultraThickMaterial)
        } else {
            Color.clear
        }
    }
}
