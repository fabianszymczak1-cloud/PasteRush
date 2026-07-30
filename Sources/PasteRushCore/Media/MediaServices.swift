import Foundation
import AppKit

public final class ThumbnailService {
    private let queue = DispatchQueue(label: "com.pasterush.thumbnails", qos: .utility)

    public init() {}

    public func generateThumbnail(clipId: String, imageData: Data, maxPixel: CGFloat = 128, completion: @escaping (String) -> Void) {
        queue.async {
            guard let source = NSImage(data: imageData) else { return }
            let target = NSSize(width: maxPixel, height: maxPixel)
            let thumb = NSImage(size: target)
            thumb.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .medium
            let ratio = min(target.width / max(source.size.width, 1), target.height / max(source.size.height, 1))
            let drawSize = NSSize(width: source.size.width * ratio, height: source.size.height * ratio)
            let origin = NSPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
            source.draw(in: NSRect(origin: origin, size: drawSize))
            thumb.unlockFocus()
            guard let tiff = thumb.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
            let url = AppPaths.thumbnailURL(clipId: clipId)
            try? jpeg.write(to: url, options: .atomic)
            completion(url.path)
        }
    }
}

import Vision

public final class OCRService {
    private let queue = DispatchQueue(label: "com.pasterush.ocr", qos: .background)

    public init() {}

    public func recognize(imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            guard let image = NSImage(data: imageData),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cgImage = rep.cgImage else {
                completion(nil)
                return
            }
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                completion(text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
