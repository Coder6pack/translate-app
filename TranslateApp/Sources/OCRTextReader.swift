import CoreGraphics
import ScreenCaptureKit
import Vision

/// An opt-in, on-demand OCR fallback for text that accessibility APIs cannot expose.
actor OCRTextReader {
    private struct RecognizedWord {
        let text: String
        let bounds: CGRect
    }

    private let captureSize: CGSize

    init(captureSize: CGSize = CGSize(width: 520, height: 260)) {
        self.captureSize = CGSize(
            width: max(1, captureSize.width),
            height: max(1, captureSize.height)
        )
    }

    func capture(for gesture: MouseGesture) async -> TextCapture? {
        let trigger: TextCapture.Trigger
        switch gesture.kind {
        case .selection:
            trigger = .selection
        case .doubleClick:
            trigger = .doubleClick
        case .singleClick:
            trigger = .singleClick
        }

        return await capture(
            at: gesture.location,
            trigger: trigger
        )
    }

    func capture(
        at point: CGPoint,
        trigger: TextCapture.Trigger = .singleClick
    ) async -> TextCapture? {
        guard !Task.isCancelled,
              CGPreflightScreenCaptureAccess(),
              let region = captureRegion(around: point),
              let words = await recognizedWords(in: region),
              !Task.isCancelled,
              let word = nearestWord(to: point, in: words) else {
            return nil
        }

        return TextCapture(
            text: word.text,
            anchor: point,
            bounds: word.bounds,
            trigger: trigger
        )
    }

    private func captureRegion(around point: CGPoint) -> CaptureRegion? {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &displayCount) == .success,
              displayCount == 1 else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        let unconstrainedRegion = CGRect(
            x: point.x - (captureSize.width / 2),
            y: point.y - (captureSize.height / 2),
            width: captureSize.width,
            height: captureSize.height
        )
        let region = unconstrainedRegion.intersection(displayBounds).integral
        guard !region.isNull, !region.isEmpty else { return nil }

        return CaptureRegion(
            displayID: displayID,
            displayBounds: displayBounds,
            screenBounds: region
        )
    }

    private func recognizedWords(in region: CaptureRegion) async -> [RecognizedWord]? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.screenBounds.offsetBy(
                dx: -region.displayBounds.minX,
                dy: -region.displayBounds.minY
            )
            configuration.width = Int(region.screenBounds.width)
            configuration.height = Int(region.screenBounds.height)
            configuration.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            guard !Task.isCancelled else { return nil }

            return recognizeWords(in: image, screenBounds: region.screenBounds)
        } catch {
            return nil
        }
    }

    private func recognizeWords(in image: CGImage, screenBounds capturedScreenBounds: CGRect) -> [RecognizedWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        var recognizedWords: [RecognizedWord] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }

            for substring in candidate.string.split(whereSeparator: { $0.isWhitespace }) {
                let wordRange = substring.startIndex..<substring.endIndex
                guard let wordObservation = try? candidate.boundingBox(for: wordRange) else {
                    continue
                }
                let bounds = wordObservation.boundingBox
                guard !bounds.isNull,
                      !bounds.isEmpty else {
                    continue
                }

                let text = String(substring).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                recognizedWords.append(
                    RecognizedWord(
                        text: text,
                        bounds: self.screenBounds(for: bounds, imageSize: imageSize, in: capturedScreenBounds)
                    )
                )
            }
        }
        return recognizedWords
    }

    private func nearestWord(to point: CGPoint, in words: [RecognizedWord]) -> RecognizedWord? {
        guard let word = words.min(by: {
            distanceSquared(from: point, to: $0.bounds) < distanceSquared(from: point, to: $1.bounds)
        }), distanceSquared(from: point, to: word.bounds) <= 900 else {
            return nil
        }
        return word
    }

    private func distanceSquared(from point: CGPoint, to bounds: CGRect) -> CGFloat {
        let nearestX = min(max(point.x, bounds.minX), bounds.maxX)
        let nearestY = min(max(point.y, bounds.minY), bounds.maxY)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return (dx * dx) + (dy * dy)
    }

    private func screenBounds(for visionBounds: CGRect, imageSize: CGSize, in captureBounds: CGRect) -> CGRect {
        let pixelBounds = CGRect(
            x: visionBounds.minX * imageSize.width,
            y: (1 - visionBounds.maxY) * imageSize.height,
            width: visionBounds.width * imageSize.width,
            height: visionBounds.height * imageSize.height
        )

        let scaleX = captureBounds.width / imageSize.width
        let scaleY = captureBounds.height / imageSize.height
        return CGRect(
            x: captureBounds.minX + (pixelBounds.minX * scaleX),
            y: captureBounds.minY + (pixelBounds.minY * scaleY),
            width: pixelBounds.width * scaleX,
            height: pixelBounds.height * scaleY
        )
    }
}

private struct CaptureRegion {
    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    let screenBounds: CGRect
}
