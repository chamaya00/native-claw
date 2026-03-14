#if canImport(FoundationModels)
import FoundationModels

// MARK: - Word Generation

@Generable
struct WordSet {
    @Guide(description: "10 English vocabulary words for the topic", .count(10))
    var words: [GeneratedWord]
}

@Generable
struct GeneratedWord {
    @Guide(description: "English word")
    var english: String
    @Guide(description: "Vietnamese translation")
    var vietnamese: String
    @Guide(description: "Part of speech: noun, verb, adjective, adverb, or phrase")
    var partOfSpeech: String
    @Guide(description: "Short example sentence using the word (A1-A2 level)")
    var exampleSentence: String
}

// MARK: - Flashcard Generation

@Generable
struct GeneratedFlashcard {
    @Guide(description: "Mnemonic hint in Vietnamese to help remember the word")
    var mnemonicVi: String
    @Guide(description: "Example sentence in English at A1-A2 level")
    var exampleEn: String
    @Guide(description: "Vietnamese translation of the example sentence")
    var exampleVi: String
    @Guide(description: "Phonetic pronunciation of the English word using Vietnamese phonemes, e.g. 'đề-li-shợs' for 'delicious'")
    var phoneticVi: String
    @Guide(description: "Intuitive English phonetic pronunciation using only common English letters with UPPERCASE for stressed syllables, e.g. 'deh-LIH-shus' for 'delicious'. No IPA symbols.")
    var phoneticEn: String
}

// MARK: - Exercise Generation

@Generable
struct GeneratedPracticeRound {
    @Guide(description: "6 exercises: 2 per selected word, mixing types", .count(6))
    var exercises: [GeneratedExercise]
}

@Generable
struct GeneratedExercise {
    @Guide(description: "Exercise type", .anyOf(["fillBlank", "multipleChoice", "translate"]))
    var type: String
    @Guide(description: "Exercise prompt shown to the student in Vietnamese (asking about the English word)")
    var prompt: String
    @Guide(description: "The correct answer in English (the target language being learned)")
    var correctAnswer: String
    @Guide(description: "4 multiple choice options in English (the target language), include correct answer in list", .count(4))
    var options: [String]
}

// MARK: - Feedback Generation

@Generable
struct GeneratedFeedback {
    @Guide(description: "Number of correct answers out of total", .range(0...6))
    var score: Int
    @Guide(description: "Encouraging or corrective comment in Vietnamese")
    var commentVi: String
    @Guide(description: "Corrections for each wrong answer, empty if all correct")
    var corrections: [GeneratedCorrection]
}

@Generable
struct GeneratedCorrection {
    @Guide(description: "The exercise prompt that was answered wrong")
    var prompt: String
    @Guide(description: "What the student answered")
    var studentAnswer: String
    @Guide(description: "The correct answer")
    var correctedAnswer: String
    @Guide(description: "Brief explanation in Vietnamese")
    var explanation: String
}

#endif
