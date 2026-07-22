//
//  GameViewController.swift
//  NeonInvaders iOS
//

import UIKit
import MetalKit

class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    private var leftTouch: UITouch?
    private var rightTouch: UITouch?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else { return }
        self.mtkView = mtkView

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        mtkView.device = device
        mtkView.backgroundColor = .black

        guard let r = Renderer(metalKitView: mtkView) else { return }
        renderer = r
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer
        mtkView.isMultipleTouchEnabled = true
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard renderer != nil else { return }
        let insets = view.safeAreaInsets
        let scale = Float(mtkView.contentScaleFactor)
        renderer.safePaddingTop    = Float(insets.top)    * scale
        renderer.safePaddingBottom = Float(insets.bottom) * scale
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let g = renderer.game
        switch g.phase {
        case .splash, .gameOver:
            g.handleTap(); return
        default: break
        }
        for t in touches {
            let x = t.location(in: view).x
            if x < view.bounds.width / 2 {
                leftTouch = t; g.moveLeft = true
            } else {
                rightTouch = t; g.moveRight = true
            }
        }
        g.firePressed = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let g = renderer.game; let mid = view.bounds.width / 2
        for t in touches {
            let x = t.location(in: view).x
            if t === leftTouch && x >= mid {
                leftTouch = nil; rightTouch = t; g.moveLeft = false; g.moveRight = true
            } else if t === rightTouch && x < mid {
                rightTouch = nil; leftTouch = t; g.moveRight = false; g.moveLeft = true
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let g = renderer.game
        for t in touches {
            if t === leftTouch  { leftTouch = nil;  g.moveLeft  = false }
            if t === rightTouch { rightTouch = nil; g.moveRight = false }
        }
        if leftTouch == nil && rightTouch == nil { g.firePressed = false }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
