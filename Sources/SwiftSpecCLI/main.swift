import Foundation
import SwiftSpecCore

let usage = "usage: swift-spec <input.yaml> [-o <output.swift>] [--enum-name <Name>] [--exclude-scheme <Scheme> ...]"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swift-spec: error: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var inputPath: String?
var outputPath: String?
var enumName: String?
var excludedSchemes: Set<String> = []

while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "-o", "--output":
        guard !arguments.isEmpty else { fail("missing value for \(argument)\n\(usage)") }
        outputPath = arguments.removeFirst()
    case "--enum-name":
        guard !arguments.isEmpty else { fail("missing value for --enum-name\n\(usage)") }
        enumName = arguments.removeFirst()
    case "--exclude-scheme":
        guard !arguments.isEmpty else { fail("missing value for --exclude-scheme\n\(usage)") }
        excludedSchemes.insert(arguments.removeFirst())
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard !argument.hasPrefix("-") else { fail("unknown option \(argument)\n\(usage)") }
        guard inputPath == nil else { fail("multiple input files given\n\(usage)") }
        inputPath = argument
    }
}

guard let inputPath else { fail("missing input file\n\(usage)") }

let yaml: String
do {
    yaml = try String(contentsOfFile: inputPath, encoding: .utf8)
} catch {
    fail("cannot read \(inputPath): \(error.localizedDescription)")
}

let generated: String
do {
    generated = try SwiftSpecGenerator(enumNameOverride: enumName, excludedSchemes: excludedSchemes).generate(yaml: yaml)
} catch {
    fail(String(describing: error))
}

if let outputPath {
    do {
        try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
    } catch {
        fail("cannot write \(outputPath): \(error.localizedDescription)")
    }
} else {
    print(generated, terminator: "")
}
