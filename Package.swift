// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WestieDeskPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WestieDeskPet", targets: ["WestieDeskPet"]),
        .library(name: "WestieDeskPetCore", targets: ["WestieDeskPetCore"])
    ],
    targets: [
        .target(
            name: "WestieDeskPetCore",
            path: "Sources/WestieDeskPet",
            exclude: ["Entry"],
            resources: [
                .copy("Resources/Sprites"),
                .copy("Resources/AppIcon.png")
            ]
        ),
        .executableTarget(
            name: "WestieDeskPet",
            dependencies: ["WestieDeskPetCore"],
            path: "Sources/WestieDeskPet/Entry"
        ),
        .testTarget(
            name: "WestieDeskPetTests",
            dependencies: ["WestieDeskPetCore"],
            path: "Tests/WestieDeskPetTests"
        )
    ]
)
