#!/usr/bin/env swift
import Foundation
import AppKit
import CoreText
import Vision

struct PosterError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw PosterError(message: message) }
}

func resolve(_ path: String, relativeTo directory: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
    return directory.appendingPathComponent(expanded).standardizedFileURL
}

func color(_ hex: String) throws -> CGColor {
    let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
        throw PosterError(message: "颜色应为 #RRGGBB，实际为 \(hex)")
    }
    return CGColor(
        red: CGFloat((rgb >> 16) & 255) / 255,
        green: CGFloat((rgb >> 8) & 255) / 255,
        blue: CGFloat(rgb & 255) / 255,
        alpha: 1
    )
}

func rectangle(_ values: [Double], inside bounds: CGRect, label: String) throws -> CGRect {
    try require(values.count == 4 && values.allSatisfy { $0.isFinite }, "\(label) 需要四个有限数值")
    let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    try require(rect.width > 0 && rect.height > 0, "\(label) 的宽高应大于零")
    try require(bounds.contains(rect), "\(label) 超出画布或源图范围")
    return rect
}

func image(_ url: URL) throws -> CGImage {
    guard let image = NSImage(contentsOf: url) else {
        throw PosterError(message: "无法读取图片 \(url.path)")
    }
    var frame = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &frame, context: nil, hints: nil) else {
        throw PosterError(message: "无法解码图片 \(url.path)")
    }
    return cgImage
}

func context(width: Int, height: Int, background: String) throws -> CGContext {
    try require(width > 0 && height > 0, "画布尺寸应大于零")
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw PosterError(message: "无法创建 \(width)×\(height) 画布") }
    context.setFillColor(try color(background))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

func checkOutput(_ url: URL, overwrite: Bool) throws {
    try require(overwrite || !FileManager.default.fileExists(atPath: url.path), "文件已存在，请使用新版本名或明确设置 overwrite 为 true，\(url.path)")
}

func write(_ data: Data, to url: URL, overwrite: Bool) throws {
    try checkOutput(url, overwrite: overwrite)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: overwrite ? [.atomic] : [.withoutOverwriting])
}

func png(_ image: CGImage) throws -> Data {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw PosterError(message: "无法编码 PNG")
    }
    return data
}

struct Canvas: Decodable {
    let width: Double
    let height: Double
    let color: String?
}

struct Layer: Decodable {
    let type: String
    let rect: [Double]
    let text: String?
    let font: String?
    let size: Double?
    let color: String?
    let alignment: String?
    let lineSpacing: Double?
    let path: String?
    let crop: [Double]?
    let fit: String?
    let interpolation: String?
    let alpha: Double?
    let fill: String?
    let stroke: String?
    let strokeWidth: Double?
    let radius: Double?
}

struct Design: Decodable {
    let canvas: Canvas
    let outputWidth: Int?
    let output: String
    let overwrite: Bool?
    let layers: [Layer]
}

func drawText(_ layer: Layer, in rect: CGRect, context: CGContext) throws {
    guard let text = layer.text, let size = layer.size else {
        throw PosterError(message: "文本层需要 text 和 size")
    }
    try require(size.isFinite && size > 0, "字号应大于零")
    let fontName = layer.font ?? "PingFangSC-Regular"
    guard let font = NSFont(name: fontName, size: size) else {
        throw PosterError(message: "本机缺少字体 \(fontName)")
    }
    let style = NSMutableParagraphStyle()
    switch layer.alignment ?? "left" {
    case "left": style.alignment = .left
    case "center": style.alignment = .center
    case "right": style.alignment = .right
    default: throw PosterError(message: "文本 alignment 应为 left、center 或 right")
    }
    let spacing = layer.lineSpacing ?? 0
    try require(spacing.isFinite && spacing >= 0, "lineSpacing 应为非负数")
    style.lineSpacing = spacing
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: try color(layer.color ?? "#F1F2EC"))!,
        .paragraphStyle: style
    ]
    let content = NSAttributedString(string: text, attributes: attributes)
    let setter = CTFramesetterCreateWithAttributedString(content)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
    let visible = CTFrameGetVisibleStringRange(frame)
    try require(visible.length == content.length, "文本框溢出，请调整文案或文本框，\(text)")
    context.textMatrix = .identity
    context.textPosition = .zero
    CTFrameDraw(frame, context)
}

func drawImage(_ layer: Layer, in rect: CGRect, context: CGContext, directory: URL) throws {
    guard let path = layer.path else { throw PosterError(message: "图片层缺少 path") }
    var source = try image(resolve(path, relativeTo: directory))
    if let crop = layer.crop {
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let cropRect = try rectangle(crop, inside: bounds, label: "图片 crop")
        guard let cropped = source.cropping(to: cropRect) else {
            throw PosterError(message: "图片裁切失败 \(path)")
        }
        source = cropped
    }
    let fit = layer.fit ?? "contain"
    try require(["contain", "cover"].contains(fit), "图片 fit 应为 contain 或 cover")
    let interpolation = layer.interpolation ?? "high"
    try require(["high", "nearest"].contains(interpolation), "图片 interpolation 应为 high 或 nearest")
    let alpha = layer.alpha ?? 1
    try require(alpha.isFinite && alpha >= 0 && alpha <= 1, "图片 alpha 应在 0 到 1 之间")
    let xScale = rect.width / CGFloat(source.width)
    let yScale = rect.height / CGFloat(source.height)
    let scale = fit == "cover" ? max(xScale, yScale) : min(xScale, yScale)
    let width = CGFloat(source.width) * scale
    let height = CGFloat(source.height) * scale
    let destination = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    context.clip(to: rect)
    context.setAlpha(alpha)
    context.interpolationQuality = interpolation == "nearest" ? .none : .high
    context.draw(source, in: destination)
}

func drawRectangle(_ layer: Layer, in rect: CGRect, context: CGContext) throws {
    let radius = layer.radius ?? 0
    let strokeWidth = layer.strokeWidth ?? 1
    try require(radius.isFinite && radius >= 0 && strokeWidth.isFinite && strokeWidth >= 0, "圆角与描边宽度应为非负数")
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let fill = layer.fill {
        context.setFillColor(try color(fill))
        context.addPath(path)
        context.fillPath()
    }
    if let stroke = layer.stroke {
        context.setStrokeColor(try color(stroke))
        context.setLineWidth(strokeWidth)
        context.addPath(path)
        context.strokePath()
    }
}

func render(_ configURL: URL) throws {
    let design = try JSONDecoder().decode(Design.self, from: Data(contentsOf: configURL))
    let directory = configURL.deletingLastPathComponent()
    let output = resolve(design.output, relativeTo: directory)
    let overwrite = design.overwrite ?? false
    try checkOutput(output, overwrite: overwrite)
    let width = design.outputWidth ?? 2160
    let canvas = design.canvas
    try require(canvas.width.isFinite && canvas.height.isFinite && canvas.width > 0 && canvas.height > 0 && width > 0, "画布尺寸必须为正数")
    let scale = Double(width) / canvas.width
    let heightValue = canvas.height * scale
    try require(heightValue.isFinite && heightValue <= 50000 && width <= 20000, "画布尺寸过大")
    let height = Int(heightValue.rounded())
    let context = try context(width: width, height: height, background: canvas.color ?? "#101210")
    context.scaleBy(x: scale, y: scale)
    let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    for (index, layer) in design.layers.enumerated() {
        let topRect = try rectangle(layer.rect, inside: bounds, label: "第 \(index + 1) 层")
        let rect = CGRect(x: topRect.minX, y: canvas.height - topRect.maxY, width: topRect.width, height: topRect.height)
        context.saveGState()
        switch layer.type {
        case "text": try drawText(layer, in: rect, context: context)
        case "image": try drawImage(layer, in: rect, context: context, directory: directory)
        case "rect": try drawRectangle(layer, in: rect, context: context)
        default: throw PosterError(message: "未知图层类型 \(layer.type)")
        }
        context.restoreGState()
    }
    guard let result = context.makeImage() else { throw PosterError(message: "图片输出失败") }
    try write(png(result), to: output, overwrite: overwrite)
    print("已输出 \(width)×\(height) PNG，\(output.path)")
}

struct Slice: Decodable {
    let source: [Double]
    let destination: [Double]
}

struct Page: Decodable {
    let output: String
    let slices: [Slice]
}

struct Split: Decodable {
    let source: String
    let width: Int
    let height: Int
    let color: String?
    let overwrite: Bool?
    let pages: [Page]
}

func split(_ configURL: URL) throws {
    let config = try JSONDecoder().decode(Split.self, from: Data(contentsOf: configURL))
    let directory = configURL.deletingLastPathComponent()
    let original = try image(resolve(config.source, relativeTo: directory))
    let sourceBounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
    let targetBounds = CGRect(x: 0, y: 0, width: config.width, height: config.height)
    try require(config.width > 0 && config.height > 0 && !config.pages.isEmpty, "拆图需要正数尺寸和至少一页")
    let outputs = config.pages.map { resolve($0.output, relativeTo: directory) }
    try require(Set(outputs.map { $0.path }).count == outputs.count, "多页输出路径不能重复")
    let overwrite = config.overwrite ?? false
    for output in outputs { try checkOutput(output, overwrite: overwrite) }
    var results = [Data]()
    for page in config.pages {
        try require(!page.slices.isEmpty, "每页需要至少一个裁切片段")
        let context = try context(width: config.width, height: config.height, background: config.color ?? "#101210")
        context.interpolationQuality = .none
        for slice in page.slices {
            let source = try rectangle(slice.source, inside: sourceBounds, label: "source")
            let destination = try rectangle(slice.destination, inside: targetBounds, label: "destination")
            try require((slice.source + slice.destination).allSatisfy { $0.rounded() == $0 }, "无损裁切坐标应为整数像素")
            try require(source.size == destination.size, "无损拆图的 source 与 destination 宽高须一致")
            guard let cropped = original.cropping(to: source) else { throw PosterError(message: "源图裁切失败") }
            let target = CGRect(x: destination.minX, y: CGFloat(config.height) - destination.maxY, width: destination.width, height: destination.height)
            context.draw(cropped, in: target)
        }
        guard let result = context.makeImage() else { throw PosterError(message: "拆图输出失败") }
        results.append(try png(result))
    }
    for (index, output) in outputs.enumerated() {
        try write(results[index], to: output, overwrite: overwrite)
        print("已输出 \(config.width)×\(config.height) PNG，\(output.path)")
    }
}

func qrCodes(_ image: CGImage) throws -> [String] {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { $0.payloadStringValue }.sorted()
}

func inspect(_ arguments: [String], directory: URL) throws {
    try require((1...3).contains(arguments.count), "inspect 用法为 图片路径 [报告路径] [原始二维码图片路径]")
    let input = resolve(arguments[0], relativeTo: directory)
    let source = try image(input)
    let text = VNRecognizeTextRequest()
    text.recognitionLanguages = ["zh-Hans", "en-US"]
    text.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: source).perform([text])
    let codes = try qrCodes(source)
    var report: [String: Any] = [
        "image": input.path,
        "width": source.width,
        "height": source.height,
        "recognizedText": (text.results ?? []).compactMap { $0.topCandidates(1).first?.string },
        "qrCount": codes.count
    ]
    if arguments.count == 3 {
        let reference = try image(resolve(arguments[2], relativeTo: directory))
        let referenceCodes = try qrCodes(reference)
        report["referenceQRCount"] = referenceCodes.count
        report["qrMatchesReference"] = !referenceCodes.isEmpty && referenceCodes == codes
    }
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    if arguments.count >= 2 {
        let output = resolve(arguments[1], relativeTo: directory)
        try write(data, to: output, overwrite: false)
        print("已保存验收报告，\(output.path)")
    } else {
        print(String(data: data, encoding: .utf8)!)
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    try require(arguments.count >= 2, "用法为 poster.swift render design.json | split split.json | inspect 图片 [报告] [二维码原图]")
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    switch arguments[0] {
    case "render":
        try require(arguments.count == 2, "render 需要一个 JSON 文件")
        try render(resolve(arguments[1], relativeTo: directory))
    case "split":
        try require(arguments.count == 2, "split 需要一个 JSON 文件")
        try split(resolve(arguments[1], relativeTo: directory))
    case "inspect":
        try inspect(Array(arguments.dropFirst()), directory: directory)
    default:
        throw PosterError(message: "未知命令 \(arguments[0])")
    }
} catch {
    FileHandle.standardError.write(Data(("错误，\(error.localizedDescription)\n").utf8))
    exit(1)
}
