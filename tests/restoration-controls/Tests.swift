import Foundation
@main struct RestorationControlTests {
    static func main() {
        var primary = RestorationStage(), secondary = RestorationStage()
        primary.denoiser = "bm3d"; secondary.denoiser = "nlmeans"
        primary.denoiserChoice = "off"
        precondition(!primary.useDenoise && primary.denoiser == "bm3d" && secondary.denoiser == "nlmeans")
        primary.denoiserChoice = "bm3d"
        precondition(primary.useDenoise && primary.denoiser == "bm3d")
        secondary.denoiserChoice = "off"
        precondition(!secondary.useDenoise && secondary.denoiser == "nlmeans" && primary.useDenoise)
        secondary.debandMethod = "f3kdb"
        secondary.debandChoice = "off"
        precondition(!secondary.useDeband && secondary.debandMethod == "f3kdb")
        secondary.debandChoice = "deband"
        precondition(secondary.useDeband && secondary.debandMethod == "f3kdb" && secondary.debandChoice == "deband")
        secondary.debandChoice = "gradfun"
        precondition(secondary.debandMethod == "gradfun")
        for original in [primary, secondary] {
            var stage = original
            stage.deringStrength.text = "0.75"; stage.useDering = false
            precondition(stage.deringAmount == "0" && stage.deringStrength.text == "0.75")
            stage.deringAmount = "0.5"; precondition(stage.useDering && stage.deringStrength.text == "0.5")
            stage.deringAmount = "0"; precondition(!stage.useDering && stage.deringAmount == "0")
            stage.deringAmount = "0.25"; precondition(stage.useDering && stage.deringAmount == "0.25")
        }
        print("PASS independent denoise Off and deringing zero/positive controls")
    }
}
