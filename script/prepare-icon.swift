import AppKit

// Remove only the light exterior connected to the image edges.
// White marks enclosed by the dark tile remain unchanged.
let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard let input = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: source))) else {
    fatalError("Cannot read source image")
}
let width = input.pixelsWide
let height = input.pixelsHigh
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32)!
let pixels = output.bitmapData!
for y in 0..<height {
    for x in 0..<width {
        let color = input.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8((color.redComponent * 255).rounded())
        pixels[offset + 1] = UInt8((color.greenComponent * 255).rounded())
        pixels[offset + 2] = UInt8((color.blueComponent * 255).rounded())
        pixels[offset + 3] = 255
    }
}
var visited = [Bool](repeating: false, count: width * height)
var queue = [Int]()
func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * width + x
    guard !visited[index] else { return }
    visited[index] = true
    let offset = index * 4
    guard min(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 28 else { return }
    queue.append(index)
}
for x in 0..<width { enqueue(x, 0); enqueue(x, height - 1) }
for y in 0..<height { enqueue(0, y); enqueue(width - 1, y) }
var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % width
    let y = index / width
    enqueue(x - 1, y); enqueue(x + 1, y); enqueue(x, y - 1); enqueue(x, y + 1)
    let offset = index * 4
    let lightness = Double(Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
    let alpha = lightness > 245 ? 0 : max(0, min(255, (255 - lightness) / 237 * 255))
    pixels[offset] = 17
    pixels[offset + 1] = 18
    pixels[offset + 2] = 21
    pixels[offset + 3] = UInt8(alpha.rounded())
}
let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
    provider: CGDataProvider(data: Data(bytes: pixels, count: width * height * 4) as CFData)!,
    decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: destination))
print("Saved transparent logo: \(width) × \(height)")
