import Foundation
import SwiftUI

// MARK: - Glossary

struct GlossaryTerm: Decodable, Identifiable, Hashable {
    var term: String
    var definition: String
    var aliases: [String] = []
    var id: String { term }

    enum CodingKeys: String, CodingKey { case term, definition, aliases }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        definition = (try? c.decode(String.self, forKey: .definition)) ?? ""
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
    }
}

/// Terms from Shared/Resources/glossary.json, plus helpers that turn plain prose into text with tappable terms.
final class Glossary {
    static let shared = Glossary()
    static let scheme = "stillpoint-glossary"
    let terms: [GlossaryTerm]

    private init() {
        struct File: Decodable { var terms: [GlossaryTerm]? }
        if let url = Bundle.main.url(forResource: "glossary", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let f = try? JSONDecoder().decode(File.self, from: d) {
            terms = (f.terms ?? []).sorted { $0.term.lowercased() < $1.term.lowercased() }
        } else {
            terms = []
        }
    }

    func term(_ id: String) -> GlossaryTerm? {
        terms.first { $0.term.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// The term a glossary link points at, or nil for ordinary links.
    func term(for url: URL) -> GlossaryTerm? {
        guard url.scheme == Self.scheme, let host = url.host?.removingPercentEncoding else { return nil }
        return term(host)
    }

    /// Marks the first occurrence of each glossary term (or alias) in `text` as a dotted-underlined link.
    func attributed(_ text: String, accent: Color) -> AttributedString {
        var out = AttributedString(text)
        var taken: [Range<AttributedString.Index>] = []
        for t in terms {
            let needles = [t.term] + t.aliases
            for n in needles where n.count >= 3 {
                guard let r = out.range(of: n, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                if taken.contains(where: { $0.overlaps(r) }) { continue }
                let encoded = t.term.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? t.term
                guard let url = URL(string: "\(Self.scheme)://\(encoded)") else { continue }
                out[r].link = url
                out[r].underlineStyle = Text.LineStyle(pattern: .dot)
                out[r].foregroundColor = accent
                taken.append(r)
                break
            }
        }
        return out
    }
}

// MARK: - Practice info (purpose, mechanism, feel, history, research)

struct ResearchSource: Identifiable, Hashable {
    var id: String
    var title: String
    var url: URL?
}

/// What we show on the "About this practice" page. Curated lines where we have them; sensible,
/// hedged derivations from the tradition and kind where we don't.
struct PracticeInfo {
    let practice: Practice
    let tradition: Tradition?
    let era: String
    let purpose: String
    let mechanism: String
    let feel: String
    let bestFor: [Intention]
    let history: String
    let sources: [ResearchSource]
    let safety: String?
    let didYouKnow: String?

    init(practice p: Practice, library lib: PracticeLibrary = .shared) {
        practice = p
        let t = lib.tradition(p.traditionId)
        tradition = t
        era = PracticeInfo.eras[p.traditionId] ?? ""
        let extra = PracticeInfo.extra(p.id)
        purpose = extra?.purpose ?? PracticeInfo.defaultPurpose(p)
        mechanism = extra?.mechanism ?? PracticeInfo.defaultMechanism(p)
        feel = extra?.feel ?? PracticeInfo.defaultFeel(p)
        bestFor = lib.intentions.filter { $0.practiceIds.contains(p.id) }
        history = p.about.isEmpty ? (t?.summary ?? "") : p.about
        sources = p.sources.map { id in
            let note = lib.note(for: id)
            let url = PracticeInfo.firstURL(in: note)
            var title = note
            if let u = url?.absoluteString, let r = title.range(of: u) { title.removeSubrange(r) }
            title = title.replacingOccurrences(of: " and ", with: " · ").trimmingCharacters(in: CharacterSet(charactersIn: " .;,"))
            if title.isEmpty { title = id }
            return ResearchSource(id: id, title: title, url: url)
        }
        safety = p.safety
        didYouKnow = extra?.fact
    }

    private static func firstURL(in s: String) -> URL? {
        guard let r = s.range(of: "https?://[^\\s)]+", options: .regularExpression) else { return nil }
        return URL(string: String(s[r]))
    }

    // Fallbacks by kind, phrased carefully.
    private static func defaultPurpose(_ p: Practice) -> String {
        switch p.kind.lowercased() {
        case "breath": return "To settle the body and steady the mind by shaping the breath."
        case "loving": return "To open the heart: warmth toward yourself and others."
        case "mantra": return "To rest attention on a simple repeated phrase until the mind quietens."
        case "body": return "To bring attention down out of thought and into the felt body."
        case "walking": return "To carry stillness into movement, one slow step at a time."
        case "visual": return "To gather scattered attention onto a single point."
        case "focus": return "To train a calm, steady attention."
        case "movement": return "To loosen the body and wake it gently before sitting still."
        case "open": return "To sit with whatever is here, without steering it."
        default: return "A short practice for settling and clarity."
        }
    }

    private static func defaultMechanism(_ p: Practice) -> String {
        if let pat = p.pattern, !p.isMovement {
            let bpm = pat.breathsPerMinute
            if pat.exhale > pat.inhale {
                return "A longer exhale than inhale leans the nervous system toward its parasympathetic, rest-and-digest side, which tends to slow the heart. Reviews of slow breathing link it with calmer arousal."
            }
            if bpm > 0 && bpm < 7 {
                return "Breathing at roughly five to six breaths a minute brings heart rhythm and breath into step (coherent breathing), which research links with higher HRV and a steadier baroreflex."
            }
            return "A regular, counted rhythm gives attention a simple job and slows the breath; slow, attentive breathing is associated with lower arousal in reviews."
        }
        switch p.kind.lowercased() {
        case "loving": return "Deliberately generating warmth appears to shift mood and reduce self-criticism; reviews of loving-kindness practice report gains in positive emotion and connection."
        case "mantra": return "A repeated phrase gives the wandering mind a soft anchor. Returning to it, again and again, is the training; thought quiets as a side effect."
        case "body": return "Sweeping attention through sensation strengthens interoception and interrupts rumination, which many people find settling."
        case "walking": return "Slow, rhythmic movement paired with attention steadies breathing and gives restless energy somewhere to go."
        case "visual": return "Holding a single visual target narrows attention and reduces eye and mind movement; a classic way to quiet mental chatter."
        case "movement": return "Gentle, rhythmic movement warms joints and muscles, raises circulation, and makes it easier to sit still afterwards."
        default: return "Attention training: noticing when the mind has wandered and returning, kindly, is the whole exercise."
        }
    }

    private static func defaultFeel(_ p: Practice) -> String {
        switch p.kind.lowercased() {
        case "breath": return "A slowing in the chest, warmth in the hands, perhaps a little lightness at first. Restlessness in the opening minute is normal."
        case "loving": return "Warmth or softness around the heart; sometimes nothing at all, which is also fine. Feelings follow practice, not the other way round."
        case "mantra": return "The phrase becomes quieter and more automatic; gaps of silence open between repetitions."
        case "body": return "Tingling, warmth, pressure, or areas that feel blank. Simply noting them is the practice."
        case "walking": return "Weight shifting foot to foot, the ground meeting you; the breath settling into the pace."
        case "visual": return "Eyes may water a little. The edges of attention go quiet; the point seems to hold you."
        case "movement": return "Joints loosening, breath deepening, a pleasant warmth. Stay well inside a comfortable range."
        default: return "Quiet, then thoughts, then quiet again. Each return is the practice working."
        }
    }

    static let eras: [String: String] = [
        "zen": "12th–13th c. Japan, from Chinese Chan",
        "theravada": "From the 3rd c. BCE, Pāli Canon",
        "tibetan": "8th c. onward, Himalayan Buddhism",
        "yoga": "Haṭha texts, 11th–15th c., older roots",
        "sufi": "Islamic mysticism, 9th c. onward",
        "christian": "Desert Fathers, 4th c. onward",
        "taoist": "Daoist practice, 4th c. BCE onward",
        "japan-nature": "Term coined in Japan, 1982",
        "modern": "Lab-studied, 20th–21st c.",
        "thai": "Thai traditional medicine, centuries old",
        "japan": "Japan, 20th c. routines"
    ]

    struct Extra { let purpose: String; let mechanism: String; let feel: String; let fact: String? }

    static func extra(_ id: String) -> Extra? {
        switch id {
        case "zazen-count": return Extra(purpose: "To give a busy mind one simple job: count the out-breath, one to ten.",
            mechanism: "Counting occupies verbal thought, and noticing when the count is lost is attention training in miniature. A naturally longer exhale nudges the body toward rest.",
            feel: "Upright and alert, breath slowing; the count will slip, and the gentle return is the point.",
            fact: "Both Sōtō and Rinzai Zen give breath counting to beginners before any kōan or 'just sitting'.")
        case "shikantaza": return Extra(purpose: "To sit, wholly, with nothing to achieve.",
            mechanism: "Dropping every technique removes the usual striving; attention widens to include everything without grasping. Open-monitoring practice is linked with less rumination.",
            feel: "Spacious, sometimes boring, sometimes vivid. Posture carries the practice.",
            fact: "Dōgen's instruction is to sit 'like a mountain': the posture is the meditation.")
        case "kinhin": return Extra(purpose: "To keep meditation going while the legs wake up.",
            mechanism: "Pairing one small step with each breath keeps attention on the body; the slow pace lowers arousal without the stiffness of long sitting.",
            feel: "Weight rolling heel to toe, the room moving slowly past; a calm, awake feeling.",
            fact: "In Rinzai halls kinhin is brisk; in Sōtō it is a half-step per breath.")
        case "anapanasati": return Extra(purpose: "To know the breath as it is: long, short, coming, going.",
            mechanism: "Sustained attention on breath sensation strengthens interoception and quiets the default mode network's wandering.",
            feel: "Coolness at the nostrils, the belly's rise and fall; a gradual thinning of thought.",
            fact: "The Ānāpānasati Sutta describes sixteen steps, from feeling the breath to letting go.")
        case "vipassana-scan": return Extra(purpose: "To meet sensation directly, without liking or disliking it.",
            mechanism: "Moving attention systematically through the body builds equanimity with discomfort and trains interoceptive awareness.",
            feel: "Tingling, heat, pressure, numb patches; the sweep moves on regardless.",
            fact: "The body sweep was popularised worldwide through S. N. Goenka's ten-day retreats.")
        case "metta": return Extra(purpose: "To wish well, sincerely and widely.",
            mechanism: "Repeating good wishes toward self and others appears to raise positive emotion and social connection in trials of loving-kindness practice.",
            feel: "Warmth, sometimes tears, sometimes dryness. The wish counts even when the feeling is quiet.",
            fact: "The Mettā Sutta is traditionally chanted as a blessing and a protection.")
        case "buddho": return Extra(purpose: "To ride the breath on a two-syllable word until the mind settles.",
            mechanism: "'Bud' on the inhale and 'dho' on the exhale ties attention to each breath; the Thai Forest teachers used it as a gateway to deeper calm.",
            feel: "The word softens and the breath takes over; a quiet, collected steadiness.",
            fact: "Ajahn Chah said if you lose the breath, just come back to 'Buddho' — the one who knows.")
        case "tonglen": return Extra(purpose: "To turn the heart toward difficulty instead of away.",
            mechanism: "Breathing in another's pain and breathing out relief reverses the habit of avoidance; compassion practice is associated with resilience rather than burnout.",
            feel: "Heaviness on the in-breath, lightness and space on the out-breath. Start with someone easy to love.",
            fact: "Pema Chödrön teaches tonglen 'on the spot', for the stranger in the queue as much as for loved ones.")
        case "nine-breaths": return Extra(purpose: "To clear the channels before sitting.",
            mechanism: "Alternating nostril breaths with a vivid intention give both body and imagination a clean slate; a short ritual that marks the shift into practice.",
            feel: "Clearer nostrils, a settled chest, a sense of starting fresh.",
            fact: "In Bön and Tibetan Buddhism this is the classic opening before many longer practices.")
        case "shamatha": return Extra(purpose: "To make attention steady and clear.",
            mechanism: "Resting on one object and returning each time it drifts is attention training; over time the mind stabilises and the body relaxes with it.",
            feel: "Short stretches of stillness, then drift, then return. Those returns are the gains.",
            fact: "Classical texts describe nine stages of attention, from placing to settled stillness.")
        case "nadi-shodhana": return Extra(purpose: "To balance and quieten before stillness or sleep.",
            mechanism: "Breathing through one nostril at a time slows the breath and adds a small motor task that keeps attention present. Slow breathing is linked with calmer arousal.",
            feel: "Cool air on one side, warm on the other; the head feels clearer.",
            fact: "Nāḍī means 'channel' and śodhana 'cleansing' — a purification of the subtle body in yoga.")
        case "bhramari": return Extra(purpose: "To soothe a racing mind with sound you feel rather than hear.",
            mechanism: "Humming lengthens the exhale and dramatically increases nasal nitric oxide; the vibration gives attention a felt anchor.",
            feel: "A buzz in the face and skull, a long slow out-breath, drowsiness afterwards.",
            fact: "Humming can raise nasal nitric oxide fifteen-fold compared with quiet exhaling.")
        case "ujjayi": return Extra(purpose: "To make the breath audible so attention stays with it.",
            mechanism: "A slight narrowing of the throat slows airflow and gives a sound to follow, which steadies both breath rate and focus.",
            feel: "An ocean-like whisper in the throat, warmth building gently.",
            fact: "Ujjāyī is the breath used throughout Ashtanga vinyasa practice.")
        case "sama-vritti": return Extra(purpose: "To even out the breath, and with it the mind.",
            mechanism: "Equal inhale and exhale remove the pull of either pace; a regular rhythm around six breaths a minute tends to raise HRV.",
            feel: "Balanced and plain; nothing dramatic, which is the idea.",
            fact: "Sama means 'equal', vṛtti 'fluctuation' — evenness in every wave of breath.")
        case "so-hum": return Extra(purpose: "To let a natural mantra ride the breath.",
            mechanism: "Hearing 'so' on the inhale and 'hum' on the exhale turns the breath itself into the mantra; no effort of repetition is needed.",
            feel: "Breath and sound blend; a quiet sense of 'I am that'.",
            fact: "Some yoga texts say we repeat So Hum 21,600 times a day without noticing — once per breath.")
        case "trataka": return Extra(purpose: "To gather attention to a single point.",
            mechanism: "Steady gazing suppresses eye movement and, with it, much mental chatter; the after-image gives the closed eyes something to rest on.",
            feel: "Eyes may water; then a stillness, and a glowing after-image.",
            fact: "Trāṭaka appears among the six cleansing practices of the Haṭha Yoga Pradīpikā.")
        case "yoga-nidra": return Extra(purpose: "To rest deeply while staying awake.",
            mechanism: "Guided rotation of attention through the body relaxes muscle tone and slows brain rhythms toward the sleep border without crossing it.",
            feel: "Heaviness, warmth, drifting; time seems to compress.",
            fact: "Twenty minutes of yoga nidra is often described as feeling like a short nap — without the grogginess.")
        case "dhikr-breath": return Extra(purpose: "To remember the sacred with every breath.",
            mechanism: "A rhythmic phrase bound to the breath occupies speech and attention together; repetition slows the breath and the mind follows.",
            feel: "Rhythm first, then a hush beneath it.",
            fact: "The Naqshbandi principle 'hūsh dar dam' means 'awareness in the breath'.")
        case "heart-breath": return Extra(purpose: "To breathe as if from the heart.",
            mechanism: "Placing attention at the chest while slowing the breath pairs interoception with a calming rhythm; heart-focused breathing is used in HRV coherence training.",
            feel: "Warmth or openness in the chest; the breath feels gentler there.",
            fact: "Sufi teachers describe the heart as a mirror that the breath polishes.")
        case "centering-prayer": return Extra(purpose: "To consent to silence, returning to one sacred word.",
            mechanism: "A single word acts as a gentle reset whenever thoughts arise; the practice is receptive rather than effortful, which many find restful.",
            feel: "Long quiet, many thoughts, the word returning like a hand on the shoulder.",
            fact: "Centering prayer was shaped in the 1970s by Trappist monks drawing on The Cloud of Unknowing.")
        case "jesus-prayer": return Extra(purpose: "To pray without ceasing, on the breath.",
            mechanism: "A short prayer split across inhale and exhale ties devotion to rhythm; as in other breath mantras, the pace slows and attention narrows.",
            feel: "The words sink from the lips to the heart; stillness between them.",
            fact: "The Way of a Pilgrim tells of a wanderer who repeated the prayer thousands of times a day.")
        case "lectio": return Extra(purpose: "To read a few words slowly enough to be changed by them.",
            mechanism: "Four movements — read, reflect, respond, rest — slow thought down and end in silence rather than analysis.",
            feel: "One phrase keeps returning; then a quiet, listening rest.",
            fact: "Guigo II likened the four steps to a ladder from earth to heaven.")
        case "microcosmic-orbit": return Extra(purpose: "To circulate attention in a loop through the body.",
            mechanism: "Tracing a path up the spine and down the front keeps attention moving and embodied; the imagery lends structure to a long sit.",
            feel: "Warmth or tingling moving along the path; a rooted, full feeling in the lower belly.",
            fact: "The orbit links the two main channels of Daoist anatomy, the Governing and Conception vessels.")
        case "embryonic-breath": return Extra(purpose: "To breathe so softly it feels like no breath at all.",
            mechanism: "Letting the breath become minimal and low in the belly lowers arousal and raises comfort with slightly higher CO₂.",
            feel: "Very quiet; the belly barely moves. Sleep may come close.",
            fact: "Daoist texts describe the ideal breath as so gentle a feather at the nose would not stir.")
        case "zhan-zhuang": return Extra(purpose: "To find stillness standing up.",
            mechanism: "Holding a relaxed standing posture builds postural strength and steady attention; the effort is in releasing, not holding.",
            feel: "Legs trembling, shoulders wanting to rise, then a settled, rooted ease.",
            fact: "Wang Xiangzhai made standing the heart of his art, Yiquan, in the early 20th century.")
        case "forest-bathing": return Extra(purpose: "To let a forest do the settling for you.",
            mechanism: "Slow walking among trees, attending through the senses, lowers stress markers in studies and gives attention a restorative, effortless object.",
            feel: "Air, scent, the texture of light; time loosening.",
            fact: "Shinrin-yoku was named by Japan's Forestry Agency in 1982 as a public-health idea.")
        case "box": return Extra(purpose: "To steady yourself quickly, anywhere.",
            mechanism: "Equal counts make the breath regular and slow; the holds add a mild CO₂ challenge that trains tolerance. Simple enough to use under pressure.",
            feel: "Square, contained, composed. Holds may feel long at first; shorten them.",
            fact: "Box breathing is widely taught to first responders and military units for composure.")
        case "478": return Extra(purpose: "To wind down toward sleep.",
            mechanism: "A long exhale and a hold slow the breath to about three a minute, leaning hard toward the parasympathetic side.",
            feel: "A little light-headed at first, then heavy and drowsy.",
            fact: "Dr Andrew Weil suggests four cycles, twice a day, and no more than that while learning.")
        case "resonance": return Extra(purpose: "To bring heart and breath into one rhythm.",
            mechanism: "At around 5.5 breaths a minute the baroreflex and breath synchronise, maximising HRV; this is the pace used in HRV biofeedback.",
            feel: "Even and unhurried; a gentle swell in the chest with each breath.",
            fact: "Most adults resonate between 4.5 and 7 breaths a minute — 5.5 is a good average.")
        case "sigh": return Extra(purpose: "To offload tension in a single breath.",
            mechanism: "Two inhales re-inflate collapsed air sacs and a long exhale clears CO₂, a reflex the body already uses. A 2023 trial found cyclic sighing improved mood more than mindfulness.",
            feel: "A relieving drop in the shoulders; often immediate.",
            fact: "We sigh involuntarily about every five minutes to keep the lungs healthy.")
        case "long-exhale": return Extra(purpose: "To calm by lengthening the out-breath.",
            mechanism: "Exhaling longer than inhaling slows the heart on each breath (respiratory sinus arrhythmia) and tilts the autonomic balance toward rest.",
            feel: "A pleasant heaviness; the mind slows with the breath.",
            fact: "This single principle — longer out than in — underlies most calming breath patterns.")
        case "baduanjin": return Extra(purpose: "To warm the whole body with eight gentle moves.",
            mechanism: "Slow, full-range movement with the breath raises circulation and joint mobility while keeping heart rate low.",
            feel: "Stretch along the sides and spine, warmth in the hands, a brighter mood.",
            fact: "'Brocade' suggests something precious: the set has been practised for around 800 years.")
        case "taichi-cloud": return Extra(purpose: "To move slowly, weight shifting, mind settling.",
            mechanism: "Continuous slow movement with turning of the waist trains balance and attention together; tai chi is well studied for balance and stress.",
            feel: "Weight pouring from one leg to the other; hands floating.",
            fact: "'Cloud hands' appears in every major tai chi family style.")
        case "rajio-taiso": return Extra(purpose: "To wake the body up in three minutes.",
            mechanism: "A brisk full-body routine raises heart rate briefly and loosens the joints; good before sitting, or on its own.",
            feel: "Breathing deeper, a light warmth, a sense of being switched on.",
            fact: "Rajio Taisō has aired on Japanese radio since 1928 and is still done in parks each morning.")
        case "makko-ho": return Extra(purpose: "To open the hips and spine with four simple stretches.",
            mechanism: "Long, relaxed holds let muscles lengthen; the exhale is used to soften into each position.",
            feel: "A deep stretch that eases on the out-breath. Never force it.",
            fact: "Makkō-hō was developed in Japan in the 1930s by Wataru Nagai after his own recovery.")
        case "surya-gentle": return Extra(purpose: "To greet the day with a slow, breathing sequence.",
            mechanism: "Linking each posture to an inhale or exhale makes the sequence a moving breath practice; done slowly it warms without strain.",
            feel: "Spine waking up, breath deepening, warmth spreading.",
            fact: "A slow sun salutation can be done at a quarter of its usual speed as a moving meditation.")
        case "ruesi-dat-ton": return Extra(purpose: "To stretch the way Thai hermits did, with the breath.",
            mechanism: "Self-stretches held with slow breathing release the back and hips; the same lineage informs Thai massage.",
            feel: "Lengthening along the spine, calm and loose afterwards.",
            fact: "Statues of hermits in these poses stand in the grounds of Wat Pho in Bangkok.")
        case "do-in": return Extra(purpose: "To wake the body with your own hands.",
            mechanism: "Tapping, rubbing and pressing the body's surface raises local circulation and brings attention into the skin and muscles.",
            feel: "Tingling, warmth, alertness; a pleasant sense of being 'in' your body.",
            fact: "Do-in is the Japanese reading of the Chinese 'daoyin', ancient guiding-and-pulling exercises.")
        case "lujong-warmup": return Extra(purpose: "To free the joints before sitting.",
            mechanism: "Circling each joint in turn lubricates it and releases held tension, so sitting is easier and longer.",
            feel: "Clicks and release, then a looser, lighter frame.",
            fact: "Lu Jong, 'body training', comes from Tibetan monastic and medical traditions.")
            default: return nil
        }
    }
}
