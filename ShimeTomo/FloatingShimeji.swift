//
//  FloatingShimeji.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

internal import Combine
import AppKit


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
    private var velocityX: CGFloat = 0.5
    private var velocityY: CGFloat = 0.25
    
    weak var manager: ShimejiManager?
    
    @Published var scale: CGFloat = 1.0
    @Published var isHovering: Bool = false
    
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
        let closeBtn = NSButton(title: "×", target: nil, action: nil)
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

        // Clear targets to break retain cycles
        closeButton?.target = nil
        closeButton?.action = nil
        slider?.target = nil
        slider?.action = nil

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
