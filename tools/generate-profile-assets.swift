// Regenerates everything in profile/assets/ from the TerraImperfecta brand kit.
//
//     swift tools/generate-profile-assets.swift
//
// SVGs are written directly. PNGs are rendered from those SVGs with `resvg`,
// which must be on PATH: `cargo install resvg --version 0.48.1 --locked`, or the
// release binary, which is what CI uses. Keep the two on the same version.
//
// Plain Swift + Foundation, so it runs unchanged on macOS and on GitHub's
// ubuntu-latest runners, which ship the same Swift.
//
// All geometry comes from the kit files in tools/kit/, copied unmodified from
// TerraImperfecta-brand-kit. Nothing here is drawn by hand: the mark's arcs,
// the outlined wordmark and tagline, and the lockup's proportions are all read
// out of those files, so a change to the kit flows through on regeneration.

import Foundation

// MARK: - Layout (1x units; files are written at 2x)

let width = 1280.0
let height = 320.0
let pixelScale = 2.0  // 2560 x 640 — sharp on high-density screens

// The lockup (small mark + wordmark + tagline) is taken from the kit's X header
// as one block, scaled uniformly and placed by its mark's centre.
let lockupScale = 1.6
let lockupLeft = 80.0

// The ghosted mark on the right, as in the kit's banners. Sized to the height
// and cropped by the right edge, the way patacognition's gear sits.
let ghostSize = 1.5 * height
let ghostCentreX = width - 0.28 * height

// MARK: - Palette (TerraImperfecta-brand-kit/README.txt)

enum Palette {
    static let void = "#071B2E"
    static let abyss = "#030C16"
    static let drift = "#536168"
    static let cloud = "#CCE1DF"
    static let vapour = "#E7ECEB"
    static let landfall = "#A8742F"
    static let ember = "#D9A05C"
}

/// Kit rule: colour appears in exactly one place — the core of the mark.
/// Landfall on light grounds, Ember on dark, never both in one composition.
struct Theme {
    let name: String
    let ground: String
    let ink: String
    let accent: String
    let tagline: String
    let ghostOpacity: Double
}

let themes = [
    Theme(name: "light", ground: Palette.vapour, ink: Palette.void,
          accent: Palette.landfall, tagline: Palette.drift, ghostOpacity: 0.08),
    // The X header's own values: Abyss ground, Cloud ink, ghost at 0.12.
    Theme(name: "reversed", ground: Palette.abyss, ink: Palette.cloud,
          accent: Palette.ember, tagline: Palette.drift, ghostOpacity: 0.12),
]

// MARK: - Reading the kit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func read(_ relative: String) -> String {
    let url = root.appendingPathComponent(relative)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("cannot read \(relative)")
    }
    return text
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// The mark: nine arcs on a 200 x 200 artboard, plus a solid core.
struct Mark {
    let arcs: [String]
    let coreRadius: String
    let strokeWidth: String
}

func readMark() -> Mark {
    let svg = read("tools/kit/even-void.svg")
    let arcs = svg.matches(of: #/<path d="([^"]+)" fill="none" stroke="currentColor" stroke-width="([\d.]+)"/#)
    let core = svg.firstMatch(of: #/<circle cx="100" cy="100" r="([\d.]+)"/#)
    guard arcs.count == 9, let core else {
        fail("even-void.svg no longer has 9 arcs and a centred core; check the kit")
    }
    let strokes = Set(arcs.map { String($0.2) })
    guard strokes.count == 1 else { fail("the mark's arcs no longer share one stroke width") }
    return Mark(arcs: arcs.map { String($0.1) }, coreRadius: String(core.1), strokeWidth: strokes.first!)
}

struct Placed { let x: Double; let y: Double; let size: Double }
struct Outline { let originX: Double; let originY: Double; let d: String; let box: Box }

/// The lockup as the kit's X header lays it out, in that file's coordinates.
struct Lockup {
    let mark: Placed
    let wordmark: Outline
    let tagline: Outline
}

func readLockup() -> Lockup {
    let svg = read("tools/kit/x-header-1500x500.svg")

    // Two nested marks: the ghost first, then the lockup's small mark.
    let marks = svg.matches(of: #/<svg x="(-?[\d.]+)" y="(-?[\d.]+)" width="([\d.]+)" height="[\d.]+" viewBox="0 0 200 200"/#)
    guard marks.count == 2 else { fail("x-header no longer has a ghost mark and a lockup mark") }
    let small = marks[1]

    let texts = svg.matches(of: #/<g transform="translate\(([\d.]+),([\d.]+)\)">\s*<path d="([^"]+)" fill="(#[0-9A-Fa-f]{6})"\/>/#)
    guard texts.count == 2,
          texts[0].4.uppercased() == Palette.cloud, texts[1].4.uppercased() == Palette.drift
    else { fail("x-header no longer has the Cloud wordmark followed by the Drift tagline") }

    func outline(_ m: Regex<(Substring, Substring, Substring, Substring, Substring)>.Match) -> Outline {
        let d = String(m.3)
        return Outline(originX: Double(m.1)!, originY: Double(m.2)!, d: d, box: boundingBox(of: d))
    }
    return Lockup(
        mark: Placed(x: Double(small.1)!, y: Double(small.2)!, size: Double(small.3)!),
        wordmark: outline(texts[0]),
        tagline: outline(texts[1]))
}

// MARK: - Path bounding boxes

struct Box { var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    mutating func add(_ x: Double, _ y: Double) {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    }
}

/// Bounding box of absolute path data, control points included — a slight
/// overestimate on curves, which is harmless for layout. `H` and `V` take a
/// single coordinate, so the path has to be walked command by command rather
/// than read as pairs of numbers.
func boundingBox(of d: String) -> Box {
    var box = Box()
    var x = 0.0, y = 0.0
    var command: Character = "M"
    var numbers: [Double] = []

    func flush() {
        let arity: Int
        switch command {
        case "M", "L", "T": arity = 2
        case "Q", "S": arity = 4
        case "C": arity = 6
        case "H", "V": arity = 1
        case "Z": arity = 0
        default: fail("path command '\(command)' is not handled — relative commands are not expected in the kit")
        }
        if arity == 0 { return }
        guard numbers.count % arity == 0 else { fail("malformed path data after '\(command)'") }
        for start in stride(from: 0, to: numbers.count, by: arity) {
            let group = Array(numbers[start..<start + arity])
            switch command {
            case "H": x = group[0]
            case "V": y = group[0]
            default:
                for pair in stride(from: 0, to: arity, by: 2) { box.add(group[pair], group[pair + 1]) }
                x = group[arity - 2]; y = group[arity - 1]
            }
            box.add(x, y)
        }
    }

    for token in d.matches(of: #/[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/#) {
        let text = token.output
        if let letter = text.first, letter.isLetter, text.count == 1 {
            flush(); command = letter; numbers = []
        } else {
            numbers.append(Double(text)!)
        }
    }
    flush()
    return box
}

// MARK: - Writing SVG

/// Fixed-point, trailing zeros trimmed — identical on macOS and Linux, so CI
/// can compare regenerated SVGs byte for byte.
func n(_ v: Double) -> String {
    var s = String(format: "%.2f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}

func markSVG(_ mark: Mark, at p: Placed, ink: String, core: String) -> String {
    let arcs = mark.arcs.map {
        #"<path d="\#($0)" fill="none" stroke="\#(ink)" stroke-width="\#(mark.strokeWidth)" stroke-linecap="butt"/>"#
    }.joined()
    return #"<svg x="\#(n(p.x))" y="\#(n(p.y))" width="\#(n(p.size))" height="\#(n(p.size))" viewBox="0 0 200 200">"#
        + arcs + #"<circle cx="100" cy="100" r="\#(mark.coreRadius)" fill="\#(core)"/></svg>"#
}

func banner(_ theme: Theme, mark: Mark, lockup: Lockup) -> String {
    // Place the lockup block: scale it about its own mark, then put the mark's
    // centre on the banner's vertical centre, left edge at lockupLeft.
    let s = lockupScale
    let markCentreY = lockup.mark.y + lockup.mark.size / 2
    let dx = lockupLeft - lockup.mark.x * s
    let dy = height / 2 - markCentreY * s
    func place(_ o: Outline, fill: String) -> String {
        #"<g transform="translate(\#(n(dx + o.originX * s)),\#(n(dy + o.originY * s))) scale(\#(n(s)))"><path d="\#(o.d)" fill="\#(fill)"/></g>"#
    }

    // The ghost carries no accent: its core is ink, like the kit's banners.
    let ghost = Placed(x: ghostCentreX - ghostSize / 2, y: height / 2 - ghostSize / 2, size: ghostSize)
    let small = Placed(x: dx + lockup.mark.x * s, y: dy + lockup.mark.y * s, size: lockup.mark.size * s)

    return [
        #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(n(width * pixelScale))" height="\#(n(height * pixelScale))" viewBox="0 0 \#(n(width)) \#(n(height))" fill="none">"#,
        #"<rect width="\#(n(width))" height="\#(n(height))" fill="\#(theme.ground)"/>"#,
        #"<g opacity="\#(n(theme.ghostOpacity))">\#(markSVG(mark, at: ghost, ink: theme.ink, core: theme.ink))</g>"#,
        markSVG(mark, at: small, ink: theme.ink, core: theme.accent),
        place(lockup.wordmark, fill: theme.ink),
        place(lockup.tagline, fill: theme.tagline),
        "</svg>",
    ].joined(separator: "\n") + "\n"
}

/// The mark alone on a transparent ground, at 512 px — the README's icon.
func icon(_ theme: Theme, mark: Mark) -> String {
    #"<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512" fill="none">"#
        + "\n" + markSVG(mark, at: Placed(x: 0, y: 0, size: 512), ink: theme.ink, core: theme.accent) + "\n</svg>\n"
}

// MARK: - Main

func write(_ text: String, to relative: String) {
    do { try text.write(to: root.appendingPathComponent(relative), atomically: true, encoding: .utf8) }
    catch { fail("cannot write \(relative): \(error)") }
    print("wrote \(relative)")
}

func render(_ svg: String, to png: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["resvg", root.appendingPathComponent(svg).path, root.appendingPathComponent(png).path]
    do { try process.run() } catch { fail("cannot start resvg: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("resvg exited \(process.terminationStatus) rendering \(svg) — is it installed and on PATH?")
    }
    print("rendered \(png)")
}

let mark = readMark()
let lockup = readLockup()

for theme in themes {
    let bannerSVG = "profile/assets/banner-\(theme.name).svg"
    let iconSVG = "profile/assets/icon-\(theme.name).svg"
    write(banner(theme, mark: mark, lockup: lockup), to: bannerSVG)
    write(icon(theme, mark: mark), to: iconSVG)
    render(bannerSVG, to: "profile/assets/banner-\(theme.name).png")
    render(iconSVG, to: "profile/assets/icon-\(theme.name)-512.png")
}
