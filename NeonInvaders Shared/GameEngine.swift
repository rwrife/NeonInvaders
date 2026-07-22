//
//  GameEngine.swift
//  NeonInvaders Shared
//

import Foundation
import CoreGraphics
import simd

enum GamePhase {
    case splash, playing, levelTransition, gameOver
}

enum PowerUpType: CaseIterable {
    case rapidFire, spreadShot, laser, extraLife, shield
}

enum AlienType: Int {
    case squid = 0
    case crab = 1
    case octopus = 2
}

struct GameEntity {
    var position: SIMD2<Float>
    var size: SIMD2<Float>
    var color: SIMD4<Float>
    var alive: Bool = true
}

struct Alien {
    var entity: GameEntity
    var type: AlienType
    var animFrame: Int = 0
    var shootTimer: Float
}

struct Bullet {
    var entity: GameEntity
    var velocity: SIMD2<Float>
    var isPlayerBullet: Bool
    var isPowerful: Bool = false
}

struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var maxLife: Float
    var color: SIMD4<Float>
    var size: Float
}

struct PowerUp {
    var entity: GameEntity
    var velocity: SIMD2<Float> = SIMD2(0, 60)
    var type: PowerUpType
    var bobTimer: Float = 0
}

struct Shield {
    var position: SIMD2<Float>
    var pixels: [[Bool]]
    static let cols = 22
    static let rows = 14
    static let pixelSize: Float = 3.5
}

struct UFO {
    var entity: GameEntity
    var velocity: SIMD2<Float>
    var points: Int
    var active: Bool = false
}

struct HighScore {
    var score: Int
    var level: Int
}

class GameEngine {

    // Game world dimensions (logical pixels)
    let W: Float = 800
    let H: Float = 600
    let alienCols = 11
    let alienRows = 5
    let alienW: Float = 34
    let alienH: Float = 24
    let alienGapX: Float = 14
    let alienGapY: Float = 14
    let playerSpeed: Float = 220
    let bulletSpeed: Float = 380
    let alienBulletSpeed: Float = 170

    var phase: GamePhase = .splash
    var score: Int = 0
    var lives: Int = 3
    var level: Int = 1
    var highScores: [HighScore] = []

    var player: GameEntity!
    var playerAlive = true
    var playerDeathTimer: Float = 0

    var aliens: [Alien] = []
    var formationX: Float = 0
    var formationVelX: Float = 40
    var alienAnimTimer: Float = 0
    var alienAnimFrame: Int = 0

    var bullets: [Bullet] = []
    var particles: [Particle] = []
    var powerUps: [PowerUp] = []
    var shields: [Shield] = []
    var ufo: UFO!
    var ufoSpawnTimer: Float = 20

    var spreadShot = false
    var rapidFire = false
    var hasShield = false
    var activePowerUp: PowerUpType? = nil
    var powerUpTimer: Float = 0

    var moveLeft = false
    var moveRight = false
    var firePressed = false
    var firePressedPrev = false

    var time: Float = 0
    var levelTransitionTimer: Float = 0
    var screenFlash: Float = 0
    var screenFlashColor: SIMD4<Float> = .zero

    init() { loadHighScores() }

    // MARK: - High scores

    func loadHighScores() {
        if let arr = UserDefaults.standard.array(forKey: "NeonHighScores") as? [[String: Int]] {
            highScores = arr.compactMap {
                guard let s = $0["score"], let l = $0["level"] else { return nil }
                return HighScore(score: s, level: l)
            }.sorted { $0.score > $1.score }
        }
        if highScores.isEmpty {
            highScores = [5000, 3500, 2000, 1200, 500].enumerated().map {
                HighScore(score: $0.element, level: max(1, $0.offset))
            }
        }
    }

    func saveHighScore() {
        var all = highScores
        all.append(HighScore(score: score, level: level))
        all.sort { $0.score > $1.score }
        if all.count > 10 { all = Array(all.prefix(10)) }
        highScores = all
        UserDefaults.standard.set(all.map { ["score": $0.score, "level": $0.level] }, forKey: "NeonHighScores")
    }

    // MARK: - Setup

    func startGame() {
        score = 0; lives = 3; level = 1
        phase = .playing
        setupLevel()
    }

    func setupLevel() {
        player = GameEntity(position: SIMD2(W/2, H-55), size: SIMD2(42, 22), color: SIMD4(0.2, 1, 0.4, 1))
        playerAlive = true; playerDeathTimer = 0
        bullets.removeAll(); powerUps.removeAll(); particles.removeAll()
        spreadShot = false; rapidFire = false; hasShield = false; activePowerUp = nil; powerUpTimer = 0
        setupAliens()
        setupShields()
        ufo = UFO(entity: GameEntity(position: SIMD2(-60, 48), size: SIMD2(44, 20), color: SIMD4(1, 0.2, 0.8, 1)),
                  velocity: SIMD2(130, 0), points: 150)
        ufoSpawnTimer = Float.random(in: 15...30)
        formationX = 0
        formationVelX = 40 + Float(level - 1) * 7
    }

    func setupAliens() {
        aliens.removeAll()
        let startX: Float = 90
        let startY: Float = 95
        for row in 0..<alienRows {
            for col in 0..<alienCols {
                let (type, color): (AlienType, SIMD4<Float>) = {
                    if row == 0 { return (.squid, SIMD4(0.5, 0.5, 1, 1)) }
                    else if row < 3 { return (.crab, SIMD4(0.3, 1, 1, 1)) }
                    else { return (.octopus, SIMD4(0.9, 0.4, 1, 1)) }
                }()
                let pos = SIMD2(startX + Float(col) * (alienW + alienGapX),
                                startY + Float(row) * (alienH + alienGapY))
                let e = GameEntity(position: pos, size: SIMD2(alienW, alienH), color: color)
                aliens.append(Alien(entity: e, type: type, shootTimer: Float.random(in: 0.5...3)))
            }
        }
    }

    func setupShields() {
        shields.removeAll()
        for i in 0..<4 {
            let x = W / 5 * Float(i + 1) - Float(Shield.cols) * Shield.pixelSize / 2
            var pixels = [[Bool]](repeating: [Bool](repeating: true, count: Shield.cols), count: Shield.rows)
            for r in 0..<5 { for c in 7..<15 { pixels[Shield.rows - 1 - r][c] = false } }
            shields.append(Shield(position: SIMD2(x, H - 155), pixels: pixels))
        }
    }

    // MARK: - Update

    func update(dt: Float) {
        time += dt
        if screenFlash > 0 { screenFlash = max(0, screenFlash - dt * 3) }
        switch phase {
        case .splash: break
        case .playing: updatePlaying(dt: dt)
        case .levelTransition:
            levelTransitionTimer -= dt
            if levelTransitionTimer <= 0 { setupLevel(); phase = .playing }
        case .gameOver: break
        }
        updateParticles(dt: dt)
    }

    func updatePlaying(dt: Float) {
        if !playerAlive {
            playerDeathTimer -= dt
            if playerDeathTimer <= 0 {
                lives -= 1
                if lives <= 0 { phase = .gameOver; saveHighScore() }
                else { playerAlive = true; player.position = SIMD2(W/2, H-55) }
            }
        } else {
            updatePlayer(dt: dt)
        }
        updateAliens(dt: dt)
        updateBullets(dt: dt)
        updatePowerUps(dt: dt)
        updateUFO(dt: dt)
        checkCollisions()

        if activePowerUp != nil {
            powerUpTimer -= dt
            if powerUpTimer <= 0 { activePowerUp = nil; spreadShot = false; rapidFire = false; hasShield = false }
        }

        if aliens.filter({ $0.entity.alive }).isEmpty {
            level += 1; levelTransitionTimer = 2.5; phase = .levelTransition
            flashScreen(SIMD4(1, 1, 0.5, 1))
            for _ in 0..<80 { spawnParticle(at: SIMD2(Float.random(in: 0...W), Float.random(in: 0...H*0.6)), color: randomNeon(), speed: 200) }
        }
    }

    func updatePlayer(dt: Float) {
        var vx: Float = 0
        if moveLeft  { vx -= playerSpeed }
        if moveRight { vx += playerSpeed }
        player.position.x = max(player.size.x/2 + 10, min(W - player.size.x/2 - 10, player.position.x + vx * dt))

        let fireJust = firePressed && !firePressedPrev
        firePressedPrev = firePressed
        let maxB = rapidFire ? 5 : 2
        if fireJust && bullets.filter({ $0.isPlayerBullet }).count < maxB { fireBullet() }
    }

    func fireBullet() {
        let pos = player.position - SIMD2(0, player.size.y/2)
        if spreadShot {
            for angle: Float in [-.pi/2, -.pi/2 - 0.28, -.pi/2 + 0.28] {
                let vel = SIMD2(cos(angle), sin(angle)) * bulletSpeed
                bullets.append(Bullet(entity: GameEntity(position: pos, size: SIMD2(4, 14), color: SIMD4(0.3, 1, 0.3, 1)), velocity: vel, isPlayerBullet: true))
            }
        } else if activePowerUp == .laser {
            bullets.append(Bullet(entity: GameEntity(position: pos, size: SIMD2(5, 30), color: SIMD4(1, 0.2, 0.2, 1)), velocity: SIMD2(0, -bulletSpeed * 1.6), isPlayerBullet: true, isPowerful: true))
        } else {
            bullets.append(Bullet(entity: GameEntity(position: pos, size: SIMD2(4, 16), color: SIMD4(0.3, 1, 0.3, 1)), velocity: SIMD2(0, -bulletSpeed), isPlayerBullet: true))
        }
    }

    func updateAliens(dt: Float) {
        alienAnimTimer += dt
        if alienAnimTimer > 0.45 { alienAnimTimer = 0; alienAnimFrame = 1 - alienAnimFrame }
        let alive = aliens.filter { $0.entity.alive }
        guard !alive.isEmpty else { return }

        let speedMult: Float = 1 + (Float(alienCols * alienRows) - Float(alive.count)) / Float(alienCols * alienRows) * 3.0
        formationX += formationVelX * speedMult * dt

        let left  = alive.map { $0.entity.position.x + formationX }.min()!
        let right = alive.map { $0.entity.position.x + formationX + $0.entity.size.x }.max()!
        if right >= W - 15 || left <= 15 {
            formationVelX = -formationVelX
            for i in 0..<aliens.count { aliens[i].entity.position.y += 18 }
        }

        let maxY = alive.map { $0.entity.position.y + $0.entity.size.y }.max()!
        if maxY >= H - 100 { killPlayer() }

        let shootDelay = max(0.25, 1.5 - Float(level - 1) * 0.1)
        for i in 0..<aliens.count {
            guard aliens[i].entity.alive else { continue }
            aliens[i].animFrame = alienAnimFrame
            aliens[i].shootTimer -= dt
            if aliens[i].shootTimer <= 0 {
                aliens[i].shootTimer = Float.random(in: shootDelay...shootDelay * 3)
                let col = i % alienCols; let row = i / alienCols
                var lowest = true
                for r in (row+1)..<alienRows {
                    if aliens[r * alienCols + col].entity.alive { lowest = false; break }
                }
                if lowest {
                    let ap = SIMD2(aliens[i].entity.position.x + formationX + aliens[i].entity.size.x/2,
                                   aliens[i].entity.position.y + aliens[i].entity.size.y)
                    bullets.append(Bullet(entity: GameEntity(position: ap, size: SIMD2(4, 12), color: SIMD4(1, 0.5, 0.1, 1)),
                                         velocity: SIMD2(Float.random(in: -25...25), alienBulletSpeed), isPlayerBullet: false))
                }
            }
        }
    }

    func updateBullets(dt: Float) {
        for i in 0..<bullets.count { bullets[i].entity.position += bullets[i].velocity * dt }
        bullets.removeAll { b in
            b.entity.position.y < -40 || b.entity.position.y > H + 40 ||
            b.entity.position.x < -40 || b.entity.position.x > W + 40
        }
    }

    func updatePowerUps(dt: Float) {
        for i in 0..<powerUps.count {
            powerUps[i].entity.position += powerUps[i].velocity * dt
            powerUps[i].bobTimer += dt
        }
        powerUps.removeAll { !$0.entity.alive || $0.entity.position.y > H + 30 }
    }

    func updateUFO(dt: Float) {
        if ufo.active {
            ufo.entity.position.x += ufo.velocity.x * dt
            if ufo.entity.position.x > W + 80 || ufo.entity.position.x < -80 {
                ufo.active = false; ufoSpawnTimer = Float.random(in: 15...30)
            }
        } else {
            ufoSpawnTimer -= dt
            if ufoSpawnTimer <= 0 {
                let goRight = Bool.random()
                ufo.entity.position = SIMD2(goRight ? -60 : W + 60, 46)
                ufo.velocity.x = goRight ? 130 : -130
                ufo.points = [50, 100, 150, 200, 300].randomElement()!
                ufo.active = true
            }
        }
    }

    func checkCollisions() {
        let pr = erect(player)
        for bi in 0..<bullets.count {
            guard bullets[bi].entity.alive else { continue }
            let br = erect(bullets[bi].entity)
            if bullets[bi].isPlayerBullet {
                for ai in 0..<aliens.count {
                    guard aliens[ai].entity.alive else { continue }
                    var ae = aliens[ai].entity; ae.position.x += formationX
                    if br.intersects(erect(ae)) {
                        killAlien(ai)
                        if !bullets[bi].isPowerful { bullets[bi].entity.alive = false }
                        break
                    }
                }
                if ufo.active, br.intersects(erect(ufo.entity)) {
                    score += ufo.points; ufo.active = false; ufoSpawnTimer = Float.random(in: 15...30)
                    spawnExplosion(at: ufo.entity.position, color: SIMD4(1, 0.2, 0.8, 1), count: 24)
                    flashScreen(SIMD4(1, 0.5, 0.5, 1))
                    bullets[bi].entity.alive = false
                }
                damageBulletVsShields(bi: bi)
            } else if playerAlive {
                if pr.intersects(br) {
                    bullets[bi].entity.alive = false
                    if hasShield {
                        hasShield = false; activePowerUp = nil
                        spawnExplosion(at: player.position, color: SIMD4(0.4, 0.8, 1, 1), count: 16)
                    } else {
                        killPlayer()
                    }
                }
                damageBulletVsShields(bi: bi)
            }
        }
        bullets.removeAll { !$0.entity.alive }

        for i in 0..<powerUps.count {
            guard powerUps[i].entity.alive else { continue }
            if pr.intersects(erect(powerUps[i].entity)) {
                collectPowerUp(powerUps[i].type)
                powerUps[i].entity.alive = false
                spawnExplosion(at: powerUps[i].entity.position, color: SIMD4(1, 1, 0.3, 1), count: 20)
            }
        }
    }

    func damageBulletVsShields(bi: Int) {
        guard bullets[bi].entity.alive else { return }
        let bp = bullets[bi].entity.position
        for si in 0..<shields.count {
            let s = shields[si]
            let sw = Float(Shield.cols) * Shield.pixelSize
            let sh = Float(Shield.rows) * Shield.pixelSize
            guard bp.x >= s.position.x && bp.x <= s.position.x + sw &&
                  bp.y >= s.position.y && bp.y <= s.position.y + sh else { continue }
            let px = Int((bp.x - s.position.x) / Shield.pixelSize)
            let py = Int((bp.y - s.position.y) / Shield.pixelSize)
            if px >= 0 && px < Shield.cols && py >= 0 && py < Shield.rows && shields[si].pixels[py][px] {
                shields[si].pixels[py][px] = false
                for dy in -1...1 { for dx in -1...1 {
                    let nx = px+dx, ny = py+dy
                    if nx >= 0 && nx < Shield.cols && ny >= 0 && ny < Shield.rows && Bool.random() {
                        shields[si].pixels[ny][nx] = false
                    }
                }}
                bullets[bi].entity.alive = false
                spawnExplosion(at: bp, color: SIMD4(0.4, 1, 0.4, 1), count: 6)
                return
            }
        }
    }

    func killAlien(_ i: Int) {
        var pos = aliens[i].entity.position; pos.x += formationX; pos += aliens[i].entity.size / 2
        let color = aliens[i].entity.color
        aliens[i].entity.alive = false
        let pts = [10, 20, 30][aliens[i].type.rawValue] * level
        score += pts
        spawnExplosion(at: pos, color: color, count: 18)
        flashScreen(SIMD4(color.x * 0.3, color.y * 0.3, color.z * 0.3, 1))
        if Float.random(in: 0...1) < 0.14 {
            let t = PowerUpType.allCases.randomElement()!
            powerUps.append(PowerUp(entity: GameEntity(position: pos, size: SIMD2(18, 18), color: powerUpColor(t)), type: t))
        }
    }

    func killPlayer() {
        guard playerAlive else { return }
        playerAlive = false; playerDeathTimer = 2.0
        spawnExplosion(at: player.position, color: SIMD4(0.2, 1, 0.4, 1), count: 50)
        flashScreen(SIMD4(0.5, 1, 0.5, 1))
        // Mark dead rather than removeAll — safe to call inside a bullets iteration loop
        for i in 0..<bullets.count where bullets[i].isPlayerBullet {
            bullets[i].entity.alive = false
        }
    }

    func collectPowerUp(_ t: PowerUpType) {
        activePowerUp = t; powerUpTimer = 10
        spreadShot = false; rapidFire = false; hasShield = false
        switch t {
        case .rapidFire:  rapidFire = true
        case .spreadShot: spreadShot = true
        case .laser:      break
        case .extraLife:  lives = min(lives + 1, 5)
        case .shield:     hasShield = true
        }
    }

    // MARK: - Particles

    func spawnParticle(at pos: SIMD2<Float>, color: SIMD4<Float>, speed: Float) {
        let angle = Float.random(in: 0...(.pi * 2))
        let s = Float.random(in: speed * 0.3...speed)
        particles.append(Particle(position: pos, velocity: SIMD2(cos(angle)*s, sin(angle)*s),
                                  life: 1, maxLife: Float.random(in: 0.5...1.5),
                                  color: color, size: Float.random(in: 2...5)))
    }

    func spawnExplosion(at pos: SIMD2<Float>, color: SIMD4<Float>, count: Int) {
        for _ in 0..<count { spawnParticle(at: pos, color: jitter(color), speed: 160) }
    }

    func updateParticles(dt: Float) {
        for i in 0..<particles.count {
            particles[i].position += particles[i].velocity * dt
            particles[i].velocity *= 0.93
            particles[i].life -= dt / particles[i].maxLife
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: - Helpers

    func flashScreen(_ color: SIMD4<Float>) { screenFlash = 1; screenFlashColor = color }

    func erect(_ e: GameEntity) -> CGRect {
        CGRect(x: CGFloat(e.position.x - e.size.x/2), y: CGFloat(e.position.y - e.size.y/2),
               width: CGFloat(e.size.x), height: CGFloat(e.size.y))
    }

    func powerUpColor(_ t: PowerUpType) -> SIMD4<Float> {
        switch t {
        case .rapidFire:  return SIMD4(1.0, 0.8, 0.0, 1)
        case .spreadShot: return SIMD4(0.0, 1.0, 1.0, 1)
        case .laser:      return SIMD4(1.0, 0.2, 0.2, 1)
        case .extraLife:  return SIMD4(0.2, 1.0, 0.2, 1)
        case .shield:     return SIMD4(0.4, 0.7, 1.0, 1)
        }
    }

    func jitter(_ c: SIMD4<Float>) -> SIMD4<Float> {
        let r = SIMD4<Float>(Float.random(in: -0.2...0.2), Float.random(in: -0.2...0.2), Float.random(in: -0.2...0.2), 0)
        return clamp(c + r, min: SIMD4(0,0,0,0.6), max: SIMD4(1,1,1,1))
    }

    func randomNeon() -> SIMD4<Float> {
        [[SIMD4<Float>]([ SIMD4(0.2,1,1,1), SIMD4(1,0.2,1,1), SIMD4(0.2,1,0.4,1),
                          SIMD4(1,0.8,0.2,1), SIMD4(0.5,0.5,1,1), SIMD4(1,0.3,0.3,1)])].first!.randomElement()!
    }

    // MARK: - Input

    func handleTap() {
        switch phase {
        case .splash:   startGame()
        case .gameOver: phase = .splash
        default: break
        }
    }
}
