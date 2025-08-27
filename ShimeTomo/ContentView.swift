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
        // Remove from array first to prevent UI updates during cleanup
        if let index = floatingShimejis.firstIndex(where: { $0.id == floating.id }) {
            floatingShimejis.remove(at: index)
        }
        
        // Break the manager reference immediately
        floating.manager = nil
        
        // Clean up immediately on main queue
        floating.prepareForClose()
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
    private var isClosing = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Clear existing tracking areas to prevent accumulation
        trackingAreas.forEach { self.removeTrackingArea($0) }
        
        // Only add tracking if not closing
        guard !isClosing else { return }
        
        let trackingArea = NSTrackingArea(rect: self.bounds,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard !isClosing else { return }
        floatingShimeji?.showControls()
    }
    
    override func mouseExited(with event: NSEvent) {
        guard !isClosing else { return }
        floatingShimeji?.hideControls()
    }
    
    func prepareForClose() {
        isClosing = true
        trackingAreas.forEach { self.removeTrackingArea($0) }
        floatingShimeji = nil
    }
}

// MARK: - Floating Shimeji
class FloatingShimeji: ObservableObject, Identifiable {
    let id = UUID()
    let shimeji: Shimeji
    private var window: NSWindow?
    private var imageView: NSImageView?
    private var containerView: FloatingContainerView?
    private var closeButton: NSButton?
    private var slider: NSSlider?
    private var timer: Timer?
    private var movementTimer: Timer?
    private var isClosing = false
    
    // DVD-style movement properties
    private var velocityX: CGFloat = 1.0
    private var velocityY: CGFloat = 0.5
    
    weak var manager: ShimejiManager?
    
    @Published var scale: CGFloat = 1.0
    
    init(shimeji: Shimeji) {
        self.shimeji = shimeji
        // Randomize initial velocity direction and speed for variety!
        self.velocityX = CGFloat.random(in: 1.0...3.0) * (Bool.random() ? 1 : -1)
        self.velocityY = CGFloat.random(in: 1.0...3.0) * (Bool.random() ? 1 : -1)
    }
    
    deinit {
        // Ensure cleanup happens
        cleanup()
    }
    
    func show() {
        guard !isClosing else { return }
        
        let baseSize: CGFloat = 150
        let scaledSize = baseSize * scale
        
        // Image View
        let imgView = NSImageView(frame: NSRect(x: 0, y: 40, width: scaledSize, height: scaledSize))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = shimeji.preview
        self.imageView = imgView
        
        // Close Button
        let closeBtn = NSButton(title: "✖️", target: nil, action: nil)
        closeBtn.isBordered = false
        closeBtn.frame = NSRect(x: scaledSize - 30, y: scaledSize + 10, width: 30, height: 30)
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor.clear.cgColor
        // Set target and action after creation to avoid retain cycles
        closeBtn.target = self
        closeBtn.action = #selector(closeButtonPressed)
        self.closeButton = closeBtn
        
        // Scale Slider
        let scaleSlider = NSSlider(value: Double(scale), minValue: 0.2, maxValue: 3.0, target: nil, action: nil)
        scaleSlider.frame = NSRect(x: 10, y: 10, width: scaledSize - 20, height: 20)
        // Set target and action after creation to avoid retain cycles
        scaleSlider.target = self
        scaleSlider.action = #selector(scaleChanged)
        self.slider = scaleSlider
        
        // Container View
        let containerHeight = scaledSize + 50
        let container = FloatingContainerView(frame: NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(imgView)
        container.addSubview(closeBtn)
        container.addSubview(scaleSlider)
        container.floatingShimeji = self
        self.containerView = container
        
        // Initially hide controls
        closeBtn.isHidden = true
        scaleSlider.isHidden = true
        
        // Window
        let win = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: scaledSize, height: containerHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.contentView = container
        self.window = win
        
        win.makeKeyAndOrderFront(nil)
        
        startAnimation()
        startMovement()
        makeDraggable()
    }
    
    func prepareForClose() {
        guard !isClosing else { return }
        isClosing = true
        
        // Break manager reference first
        manager = nil
        
        // Stop all timers immediately
        timer?.invalidate()
        timer = nil
        movementTimer?.invalidate()
        movementTimer = nil
        
        // Prepare container for close
        containerView?.prepareForClose()
        
        // Remove gesture recognizers
        containerView?.gestureRecognizers.forEach { gestureRecognizer in
            containerView?.removeGestureRecognizer(gestureRecognizer)
        }
        
        // Clear targets to break retain cycles
        closeButton?.target = nil
        closeButton?.action = nil
        slider?.target = nil
        slider?.action = nil
        
        // Close window
        window?.orderOut(nil)
        
        // Delay window close slightly to ensure UI updates complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.window?.close()
            self?.cleanup()
        }
    }
    
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        movementTimer?.invalidate()
        movementTimer = nil
        
        // Clear all UI references
        imageView?.removeFromSuperview()
        closeButton?.removeFromSuperview()
        slider?.removeFromSuperview()
        containerView?.removeFromSuperview()
        
        imageView = nil
        closeButton = nil
        slider = nil
        containerView = nil
        window = nil
        manager = nil
    }
    
    func showControls() {
        guard !isClosing else { return }
        DispatchQueue.main.async { [weak self] in
            self?.closeButton?.isHidden = false
            self?.slider?.isHidden = false
        }
    }
    
    func hideControls() {
        guard !isClosing else { return }
        DispatchQueue.main.async { [weak self] in
            self?.closeButton?.isHidden = true
            self?.slider?.isHidden = true
        }
    }
    
    private func startAnimation() {
        guard !isClosing else { return }
        
        var index = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, !self.isClosing else {
                timer.invalidate()
                return
            }
            
            if self.shimeji.images.isEmpty { return }
            let imageName = self.shimeji.images[index % self.shimeji.images.count].name
            let imageURL = self.shimeji.folderURL.appendingPathComponent(imageName)
            if let nsImage = NSImage(contentsOf: imageURL) {
                self.imageView?.image = nsImage
            }
            index += 1
        }
    }
    
    private func startMovement() {
        guard !isClosing else { return }
        
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in // ~60fps for smooth movement
            guard let self = self, !self.isClosing, let window = self.window else {
                timer.invalidate()
                return
            }
            
            // Get current position
            var frame = window.frame
            
            // Apply velocity
            frame.origin.x += self.velocityX
            frame.origin.y += self.velocityY
            
            // Get screen bounds
            guard let screenFrame = window.screen?.visibleFrame else { return }
            
            // Bounce off edges! 🏓
            // Left or right edge
            if frame.origin.x <= screenFrame.minX || frame.origin.x + frame.size.width >= screenFrame.maxX {
                self.velocityX = -self.velocityX
                // Clamp position to stay in bounds
                frame.origin.x = max(screenFrame.minX, min(frame.origin.x, screenFrame.maxX - frame.size.width))
            }
            
            // Top or bottom edge
            if frame.origin.y <= screenFrame.minY || frame.origin.y + frame.size.height >= screenFrame.maxY {
                self.velocityY = -self.velocityY
                // Clamp position to stay in bounds
                frame.origin.y = max(screenFrame.minY, min(frame.origin.y, screenFrame.maxY - frame.size.height))
            }
            
            window.setFrame(frame, display: true)
        }
    }
    
    private func makeDraggable() {
        guard let container = containerView else { return }
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleDrag))
        container.addGestureRecognizer(pan)
    }
    
    @objc private func handleDrag(gesture: NSPanGestureRecognizer) {
        guard !isClosing, let window = gesture.view?.window else { return }
        
        let translation = gesture.translation(in: gesture.view)
        var frame = window.frame
        frame.origin.x += translation.x
        frame.origin.y += translation.y
        window.setFrame(frame, display: true)
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    @objc func closeButtonPressed() {
        manager?.closeFloating(self)
    }
    
    @objc private func scaleChanged(slider: NSSlider) {
        guard !isClosing, let window = self.window, let container = self.containerView else { return }
        
        scale = CGFloat(slider.doubleValue)
        let baseSize: CGFloat = 150
        let scaledSize = baseSize * scale
        let containerHeight = scaledSize + 50
        
        // Resize window and container view
        var frame = window.frame
        frame.size = NSSize(width: scaledSize, height: containerHeight)
        window.setFrame(frame, display: true)
        
        container.frame = NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight)
        
        // Resize and reposition subviews
        imageView?.frame = NSRect(x: 0, y: 40, width: scaledSize, height: scaledSize)
        closeButton?.frame = NSRect(x: scaledSize - 30, y: scaledSize + 10, width: 30, height: 30)
        self.slider?.frame = NSRect(x: 10, y: 10, width: scaledSize - 20, height: 20)
        self.slider?.doubleValue = Double(scale)
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
