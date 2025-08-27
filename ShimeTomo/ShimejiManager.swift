//
//  ShimejiManager.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

internal import Combine
import AppKit


class ShimejiManager: ObservableObject {
    @Published var shimejis: [Shimeji] = [] {
        didSet {
            saveShimejis()
        }
    }
    @Published var floatingShimejis: [FloatingShimeji] = []
    
    let appFolder: URL = {
        let fm = FileManager.default
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("しめとも")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    private var saveFileURL: URL {
        appFolder.appendingPathComponent("shimejis.json")
    }
    
    init() {
        loadShimejis()
    }
    
    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let folder = panel.url {
                self.copyFolderToApp(folder: folder)
            }
        }
    }
    
    private func copyFolderToApp(folder: URL) {
        let dest = appFolder.appendingPathComponent(folder.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: folder, to: dest)
            let images = loadImages(from: dest)
            let shimeji = Shimeji(name: folder.lastPathComponent, folderURL: dest, images: images)
            DispatchQueue.main.async {
                self.shimejis.append(shimeji)
            }
        } catch {
            print("Error importing folder: \(error)")
        }
    }
    
    private func loadImages(from folder: URL) -> [ShimejiImage] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { file in
            if NSImage(contentsOf: file) != nil {
                return ShimejiImage(name: file.lastPathComponent)
            }
            return nil
        }
        .sorted { $0.name < $1.name } // sorts by filename
    }
    
    func remove(shimeji: Shimeji) {
        let fm = FileManager.default
        try? fm.removeItem(at: shimeji.folderURL)
        shimejis.removeAll { $0.id == shimeji.id }
    }
    
    func showFloating(shimeji: Shimeji) {
        let floating = FloatingShimeji(shimeji: shimeji)
        floating.manager = self
        floatingShimejis.append(floating)
        floating.show()
    }
    
    func closeFloating(_ floating: FloatingShimeji) {
        // Remove from array first to prevent UI updates during cleanup
        if let index = floatingShimejis.firstIndex(where: { $0.id == floating.id }) {
            floatingShimejis.remove(at: index)
        }
        
        // Break the manager reference immediately
        floating.manager = nil
        
        // Clean up immediately on main queue
        floating.prepareForClose()
    }
    
    func rename(shimeji: Shimeji, to newName: String) {
        guard let index = shimejis.firstIndex(where: { $0.id == shimeji.id }) else { return }
        shimejis[index].name = newName
        saveShimejis()
    }
    
    private func saveShimejis() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(shimejis)
            try data.write(to: saveFileURL, options: [.atomic])
        } catch {
            print("Failed to save shimejis: \(error)")
        }
    }
    
    private func loadShimejis() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: saveFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoder = JSONDecoder()
            let loadedShimejis = try decoder.decode([Shimeji].self, from: data)
            DispatchQueue.main.async {
                self.shimejis = loadedShimejis
            }
        } catch {
            print("Failed to load shimejis: \(error)")
        }
    }
}
