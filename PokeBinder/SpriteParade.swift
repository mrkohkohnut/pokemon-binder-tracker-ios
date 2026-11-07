import SwiftUI

/// Little things a Pokémon can get up to in the background.
enum Antic: CaseIterable {
    case walk, hop, wave, spin, sleep, dance, backflip
}

/// One Pokémon on stage: who it is, what it does, and where it lives (positions are 0…1 fractions).
struct Actor: Identifiable {
    let id: Int
    let pokemon: Int
    let antic: Antic
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let speed: Double
    let phase: Double

    /// Pokémon fans will recognise, used until you've caught your own.
    static let favourites = [25, 1, 4, 7, 133, 39, 52, 54, 143, 151, 175, 255, 258, 252, 152, 155, 158,
                             387, 390, 393, 495, 498, 501, 650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912]

    /// A cast drawn mostly from the Pokémon you've caught, topped up with favourites.
    static func cast(count: Int, caught: [Int], antics: [Antic] = Antic.allCases,
                     ys: ClosedRange<CGFloat> = 0.05...0.95, sizes: ClosedRange<CGFloat> = 44...64) -> [Actor] {
        let pool = (caught.shuffled().prefix(count / 2 + 1) + favourites.shuffled()).uniqued().prefix(count)
        return pool.enumerated().map { index, pokemon in
            Actor(id: index, pokemon: pokemon, antic: antics[index % antics.count],
                  // Spread across the width so they don't bunch up.
                  x: (CGFloat(index) + .random(in: 0.2...0.8)) / CGFloat(count),
                  y: .random(in: ys), size: .random(in: sizes),
                  speed: .random(in: 0.8...1.25), phase: .random(in: 0...10))
        }
    }

    var spriteURL: URL { URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(pokemon).png")! }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// Where an actor is and how it's posed at a moment in time.
struct Pose {
    var x: CGFloat = 0
    var lift: CGFloat = 0
    var angle: Double = 0
    var spin: Double = 0
    var facingRight = false
    var squash: CGFloat = 1
    var emote: String?
    var emoteAngle: Double = 0
    var emoteRise: CGFloat = 0

    // ponytail: hand-tuned closed-form motion, no physics; tweak the numbers to taste.
    static func of(_ a: Actor, at time: Double, width: CGFloat) -> Pose {
        let t = time * a.speed + a.phase
        let home = a.x * width
        var p = Pose(x: home)
        func frac(_ v: Double) -> Double { v - floor(v) }

        switch a.antic {
        case .walk:
            // Stroll back and forth across a stretch of the screen, bobbing with each step.
            let range = min(width * 0.35, 160)
            let cycle = frac(t / 12)
            let there = cycle < 0.5
            let q = there ? cycle * 2 : 2 - cycle * 2
            p.x = home - range / 2 + q * range
            p.facingRight = there // PokeAPI sprites face left.
            p.lift = -abs(sin(t * 9)) * 4
            p.angle = sin(t * 9) * 4
        case .hop:
            let cycle = frac(t / 1.4)
            if cycle < 0.45 {
                p.lift = -sin(cycle / 0.45 * .pi) * 26
            } else if cycle < 0.58 {
                p.squash = 0.86 // Squish on landing.
            }
            p.facingRight = Int(t / 4.2) % 2 == 0
        case .wave:
            p.angle = sin(t * 6) * 8
            p.emote = "hand.wave.fill"
            p.emoteAngle = sin(t * 10) * 28
        case .spin:
            let cycle = frac(t / 3.2)
            if cycle < 0.35 {
                let s = cycle / 0.35
                p.spin = s * 360
                p.lift = -sin(s * .pi) * 18
                p.emote = "sparkles"
            }
        case .sleep:
            p.squash = 1 + sin(t * 1.8) * 0.04
            p.angle = -6
            p.emote = "zzz"
            p.emoteRise = -CGFloat(frac(t / 2.5)) * 14
        case .dance:
            p.angle = sin(t * 5) * 14
            p.lift = -abs(sin(t * 5)) * 9
            p.facingRight = sin(t * 2.5) > 0
            p.emote = "music.note"
            p.emoteAngle = sin(t * 5) * 15
            p.emoteRise = -abs(sin(t * 5)) * 6
        case .backflip:
            let cycle = frac(t / 2.6)
            if cycle < 0.4 {
                let s = cycle / 0.4
                p.lift = -sin(s * .pi) * 34
                p.angle = -s * 360
            } else if cycle < 0.5 {
                p.squash = 0.88
            }
        }
        return p
    }
}

/// Draws one actor in its pose, with a ground shadow and an emote bubble.
struct ActorView: View {
    let actor: Actor
    let pose: Pose

    var body: some View {
        let s = actor.size
        ZStack(alignment: .bottom) {
            Ellipse().fill(.black.opacity(0.14))
                .frame(width: s * 0.55 * max(0.5, 1 + pose.lift / 70), height: s * 0.1)
            Sprite(url: actor.spriteURL)
                .frame(width: s, height: s)
                .scaleEffect(x: pose.facingRight ? -1 : 1, y: 1)
                .rotation3DEffect(.degrees(pose.spin), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(x: 2 - pose.squash, y: pose.squash, anchor: .bottom)
                .rotationEffect(.degrees(pose.angle), anchor: pose.angle.magnitude > 30 ? .center : .bottom)
                .offset(y: pose.lift + s * 0.2) // Sprites have empty space below their feet.
                .overlay(alignment: .topTrailing) {
                    if let emote = pose.emote {
                        Group {
                            if emote == "zzz" {
                                Text("z").font(.system(size: s * 0.22, weight: .heavy, design: .rounded))
                                    .opacity(Double(1 + pose.emoteRise / 14))
                            } else {
                                Image(systemName: emote).font(.system(size: s * 0.24, weight: .bold))
                                    .symbolRenderingMode(.multicolor)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(pose.emoteAngle))
                        .offset(x: 2, y: pose.lift + pose.emoteRise + s * 0.1)
                    }
                }
        }
        .frame(width: s, height: s + 6, alignment: .bottom)
    }
}

/// Pokémon scattered around a backdrop, each doing its own thing.
struct SpriteParade: View {
    var caught: [Int] = []
    var count = 8
    var antics: [Antic] = Antic.allCases
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actors: [Actor] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(actors) { actor in
                        let pose = Pose.of(actor, at: time, width: geo.size.width)
                        ActorView(actor: actor, pose: pose)
                            .position(x: pose.x, y: actor.y * geo.size.height)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if actors.isEmpty { actors = Actor.cast(count: count, caught: caught, antics: antics) } }
    }
}

/// A row of Pokémon hanging out on top of a card, feet on its edge.
struct PokemonLedge: View {
    var caught: [Int] = []
    var count = 5
    var height: CGFloat = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actors: [Actor] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .bottomLeading) {
                    ForEach(actors) { actor in
                        let pose = Pose.of(actor, at: time, width: geo.size.width)
                        ActorView(actor: actor, pose: pose)
                            .position(x: pose.x, y: geo.size.height - (actor.size + 6) / 2)
                    }
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if actors.isEmpty {
                actors = Actor.cast(count: count, caught: caught,
                                    antics: [.walk, .hop, .wave, .dance, .sleep, .backflip, .spin],
                                    ys: 1...1, sizes: 46...54)
            }
        }
    }
}

/// Gentle idle bounce for a hero sprite; a happy hop once it's caught.
struct IdleBounce: ViewModifier {
    var excited: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = t / 1.3 - floor(t / 1.3)
            let lift = excited ? (cycle < 0.4 ? -sin(cycle / 0.4 * .pi) * 14 : 0) : -abs(sin(t * 1.6)) * 4
            content
                .rotationEffect(.degrees(excited ? 0 : sin(t * 1.2) * 3), anchor: .bottom)
                .offset(y: lift)
        }
    }
}
