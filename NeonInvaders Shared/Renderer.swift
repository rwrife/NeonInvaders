//
//  Renderer.swift
//  NeonInvaders Shared
//

import Metal
import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let normalPipeline: MTLRenderPipelineState
    let additivePipeline: MTLRenderPipelineState

    let game = GameEngine()

    var normalVerts: [SpriteVertex] = []
    var additiveVerts: [SpriteVertex] = []

    // Pre-allocated GPU buffers
    var normalBuffer: MTLBuffer!
    var additiveBuffer: MTLBuffer!
    static let maxVertices = 150_000

    // Actual drawable size in pixels (updated from MTKViewDelegate)
    var viewSize: SIMD2<Float> = SIMD2(800, 600)

    // Safe-area padding in drawable pixels (set from view controller)
    var safePaddingTop:    Float = 0
    var safePaddingBottom: Float = 0

    // Logical game dimensions
    static let gameW: Float = 400
    static let gameH: Float = 780

    // Stars: normalized (0..1) positions so they always fill the drawable
    var stars: [(SIMD2<Float>, Float, Float)] = []  // normPos, brightness, twinkle

    // Computed letterbox parameters
    var gameScale: Float {
        let availH = viewSize.y - safePaddingTop - safePaddingBottom
        return min(viewSize.x / Renderer.gameW, availH / Renderer.gameH)
    }
    var gameOffset: SIMD2<Float> {
        let s = gameScale
        let availH = viewSize.y - safePaddingTop - safePaddingBottom
        return SIMD2(
            (viewSize.x - Renderer.gameW * s) / 2,
            safePaddingTop + (availH - Renderer.gameH * s) / 2
        )
    }

    var lastTime: CFTimeInterval = 0

    // 5×7 bitmap font – 7 rows, each row = 5 bits (bit4 = leftmost)
    static let font: [Character: [UInt8]] = [
        "0": [0x0E,0x11,0x13,0x15,0x19,0x11,0x0E],
        "1": [0x04,0x0C,0x04,0x04,0x04,0x04,0x0E],
        "2": [0x0E,0x11,0x01,0x06,0x08,0x10,0x1F],
        "3": [0x1E,0x01,0x01,0x0E,0x01,0x01,0x1E],
        "4": [0x02,0x06,0x0A,0x12,0x1F,0x02,0x02],
        "5": [0x1F,0x10,0x10,0x1E,0x01,0x01,0x1E],
        "6": [0x06,0x08,0x10,0x1E,0x11,0x11,0x0E],
        "7": [0x1F,0x01,0x02,0x04,0x08,0x08,0x08],
        "8": [0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E],
        "9": [0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C],
        "A": [0x0E,0x11,0x11,0x1F,0x11,0x11,0x11],
        "B": [0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E],
        "C": [0x0E,0x11,0x10,0x10,0x10,0x11,0x0E],
        "D": [0x1E,0x11,0x11,0x11,0x11,0x11,0x1E],
        "E": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F],
        "F": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x10],
        "G": [0x0E,0x11,0x10,0x17,0x11,0x11,0x0F],
        "H": [0x11,0x11,0x11,0x1F,0x11,0x11,0x11],
        "I": [0x0E,0x04,0x04,0x04,0x04,0x04,0x0E],
        "K": [0x11,0x12,0x14,0x18,0x14,0x12,0x11],
        "L": [0x10,0x10,0x10,0x10,0x10,0x10,0x1F],
        "M": [0x11,0x1B,0x15,0x11,0x11,0x11,0x11],
        "N": [0x11,0x19,0x15,0x13,0x11,0x11,0x11],
        "O": [0x0E,0x11,0x11,0x11,0x11,0x11,0x0E],
        "P": [0x1E,0x11,0x11,0x1E,0x10,0x10,0x10],
        "R": [0x1E,0x11,0x11,0x1E,0x14,0x12,0x11],
        "S": [0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E],
        "T": [0x1F,0x04,0x04,0x04,0x04,0x04,0x04],
        "U": [0x11,0x11,0x11,0x11,0x11,0x11,0x0E],
        "V": [0x11,0x11,0x11,0x11,0x0A,0x0A,0x04],
        "W": [0x11,0x11,0x15,0x15,0x15,0x0A,0x0A],
        "X": [0x11,0x0A,0x04,0x04,0x04,0x0A,0x11],
        "Y": [0x11,0x11,0x0A,0x04,0x04,0x04,0x04],
        "Z": [0x1F,0x01,0x02,0x04,0x08,0x10,0x1F],
        " ": [0x00,0x00,0x00,0x00,0x00,0x00,0x00],
        ":": [0x00,0x04,0x04,0x00,0x04,0x04,0x00],
        "-": [0x00,0x00,0x00,0x1F,0x00,0x00,0x00],
        "!": [0x04,0x04,0x04,0x04,0x04,0x00,0x04],
        ".": [0x00,0x00,0x00,0x00,0x00,0x00,0x04],
        "+": [0x00,0x04,0x04,0x1F,0x04,0x04,0x00],
    ]

    // 8×8 alien pixel art – two animation frames each
    static let alienArt: [AlienType: [[UInt8]]] = [
        .squid:   [[0x18,0x3C,0x7E,0xDB,0xFF,0x5A,0x81,0x42],
                   [0x18,0x3C,0x7E,0xDB,0xFF,0xA5,0x24,0x00]],
        .crab:    [[0x42,0x24,0x7E,0xDB,0xFF,0x7E,0xA5,0x24],
                   [0x42,0x81,0xFF,0xDB,0xFF,0x7E,0x24,0x42]],
        .octopus: [[0x3C,0x7E,0xFF,0xDB,0xFF,0x3C,0x5A,0xA5],
                   [0x3C,0x7E,0xFF,0xDB,0xFF,0xA5,0x5A,0x00]],
    ]

    // Player ship: 9 cols × 6 rows
    static let playerArt: [UInt16] = [
        0b000010000,
        0b000111000,
        0b000111000,
        0b111111111,
        0b111111111,
        0b111111111,
    ]

    // UFO: 12 cols × 5 rows
    static let ufoArt: [UInt16] = [
        0b000111111000,
        0b011111111110,
        0b110110110110,
        0b111111111111,
        0b011011011010,
    ]

    init?(metalKitView: MTKView) {
        guard let dev = metalKitView.device,
              let queue = dev.makeCommandQueue() else { return nil }
        device = dev; commandQueue = queue

        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = .invalid
        metalKitView.clearColor = MTLClearColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1)
        metalKitView.preferredFramesPerSecond = 60

        guard let lib = dev.makeDefaultLibrary(),
              let vert = lib.makeFunction(name: "spriteVertex"),
              let frag = lib.makeFunction(name: "spriteFragment") else { return nil }

        func pipeline(dstBlend: MTLBlendFactor) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vert; d.fragmentFunction = frag
            d.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
            d.colorAttachments[0].isBlendingEnabled = true
            d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            d.colorAttachments[0].destinationRGBBlendFactor = dstBlend
            d.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            d.colorAttachments[0].destinationAlphaBlendFactor = dstBlend
            return try dev.makeRenderPipelineState(descriptor: d)
        }
        do {
            normalPipeline   = try pipeline(dstBlend: .oneMinusSourceAlpha)
            additivePipeline = try pipeline(dstBlend: .one)
        } catch { print("Pipeline error: \(error)"); return nil }

        super.init()

        let bufLen = Renderer.maxVertices * MemoryLayout<SpriteVertex>.stride
        normalBuffer   = dev.makeBuffer(length: bufLen, options: .storageModeShared)
        additiveBuffer = dev.makeBuffer(length: bufLen, options: .storageModeShared)

        // Normalized (0..1) star positions so they always fill the full drawable
        for _ in 0..<280 {
            stars.append((SIMD2(Float.random(in: 0...1), Float.random(in: 0...1)),
                          Float.random(in: 0.3...1.0),
                          Float.random(in: 0...(.pi * 2))))
        }
    }

    // MARK: - Primitive helpers

    @inline(__always)
    func quad(x: Float, y: Float, w: Float, h: Float, _ c: SIMD4<Float>, to arr: inout [SpriteVertex]) {
        let tl = SpriteVertex(position: SIMD2(x,   y),   color: c)
        let tr = SpriteVertex(position: SIMD2(x+w, y),   color: c)
        let bl = SpriteVertex(position: SIMD2(x,   y+h), color: c)
        let br = SpriteVertex(position: SIMD2(x+w, y+h), color: c)
        arr += [tl, tr, bl, tr, br, bl]
    }

    func pixelArt8(_ rows: [UInt8], x: Float, y: Float, s: Float, _ c: SIMD4<Float>, to arr: inout [SpriteVertex]) {
        for (row, byte) in rows.enumerated() {
            for col in 0..<8 where (byte >> (7-col)) & 1 == 1 {
                quad(x: x + Float(col)*s, y: y + Float(row)*s, w: s, h: s, c, to: &arr)
            }
        }
    }

    func pixelArt16(_ rows: [UInt16], bits: Int, x: Float, y: Float, s: Float, _ c: SIMD4<Float>, to arr: inout [SpriteVertex]) {
        for (row, word) in rows.enumerated() {
            for col in 0..<bits where (word >> (bits-1-col)) & 1 == 1 {
                quad(x: x + Float(col)*s, y: y + Float(row)*s, w: s, h: s, c, to: &arr)
            }
        }
    }

    func drawText(_ text: String, x: Float, y: Float, s: Float, _ c: SIMD4<Float>, to arr: inout [SpriteVertex]) {
        var cx = x
        for ch in text.uppercased() {
            if let rows = Self.font[ch] {
                for (row, byte) in rows.enumerated() {
                    for col in 0..<5 where (byte >> (4-col)) & 1 == 1 {
                        quad(x: cx + Float(col)*s, y: y + Float(row)*s, w: s, h: s, c, to: &arr)
                    }
                }
            }
            cx += 6 * s
        }
    }

    func textW(_ t: String, s: Float) -> Float { Float(t.count) * 6 * s }

    func drawTextC(_ text: String, cx: Float, y: Float, s: Float, _ c: SIMD4<Float>, to arr: inout [SpriteVertex]) {
        drawText(text, x: cx - textW(text, s: s) / 2, y: y, s: s, c, to: &arr)
    }

    // MARK: - Full-screen background (drawable space)

    func drawBackground(to arr: inout [SpriteVertex]) {
        let vx = viewSize.x, vy = viewSize.y

        // Subtle deep-space nebula blobs (additive)
        let nebulae: [(Float, Float, SIMD4<Float>)] = [
            (0.2, 0.3, SIMD4(0.05, 0.02, 0.12, 1)),
            (0.7, 0.6, SIMD4(0.02, 0.05, 0.10, 1)),
            (0.5, 0.15, SIMD4(0.06, 0.02, 0.08, 1)),
            (0.3, 0.8, SIMD4(0.02, 0.06, 0.08, 1)),
        ]
        for (nx, ny, nc) in nebulae {
            let pulse = 0.6 + 0.4 * sin(game.time * 0.3 + nx * 5)
            var c = nc; c.w = Float(pulse) * 0.8
            // Slow parallax drift (farthest layer), wrapping vertically.
            let baseY = ny * vy - 100
            let y = (baseY + game.time * 5).truncatingRemainder(dividingBy: vy + 200) - 100
            quad(x: nx*vx - 150, y: y, w: 300, h: 200, c, to: &additiveVerts)
        }

        // Parallax scrolling starfield: brighter (nearer) stars scroll faster.
        for (pos, bright, tw) in stars {
            let speed = 8 + bright * 55            // drawable px/sec by depth layer
            let y = (pos.y * vy + game.time * speed).truncatingRemainder(dividingBy: vy)
            let b = Float(bright) * (0.5 + 0.5 * sin(game.time * 1.2 + tw))
            let c: SIMD4<Float> = SIMD4(b*0.85, b*0.9, b, 1)
            let sz: Float = bright > 0.85 ? 2.5 : (bright > 0.65 ? 1.8 : 1.2)
            quad(x: pos.x * vx, y: y, w: sz, h: sz, c, to: &arr)
            // Brightest stars get a tiny additive cross-flare
            if bright > 0.92 {
                let f: SIMD4<Float> = SIMD4(b*0.5, b*0.55, b*0.6, 0.6)
                quad(x: pos.x*vx - sz, y: y, w: sz*3, h: sz*0.5, f, to: &additiveVerts)
                quad(x: pos.x*vx, y: y - sz, w: sz*0.5, h: sz*3, f, to: &additiveVerts)
            }
        }
    }

    // MARK: - Game entity drawing (game space 0..800, 0..600)

    func drawAlien(_ alien: Alien, to arr: inout [SpriteVertex]) {
        guard alien.entity.alive else { return }
        let frames = Self.alienArt[alien.type]!
        let frame  = frames[alien.animFrame & 1]
        let sc = alien.entity.size.x / 8
        let x  = alien.entity.position.x + (alien.isDiving ? 0 : game.formationX)
        let y  = alien.entity.position.y
        let c  = alien.entity.color
        pixelArt8(frame, x: x, y: y, s: sc, c, to: &arr)
        var glow = c; glow.w = 0.15
        pixelArt8(frame, x: x-0.5, y: y-0.5, s: sc+0.3, glow, to: &additiveVerts)
    }

    func drawPlayer(to arr: inout [SpriteVertex]) {
        guard game.playerAlive else { return }
        let e = game.player!
        let sc = e.size.x / 9
        let x  = e.position.x - e.size.x/2
        let y  = e.position.y - e.size.y/2
        var c  = e.color
        if game.hasShield { c = SIMD4(0.4 + 0.2*sin(game.time*8), 0.7, 1.0, 1) }
        pixelArt16(Self.playerArt, bits: 9, x: x, y: y, s: sc, c, to: &arr)
        let throb: Float = 0.5 + 0.5*sin(game.time*12)
        quad(x: e.position.x-5, y: e.position.y+e.size.y/2-2, w: 10, h: 7,
             SIMD4(0.2, 0.7, 1, 0.5*throb), to: &additiveVerts)
        if game.hasShield {
            let r: Float = 30; let seg = 32
            let sc2: SIMD4<Float> = SIMD4(0.4, 0.7, 1, 0.2+0.1*sin(game.time*5))
            for i in 0..<seg {
                let a0 = Float(i)/Float(seg) * .pi*2
                let a1 = Float(i+1)/Float(seg) * .pi*2
                let v0 = SpriteVertex(position: SIMD2(e.position.x+cos(a0)*r, e.position.y+sin(a0)*r), color: sc2)
                let v1 = SpriteVertex(position: SIMD2(e.position.x+cos(a1)*r, e.position.y+sin(a1)*r), color: sc2)
                let vc = SpriteVertex(position: e.position, color: SIMD4(0.4,0.7,1,0.04))
                additiveVerts += [v0,v1,vc]
            }
        }
    }

    func drawBullets(to arr: inout [SpriteVertex]) {
        for b in game.bullets {
            let e = b.entity
            let x = e.position.x - e.size.x/2; let y = e.position.y - e.size.y/2
            quad(x: x, y: y, w: e.size.x, h: e.size.y, e.color, to: &arr)
            var g = e.color; g.w = 0.4
            quad(x: x-e.size.x, y: y, w: e.size.x*3, h: e.size.y, g, to: &additiveVerts)
        }
    }

    func drawShields(to arr: inout [SpriteVertex]) {
        let ps = Shield.pixelSize
        let c: SIMD4<Float> = SIMD4(0.3, 0.95, 0.3, 1)
        for s in game.shields {
            for row in 0..<Shield.rows { for col in 0..<Shield.cols where s.pixels[row][col] {
                quad(x: s.position.x + Float(col)*ps, y: s.position.y + Float(row)*ps,
                     w: ps-0.5, h: ps-0.5, c, to: &arr)
            }}
        }
    }

    func drawUFO(to arr: inout [SpriteVertex]) {
        guard game.ufo.active else { return }
        let e = game.ufo.entity
        let sc = e.size.x / 12
        let x = e.position.x - e.size.x/2; let y = e.position.y - e.size.y/2
        pixelArt16(Self.ufoArt, bits: 12, x: x, y: y, s: sc, e.color, to: &arr)
        var g = e.color; g.w = 0.3+0.2*sin(game.time*10)
        quad(x: x-3, y: y-3, w: e.size.x+6, h: e.size.y+6, g, to: &additiveVerts)
    }

    func drawPowerUps(to arr: inout [SpriteVertex]) {
        for pu in game.powerUps {
            guard pu.entity.alive else { continue }
            let e = pu.entity; let bob = sin(pu.bobTimer*4)*3
            let x = e.position.x - e.size.x/2; let y = e.position.y - e.size.y/2 + bob
            quad(x: x, y: y, w: e.size.x, h: e.size.y, e.color, to: &arr)
            var g = e.color; g.w = 0.5 + 0.3*sin(pu.bobTimer*5)
            quad(x: x-4, y: y-4, w: e.size.x+8, h: e.size.y+8, g, to: &additiveVerts)
            let label: String
            switch pu.type {
            case .rapidFire: label = "R"; case .spreadShot: label = "S"
            case .laser: label = "L"; case .extraLife: label = "+"; case .shield: label = "B"
            }
            drawTextC(label, cx: e.position.x, y: y+2, s: 3, SIMD4(0,0,0,1), to: &arr)
        }
    }

    func drawParticles(to arr: inout [SpriteVertex]) {
        for p in game.particles {
            var c = p.color; c.w = p.life * p.life
            quad(x: p.position.x-p.size/2, y: p.position.y-p.size/2, w: p.size, h: p.size, c, to: &arr)
        }
    }

    func drawHUD(to arr: inout [SpriteVertex]) {
        let W = Renderer.gameW, H = Renderer.gameH
        drawText("SCORE:\(game.score)", x: 10, y: 8, s: 2, SIMD4(0.3,1,0.3,1), to: &arr)
        let hi = game.highScores.first?.score ?? 0
        drawTextC("HI:\(hi)", cx: W/2, y: 8, s: 2, SIMD4(1,0.8,0.2,1), to: &arr)
        let lvl = "LVL:\(game.level)"
        drawText(lvl, x: W - textW(lvl, s: 2) - 10, y: 8, s: 2, SIMD4(0.6,0.6,1,1), to: &arr)
        let wv = "WAVE \(game.wave)/3"
        drawText(wv, x: W - textW(wv, s: 1.5) - 10, y: 24, s: 1.5, SIMD4(1,0.5,0.9,1), to: &arr)

        for i in 0..<game.lives {
            pixelArt16(Self.playerArt, bits: 9, x: 10 + Float(i)*22, y: H-20, s: 1.8, SIMD4(0.2,1,0.4,1), to: &arr)
        }

        if let pu = game.activePowerUp {
            let (label, c): (String, SIMD4<Float>) = {
                switch pu {
                case .rapidFire:  return ("RAPID FIRE", SIMD4(1,0.8,0.2,1))
                case .spreadShot: return ("SPREAD",     SIMD4(0.2,1,1,1))
                case .laser:      return ("LASER",      SIMD4(1,0.3,0.3,1))
                case .extraLife:  return ("EXTRA LIFE", SIMD4(0.2,1,0.2,1))
                case .shield:     return ("SHIELD",     SIMD4(0.4,0.7,1,1))
                }
            }()
            var blink = c; blink.w = 0.6 + 0.4*sin(game.time*6)
            drawTextC(label, cx: W/2, y: H-20, s: 2, blink, to: &arr)
        }

        quad(x: 0, y: H-32, w: W, h: 1.5, SIMD4(0.3,0.9,0.3,0.7), to: &arr)
        quad(x: 0, y: 28,   w: W, h: 1.5, SIMD4(0.3,0.9,0.3,0.5), to: &arr)
    }

    // MARK: - Screens

    func drawSplash(to arr: inout [SpriteVertex]) {
        let W = Renderer.gameW, H = Renderer.gameH; let cx = W/2
        let title = "NEON INVADERS"; let ts: Float = 3.5
        let tw = textW(title, s: ts)
        var tx = cx - tw/2
        for (i, ch) in title.enumerated() {
            let hue = (Float(i)/Float(title.count) + game.time*0.15).truncatingRemainder(dividingBy: 1)
            let c = hsvToRgb(hue, 1, 1)
            let bounce = sin(game.time*3 + Float(i)*0.5) * ts * 1.5
            drawText(String(ch), x: tx, y: H*0.12 - bounce, s: ts, c, to: &arr)
            tx += 6*ts
        }

        drawTextC("HIGH SCORES", cx: cx, y: H*0.30, s: 3, SIMD4(1,0.8,0.2,1), to: &arr)
        quad(x: cx-130, y: H*0.30+24, w: 260, h: 2, SIMD4(1,0.8,0.2,0.6), to: &arr)

        let rankColors: [SIMD4<Float>] = [
            SIMD4(1,0.85,0.1,1), SIMD4(0.8,0.8,0.8,1), SIMD4(0.8,0.55,0.3,1),
            SIMD4(0.7,0.9,1,1), SIMD4(0.7,0.9,1,1)
        ]
        for (i, hs) in game.highScores.prefix(5).enumerated() {
            let ry = H*0.38 + Float(i)*28; let c = rankColors[i]
            drawText("#\(i+1)", x: cx-130, y: ry, s: 2, c, to: &arr)
            drawText("\(hs.score)", x: cx-60, y: ry, s: 2, c, to: &arr)
            drawText("LVL \(hs.level)", x: cx+60, y: ry, s: 2, c, to: &arr)
        }

        let demos: [(AlienType, SIMD4<Float>, String)] = [
            (.squid,   SIMD4(0.5,0.5,1,1),  "= 30 PTS"),
            (.crab,    SIMD4(0.3,1,1,1),    "= 20 PTS"),
            (.octopus, SIMD4(0.9,0.4,1,1),  "= 10 PTS"),
        ]
        let af = Int(game.time*2) & 1
        for (i, demo) in demos.enumerated() {
            let (t, c, pts) = demo
            let dy = H*0.66 + Float(i)*32
            pixelArt8(Self.alienArt[t]![af], x: cx-80, y: dy, s: 3, c, to: &arr)
            drawText(pts, x: cx-40, y: dy+8, s: 2, c, to: &arr)
        }
        let uy = H*0.66 + 3*32
        pixelArt16(Self.ufoArt, bits: 12, x: cx-88, y: uy, s: 2.5, SIMD4(1,0.2,0.8,1), to: &arr)
        drawText("= ??? PTS", x: cx-40, y: uy+6, s: 2, SIMD4(1,0.2,0.8,1), to: &arr)

        if Int(game.time*2) & 1 == 0 {
            #if os(iOS)
            let prompt = "TAP TO PLAY"
            #else
            let prompt = "PRESS SPACE TO PLAY"
            #endif
            drawTextC(prompt, cx: cx, y: H*0.88, s: 2.5, SIMD4(0.3,1,0.3,1), to: &arr)
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        drawTextC("COPYRIGHT RYAN RIFE   V\(version)", cx: cx, y: H*0.95, s: 1.5, SIMD4(0.5,0.5,0.6,1), to: &arr)
    }

    func drawGameOver(to arr: inout [SpriteVertex]) {
        let cx = Renderer.gameW/2; let H = Renderer.gameH
        let pulse = 0.6 + 0.4*sin(game.time*4)
        drawTextC("GAME OVER", cx: cx, y: H*0.33, s: 5.5, SIMD4(1,0.2,0.2,Float(pulse)), to: &arr)
        drawTextC("SCORE:\(game.score)", cx: cx, y: H*0.52, s: 3, SIMD4(1,0.8,0.2,1), to: &arr)
        if Int(game.time*1.5) & 1 == 0 {
            #if os(iOS)
            drawTextC("TAP TO CONTINUE", cx: cx, y: H*0.70, s: 2.5, SIMD4(0.8,0.8,0.8,1), to: &arr)
            #else
            drawTextC("PRESS SPACE", cx: cx, y: H*0.70, s: 2.5, SIMD4(0.8,0.8,0.8,1), to: &arr)
            #endif
        }
    }

    func drawLevelBanner(to arr: inout [SpriteVertex]) {
        let cx = Renderer.gameW/2; let H = Renderer.gameH
        let pulse = 0.7 + 0.3*sin(game.time*5)
        let title = game.isLevelTransition ? "LEVEL \(game.level)" : "WAVE \(game.wave)"
        drawTextC(title, cx: cx, y: H*0.38, s: 4, SIMD4(0.3,1,0.5,Float(pulse)), to: &arr)
        drawTextC("SCORE:\(game.score)", cx: cx, y: H*0.50, s: 2.5, SIMD4(1,0.8,0.2,1), to: &arr)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = SIMD2(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = lastTime > 0 ? min(Float(now - lastTime), 0.05) : 1/60
        lastTime = now
        game.update(dt: dt)

        normalVerts.removeAll(keepingCapacity: true)
        additiveVerts.removeAll(keepingCapacity: true)

        // --- Phase 1: full-screen background in drawable space (not transformed) ---
        drawBackground(to: &normalVerts)
        let bgNormal   = normalVerts.count
        let bgAdditive = additiveVerts.count

        // --- Phase 2: game content in logical game space (0..800, 0..600) ---
        switch game.phase {
        case .splash:
            drawSplash(to: &normalVerts)
        case .playing:
            for a in game.aliens { drawAlien(a, to: &normalVerts) }
            drawShields(to: &normalVerts)
            drawPowerUps(to: &normalVerts)
            drawBullets(to: &normalVerts)
            drawUFO(to: &normalVerts)
            drawPlayer(to: &normalVerts)
            drawParticles(to: &additiveVerts)
            drawHUD(to: &normalVerts)
        case .levelTransition:
            for a in game.aliens { drawAlien(a, to: &normalVerts) }
            drawShields(to: &normalVerts)
            drawPlayer(to: &normalVerts)
            drawParticles(to: &additiveVerts)
            drawHUD(to: &normalVerts)
            drawLevelBanner(to: &normalVerts)
        case .gameOver:
            for a in game.aliens { drawAlien(a, to: &normalVerts) }
            drawShields(to: &normalVerts)
            drawBullets(to: &normalVerts)
            drawPlayer(to: &normalVerts)
            drawParticles(to: &additiveVerts)
            drawHUD(to: &normalVerts)
            drawGameOver(to: &normalVerts)
        }

        // Screen flash (game space — will be scaled with everything else)
        if game.screenFlash > 0 {
            var fc = game.screenFlashColor; fc.w = game.screenFlash * 0.35
            quad(x: 0, y: 0, w: Renderer.gameW, h: Renderer.gameH, fc, to: &additiveVerts)
        }

        // --- Phase 3: apply letterbox transform to game content only ---
        let s = gameScale; let off = gameOffset
        for i in bgNormal..<normalVerts.count {
            normalVerts[i].position = normalVerts[i].position * s + off
        }
        for i in bgAdditive..<additiveVerts.count {
            additiveVerts[i].position = additiveVerts[i].position * s + off
        }

        // --- Submit ---
        guard let rpd = view.currentRenderPassDescriptor,
              let cb  = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }

        var uniforms = GameUniforms(resolution: viewSize, time: game.time, padding: 0)

        func submit(_ verts: [SpriteVertex], gpuBuf: MTLBuffer, pipeline: MTLRenderPipelineState) {
            guard !verts.isEmpty else { return }
            let byteLen = verts.count * MemoryLayout<SpriteVertex>.stride
            verts.withUnsafeBytes { gpuBuf.contents().copyMemory(from: $0.baseAddress!, byteCount: byteLen) }
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<GameUniforms>.stride, index: 1)
            enc.setVertexBuffer(gpuBuf, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
        }

        submit(normalVerts,   gpuBuf: normalBuffer,   pipeline: normalPipeline)
        submit(additiveVerts, gpuBuf: additiveBuffer, pipeline: additivePipeline)

        enc.endEncoding()
        if let drawable = view.currentDrawable { cb.present(drawable) }
        cb.commit()
    }

    // MARK: - Utility

    func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> SIMD4<Float> {
        let i = Int(h * 6); let f = h * 6 - Float(i)
        let p = v*(1-s), q = v*(1-f*s), t = v*(1-(1-f)*s)
        switch i % 6 {
        case 0: return SIMD4(v,t,p,1); case 1: return SIMD4(q,v,p,1)
        case 2: return SIMD4(p,v,t,1); case 3: return SIMD4(p,q,v,1)
        case 4: return SIMD4(t,p,v,1); default: return SIMD4(v,p,q,1)
        }
    }
}
