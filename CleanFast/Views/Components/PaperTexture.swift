import SwiftUI

struct PaperTexture: View {
    var density: CGFloat = 0.35
    var dotSize: ClosedRange<CGFloat> = 0.4...0.9

    var body: some View {
        Canvas { ctx, size in
            let seed = UInt64(size.width * 100 + size.height) & 0xFFFFFFFF
            var rng = SeededRNG(seed: seed)
            let count = Int(size.width * size.height / 1000.0 * density)

            for _ in 0..<count {
                let x = rng.nextFloat() * size.width
                let y = rng.nextFloat() * size.height
                let s = CGFloat.random(in: dotSize, using: &rng)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                    with: .color(.black)
                )
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextFloat() -> CGFloat {
        CGFloat(Double(next() >> 11) / Double(1 << 53))
    }
}
