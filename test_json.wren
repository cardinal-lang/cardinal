import "io" for Directory, File
import "./json" for Json
import "./string" for Format

var tests = Directory.list("json_test_suite/test_parsing")

var alignmentWidth = 60 

var testsFailed = 0
var testsPassed = 0

for (test in tests) {
	var testPath = "json_test_suite/test_parsing/" + test
	var testData = File.read(testPath)
	if (test.endsWith(".json")) {
		var testTrimmedName = test[0...test.bytes.count - 5]
		System.write(Format.ljust(testTrimmedName, alignmentWidth))
		var error = Fiber.new{
			Json.decode(testData)
			return null
		}.try()

		var passed = true
		if (error is String) {
			System.write("rejected  ")
			if (test.startsWith("y_")) passed = false
		} else {
			System.write("accepted  ")
			if (test.startsWith("n_")) passed = false
		}

		if (passed) {
			System.write("\x1b[32mpassed\x1b[m")
			testsPassed = testsPassed + 1
		} else {
			System.write("\x1b[31mfailed\x1b[m")
			testsFailed = testsFailed + 1
		}

		System.print("")
	}
}

System.print("\n%(testsPassed) passed, %(testsFailed) failed.")
