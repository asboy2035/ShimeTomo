//
//  Models.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

import Foundation
import AppKit

struct ShimejiImage: Identifiable, Codable {
    let id = UUID()
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct Shimeji: Identifiable, Codable {
    let id: UUID
    var name: String
    var folderURL: URL
    var images: [ShimejiImage]
    
    enum CodingKeys: String, CodingKey {
        case id, name, folderURL, images
    }
    
    init(id: UUID = UUID(), name: String, folderURL: URL, images: [ShimejiImage] = []) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.images = images
    }
    
    var preview: NSImage? {
        guard let firstImageName = images.first?.name else { return nil }
        let imageURL = folderURL.appendingPathComponent(firstImageName)
        return NSImage(contentsOf: imageURL)
    }
}
