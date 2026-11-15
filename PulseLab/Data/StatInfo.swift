import Foundation

/// Plain-English context for a metric's detail screen: what it is, why it matters, how to nudge it,
/// and which other metrics to look at next. General wellness information, not medical advice.
struct StatInfo {
    enum Better { case higher, lower }

    var what: String
    var why: String
    var improve: [String]
    /// AllStats ids shown as "Related" links.
    var related: [String]
    /// Which direction is usually the good one for you (colours the trend arrow). Nil = neither.
    var better: Better? = nil
}

@MainActor
enum StatGuide {
    /// Name used by `Compare.agreements` for a stat id, when the two trackers can be scored against each other.
    static func compareName(_ id: String) -> String? {
        switch id {
        case "rhr": "Resting HR"
        case "hrv": "HRV"
        case "resp": "Respiratory rate"
        case "spo2": "Blood oxygen"
        case "tempDev": "Temp deviation"
        case "totalKcal": "Calories"
        case "asleep": "Sleep"
        case "deep": "Deep sleep"
        case "rem": "REM sleep"
        default: nil
        }
    }

    static func info(_ def: StatDef) -> StatInfo {
        if let i = table[def.id] { return i }
        if def.id.hasPrefix("zone") {
            return StatInfo(what: def.note,
                            why: String(localized: "Time spread across heart-rate zones shows whether your training is mostly easy, mostly hard or a mix."),
                            improve: [String(localized: "Most weekly training time in zones 1–2 builds an aerobic base."),
                                      String(localized: "Keep zone 4–5 work to short, planned efforts with easy days around them.")],
                            related: ["workoutMin", "strain", "workoutHR"])
        }
        return StatInfo(what: def.note, why: fallbackWhy(def.section), improve: fallbackImprove(def.section), related: fallbackRelated(def.section))
    }

    private static func fallbackWhy(_ s: StatSection) -> String {
        switch s {
        case .recovery: String(localized: "Overnight signals like this move with sleep, stress, training load and illness, so changes from your own normal are worth noticing.")
        case .sleep: String(localized: "Sleep is when your body recovers; how long and how well you sleep shows up in almost every other number the next day.")
        case .strain: String(localized: "Day-to-day activity adds up: it shapes fitness, energy use and how much recovery you need.")
        case .heart: String(localized: "Heart numbers taken during everyday activity track fitness changes over weeks.")
        case .body: String(localized: "Body measurements change slowly; the trend over weeks matters far more than any single reading.")
        case .mobility: String(localized: "How you walk and move tends to stay steady; lasting changes are worth a look.")
        case .nutrition: String(localized: "What you log here gives context to energy, sleep and recovery.")
        }
    }

    private static func fallbackImprove(_ s: StatSection) -> [String] {
        switch s {
        case .recovery: [String(localized: "Keep a regular sleep schedule."), String(localized: "Balance hard training days with easy ones.")]
        case .sleep: [String(localized: "Go to bed and get up at similar times every day."), String(localized: "Keep the bedroom dark, quiet and cool.")]
        case .strain: [String(localized: "Build activity gradually, week over week."), String(localized: "Mix movement through the day rather than one long sit.")]
        case .heart: [String(localized: "Regular easy cardio improves most heart numbers over time."), String(localized: "Compare like with like: similar times, similar activities.")]
        case .body: [String(localized: "Measure at the same time of day, under the same conditions."), String(localized: "Look at the weekly average, not single days.")]
        case .mobility: [String(localized: "Walk regularly at a comfortable, brisk pace."), String(localized: "Keep your phone in the same pocket for consistent readings.")]
        case .nutrition: [String(localized: "Log consistently, so trends are meaningful."), String(localized: "Pair logs with how you slept and felt.")]
        }
    }

    private static func fallbackRelated(_ s: StatSection) -> [String] {
        switch s {
        case .recovery: ["readiness", "hrv", "rhr"]
        case .sleep: ["asleep", "efficiency", "readiness"]
        case .strain: ["steps", "activeKcal", "strain"]
        case .heart: ["rhr", "vo2", "avgHR"]
        case .body: ["weight", "bodyFat", "bmi"]
        case .mobility: ["walkSpeed", "steps", "asymmetry"]
        case .nutrition: ["food", "totalKcal", "asleep"]
        }
    }

    private static let table: [String: StatInfo] = [
        "readiness": StatInfo(
            what: String(localized: "Pulse Lab's own 1–99 score from your Apple Watch: overnight HRV and resting heart rate against your baseline, plus last night's sleep."),
            why: String(localized: "It's a quick read on how your body is handling recent load, built to sit next to WHOOP recovery so you can see when they agree."),
            improve: [String(localized: "Wear your Watch to bed so HRV, sleep, breathing and temperature are measured overnight."),
                      String(localized: "Aim for 7+ hours asleep on a regular schedule."),
                      String(localized: "Follow hard days with easier ones."),
                      String(localized: "Late meals and alcohol tend to lower next-morning scores.")],
            related: ["recovery", "hrv", "rhr", "asleep"], better: .higher),
        "recovery": StatInfo(
            what: String(localized: "WHOOP's 0–100% recovery, scored each morning from HRV, resting heart rate, sleep and breathing rate."),
            why: String(localized: "It sums up how ready your body is for strain today. Green is 67+, yellow 34–66, red below 34."),
            improve: [String(localized: "Prioritise sleep: WHOOP weighs it heavily."),
                      String(localized: "Match strain to recovery: push on green days, go easy on red ones."),
                      String(localized: "Hydrate and avoid late alcohol.")],
            related: ["readiness", "hrv", "rhr", "performance"], better: .higher),
        "recoveryVs": StatInfo(
            what: String(localized: "WHOOP recovery and Pulse Lab's Watch readiness on one chart, both 0–100."),
            why: String(localized: "When both agree you can trust the read; when they split, last night's sleep usually explains why."),
            improve: [String(localized: "Wear both trackers to bed for comparable mornings."),
                      String(localized: "Keep a regular sleep schedule.")],
            related: ["readiness", "recovery", "hrv"], better: .higher),
        "hrv": StatInfo(
            what: String(localized: "How much the time between heartbeats varies, in milliseconds. Watch reports SDNN; WHOOP reports RMSSD, which usually reads higher."),
            why: String(localized: "HRV rises when you're well rested and drops with stress, hard training, poor sleep, alcohol or illness. Your own trend matters more than the number."),
            improve: [String(localized: "Keep bed and wake times consistent."),
                      String(localized: "Slow breathing (about 6 breaths a minute) for a few minutes a day."),
                      String(localized: "Build training gradually and take easy days."),
                      String(localized: "Limit alcohol, especially in the evening.")],
            related: ["readiness", "rhr", "asleep", "resp"], better: .higher),
        "rhr": StatInfo(
            what: String(localized: "Your lowest steady heart rate. WHOOP takes it during deep sleep; the Watch estimates it from calm moments across the day."),
            why: String(localized: "It tends to fall as fitness improves and rise a few beats with fatigue, stress, heat, alcohol or a cold coming on."),
            improve: [String(localized: "Regular aerobic exercise lowers it over weeks."),
                      String(localized: "Sleep enough and keep hydrated."),
                      String(localized: "Notice spikes after late meals or alcohol.")],
            related: ["hrv", "readiness", "walkHR", "vo2"], better: .lower),
        "spo2": StatInfo(
            what: String(localized: "How saturated your blood is with oxygen, mostly measured while you sleep."),
            why: String(localized: "It's usually steady in the mid-to-high 90s. Altitude and a loose band can lower readings; wrist sensors are less precise than a finger clip."),
            improve: [String(localized: "Wear the band snug, about a finger's width above the wrist bone."),
                      String(localized: "Look at the weekly trend rather than single nights.")],
            related: ["resp", "breathingDist", "asleep"], better: .higher),
        "tempDev": StatInfo(
            what: String(localized: "Wrist (Watch) or skin (WHOOP) temperature during sleep, shown as change from your own average, not body temperature."),
            why: String(localized: "Rises can come with a hot room, alcohol, late meals, the menstrual cycle or a cold coming on. Readiness takes points off when it's raised."),
            improve: [String(localized: "Keep the bedroom cool and the bedding consistent."),
                      String(localized: "Avoid heavy late meals and alcohol before bed.")],
            related: ["readiness", "resp", "rhr"], better: nil),
        "skinTemp": StatInfo(
            what: String(localized: "WHOOP's absolute skin temperature while you sleep."),
            why: String(localized: "Skin temperature depends on the room and bedding, so the change from your usual matters more than the number."),
            improve: [String(localized: "Keep sleep conditions consistent so changes mean something.")],
            related: ["tempDev", "recovery"]),
        "resp": StatInfo(
            what: String(localized: "Breaths per minute while you sleep."),
            why: String(localized: "It's very stable night to night, so a rise of 1 or more can follow heavy training, alcohol or a cold. Readiness takes points off when it's raised."),
            improve: [String(localized: "Wear your tracker to bed for a nightly reading."),
                      String(localized: "Compare with your own baseline, not other people.")],
            related: ["readiness", "spo2", "hrv"], better: .lower),
        "asleep": StatInfo(
            what: String(localized: "Time actually asleep (light + deep + REM), credited to the morning you woke up."),
            why: String(localized: "Most adults feel and perform best with 7–9 hours. Short nights show up as lower HRV, higher resting HR and lower readiness."),
            improve: [String(localized: "Set a regular bedtime and wake time, weekends too."),
                      String(localized: "Dim screens and lights for the last hour."),
                      String(localized: "Keep caffeine to the morning."),
                      String(localized: "A cool, dark, quiet room helps.")],
            related: ["readiness", "deep", "rem", "efficiency"], better: .higher),
        "inBed": StatInfo(
            what: String(localized: "Time in bed, whether asleep or not."),
            why: String(localized: "Giving yourself enough time in bed is the first step to enough sleep."),
            improve: [String(localized: "Allow about 30 minutes more in bed than the sleep you want.")],
            related: ["asleep", "efficiency"]),
        "deep": StatInfo(
            what: String(localized: "Slow-wave sleep, the deepest stage. It's front-loaded into the first half of the night."),
            why: String(localized: "Deep sleep is when the body does much of its physical recovery. Trackers estimate stages and disagree on them."),
            improve: [String(localized: "Regular exercise, not too close to bedtime."),
                      String(localized: "Avoid alcohol in the evening."),
                      String(localized: "Keep the room cool.")],
            related: ["asleep", "rem", "readiness"], better: .higher),
        "rem": StatInfo(
            what: String(localized: "Dream sleep, mostly in the second half of the night."),
            why: String(localized: "REM is linked to memory and mood. Cutting the night short cuts REM the most."),
            improve: [String(localized: "Protect the last hours of sleep: avoid early alarms when you can."),
                      String(localized: "Limit alcohol, which suppresses REM.")],
            related: ["asleep", "deep"], better: .higher),
        "light": StatInfo(
            what: String(localized: "Core or light sleep, the bulk of the night."),
            why: String(localized: "Light sleep fills about half the night and links the deeper stages."),
            improve: [String(localized: "Focus on total sleep; light sleep follows.")],
            related: ["asleep", "deep", "rem"]),
        "awake": StatInfo(
            what: String(localized: "Time awake between falling asleep and getting up."),
            why: String(localized: "Some waking is normal. Long or frequent wake-ups make sleep less restful."),
            improve: [String(localized: "Keep the room dark and quiet."),
                      String(localized: "Limit fluids and alcohol late in the evening.")],
            related: ["efficiency", "asleep", "disturbances"], better: .lower),
        "efficiency": StatInfo(
            what: String(localized: "The share of time in bed you were actually asleep."),
            why: String(localized: "85% or more is generally considered good. Low efficiency often means too long in bed or broken sleep."),
            improve: [String(localized: "Go to bed when sleepy, not just tired."),
                      String(localized: "Get up at the same time every day.")],
            related: ["asleep", "awake", "inBed"], better: .higher),
        "performance": StatInfo(
            what: String(localized: "WHOOP: the sleep you got compared with the sleep it estimated you needed."),
            why: String(localized: "It folds sleep debt and strain into one percentage; WHOOP weighs it heavily in recovery."),
            improve: [String(localized: "Go to bed earlier after hard days."),
                      String(localized: "Pay back sleep debt with a slightly longer night.")],
            related: ["need", "asleep", "recovery"], better: .higher),
        "consistency": StatInfo(
            what: String(localized: "WHOOP: how similar your bed and wake times are from day to day."),
            why: String(localized: "A regular schedule keeps your body clock steady, which helps sleep quality."),
            improve: [String(localized: "Keep wake time within about 30 minutes, weekends included.")],
            related: ["asleep", "performance"], better: .higher),
        "need": StatInfo(
            what: String(localized: "WHOOP's estimate of sleep you need tonight: baseline plus sleep debt and recent strain, minus naps."),
            why: String(localized: "It moves with your training and past nights, so it's a nightly target rather than a fixed number."),
            improve: [String(localized: "Use it to plan bedtime on hard training days.")],
            related: ["performance", "asleep", "strain"]),
        "cycles": StatInfo(
            what: String(localized: "WHOOP: complete sleep cycles in the night, each about 90 minutes."),
            why: String(localized: "More complete cycles usually means a longer, less broken night."),
            improve: [String(localized: "A longer, uninterrupted night adds cycles.")],
            related: ["asleep", "disturbances"], better: .higher),
        "disturbances": StatInfo(
            what: String(localized: "WHOOP: times you were disturbed during the night."),
            why: String(localized: "Fewer disturbances means more continuous sleep."),
            improve: [String(localized: "Reduce noise and light; keep pets and phones out of bed.")],
            related: ["awake", "efficiency"], better: .lower),
        "breathingDist": StatInfo(
            what: String(localized: "Watch: how often breathing was briefly interrupted, per hour asleep."),
            why: String(localized: "Apple uses this for its sleep apnea notifications. Look at the long-term trend; talk to a doctor if it worries you."),
            improve: [String(localized: "Sleep position, alcohol and congestion can all raise it.")],
            related: ["spo2", "resp", "asleep"], better: .lower),
        "strain": StatInfo(
            what: String(localized: "WHOOP's 0–21 day strain, from how hard and how long your heart worked."),
            why: String(localized: "It's built to be matched to recovery: higher strain on green days, lower on red."),
            improve: [String(localized: "Plan hard sessions for well-recovered days."),
                      String(localized: "Keep easy days truly easy.")],
            related: ["recovery", "workoutStrain", "totalKcal"]),
        "totalKcal": StatInfo(
            what: String(localized: "Everything you burned in the day: active plus resting energy."),
            why: String(localized: "It's an estimate; the two trackers often differ by a few hundred kcal. Your own trend is what's useful."),
            improve: [String(localized: "More daily movement raises it more than one big workout."),
                      String(localized: "Keep your height, weight and age up to date in Health.")],
            related: ["activeKcal", "basalKcal", "steps"]),
        "activeKcal": StatInfo(
            what: String(localized: "Calories burned above resting, from movement and exercise."),
            why: String(localized: "It drives the Move ring and shows how active the day was."),
            improve: [String(localized: "Short walks after meals add up."),
                      String(localized: "Take stairs and stand up regularly.")],
            related: ["totalKcal", "steps", "exercise"], better: .higher),
        "basalKcal": StatInfo(
            what: String(localized: "Calories your body burns at rest to keep running."),
            why: String(localized: "It depends mostly on body size and changes slowly."),
            improve: [String(localized: "Strength training can raise it slightly over time.")],
            related: ["totalKcal", "weight", "lean"]),
        "steps": StatInfo(
            what: String(localized: "Steps counted from motion, de-duplicated between Watch and iPhone by Health."),
            why: String(localized: "Regular walking is one of the simplest habits linked to everyday health and energy."),
            improve: [String(localized: "Add a 10-minute walk after meals."),
                      String(localized: "Take calls on foot."),
                      String(localized: "Raise your daily goal gradually.")],
            related: ["distance", "activeKcal", "walkSpeed"], better: .higher),
        "distance": StatInfo(
            what: String(localized: "Distance covered on foot, walking and running."),
            why: String(localized: "It tracks how much you move under your own power."),
            improve: [String(localized: "Build weekly distance gradually.")],
            related: ["steps", "walkSpeed"], better: .higher),
        "flights": StatInfo(
            what: String(localized: "Flights of stairs climbed, about 3 m / 10 ft each."),
            why: String(localized: "Climbing is a quick way to raise your heart rate during the day."),
            improve: [String(localized: "Choose stairs over lifts when you can.")],
            related: ["steps", "activeKcal"], better: .higher),
        "exercise": StatInfo(
            what: String(localized: "Minutes of brisk-or-harder movement (the green Exercise ring)."),
            why: String(localized: "Common guidance suggests about 150 minutes of moderate activity a week."),
            improve: [String(localized: "Brisk walking counts: aim for 20–30 minutes a day.")],
            related: ["activeKcal", "workoutMin", "steps"], better: .higher),
        "standMin": StatInfo(
            what: String(localized: "Minutes spent standing and moving."),
            why: String(localized: "Breaking up long sitting keeps you moving through the day."),
            improve: [String(localized: "Stand or walk for a few minutes every hour.")],
            related: ["standHours", "steps"], better: .higher),
        "standHours": StatInfo(
            what: String(localized: "Hours with at least a minute of standing (the blue Stand ring)."),
            why: String(localized: "It nudges you to move a little every hour."),
            improve: [String(localized: "Use the Watch's stand reminders.")],
            related: ["standMin", "steps"], better: .higher),
        "cycling": StatInfo(
            what: String(localized: "Distance ridden on a bike."),
            why: String(localized: "Cycling builds aerobic fitness with low impact."),
            improve: [String(localized: "Build distance gradually.")],
            related: ["workoutMin", "activeKcal"]),
        "daylight": StatInfo(
            what: String(localized: "Minutes outdoors in daylight, measured by the Watch."),
            why: String(localized: "Daylight, especially in the morning, helps set your body clock and can make it easier to fall asleep at night."),
            improve: [String(localized: "Get outside within an hour of waking."),
                      String(localized: "Take a walk at lunch.")],
            related: ["asleep", "steps"], better: .higher),
        "workoutMin": StatInfo(
            what: String(localized: "Total minutes of logged workouts in the day."),
            why: String(localized: "Training time over the week matters more than any single session."),
            improve: [String(localized: "Plan the week with easy and hard days.")],
            related: ["exercise", "strain", "workoutHR"]),
        "workoutStrain": StatInfo(
            what: String(localized: "WHOOP strain from the day's hardest workout."),
            why: String(localized: "It shows how much a session demanded, compared on the same 0–21 scale as day strain."),
            improve: [String(localized: "Match workout strain to recovery.")],
            related: ["strain", "recovery"]),
        "avgHR": StatInfo(
            what: String(localized: "Average heart rate across the whole day (WHOOP: across the cycle)."),
            why: String(localized: "It mixes rest and activity, so it's useful as a trend alongside resting HR."),
            improve: [String(localized: "Fitness and good sleep tend to lower it over time.")],
            related: ["rhr", "walkHR"]),
        "maxHR": StatInfo(
            what: String(localized: "WHOOP: the highest heart rate in the cycle."),
            why: String(localized: "It shows how hard your hardest moment was."),
            improve: [String(localized: "Use it to check hard sessions reached the intensity you planned.")],
            related: ["strain", "avgHR"]),
        "walkHR": StatInfo(
            what: String(localized: "Average heart rate while walking."),
            why: String(localized: "Walking is a steady effort, so this drifts down as fitness improves."),
            improve: [String(localized: "Regular brisk walking and cardio lower it over months.")],
            related: ["rhr", "vo2", "walkSpeed"], better: .lower),
        "hrRecovery": StatInfo(
            what: String(localized: "How far your heart rate drops in the minute after a workout ends."),
            why: String(localized: "A bigger drop generally goes with better cardio fitness."),
            improve: [String(localized: "End workouts with a short, easy cool-down."),
                      String(localized: "Regular aerobic training improves it.")],
            related: ["vo2", "rhr"], better: .higher),
        "vo2": StatInfo(
            what: String(localized: "Apple's cardio fitness estimate, from heart rate during outdoor walks, runs and hikes."),
            why: String(localized: "It's one of the best single measures of aerobic fitness and changes over weeks to months."),
            improve: [String(localized: "Mix steady zone 2 work with some harder intervals."),
                      String(localized: "Do outdoor walks or runs with the Watch so it can update.")],
            related: ["rhr", "hrRecovery", "walkHR"], better: .higher),
        "workoutHR": StatInfo(
            what: String(localized: "Average heart rate across the day's workouts."),
            why: String(localized: "Compare it for similar sessions: the same effort at a lower heart rate is a sign of fitness."),
            improve: [String(localized: "Repeat a benchmark workout every few weeks.")],
            related: ["workoutMin", "maxHR", "vo2"]),
        "weight": StatInfo(
            what: String(localized: "Body weight from a scale, Health or WHOOP's profile."),
            why: String(localized: "Day-to-day swings are mostly water; the weekly average is the useful number."),
            improve: [String(localized: "Weigh at the same time each morning."),
                      String(localized: "Watch the 7-day average, not single days.")],
            related: ["bodyFat", "lean", "bmi"]),
        "bodyFat": StatInfo(
            what: String(localized: "Body fat percentage from a smart scale or entered in Health."),
            why: String(localized: "Home scales are rough, but consistent conditions make the trend useful."),
            improve: [String(localized: "Measure under the same conditions each time.")],
            related: ["weight", "lean"]),
        "lean": StatInfo(
            what: String(localized: "Everything that isn't fat: muscle, bone, water and organs."),
            why: String(localized: "Keeping lean mass supports strength and resting energy use."),
            improve: [String(localized: "Strength training a few times a week."),
                      String(localized: "Enough protein spread across meals.")],
            related: ["weight", "bodyFat", "basalKcal"], better: .higher),
        "bmi": StatInfo(
            what: String(localized: "Body mass index: weight divided by height squared."),
            why: String(localized: "It's a rough population measure that doesn't separate muscle from fat."),
            improve: [String(localized: "Use alongside body fat and waist measurements.")],
            related: ["weight", "bodyFat"]),
        "height": StatInfo(
            what: String(localized: "Your height, from Health or WHOOP's profile."),
            why: String(localized: "Used to estimate calories, stride and BMI."),
            improve: [String(localized: "Keep it up to date so estimates stay accurate.")],
            related: ["bmi", "stepLength"]),
        "walkSpeed": StatInfo(
            what: String(localized: "Your usual walking speed, measured by the iPhone in your pocket."),
            why: String(localized: "Walking speed is a simple, steady marker of everyday mobility."),
            improve: [String(localized: "Include some brisk walking most days.")],
            related: ["stepLength", "steps", "asymmetry"], better: .higher),
        "stepLength": StatInfo(
            what: String(localized: "Average length of a walking step."),
            why: String(localized: "It tends to stay steady; lasting changes can follow injury or stiffness."),
            improve: [String(localized: "Mobility work and regular walking keep stride comfortable.")],
            related: ["walkSpeed", "asymmetry"]),
        "asymmetry": StatInfo(
            what: String(localized: "How uneven your left and right steps are, as a percentage."),
            why: String(localized: "Low is steadier. A lasting rise can follow an injury or stiffness."),
            improve: [String(localized: "Supportive shoes and balance work can help."),
                      String(localized: "Ease back if a niggle is changing how you walk.")],
            related: ["doubleSupport", "walkSpeed"], better: .lower),
        "doubleSupport": StatInfo(
            what: String(localized: "The share of each step with both feet on the ground."),
            why: String(localized: "It rises when walking feels less steady."),
            improve: [String(localized: "Balance and leg strength work help keep it low.")],
            related: ["asymmetry", "walkSpeed"], better: .lower),
        "effort": StatInfo(
            what: String(localized: "Average physical effort level in METs (kcal per kg per hour)."),
            why: String(localized: "It shows how intense your activity was, independent of body size."),
            improve: [String(localized: "Add brisk or uphill segments to walks.")],
            related: ["activeKcal", "exercise"]),
        "runSpeed": StatInfo(
            what: String(localized: "Average running speed."),
            why: String(localized: "Compare similar runs to see fitness change."),
            improve: [String(localized: "Mostly easy runs with one quality session a week.")],
            related: ["runPower", "stride", "vo2"], better: .higher),
        "runPower": StatInfo(
            what: String(localized: "Average running power in watts."),
            why: String(localized: "Power reacts to hills and wind faster than heart rate does."),
            improve: [String(localized: "Use it to pace hills evenly.")],
            related: ["runSpeed", "stride"]),
        "stride": StatInfo(
            what: String(localized: "Average running stride length."),
            why: String(localized: "It changes with pace and fatigue."),
            improve: [String(localized: "Don't force longer strides; they follow fitness.")],
            related: ["runSpeed", "runPower"]),
        "food": StatInfo(
            what: String(localized: "Calories logged by a food app."),
            why: String(localized: "Compared with calories burned, it shows your daily balance."),
            improve: [String(localized: "Log consistently for a week before drawing conclusions.")],
            related: ["totalKcal", "weight"]),
        "water": StatInfo(
            what: String(localized: "Water logged in Health."),
            why: String(localized: "Being well hydrated supports energy and recovery."),
            improve: [String(localized: "Keep a bottle in sight; drink with each meal.")],
            related: ["food", "readiness"]),
        "mindful": StatInfo(
            what: String(localized: "Breathe and Reflect sessions plus meditation apps."),
            why: String(localized: "A few calm minutes a day can help with stress, which shows up in HRV."),
            improve: [String(localized: "Start with 3 minutes of slow breathing a day.")],
            related: ["hrv", "readiness"], better: .higher),
        "noise": StatInfo(
            what: String(localized: "Average sound level around you, measured by the Watch."),
            why: String(localized: "Long exposure to loud environments can affect hearing."),
            improve: [String(localized: "Take breaks from loud places; use hearing protection at concerts.")],
            related: ["asleep"], better: .lower),
    ]
}
