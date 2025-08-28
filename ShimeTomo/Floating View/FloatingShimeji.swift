//
//  FloatingShimeji.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

internal import Combine
import AppKit
import SwiftUI


// MARK: - SwiftUI Content View
struct FloatingShimejiContentView: View {
    let shimeji: Shimeji
    @ObservedObject var floatingShimeji: FloatingShimeji
    
    private let baseSize: CGFloat = 150
    
    private var scaledSize: CGFloat {
        baseSize * floatingShimeji.scale
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let image = floatingShimeji.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: scaledSize)
                        .frame(width: scaledSize)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: scaledSize, height: scaledSize)
                }
            }
            
            if floatingShimeji.isHovering {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            floatingShimeji.closeButtonPressed()
                        }) {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial)
                                .overlay(Circle().stroke(.tertiary.opacity(0.5), lineWidth: 1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity.combined(with: .scale))
                    }
                    Spacer()
                    Slider(value: Binding(
                        get: { floatingShimeji.scale },
                        set: { newValue in
                            floatingShimeji.updateScale(newValue)
                        }
                    ), in: 0.2...3.0)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: floatingShimeji.isHovering)
                .animation(.easeInOut(duration: 0.2), value: floatingShimeji.scale)
            }
        }
        .background(
            VisualEffectView(
                material: .fullScreenUI,
                blendingMode: .behindWindow
            )
            .opacity(floatingShimeji.isHovering ? 1 : 0)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.tertiary.opacity(0.5), lineWidth: floatingShimeji.isHovering ? 2 : 0))
        .mask(RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - FloatingShimeji Class
class FloatingShimeji: ObservableObject, Identifiable {
    let id = UUID()
    let shimeji: Shimeji
    private var window: NSWindow?
    private var hostingView: NSHostingView<FloatingShimejiContentView>?
    private var containerView: FloatingContainerView?
    private var timer: Timer?
    private var movementTimer: Timer?
    private var isClosing = false
    
    // DVD-style movement properties
    private var velocityX: CGFloat = 0.5
    private var velocityY: CGFloat = 0.25
    
    // Current animation state
    @Published var currentImage: NSImage?
    
    weak var manager: ShimejiManager?
    
    @Published var scale: CGFloat = 1.0
    @Published var isHovering: Bool = false
    
    init(shimeji: Shimeji) {
        self.shimeji = shimeji
        self.currentImage = shimeji.preview
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
        
        // Create SwiftUI Content View with ObservedObject
        let contentView = FloatingShimejiContentView(
            shimeji: shimeji,
            floatingShimeji: self
        )
        
        // Create NSHostingView to wrap SwiftUI content
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: scaledSize + 35, height: scaledSize + 35)
        self.hostingView = hosting
        
        // Container View for tracking mouse events
        let container = FloatingContainerView(frame: NSRect(x: 0, y: 0, width: scaledSize, height: scaledSize + 35))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        container.floatingShimeji = self
        self.containerView = container
        
        // Window
        let win = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: scaledSize + 35, height: scaledSize + 35),
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
    
    func prepareForClose(completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true

        // Stop all timers immediately
        timer?.invalidate()
        timer = nil
        movementTimer?.invalidate()
        movementTimer = nil

        // Prepare container for close
        containerView?.prepareForClose()

        // Remove gesture recognizers
        if let containerView = containerView {
            containerView.gestureRecognizers.forEach { gestureRecognizer in
                containerView.removeGestureRecognizer(gestureRecognizer)
            }
        }

        // Animate window out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
            self.cleanup()
            completion?()
        })
    }
    
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        movementTimer?.invalidate()
        movementTimer = nil
        
        // Clear all UI references
        hostingView?.removeFromSuperview()
        containerView?.removeFromSuperview()
        
        hostingView = nil
        containerView = nil
        window = nil
        manager = nil
    }
    
    func showControls() {
        guard !isClosing else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isHovering = true
        }
    }
    
    func hideControls() {
        guard !isClosing else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isHovering = false
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
                DispatchQueue.main.async {
                    self.currentImage = nsImage
                }
            }
            index += 1
        }
    }
    
    private func startMovement() {
        guard !isClosing else { return }
        
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self, !self.isClosing, let window = self.window else {
                timer.invalidate()
                return
            }

            // skip movement if hovering
            if self.isHovering { return }

            var frame = window.frame
            frame.origin.x += self.velocityX
            frame.origin.y += self.velocityY
            
            guard let screenFrame = window.screen?.visibleFrame else { return }
            
            if frame.origin.x <= screenFrame.minX || frame.origin.x + frame.size.width >= screenFrame.maxX {
                self.velocityX = -self.velocityX
                frame.origin.x = max(screenFrame.minX, min(frame.origin.x, screenFrame.maxX - frame.size.width))
            }
            if frame.origin.y <= screenFrame.minY || frame.origin.y + frame.size.height >= screenFrame.maxY {
                self.velocityY = -self.velocityY
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
    
    func updateScale(_ newScale: CGFloat) {
        guard !isClosing, let window = self.window, let container = self.containerView, let hosting = self.hostingView else { return }
        
        scale = newScale
        let baseSize: CGFloat = 150
        let scaledSize = baseSize * scale
        let containerHeight = scaledSize + (isHovering ? 50 : 0)
        
        // Resize window and container view
        var frame = window.frame
        frame.size = NSSize(width: scaledSize, height: containerHeight)
        window.setFrame(frame, display: true)
        
        container.frame = NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight)
        hosting.frame = NSRect(x: 0, y: 0, width: scaledSize, height: containerHeight)
    }
}

