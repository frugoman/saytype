import Foundation

/// Where SayType points people: the website, the tip jar, and how to update.
enum Links {
    static let website = URL(string: "https://frugoman.github.io/saytype-site/")!
    static let coffee = URL(string: "https://buymeacoffee.com/frugoman")!
    static let upgradeCommand = "brew upgrade --cask saytype"
}
