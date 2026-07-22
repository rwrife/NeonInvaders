//
//  GameViewController.swift
//  NeonInvaders macOS
//

import Cocoa
import MetalKit

class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View is not an MTKView"); return
        }
        self.mtkView = mtkView

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not supported"); return
        }
        mtkView.device = device

        guard let r = Renderer(metalKitView: mtkView) else {
            print("Renderer failed"); return
        }
        renderer = r
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // Accept key events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event); return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event); return event
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) {
        let g = renderer.game
        switch event.keyCode {
        case 0x7B, 0x00: g.moveLeft  = true   // left arrow, A
        case 0x7C, 0x02: g.moveRight = true   // right arrow, D
        case 0x31:                             // space
            switch g.phase {
            case .splash, .gameOver: g.handleTap()
            case .playing:           g.firePressed = true
            default: break
            }
        case 0x35: break  // escape – ignore
        default: break
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        let g = renderer.game
        switch event.keyCode {
        case 0x7B, 0x00: g.moveLeft  = false
        case 0x7C, 0x02: g.moveRight = false
        case 0x31:        g.firePressed = false
        default: break
        }
    }
}
