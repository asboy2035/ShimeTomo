//
//  FloatingContainerView.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

import AppKit


class FloatingContainerView: NSView {
    weak var floatingShimeji: FloatingShimeji?
    private var isClosing = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Clear existing tracking areas to prevent accumulation
        trackingAreas.forEach { self.removeTrackingArea($0) }
        
        // Only add tracking if not closing
        guard !isClosing else { return }
        
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard !isClosing else { return }
        floatingShimeji?.showControls()
        floatingShimeji?.isHovering = true
    }
    
    override func mouseExited(with event: NSEvent) {
        guard !isClosing else { return }
        floatingShimeji?.hideControls()
        floatingShimeji?.isHovering = false
    }
    
    func prepareForClose() {
        isClosing = true
        trackingAreas.forEach { self.removeTrackingArea($0) }
        floatingShimeji = nil
    }
}
