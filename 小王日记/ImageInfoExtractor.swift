import Foundation
import ImageIO
@preconcurrency import Vision

/// 图片信息只在设备本机提取；不会上传图片，也不会将识别结果发送给 AI，除非用户主动点击 AI 润色。
enum ImageInfoExtractor {
    static func extract(from data: Data) async -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var parts: [String] = []
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateText = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            parts.append("拍摄时间：\(dateText)")
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let location = locationText(from: gps) {
            parts.append("拍摄地点坐标：\(location)")
        }
        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let text = await recognizedText(in: cgImage), !text.isEmpty {
            parts.append("图片文字：\(text)")
        }
        guard !parts.isEmpty else { return nil }
        return "【图片识别信息】\n" + parts.joined(separator: "\n")
    }

    private static func locationText(from gps: [CFString: Any]) -> String? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -1.0 : 1.0
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -1.0 : 1.0
        return String(format: "%.6f, %.6f", latitude * latRef, longitude * lonRef)
    }

    private static func recognizedText(in image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .prefix(12) ?? []
                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
                catch { continuation.resume(returning: nil) }
            }
        }
    }
}
