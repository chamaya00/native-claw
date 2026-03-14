import SwiftUI
import AVFoundation

struct FlashcardSheet: View {
    let flashcards: [Flashcard]
    let flashcardImages: [UUID: UIImage]
    var direction: LanguageDirection = .vietnameseToEnglish
    let onFinish: () -> Void

    @State private var currentIndex: Int = 0
    @State private var viewedIndices: Set<Int> = []
    @State private var isFlipped: Bool = false
    @State private var dragOffset: CGSize = .zero

    private var allViewed: Bool { viewedIndices.count >= flashcards.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                ZStack {
                    if flashcards.isEmpty {
                        Text(direction == .vietnameseToEnglish ? "Khong co the hoc" : "No flashcards")
                            .foregroundStyle(.secondary)
                    } else {
                        cardStack
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomControls
            }
            .navigationTitle(direction == .vietnameseToEnglish
                             ? "The hoc (\(currentIndex + 1)/\(flashcards.count))"
                             : "Flashcard (\(currentIndex + 1)/\(flashcards.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5)).frame(height: 4)
                Capsule()
                    .fill(Color.blue)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.tutorSpring, value: progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var progress: Double {
        guard !flashcards.isEmpty else { return 0 }
        return Double(viewedIndices.count) / Double(flashcards.count)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        let card = flashcards[currentIndex]
        return FlashcardView(
            flashcard: card,
            image: flashcardImages[card.id],
            isFlipped: isFlipped,
            direction: direction
        )
        .padding(.horizontal, 24)
        .offset(x: dragOffset.width)
        .rotationEffect(.degrees(dragOffset.width / 20))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    handleSwipe(value.translation.width)
                }
        )
        .onTapGesture {
            withAnimation(.tutorSpring) {
                isFlipped.toggle()
                if isFlipped { viewedIndices.insert(currentIndex) }
                Haptics.impact(.light)
            }
        }
        .id(currentIndex)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if direction == .vietnameseToEnglish {
                Text(isFlipped ? "Vuot de tiep tuc" : "Nhan de xem tieng Anh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(isFlipped ? "Swipe to continue" : "Tap to see Vietnamese")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if currentIndex > 0 {
                    Button {
                        navigate(by: -1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onFinish) {
                    Text(allViewed
                         ? (direction == .vietnameseToEnglish ? "Luyen tap ngay!" : "Practice now!")
                         : (direction == .vietnameseToEnglish ? "Bo qua" : "Skip"))
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(allViewed ? Color.blue : Color(.secondarySystemBackground))
                        .foregroundStyle(allViewed ? .white : .secondary)
                        .clipShape(Capsule())
                }
                .animation(.tutorSpring, value: allViewed)

                Spacer()

                if currentIndex < flashcards.count - 1 {
                    Button {
                        navigate(by: 1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
        .padding(.top, 12)
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0, next < flashcards.count else { return }
        withAnimation(.tutorSpring) {
            currentIndex = next
            isFlipped = false
            dragOffset = .zero
        }
        Haptics.impact(.light)
    }

    private func handleSwipe(_ dx: CGFloat) {
        if abs(dx) > 80 {
            navigate(by: dx < 0 ? 1 : -1)
        }
        withAnimation(.tutorSpring) { dragOffset = .zero }
    }
}

// MARK: - Single Flashcard View

private struct FlashcardView: View {
    let flashcard: Flashcard
    let image: UIImage?
    let isFlipped: Bool
    var direction: LanguageDirection = .vietnameseToEnglish

    @StateObject private var speaker = CardSpeaker()

    /// The face shown first is the native language; the flipped face is the target language.
    private var nativeBadge: (code: String, color: Color) {
        direction == .vietnameseToEnglish ? ("VN", .red) : ("EN", .blue)
    }
    private var targetBadge: (code: String, color: Color) {
        direction == .vietnameseToEnglish ? ("EN", .blue) : ("VN", .red)
    }

    var body: some View {
        ZStack {
            if !isFlipped {
                nativeFace
            } else {
                targetFace
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.tutorSpring, value: isFlipped)
    }

    // MARK: Native Face (shown first — the word the learner already knows)

    private var nativeFace: some View {
        VStack(spacing: 20) {
            HStack {
                languageBadge(nativeBadge.code, color: nativeBadge.color)
                Spacer()
            }

            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                } else {
                    gradientPlaceholder
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: image != nil)

            VStack(spacing: 6) {
                Text(flashcard.wordEntry.nativeWord(for: direction))
                    .font(.largeTitle.weight(.bold))
                Text(flashcard.wordEntry.partOfSpeech)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Spacer()

            Text(direction == .vietnameseToEnglish
                 ? "Nhan de xem tieng Anh"
                 : "Tap to see Vietnamese")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    // MARK: Target Face (shown after flip — the word being learned)

    private var targetFace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                languageBadge(targetBadge.code, color: targetBadge.color)
                Spacer()
                speakerButton
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(flashcard.wordEntry.targetWord(for: direction))
                    .font(.largeTitle.weight(.bold))
                Text(flashcard.wordEntry.partOfSpeech)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Phonetic guides
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("VN")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(flashcard.phoneticVi)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text("EN")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(flashcard.phoneticEn)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(direction == .vietnameseToEnglish ? "Goi nho" : "Mnemonic", systemImage: "lightbulb.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(flashcard.mnemonicVi)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(flashcard.exampleEn)
                    .font(.subheadline.italic())
                Text(flashcard.exampleVi)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 400)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    // MARK: - Speaker Button

    private var speakerButton: some View {
        Button {
            speaker.speak(flashcard.wordEntry.targetWord(for: direction), language: direction.ttsLanguageCode)
        } label: {
            Image(systemName: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.2.fill")
                .font(.title3)
                .foregroundStyle(speaker.isSpeaking ? .blue : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    // MARK: - Language Badge

    private func languageBadge(_ code: String, color: Color) -> some View {
        Text(code)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
    }

    // MARK: - Gradient Placeholder

    private var gradientPlaceholder: some View {
        let hue = Double(abs(flashcard.wordEntry.english.hashValue) % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.5, brightness: 0.85),
                Color(hue: hue + 0.1, saturation: 0.6, brightness: 0.7),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text(flashcard.wordEntry.targetWord(for: direction).prefix(1).uppercased())
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        )
    }
}

// MARK: - Text-to-Speech Helper

private final class CardSpeaker: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-US") {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.42
        synthesizer.speak(utterance)
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
