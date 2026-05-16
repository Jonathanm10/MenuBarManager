import ProjectDescription

let project = Project(
    name: "MenuBarManager",
    organizationName: "Jonathan",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "MenuBarManager",
            destinations: .macOS,
            product: .app,
            bundleId: "com.jonathan.MenuBarManager",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "MenuBarManager",
                "CFBundleIconName": "AppIcon",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "LSUIElement": true,
                "NSHighResolutionCapable": true,
                "NSSupportsAutomaticTermination": false,
                "NSSupportsSuddenTermination": false,
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"]
        ),
        .target(
            name: "MenuBarManagerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.jonathan.MenuBarManagerTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: [
                "Tests/**",
                .glob("Sources/**", excluding: "Sources/MenuBarManagerApp.swift"),
            ]
        ),
        .target(
            name: "MenuBarManagerUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.jonathan.MenuBarManagerUITests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "MenuBarManager"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "MenuBarManager",
            buildAction: .buildAction(targets: ["MenuBarManager"]),
            testAction: .targets(["MenuBarManagerTests", "MenuBarManagerUITests"]),
            runAction: .runAction(executable: "MenuBarManager")
        ),
    ]
)
