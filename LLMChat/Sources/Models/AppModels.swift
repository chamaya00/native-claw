import Foundation
import UIKit

// MARK: - Language Direction

enum LanguageDirection: String, CaseIterable {
    case vietnameseToEnglish  // Vietnamese speaker learning English
    case englishToVietnamese  // English speaker learning Vietnamese

    /// The language the learner already speaks.
    var nativeLanguageCode: String {
        switch self {
        case .vietnameseToEnglish: return "vi"
        case .englishToVietnamese: return "en"
        }
    }

    /// The language the learner is studying.
    var targetLanguageCode: String {
        switch self {
        case .vietnameseToEnglish: return "en"
        case .englishToVietnamese: return "vi"
        }
    }

    /// BCP-47 code for TTS of the target language.
    var ttsLanguageCode: String {
        switch self {
        case .vietnameseToEnglish: return "en-US"
        case .englishToVietnamese: return "vi-VN"
        }
    }

    /// Short label shown in the direction picker.
    var label: String {
        switch self {
        case .vietnameseToEnglish: return "🇻🇳 → 🇬🇧 English"
        case .englishToVietnamese: return "🇬🇧 → 🇻🇳 Tiếng Việt"
        }
    }

    /// Fallback name when learner name is absent.
    var defaultLearnerName: String {
        switch self {
        case .vietnameseToEnglish: return "bạn"
        case .englishToVietnamese: return "friend"
        }
    }
}

// MARK: - Session Phase

enum SessionPhase: Equatable {
    case greeting
    case topicSelection
    case wordGeneration
    case wordSelection
    case flashcardGeneration
    case flashcardReview
    case practiceRound
    case feedback
    case freeChat
}

// MARK: - Learner Profile

struct LearnerProfile {
    var name: String
    var direction: LanguageDirection
}

// MARK: - Topic

struct Topic: Identifiable {
    let id: UUID
    let emoji: String
    let labelVi: String
    let labelEn: String

    func label(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? labelVi : labelEn
    }

    static let defaults: [Topic] = [
        Topic(id: UUID(), emoji: "🍔", labelVi: "Đồ ăn", labelEn: "Food"),
        Topic(id: UUID(), emoji: "✈️", labelVi: "Du lịch", labelEn: "Travel"),
        Topic(id: UUID(), emoji: "💼", labelVi: "Công việc", labelEn: "Work"),
        Topic(id: UUID(), emoji: "🏠", labelVi: "Nhà cửa", labelEn: "Home"),
        Topic(id: UUID(), emoji: "🏥", labelVi: "Sức khỏe", labelEn: "Health"),
        Topic(id: UUID(), emoji: "🛍️", labelVi: "Mua sắm", labelEn: "Shopping"),
    ]
}

// MARK: - Word Entry

struct WordEntry: Identifiable {
    let id: UUID
    let english: String
    let vietnamese: String
    let partOfSpeech: String
    let exampleSentence: String

    /// The word in the learner's native language.
    func nativeWord(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? vietnamese : english
    }

    /// The word in the language being learned.
    func targetWord(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? english : vietnamese
    }

    // Hardcoded starter words (10 nouns per topic).
    // LLM generation will replace this after user history is implemented.
    static func stubWords(for topic: Topic) -> [WordEntry] {
        switch topic.labelEn {
        case "Food":
            return [
                WordEntry(id: UUID(), english: "recipe",      vietnamese: "công thức nấu ăn", partOfSpeech: "noun", exampleSentence: "Can you share the recipe?"),
                WordEntry(id: UUID(), english: "ingredient",  vietnamese: "nguyên liệu",       partOfSpeech: "noun", exampleSentence: "Fresh ingredients make better food."),
                WordEntry(id: UUID(), english: "meal",        vietnamese: "bữa ăn",            partOfSpeech: "noun", exampleSentence: "We enjoy every meal together."),
                WordEntry(id: UUID(), english: "restaurant",  vietnamese: "nhà hàng",           partOfSpeech: "noun", exampleSentence: "Let's go to a restaurant tonight."),
                WordEntry(id: UUID(), english: "dessert",     vietnamese: "món tráng miệng",    partOfSpeech: "noun", exampleSentence: "I always want dessert after dinner."),
                WordEntry(id: UUID(), english: "breakfast",   vietnamese: "bữa sáng",           partOfSpeech: "noun", exampleSentence: "Breakfast is the most important meal."),
                WordEntry(id: UUID(), english: "vegetable",   vietnamese: "rau củ",             partOfSpeech: "noun", exampleSentence: "Eat more vegetables every day."),
                WordEntry(id: UUID(), english: "chopstick",   vietnamese: "đũa",                partOfSpeech: "noun", exampleSentence: "She uses chopsticks to eat rice."),
                WordEntry(id: UUID(), english: "flavor",      vietnamese: "hương vị",           partOfSpeech: "noun", exampleSentence: "This dish has a rich flavor."),
                WordEntry(id: UUID(), english: "noodle",      vietnamese: "mì",                 partOfSpeech: "noun", exampleSentence: "I love noodle soup for lunch."),
            ]
        case "Travel":
            return [
                WordEntry(id: UUID(), english: "journey",     vietnamese: "chuyến đi",          partOfSpeech: "noun", exampleSentence: "Our journey was amazing."),
                WordEntry(id: UUID(), english: "passport",    vietnamese: "hộ chiếu",           partOfSpeech: "noun", exampleSentence: "Don't forget your passport!"),
                WordEntry(id: UUID(), english: "luggage",     vietnamese: "hành lý",            partOfSpeech: "noun", exampleSentence: "My luggage is very heavy."),
                WordEntry(id: UUID(), english: "destination", vietnamese: "điểm đến",           partOfSpeech: "noun", exampleSentence: "Paris is our destination."),
                WordEntry(id: UUID(), english: "souvenir",    vietnamese: "quà lưu niệm",       partOfSpeech: "noun", exampleSentence: "I bought a souvenir for my mom."),
                WordEntry(id: UUID(), english: "hotel",       vietnamese: "khách sạn",          partOfSpeech: "noun", exampleSentence: "The hotel is near the beach."),
                WordEntry(id: UUID(), english: "ticket",      vietnamese: "vé",                 partOfSpeech: "noun", exampleSentence: "I need two tickets please."),
                WordEntry(id: UUID(), english: "airport",     vietnamese: "sân bay",            partOfSpeech: "noun", exampleSentence: "The airport opens at 5 AM."),
                WordEntry(id: UUID(), english: "itinerary",   vietnamese: "lịch trình",         partOfSpeech: "noun", exampleSentence: "We planned the itinerary together."),
                WordEntry(id: UUID(), english: "map",         vietnamese: "bản đồ",             partOfSpeech: "noun", exampleSentence: "Check the map before you go."),
            ]
        case "Work":
            return [
                WordEntry(id: UUID(), english: "meeting",     vietnamese: "cuộc họp",           partOfSpeech: "noun", exampleSentence: "We have a meeting at 9 AM."),
                WordEntry(id: UUID(), english: "deadline",    vietnamese: "thời hạn",           partOfSpeech: "noun", exampleSentence: "The deadline is Friday."),
                WordEntry(id: UUID(), english: "colleague",   vietnamese: "đồng nghiệp",        partOfSpeech: "noun", exampleSentence: "My colleague helped me finish the report."),
                WordEntry(id: UUID(), english: "office",      vietnamese: "văn phòng",          partOfSpeech: "noun", exampleSentence: "I work in an open office."),
                WordEntry(id: UUID(), english: "project",     vietnamese: "dự án",              partOfSpeech: "noun", exampleSentence: "This project has three phases."),
                WordEntry(id: UUID(), english: "salary",      vietnamese: "lương",              partOfSpeech: "noun", exampleSentence: "She received a salary raise."),
                WordEntry(id: UUID(), english: "contract",    vietnamese: "hợp đồng",           partOfSpeech: "noun", exampleSentence: "Please sign the contract."),
                WordEntry(id: UUID(), english: "manager",     vietnamese: "quản lý",            partOfSpeech: "noun", exampleSentence: "The manager gave feedback."),
                WordEntry(id: UUID(), english: "presentation",vietnamese: "bài thuyết trình",   partOfSpeech: "noun", exampleSentence: "Her presentation was very clear."),
                WordEntry(id: UUID(), english: "promotion",   vietnamese: "sự thăng chức",      partOfSpeech: "noun", exampleSentence: "He got a promotion last month."),
            ]
        case "Home":
            return [
                WordEntry(id: UUID(), english: "kitchen",     vietnamese: "nhà bếp",            partOfSpeech: "noun", exampleSentence: "The kitchen smells amazing."),
                WordEntry(id: UUID(), english: "bedroom",     vietnamese: "phòng ngủ",          partOfSpeech: "noun", exampleSentence: "Her bedroom is very cozy."),
                WordEntry(id: UUID(), english: "furniture",   vietnamese: "đồ nội thất",        partOfSpeech: "noun", exampleSentence: "We bought new furniture last week."),
                WordEntry(id: UUID(), english: "neighbor",    vietnamese: "hàng xóm",           partOfSpeech: "noun", exampleSentence: "My neighbor is very friendly."),
                WordEntry(id: UUID(), english: "balcony",     vietnamese: "ban công",           partOfSpeech: "noun", exampleSentence: "We drink coffee on the balcony."),
                WordEntry(id: UUID(), english: "appliance",   vietnamese: "thiết bị gia dụng",  partOfSpeech: "noun", exampleSentence: "Every appliance is energy efficient."),
                WordEntry(id: UUID(), english: "ceiling",     vietnamese: "trần nhà",           partOfSpeech: "noun", exampleSentence: "The ceiling is very high."),
                WordEntry(id: UUID(), english: "garden",      vietnamese: "khu vườn",           partOfSpeech: "noun", exampleSentence: "She grows herbs in her garden."),
                WordEntry(id: UUID(), english: "doorbell",    vietnamese: "chuông cửa",         partOfSpeech: "noun", exampleSentence: "The doorbell rang twice."),
                WordEntry(id: UUID(), english: "hallway",     vietnamese: "hành lang",          partOfSpeech: "noun", exampleSentence: "Hang your coat in the hallway."),
            ]
        case "Health":
            return [
                WordEntry(id: UUID(), english: "doctor",      vietnamese: "bác sĩ",             partOfSpeech: "noun", exampleSentence: "The doctor prescribed medicine."),
                WordEntry(id: UUID(), english: "hospital",    vietnamese: "bệnh viện",          partOfSpeech: "noun", exampleSentence: "He was taken to the hospital."),
                WordEntry(id: UUID(), english: "medicine",    vietnamese: "thuốc",              partOfSpeech: "noun", exampleSentence: "Take your medicine after meals."),
                WordEntry(id: UUID(), english: "symptom",     vietnamese: "triệu chứng",        partOfSpeech: "noun", exampleSentence: "Fever is a common symptom."),
                WordEntry(id: UUID(), english: "appointment", vietnamese: "cuộc hẹn",           partOfSpeech: "noun", exampleSentence: "I have a doctor appointment today."),
                WordEntry(id: UUID(), english: "pharmacy",    vietnamese: "nhà thuốc",          partOfSpeech: "noun", exampleSentence: "The pharmacy closes at 10 PM."),
                WordEntry(id: UUID(), english: "diet",        vietnamese: "chế độ ăn",          partOfSpeech: "noun", exampleSentence: "A balanced diet keeps you healthy."),
                WordEntry(id: UUID(), english: "vitamin",     vietnamese: "vitamin",            partOfSpeech: "noun", exampleSentence: "Vitamin C boosts your immune system."),
                WordEntry(id: UUID(), english: "allergy",     vietnamese: "dị ứng",             partOfSpeech: "noun", exampleSentence: "She has an allergy to peanuts."),
                WordEntry(id: UUID(), english: "surgeon",     vietnamese: "bác sĩ phẫu thuật",  partOfSpeech: "noun", exampleSentence: "The surgeon performed the operation."),
            ]
        case "Shopping":
            return [
                WordEntry(id: UUID(), english: "receipt",     vietnamese: "hóa đơn",            partOfSpeech: "noun", exampleSentence: "Keep the receipt for returns."),
                WordEntry(id: UUID(), english: "discount",    vietnamese: "khoản giảm giá",     partOfSpeech: "noun", exampleSentence: "There is a 20% discount today."),
                WordEntry(id: UUID(), english: "cashier",     vietnamese: "thu ngân",           partOfSpeech: "noun", exampleSentence: "The cashier was very polite."),
                WordEntry(id: UUID(), english: "cart",        vietnamese: "xe đẩy hàng",        partOfSpeech: "noun", exampleSentence: "Put the items in the cart."),
                WordEntry(id: UUID(), english: "brand",       vietnamese: "thương hiệu",        partOfSpeech: "noun", exampleSentence: "That brand is very popular."),
                WordEntry(id: UUID(), english: "refund",      vietnamese: "tiền hoàn lại",      partOfSpeech: "noun", exampleSentence: "I requested a refund online."),
                WordEntry(id: UUID(), english: "aisle",       vietnamese: "lối đi",             partOfSpeech: "noun", exampleSentence: "The sugar is in aisle five."),
                WordEntry(id: UUID(), english: "coupon",      vietnamese: "phiếu giảm giá",     partOfSpeech: "noun", exampleSentence: "Use this coupon for 10% off."),
                WordEntry(id: UUID(), english: "checkout",    vietnamese: "quầy tính tiền",     partOfSpeech: "noun", exampleSentence: "There is a line at the checkout."),
                WordEntry(id: UUID(), english: "bargain",     vietnamese: "món hàng rẻ",        partOfSpeech: "noun", exampleSentence: "That coat was a real bargain."),
            ]
        default:
            return []
        }
    }
}

// MARK: - Flashcard

struct Flashcard: Identifiable {
    let id: UUID
    let wordEntry: WordEntry
    let mnemonicVi: String
    let exampleEn: String
    let exampleVi: String
    let phoneticVi: String  // pronunciation using Vietnamese phonemes
    let phoneticEn: String  // intuitive English phonetics with CAPS for stress
    var image: UIImage?

    // STUB
    static func stub(for word: WordEntry) -> Flashcard {
        let (pVi, pEn) = stubPhonetics[word.english.lowercased()] ?? (word.english, word.english.uppercased())
        return Flashcard(
            id: UUID(),
            wordEntry: word,
            mnemonicVi: "Nhớ từ \"\(word.english)\" giống như \"\(word.vietnamese)\" — hãy tưởng tượng hình ảnh!",
            exampleEn: word.exampleSentence,
            exampleVi: "Câu ví dụ bằng tiếng Việt cho \"\(word.vietnamese)\".",
            phoneticVi: pVi,
            phoneticEn: pEn
        )
    }

    private static let stubPhonetics: [String: (String, String)] = [
        // Food
        "recipe":        ("re-xi-pi",             "RES-ih-pee"),
        "ingredient":    ("in-gri-đi-ợt",         "in-GREE-dee-ent"),
        "meal":          ("min",                  "MEEL"),
        "restaurant":    ("re-xờ-tơ-rần",         "RES-tuh-runt"),
        "dessert":       ("đi-zợt",               "deh-ZURT"),
        "breakfast":     ("brek-phớt",            "BREK-fust"),
        "vegetable":     ("vệch-tờ-bồl",          "VEJ-tuh-bul"),
        "chopstick":     ("chóp-xtíc",            "CHOP-stik"),
        "flavor":        ("phléi-vờ",             "FLAY-ver"),
        "noodle":        ("nu-đồl",               "NOO-dul"),
        // Travel
        "journey":       ("dơ-ni",                "JUR-nee"),
        "passport":      ("pa-xờ-pót",            "PAS-port"),
        "luggage":       ("lắc-gịt",              "LUG-ij"),
        "destination":   ("đe-xờ-ti-nê-shần",     "des-tih-NAY-shun"),
        "souvenir":      ("xu-vờ-nia",            "soo-veh-NEER"),
        "hotel":         ("hô-ten",               "hoh-TEL"),
        "ticket":        ("tích-kịt",             "TIK-it"),
        "airport":       ("e-pót",                "AIR-port"),
        "itinerary":     ("ai-ti-nờ-re-ri",       "eye-TIN-uh-rer-ee"),
        "map":           ("mép",                  "MAP"),
        // Work
        "meeting":       ("mi-tinh",              "MEE-ting"),
        "deadline":      ("đét-lai",              "DED-lyne"),
        "colleague":     ("co-lig",               "KOL-eeg"),
        "office":        ("o-phịt",               "AW-fis"),
        "project":       ("pro-dzhết",            "PROJ-ekt"),
        "salary":        ("xe-lờ-ri",             "SAL-uh-ree"),
        "contract":      ("con-trét",             "KON-trakt"),
        "manager":       ("me-nịt-dzhờ",          "MAN-ih-jer"),
        "presentation":  ("pre-zen-tê-shần",      "prez-en-TAY-shun"),
        "promotion":     ("prờ-mou-shần",         "pruh-MOH-shun"),
        // Home
        "kitchen":       ("kít-chần",             "KIT-chun"),
        "bedroom":       ("béd-rum",              "BED-room"),
        "furniture":     ("phơ-ni-chờ",           "FUR-nih-cher"),
        "neighbor":      ("néi-bờ",               "NAY-ber"),
        "balcony":       ("bel-cờ-ni",            "BAL-kuh-nee"),
        "appliance":     ("ờ-plai-ợnt",           "uh-PLY-unts"),
        "ceiling":       ("xi-linh",              "SEE-ling"),
        "garden":        ("ga-đần",               "GAR-den"),
        "doorbell":      ("đo-ben",               "DOR-bel"),
        "hallway":       ("hon-uây",              "HAWL-way"),
        // Health
        "doctor":        ("đóc-tờ",               "DOK-ter"),
        "hospital":      ("hóx-pi-tồl",           "HOS-pih-tul"),
        "medicine":      ("me-đi-xần",            "MED-ih-sun"),
        "symptom":       ("xim-tờm",              "SIM-tum"),
        "appointment":   ("ờ-point-mợnt",         "uh-POINT-ment"),
        "pharmacy":      ("pha-mờ-xi",            "FAR-muh-see"),
        "diet":          ("đai-ợt",               "DY-et"),
        "vitamin":       ("vai-tờ-min",           "VY-tuh-min"),
        "allergy":       ("e-lờ-dzi",             "AL-er-jee"),
        "surgeon":       ("xơ-dzhần",             "SUR-jun"),
        // Shopping
        "receipt":       ("ri-xít",               "rih-SEET"),
        "discount":      ("đít-kao",              "DIS-kount"),
        "cashier":       ("ke-shia",              "ka-SHEER"),
        "cart":          ("kát",                  "KART"),
        "brand":         ("bren",                 "BRAND"),
        "refund":        ("ri-phănd",             "REE-fund"),
        "aisle":         ("ai",                   "YLE"),
        "coupon":        ("kiu-pon",              "KYOO-pon"),
        "checkout":      ("chéc-ao",              "CHEK-out"),
        "bargain":       ("ba-gần",               "BAR-gun"),
    ]
}

// MARK: - Exercise

enum ExerciseType: String {
    case fillBlank
    case multipleChoice
    case translate
}

struct Exercise: Identifiable {
    let id: UUID
    let type: ExerciseType
    let prompt: String
    let correctAnswer: String
    let options: [String]
    let wordEntry: WordEntry

    // STUB: generate 6 exercises (2 per word, up to 3 words) with mix of types
    static func stubExercises(for words: [WordEntry], direction: LanguageDirection = .vietnameseToEnglish) -> [Exercise] {
        var exercises: [Exercise] = []
        let limited = Array(words.prefix(3))
        for word in limited {
            if direction == .vietnameseToEnglish {
                // Vi→En: show English word, ask for Vietnamese meaning
                exercises.append(Exercise(
                    id: UUID(),
                    type: .multipleChoice,
                    prompt: "'\(word.english)' nghĩa là gì?",
                    correctAnswer: word.vietnamese,
                    options: distractors(correct: word.vietnamese, pool: limited.map { $0.vietnamese }),
                    wordEntry: word
                ))
                exercises.append(Exercise(
                    id: UUID(),
                    type: .translate,
                    prompt: "Dịch sang tiếng Anh: \"\(word.vietnamese)\"",
                    correctAnswer: word.english,
                    options: [],
                    wordEntry: word
                ))
            } else {
                // En→Vi: show Vietnamese word, ask for English meaning
                exercises.append(Exercise(
                    id: UUID(),
                    type: .multipleChoice,
                    prompt: "What does '\(word.vietnamese)' mean?",
                    correctAnswer: word.english,
                    options: distractors(correct: word.english, pool: limited.map { $0.english }),
                    wordEntry: word
                ))
                exercises.append(Exercise(
                    id: UUID(),
                    type: .translate,
                    prompt: "Translate to Vietnamese: \"\(word.english)\"",
                    correctAnswer: word.vietnamese,
                    options: [],
                    wordEntry: word
                ))
            }
        }
        return exercises
    }

    private static func distractors(correct: String, pool: [String]) -> [String] {
        var options = [correct]
        let others = pool.filter { $0 != correct }
        options += others.prefix(3)
        while options.count < 4 {
            options.append("---")
        }
        return options.shuffled()
    }
}

// MARK: - Exercise Result

struct ExerciseResult {
    let exerciseId: UUID
    let userAnswer: String
    let isCorrect: Bool
}

// MARK: - Practice Round

struct PracticeRound {
    var exercises: [Exercise]
    var results: [ExerciseResult]
}

// MARK: - Round Feedback

struct RoundFeedback {
    let score: Int
    let total: Int
    let commentVi: String
    let corrections: [Correction]

    struct Correction {
        let prompt: String
        let studentAnswer: String
        let correctedAnswer: String
        let explanation: String
    }

    // STUB
    static func stub(score: Int, results: [ExerciseResult], exercises: [Exercise], direction: LanguageDirection = .vietnameseToEnglish) -> RoundFeedback {
        let total = exercises.count
        let comment: String
        if direction == .vietnameseToEnglish {
            if score == total {
                comment = "Xuất sắc! Bạn trả lời đúng tất cả câu hỏi! 🎉"
            } else if score >= total / 2 {
                comment = "Tốt lắm! Bạn trả lời đúng \(score)/\(total) câu. Tiếp tục luyện tập nhé! 💪"
            } else {
                comment = "Cố lên! Bạn trả lời đúng \(score)/\(total) câu. Hãy ôn lại và thử lần nữa! 📖"
            }
        } else {
            if score == total {
                comment = "Excellent! You got all answers right! 🎉"
            } else if score >= total / 2 {
                comment = "Good job! You got \(score)/\(total) correct. Keep practicing! 💪"
            } else {
                comment = "Keep going! You got \(score)/\(total) correct. Review and try again! 📖"
            }
        }

        var corrections: [Correction] = []
        for result in results where !result.isCorrect {
            if let exercise = exercises.first(where: { $0.id == result.exerciseId }) {
                let explanation = direction == .vietnameseToEnglish
                    ? "Câu trả lời đúng là \"\(exercise.correctAnswer)\"."
                    : "The correct answer is \"\(exercise.correctAnswer)\"."
                corrections.append(Correction(
                    prompt: exercise.prompt,
                    studentAnswer: result.userAnswer,
                    correctedAnswer: exercise.correctAnswer,
                    explanation: explanation
                ))
            }
        }

        return RoundFeedback(score: score, total: total, commentVi: comment, corrections: corrections)
    }
}

// MARK: - Quick Reply

enum QuickReplyAction {
    case newTopic
    case addMoreWords
    case freeChat
    case tryAgain
}

struct QuickReply: Identifiable {
    let id: UUID
    let labelVi: String
    let labelEn: String
    let action: QuickReplyAction

    func label(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? labelVi : labelEn
    }

    static let postFeedback: [QuickReply] = [
        QuickReply(id: UUID(), labelVi: "Chủ đề mới", labelEn: "New topic", action: .newTopic),
        QuickReply(id: UUID(), labelVi: "Thêm từ mới", labelEn: "More words", action: .addMoreWords),
        QuickReply(id: UUID(), labelVi: "Hỏi tự do", labelEn: "Free chat", action: .freeChat),
    ]
}
