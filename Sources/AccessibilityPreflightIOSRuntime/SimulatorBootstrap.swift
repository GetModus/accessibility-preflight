import Foundation
import AccessibilityPreflightBuild

public struct SimulatorDevice: Equatable {
    public let identifier: String
    public let name: String
    public let wasBooted: Bool

    public init(identifier: String, name: String, wasBooted: Bool) {
        self.identifier = identifier
        self.name = name
        self.wasBooted = wasBooted
    }
}

public struct SimulatorLaunchResult: Equatable {
    public let device: SimulatorDevice
    public let bundleIdentifier: String
    public let processIdentifier: String?
    public let launchOutput: String

    public init(device: SimulatorDevice, bundleIdentifier: String, processIdentifier: String?, launchOutput: String) {
        self.device = device
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.launchOutput = launchOutput
    }
}

public struct SimulatorLaunchRequest: Equatable, Sendable {
    public let bundleIdentifier: String
    public let environment: [String: String]

    public init(bundleIdentifier: String, environment: [String: String] = [:]) {
        self.bundleIdentifier = bundleIdentifier
        self.environment = environment
    }
}

public enum SimulatorBootstrapError: LocalizedError {
    case simulatorUnavailable(String)
    case appContainerUnavailable(String)
    case installFailed(String)
    case uninstallFailed(String)
    case launchFailed(String)
    case terminateFailed(String)
    case uiConfigurationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .simulatorUnavailable(let detail):
            return "Unable to resolve an iOS simulator: \(detail)"
        case .appContainerUnavailable(let detail):
            return "Failed to resolve the simulator app container: \(detail)"
        case .installFailed(let detail):
            return "Failed to install the app in the simulator: \(detail)"
        case .uninstallFailed(let detail):
            return "Failed to uninstall the app from the simulator: \(detail)"
        case .launchFailed(let detail):
            return "Failed to launch the app in the simulator: \(detail)"
        case .terminateFailed(let detail):
            return "Failed to terminate the app in the simulator: \(detail)"
        case .uiConfigurationFailed(let detail):
            return "Failed to update simulator UI configuration: \(detail)"
        }
    }
}

public struct SimulatorBootstrap {
    private let resolveDeviceHandler: (String) throws -> SimulatorDevice
    private let uninstallAppHandler: (String, SimulatorDevice) throws -> Void
    private let installAppHandler: (String, SimulatorDevice) throws -> Void
    private let terminateAppHandler: (String, SimulatorDevice) throws -> Void
    private let launchAppHandler: (SimulatorLaunchRequest, SimulatorDevice) throws -> SimulatorLaunchResult
    private let contentSizeCategoryHandler: (SimulatorDevice) throws -> String
    private let setContentSizeCategoryHandler: (String, SimulatorDevice) throws -> Void
    private let appDataContainerPathHandler: (String, SimulatorDevice) throws -> String

    public init(
        commandRunner: @escaping (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run
    ) {
        self.resolveDeviceHandler = { simulatorID in
            try Self.resolveDevice(simulatorID: simulatorID, commandRunner: commandRunner)
        }
        self.uninstallAppHandler = { bundleIdentifier, device in
            try Self.uninstallApp(bundleIdentifier: bundleIdentifier, on: device, commandRunner: commandRunner)
        }
        self.installAppHandler = { appPath, device in
            try Self.installApp(at: appPath, on: device, commandRunner: commandRunner)
        }
        self.terminateAppHandler = { bundleIdentifier, device in
            try Self.terminateApp(bundleIdentifier: bundleIdentifier, on: device, commandRunner: commandRunner)
        }
        self.launchAppHandler = { request, device in
            try Self.launchApp(request: request, on: device, commandRunner: commandRunner)
        }
        self.contentSizeCategoryHandler = { device in
            try Self.contentSizeCategory(on: device, commandRunner: commandRunner)
        }
        self.setContentSizeCategoryHandler = { category, device in
            try Self.setContentSizeCategory(category, on: device, commandRunner: commandRunner)
        }
        self.appDataContainerPathHandler = { bundleIdentifier, device in
            try Self.appDataContainerPath(bundleIdentifier: bundleIdentifier, on: device, commandRunner: commandRunner)
        }
    }

    public init(
        resolveDevice: @escaping (String) throws -> SimulatorDevice,
        uninstallApp: @escaping (String, SimulatorDevice) throws -> Void,
        installApp: @escaping (String, SimulatorDevice) throws -> Void,
        terminateApp: @escaping (String, SimulatorDevice) throws -> Void,
        launchApp: @escaping (SimulatorLaunchRequest, SimulatorDevice) throws -> SimulatorLaunchResult,
        contentSizeCategory: @escaping (SimulatorDevice) throws -> String,
        setContentSizeCategory: @escaping (String, SimulatorDevice) throws -> Void,
        appDataContainerPath: @escaping (String, SimulatorDevice) throws -> String = { _, _ in
            throw SimulatorBootstrapError.appContainerUnavailable("App data container lookup was not configured.")
        }
    ) {
        self.resolveDeviceHandler = resolveDevice
        self.uninstallAppHandler = uninstallApp
        self.installAppHandler = installApp
        self.terminateAppHandler = terminateApp
        self.launchAppHandler = launchApp
        self.contentSizeCategoryHandler = contentSizeCategory
        self.setContentSizeCategoryHandler = setContentSizeCategory
        self.appDataContainerPathHandler = appDataContainerPath
    }

    public func resolveDevice(simulatorID: String) throws -> SimulatorDevice {
        try resolveDeviceHandler(simulatorID)
    }

    public func uninstallApp(bundleIdentifier: String, on device: SimulatorDevice) throws {
        try uninstallAppHandler(bundleIdentifier, device)
    }

    public func installApp(at appPath: String, on device: SimulatorDevice) throws {
        try installAppHandler(appPath, device)
    }

    public func terminateApp(bundleIdentifier: String, on device: SimulatorDevice) throws {
        try terminateAppHandler(bundleIdentifier, device)
    }

    public func launchApp(request: SimulatorLaunchRequest, on device: SimulatorDevice) throws -> SimulatorLaunchResult {
        try launchAppHandler(request, device)
    }

    public func launchApp(bundleIdentifier: String, on device: SimulatorDevice) throws -> SimulatorLaunchResult {
        try launchApp(request: SimulatorLaunchRequest(bundleIdentifier: bundleIdentifier), on: device)
    }

    public func contentSizeCategory(on device: SimulatorDevice) throws -> String {
        try contentSizeCategoryHandler(device)
    }

    public func setContentSizeCategory(_ category: String, on device: SimulatorDevice) throws {
        try setContentSizeCategoryHandler(category, device)
    }

    public func appDataContainerPath(bundleIdentifier: String, on device: SimulatorDevice) throws -> String {
        try appDataContainerPathHandler(bundleIdentifier, device)
    }
}

private extension SimulatorBootstrap {
    static func resolveDevice(
        simulatorID: String,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> SimulatorDevice {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "available", "-j"],
                workingDirectory: nil
            )
        )

        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.simulatorUnavailable(result.stderr)
        }

        let list = try JSONDecoder().decode(SimulatorList.self, from: Data(result.stdout.utf8))
        let devices = list.devices.keys.sorted().flatMap { list.devices[$0] ?? [] }.filter { $0.isAvailable ?? true }
        let requested = simulatorID.trimmingCharacters(in: .whitespacesAndNewlines)

        let selected: SimctlDevice
        if requested.isEmpty || requested.lowercased() == "booted" {
            if let booted = devices.first(where: { $0.state == "Booted" && $0.name.contains("iPhone") }) ??
                devices.first(where: { $0.state == "Booted" }) {
                selected = booted
            } else if let available = devices.first(where: { $0.name.contains("iPhone") }) ?? devices.first {
                selected = available
            } else {
                throw SimulatorBootstrapError.simulatorUnavailable("No available iOS simulator devices were found.")
            }
        } else if let matched = devices.first(where: { $0.udid == requested || $0.name == requested }) {
            selected = matched
        } else {
            throw SimulatorBootstrapError.simulatorUnavailable("No available simulator matched '\(requested)'.")
        }

        if selected.state != "Booted" {
            let boot = try commandRunner(
                CommandInvocation(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "boot", selected.udid],
                    workingDirectory: nil
                )
            )
            guard boot.exitCode == 0 || boot.stderr.contains("Unable to boot device in current state: Booted") else {
                throw SimulatorBootstrapError.simulatorUnavailable(boot.stderr.isEmpty ? boot.stdout : boot.stderr)
            }

            let bootStatus = try commandRunner(
                CommandInvocation(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "bootstatus", selected.udid, "-b"],
                    workingDirectory: nil
                )
            )
            guard bootStatus.exitCode == 0 else {
                throw SimulatorBootstrapError.simulatorUnavailable(bootStatus.stderr.isEmpty ? bootStatus.stdout : bootStatus.stderr)
            }
        }

        return SimulatorDevice(identifier: selected.udid, name: selected.name, wasBooted: selected.state == "Booted")
    }

    static func installApp(
        at appPath: String,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "install", device.identifier, appPath],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.installFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    static func uninstallApp(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "uninstall", device.identifier, bundleIdentifier],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.uninstallFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    static func terminateApp(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "terminate", device.identifier, bundleIdentifier],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.terminateFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    static func launchApp(
        request: SimulatorLaunchRequest,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> SimulatorLaunchResult {
        let childEnvironment = Dictionary(
            uniqueKeysWithValues: request.environment.map { ("SIMCTL_CHILD_\($0.key)", $0.value) }
        )
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "launch", device.identifier, request.bundleIdentifier],
                workingDirectory: nil,
                environment: childEnvironment
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.launchFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let pid = result.stdout
            .split(separator: ":")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SimulatorLaunchResult(
            device: device,
            bundleIdentifier: request.bundleIdentifier,
            processIdentifier: pid,
            launchOutput: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func appDataContainerPath(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> String {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "get_app_container", device.identifier, bundleIdentifier, "data"],
                workingDirectory: nil
            )
        )
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !path.isEmpty else {
            throw SimulatorBootstrapError.appContainerUnavailable(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return path
    }

    static func contentSizeCategory(
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> String {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "ui", device.identifier, "content_size"],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.uiConfigurationFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func setContentSizeCategory(
        _ category: String,
        on device: SimulatorDevice,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "ui", device.identifier, "content_size", category],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorBootstrapError.uiConfigurationFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}

private struct SimulatorList: Decodable {
    let devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
    let isAvailable: Bool?
}
