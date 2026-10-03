import ActivityKit
import Foundation

struct PawPaceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceKilometers: Double
        var elapsedSeconds: Int
        var paceSecondsPerKilometer: Int
        var heartRate: Int
        var experienceEarned: Int
        var isPaused: Bool
        var encouragement: String
        var petMood: PetMood?
        var petStage: EvolutionStage?
        var petEnergy: Int?
        var petAccessory: String?
        var petSpecies: PetSpecies?
        var workoutConfiguration: WorkoutConfiguration?
        var activeEnergyKilocalories: Double?
        var petLifeStage: PetLifeStage? = nil
        var petVariant: PetColorVariant? = nil
    }

    var petName: String
    var questTargetKilometers: Double
}
