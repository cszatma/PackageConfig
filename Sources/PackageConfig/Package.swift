
import class Foundation.Process
import class Foundation.Pipe
import class Foundation.FileHandle
import class Foundation.FileManager

enum Package {
	
	static func compile() throws {
		let swiftC = try runXCRun(tool: "swiftc")
		let process = Process()
		let linkedLibraries = try libraryLinkingArguments()
		var arguments = [String]()
			arguments += ["--driver-mode=swift"] // Eval in swift mode, I think?
			arguments += getSwiftPMManifestArgs(swiftPath: swiftC) // SwiftPM lib
			arguments += linkedLibraries
			arguments += ["-suppress-warnings"] // SPM does that too
		 	arguments += ["Package.swift"] // The Package.swift in the CWD

		// Create a process to eval the Swift Package manifest as a subprocess
		process.launchPath = swiftC
		process.arguments = arguments
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardOutput

		debugLog("CMD: \(swiftC) \( arguments.joined(separator: " "))")

		// Evaluation of the package swift code will end up
		// creating a file in the tmpdir that stores the JSON
		// settings when a new instance of PackageConfig is created
		process.launch()
		process.waitUntilExit()
		debugLog("Finished launching swiftc")
	}

	static private func runXCRun(tool: String) throws -> String {
		let process = Process()
		let pipe = Pipe()

		process.launchPath = "/usr/bin/xcrun"
		process.arguments = ["--find", tool]
		process.standardOutput = pipe

		debugLog("CMD: \(process.launchPath!) \( ["--find", tool].joined(separator: " "))")

		process.launch()
		process.waitUntilExit()
		return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static private func libraryPath(for library: String) -> String? {
		let fileManager = FileManager.default
		let libPaths = [
			".build/debug",
			".build/x86_64-unknown-linux/debug",
			".build/release",
		]

		#warning("needs to be improved")
		#warning("consider adding `/usr/lib` to libPath maybe")

		func isLibPath(path: String) -> Bool {
			return fileManager.fileExists(atPath: path + "/lib\(library).dylib") || // macOS
				fileManager.fileExists(atPath: path + "/lib\(library).so") // Linux
		}

		return libPaths.first(where: isLibPath)
	}

	static private func libraryLinkingArguments() throws -> [String] {
        let packageConfigLib = "PackageConfig"
        guard let packageConfigPath = libraryPath(for: packageConfigLib) else {
            throw Error("PackageConfig: Could not find lib\(packageConfigLib) to link against, is it possible you've not built yet?")
        }
        
		return try DynamicLibraries.list().map { libraryName in
			guard let path = libraryPath(for: libraryName) else {
				throw Error("PackageConfig: Could not find lib\(libraryName) to link against, is it possible you've not built yet?")
			}

			return [
				"-L", path,
				"-I", path,
				"-l\(libraryName)"
			]
        }.reduce([
            "-L", packageConfigPath,
            "-I", packageConfigPath,
            "-l\(packageConfigLib)"
        ], +)
    }
	

	static private func getSwiftPMManifestArgs(swiftPath: String) -> [String] {
		// using "xcrun --find swift" we get
		// /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
		// we need to transform it to something like:
		// /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/4_2
		let fileManager = FileManager.default

		let swiftPMDir = swiftPath.replacingOccurrences(of: "bin/swiftc", with: "lib/swift/pm")
		let versions = try! fileManager.contentsOfDirectory(atPath: swiftPMDir)
		#warning("TODO: handle //swift-tools-version:4.2 declarations")
		let latestSPM = versions.sorted().last!
		let libraryPathSPM = swiftPMDir + "/" + latestSPM

		debugLog("Using SPM version: \(libraryPathSPM)")
		return ["-L", libraryPathSPM, "-I", libraryPathSPM, "-lPackageDescription"]
	}
}
