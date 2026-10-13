import Foundation

/// The research the focus plan is built on. Every rule, break idea, phase and metric
/// points at one or more of these, and the app shows them on request.
///
/// Only peer-reviewed work is listed, with what it actually found. Where the evidence is
/// thin or popular claims overreach, `FocusScience.limits` says so plainly.
struct Citation: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case proximalGoals, selfEfficacy, goalSetting, implementationIntentions, habitFormation
        case phonePresence, notificationCost, interruptionCost, attentionResidue, shortFormVideo
        case planMaking, mindWandering, microBreaks, breaksVigilance, vigilanceWork
        case natureAttention, restorationTheory, exerciseCognition, diaphragmaticBreathing
        case premackPrinciple, progressMonitoring, circadianCognition
    }

    let id: ID
    let authors: String
    let year: Int
    let title: String
    let venue: String
    /// What the study found, in plain words.
    let finding: String

    var shortLabel: String { "\(authors.components(separatedBy: ",").first ?? authors) (\(year))" }

    var reference: String { "\(authors) (\(year)). \(title). \(venue)." }

    /// A search, not a guessed link: it always resolves to the paper's real listing.
    var scholarURL: URL? {
        var components = URLComponents(string: "https://scholar.google.com/scholar")
        components?.queryItems = [URLQueryItem(name: "q", value: "\"\(title)\" \(year)")]
        return components?.url
    }
}

enum FocusScience {
    static func citation(_ id: Citation.ID) -> Citation { library[id]! }

    static func citations(_ ids: [Citation.ID]) -> [Citation] { ids.map(citation) }

    static let library: [Citation.ID: Citation] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let all: [Citation] = [
        Citation(id: .proximalGoals, authors: "Bandura, A., & Schunk, D. H.", year: 1981,
                 title: "Cultivating competence, self-efficacy, and intrinsic interest through proximal self-motivation",
                 venue: "Journal of Personality and Social Psychology, 41(3), 586–598",
                 finding: "Children given small, near-term goals progressed faster, felt more capable and enjoyed the work more than those given one distant goal. The plan's 5-minute steps are proximal goals."),
        Citation(id: .selfEfficacy, authors: "Bandura, A.", year: 1977,
                 title: "Self-efficacy: Toward a unifying theory of behavioral change",
                 venue: "Psychological Review, 84(2), 191–215",
                 finding: "Mastery experiences, actually succeeding, are the strongest source of belief in your ability. That is why the plan starts below your limit and steps back when blocks keep failing."),
        Citation(id: .goalSetting, authors: "Locke, E. A., & Latham, G. P.", year: 2002,
                 title: "Building a practically useful theory of goal setting and task motivation: A 35-year odyssey",
                 venue: "American Psychologist, 57(9), 705–717",
                 finding: "Specific, challenging-but-reachable goals with feedback outperform vague 'do your best' goals across hundreds of studies."),
        Citation(id: .implementationIntentions, authors: "Gollwitzer, P. M.", year: 1999,
                 title: "Implementation intentions: Strong effects of simple plans",
                 venue: "American Psychologist, 54(7), 493–503",
                 finding: "Deciding in advance when and where you'll act ('at 7 pm at my desk, I start a block') makes people far more likely to actually start."),
        Citation(id: .habitFormation, authors: "Lally, P., van Jaarsveld, C. H. M., Potts, H. W. W., & Wardle, J.", year: 2010,
                 title: "How are habits formed: Modelling habit formation in the real world",
                 venue: "European Journal of Social Psychology, 40(6), 998–1009",
                 finding: "Repeating a behaviour in the same context made it automatic in a median of 66 days (range 18–254). Missing a single day did not derail it."),
        Citation(id: .phonePresence, authors: "Ward, A. F., Duke, K., Gneezy, A., & Bos, M. W.", year: 2017,
                 title: "Brain drain: The mere presence of one's own smartphone reduces available cognitive capacity",
                 venue: "Journal of the Association for Consumer Research, 2(2), 140–154",
                 finding: "Working memory and fluid intelligence scores were highest with the phone in another room, even compared with the phone face-down and silent on the desk."),
        Citation(id: .notificationCost, authors: "Stothart, C., Mitchum, A., & Yehnert, C.", year: 2015,
                 title: "The attentional cost of receiving a cell phone notification",
                 venue: "Journal of Experimental Psychology: Human Perception and Performance, 41(4), 893–897",
                 finding: "Just receiving a notification, without looking at it, disrupted performance on an attention task about as much as using the phone."),
        Citation(id: .interruptionCost, authors: "Mark, G., Gudith, D., & Klocke, U.", year: 2008,
                 title: "The cost of interrupted work: More speed and stress",
                 venue: "Proceedings of CHI 2008, 107–110",
                 finding: "Interrupted people compensated by working faster, at the cost of more stress, frustration and effort."),
        Citation(id: .attentionResidue, authors: "Leroy, S.", year: 2009,
                 title: "Why is it so hard to do my work? The challenge of attention residue when switching between work tasks",
                 venue: "Organizational Behavior and Human Decision Processes, 109(2), 168–181",
                 finding: "After switching tasks, part of your attention stays on the old one ('attention residue'), lowering performance on the new one. Batching checks reduces switches."),
        Citation(id: .shortFormVideo, authors: "Chiossi, F., Haliburton, L., Ou, C., Butz, A., & Schmidt, A.", year: 2023,
                 title: "Short-form videos degrade our capacity to retain intentions: Effect of context switching on prospective memory",
                 venue: "Proceedings of CHI 2023",
                 finding: "Watching short-form video feeds (TikTok-style) impaired people's ability to remember and carry out intended tasks afterwards, more than other activities."),
        Citation(id: .planMaking, authors: "Masicampo, E. J., & Baumeister, R. F.", year: 2011,
                 title: "Consider it done! Plan making can eliminate the cognitive effects of unfulfilled goals",
                 venue: "Journal of Personality and Social Psychology, 101(4), 667–683",
                 finding: "Unfinished goals keep intruding on your thoughts, but writing down a concrete plan for them stopped the intrusions. That is the 'later list'."),
        Citation(id: .mindWandering, authors: "Killingsworth, M. A., & Gilbert, D. T.", year: 2010,
                 title: "A wandering mind is an unhappy mind",
                 venue: "Science, 330(6006), 932",
                 finding: "Sampling thousands of people through the day, minds wandered about 47% of the time, and people were less happy while it did."),
        Citation(id: .microBreaks, authors: "Albulescu, P., Macsinga, I., Rusu, A., Sulea, C., Bodnaru, A., & Tulbure, B. T.", year: 2022,
                 title: "\"Give me a break!\" A systematic review and meta-analysis on the efficacy of micro-breaks for increasing well-being and performance",
                 venue: "PLOS ONE, 17(8), e0272460",
                 finding: "Short breaks reliably boosted vigour and reduced fatigue. Performance gains were clearer for routine work and with longer breaks."),
        Citation(id: .breaksVigilance, authors: "Ariga, A., & Lleras, A.", year: 2011,
                 title: "Brief and rare mental \"breaks\" keep you focused: Deactivation and reactivation of task goals preempt vigilance decrements",
                 venue: "Cognition, 118(3), 439–443",
                 finding: "On a long task, people who briefly switched away and back did not show the usual decline in performance; those who never paused did."),
        Citation(id: .vigilanceWork, authors: "Warm, J. S., Parasuraman, R., & Matthews, G.", year: 2008,
                 title: "Vigilance requires hard mental work and is stressful",
                 venue: "Human Factors, 50(3), 433–441",
                 finding: "Sustaining attention is effortful and tiring, and performance declines over time. Rest is part of the work, not a reward for it."),
        Citation(id: .natureAttention, authors: "Berman, M. G., Jonides, J., & Kaplan, S.", year: 2008,
                 title: "The cognitive benefits of interacting with nature",
                 venue: "Psychological Science, 19(12), 1207–1212",
                 finding: "A walk in nature, or even viewing nature pictures, improved directed-attention performance compared with an urban walk."),
        Citation(id: .restorationTheory, authors: "Kaplan, S.", year: 1995,
                 title: "The restorative benefits of nature: Toward an integrative framework",
                 venue: "Journal of Environmental Psychology, 15(3), 169–182",
                 finding: "Attention Restoration Theory: effortless, 'softly fascinating' surroundings let the attention you use for focus recover."),
        Citation(id: .exerciseCognition, authors: "Hillman, C. H., Erickson, K. I., & Kramer, A. F.", year: 2008,
                 title: "Be smart, exercise your heart: Exercise effects on brain and cognition",
                 venue: "Nature Reviews Neuroscience, 9(1), 58–65",
                 finding: "Physical activity, including single bouts, is associated with better attention and executive function."),
        Citation(id: .diaphragmaticBreathing, authors: "Ma, X., Yue, Z.-Q., Gong, Z.-Q., Zhang, H., Duan, N.-Y., Shi, Y.-T., Wei, G.-X., & Li, Y.-F.", year: 2017,
                 title: "The effect of diaphragmatic breathing on attention, negative affect and stress in healthy adults",
                 venue: "Frontiers in Psychology, 8, 874",
                 finding: "Eight weeks of slow diaphragmatic breathing practice improved sustained attention and lowered stress compared with controls."),
        Citation(id: .premackPrinciple, authors: "Premack, D.", year: 1959,
                 title: "Toward empirical behavior laws: I. Positive reinforcement",
                 venue: "Psychological Review, 66(4), 219–233",
                 finding: "A preferred activity can reinforce a less-preferred one when it comes after it ('first work, then play')."),
        Citation(id: .progressMonitoring, authors: "Harkin, B., Webb, T. L., Chang, B. P. I., Prestwich, A., Conner, M., Kellar, I., Benn, Y., & Sheeran, P.", year: 2016,
                 title: "Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence",
                 venue: "Psychological Bulletin, 142(2), 198–229",
                 finding: "Across 138 studies, tracking your progress increased goal attainment, especially when progress was recorded or made visible."),
        Citation(id: .circadianCognition, authors: "Schmidt, C., Collette, F., Cajochen, C., & Peigneux, P.", year: 2007,
                 title: "A time to think: Circadian rhythms in human cognition",
                 venue: "Cognitive Neuropsychology, 24(7), 755–789",
                 finding: "Attention and other cognitive abilities vary over the day and peak at different times for morning and evening types."),
    ]

    /// Where the evidence stops. Shown at the bottom of the sources sheet.
    static let limits: [String] = [
        "No study shows that one block length, 25, 45 or 90 minutes, is best for everyone. The plan uses your own completion rate to decide when you're ready for longer blocks.",
        "\"Dopamine detox\" is a popular idea, not a literal effect: breaks won't lower your dopamine. What the research supports is removing cues and interruptions, rewarding effort after it happens, and choosing breaks that don't hijack your attention.",
        "Most studies measure averages over weeks, not individual people. Treat the plan as a well-founded starting point and adjust it to how you actually respond.",
        "This is not medical advice. If focus problems are severe or persistent, an assessment by a doctor or psychologist (for example, for ADHD, sleep problems or depression) can help more than any timer."
    ]
}
