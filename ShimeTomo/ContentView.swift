//
//  ContentView.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

import SwiftUI
import AppKit
internal import Combine

// MARK: - Model
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

// MARK: - ViewModel
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
        floating.prepareForClose()  // invalidate timers & remove tracking areas
        floating.close()            // close window
        floatingShimejis.removeAll { $0.id == floating.id } // remove reference last
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

// MARK: - Floating Container View
class FloatingContainerView: NSView {
    weak var floatingShimeji: FloatingShimeji?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { self.removeTrackingArea($0) }
        let trackingArea = NSTrackingArea(rect: self.bounds,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        floatingShimeji?.showControls()
    }
    
    override func mouseExited(with event: NSEvent) {
        floatingShimeji?.hideControls()
    }
}

// MARK: - Floating Shimeji
class FloatingShimeji: ObservableObject, Identifiable {
    let id = UUID()
    let shimeji: Shimeji
    var window: NSWindow!
    var imageView: NSImageView!
    var containerView: FloatingContainerView!
    var closeButton: NSButton!
    var slider: NSSlider!
    var timer: Timer?
    var movementTimer: Timer?
    
    weak var manager: ShimejiManager?
    
    @Published var scale: CGFloat = 1.0
    
    init(shimeji: Shimeji) {
        self.shimeji = shimeji
    }
    
    func show() {
        let baseSize: CGFloat = 150
        let scaledSize = baseSize * scale
        
        // Image View
        imageView = NSImageView(frame: NSRect(x: 0, y: 40, width: scaledSize, height: scaledSize))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = shimeji.preview
        
        // Close Button
        closeButton = NSButton(title: "✖️", target: self, action: #selector(closeButtonPressed))
        closeButton.isBordered = false
        closeButton.frame = NSRect(x: scaledSize - 30, y: scaledSize + 10, width: 30, height: 30)
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Scale Slider
        slider = NSSlider(value: Double(scale), minValue: 0.2, maxValue: 3.0, target: self, action: #selector(scaleChanged))
        slider.frame = NSRect(x: 10, y: 10, width: scaledSize - 20, height: 20)
        
        // Container View
        let containerHeight = scaledSize + 50
        containerView = FloatingContainerView(frame: NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(imageView)
        containerView.addSubview(closeButton)
        containerView.addSubview(slider)
        containerView.floatingShimeji = self
        
        // Initially hide controls
        closeButton.isHidden = true
        slider.isHidden = true
        
        // Window
        window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: scaledSize, height: containerHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        
        startAnimation()
        startMovement()
        
        makeDraggable()
    }
    
    func prepareForClose() {
        timer?.invalidate()
        movementTimer?.invalidate()
        containerView?.removeFromSuperview()
        window?.orderOut(nil)
    }
    
    func showControls() {
        DispatchQueue.main.async {
            self.closeButton.isHidden = false
            self.slider.isHidden = false
        }
    }
    
    func hideControls() {
        DispatchQueue.main.async {
            self.closeButton.isHidden = true
            self.slider.isHidden = true
        }
    }
    
    private func startAnimation() {
        var index = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.shimeji.images.isEmpty { return }
            let imageName = self.shimeji.images[index % self.shimeji.images.count].name
            let imageURL = self.shimeji.folderURL.appendingPathComponent(imageName)
            if let nsImage = NSImage(contentsOf: imageURL) {
                self.imageView.image = nsImage
            }
            index += 1
        }
    }
    
    private func startMovement() {
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Pick a small random direction
            let dx = CGFloat.random(in: -1...1)
            let dy = CGFloat.random(in: -1...1)
            
            // Update frame
            var frame = self.window.frame
            frame.origin.x += dx
            frame.origin.y += dy
            
            // Keep within screen bounds
            if let screenFrame = self.window.screen?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, screenFrame.minX), screenFrame.maxX - frame.size.width)
                frame.origin.y = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - frame.size.height)
            }
            
            self.window.setFrame(frame, display: true)
        }
    }
    
    private func makeDraggable() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleDrag))
        containerView.addGestureRecognizer(pan)
    }
    
    @objc private func handleDrag(gesture: NSPanGestureRecognizer) {
        guard let window = gesture.view?.window else { return }
        let translation = gesture.translation(in: gesture.view)
        var frame = window.frame
        frame.origin.x += translation.x
        frame.origin.y += translation.y // use +=, not -=
        window.setFrame(frame, display: true)
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    func close() {
        timer?.invalidate()
        movementTimer?.invalidate()
        window.close()
    }
    
    @objc func closeButtonPressed() {
        manager?.closeFloating(self)
    }
    
    @objc private func scaleChanged(slider: NSSlider) {
        scale = CGFloat(slider.doubleValue)
        let baseSize: CGFloat = 150
        let scaledSize = baseSize * scale
        let containerHeight = scaledSize + 50
        
        // Resize window and container view
        var frame = window.frame
        frame.size = NSSize(width: scaledSize, height: containerHeight)
        window.setFrame(frame, display: true)
        
        containerView.frame = NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight)
        
        // Resize and reposition subviews
        imageView.frame = NSRect(x: 0, y: 40, width: scaledSize, height: scaledSize)
        
        closeButton.frame = NSRect(x: scaledSize - 30, y: scaledSize + 10, width: 30, height: 30)
        
        slider.frame = NSRect(x: 10, y: 10, width: scaledSize - 20, height: 20)
        slider.doubleValue = Double(scale)
    }
}

// MARK: - Main App View
struct ContentView: View {
    @StateObject var manager = ShimejiManager()
    
    var body: some View {
        VStack {
            HStack {
                Button("Import Folder") { manager.importFolder() }
                Spacer()
                Text("Currently Floating: \(manager.floatingShimejis.count)")
            }
            .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(manager.shimejis) { shimeji in
                        VStack {
                            if let image = shimeji.preview {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                            } else {
                                Rectangle().fill(.gray).frame(width: 80, height: 80)
                            }
                            Text(shimeji.name).lineLimit(1)
                        }
                        .contextMenu {
                            Button("Rename") { /* add rename logic */ }
                            Button("Delete") { manager.remove(shimeji: shimeji) }
                            Button("Show") { manager.showFloating(shimeji: shimeji) }
                        }
                        .onTapGesture { manager.showFloating(shimeji: shimeji) }
                    }
                }
                .padding()
                
                // List of floating shimejis with close buttons
                if !manager.floatingShimejis.isEmpty {
                    Divider()
                    Text("Floating Shimejis")
                        .font(.headline)
                        .padding(.top)
                    List {
                        ForEach(manager.floatingShimejis) { floating in
                            HStack {
                                Text(floating.shimeji.name)
                                Spacer()
                                Button("Close") {
                                    manager.closeFloating(floating)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
