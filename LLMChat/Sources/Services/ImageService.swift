import Foundation
import UIKit

#if canImport(ImagePlayground)
import ImagePlayground
#endif

actor ImageService {

#if canImport(ImagePlayground)

    private var creator: ImageCreator?
    private var isUnsupported = false

    private func getOrCreateCreator() async throws -> ImageCreator {
        guard !isUnsupported else { throw CancellationError() }
        if let existing = creator { return existing }
        do {
            let new = try await ImageCreator()
            creator = new
            return new
        } catch {
            isUnsupported = true
            throw error
        }
    }

#endif

    /// Generates an illustration for a vocabulary word.
    /// Returns nil silently on unsupported devices or on any error — the
    /// gradient placeholder in FlashcardSheet is shown instead.
    func generateImage(for word: WordEntry) async -> UIImage? {
#if canImport(ImagePlayground)
        do {
            let creator = try await getOrCreateCreator()
            // Prefer the animation style for a cartoonish, kid-friendly look.
            let style = creator.availableStyles.first(where: { $0 == .animation }) ?? .animation
            let stream = creator.images(
                for: [
                    .text(word.english),
                    .text("cute cartoon"),
                    .text("colorful"),
                    .text("kid friendly"),
                    .text("friendly characters"),
                    .text("safe for children"),
                ],
                style: style,
                limit: 1
            )
            for try await generated in stream {
                return UIImage(cgImage: generated.cgImage)
            }
        } catch {
            // Silent degradation — gradient placeholder remains visible
        }
        return nil
#else
        return nil
#endif
    }
}
