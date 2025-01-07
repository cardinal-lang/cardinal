import "./string" for Buffer, Stream, Format

var STRING_ESCAPES = {"\"": "\\\"", "\b":"\\b", "\n":"\\n", "\r":"\\r","\f":"\\f","\\":"\\\\","\t":"\\t"}

var REVERSE_STRING_ESCAPES = {
	"\"": "\"",
	"\\": "\\",
	"/": "/",
	"b": "\b",
	"f": "\f",
	"n": "\n",
	"r": "\r",
	"t": "\t"
}

class Json {
	static encode(value) {
		return Json.encodeValue(value)
	}

	static decode(value) {
		var stream = Stream.new(value)

		stream.eatWhitespace()
		var result = Json.decodeValue(stream)
		stream.eatWhitespace()

		if (stream.peek) {
			Fiber.abort("[JSON decoder] (%(stream.traceback)) Trailing data after value.")
		}
		return result
	}

	static encodeValue(value) {
		if (value is Null) {
			return "null"
		}
		if (value is Bool) {
			if (value)	return "true"
						return "false"
		}
		if (value is Num) {
			return value.toString
		}
		if (value is String) {
			var result = Buffer.new() 
			for (c in value) {
				var escape = STRING_ESCAPES[c]
				if (escape) {
					result.push(escape)
				} else if ((c.codePoints[0] < 32) || (c.codePoints[0] > 126)) {
					result.push("\\u" + Format.hex(c.codePoints[0], 4))
				} else {
					result.push(c)
				}
			}
			return "\"" + result.toString + "\""
		}
		if (value is List) {
			return "[" + value.map{|x| Json.encodeValue(x)}.join(",") + "]" 
		}
		if (value is Map) {
			return "{" + value.map{|e|
				if (!(e.key is String)) Fiber.abort("[JSON decoder] In JSON, all map keys must be strings; found %(e.key.type) instead.")
				return Json.encodeValue(e.key) + ":" + Json.encodeValue(e.value)
			}.join(",") + "}"
		}
		return Json.encodeValue(value.toStructure)
	}

	static decodeString(stream) {
		if (!stream.match("\"")) {
			Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected string.")
		}

		var result = Buffer.new()
		while (true) {
			if (stream.peek == null) {
				Fiber.abort("[JSON decoder] (%(stream.traceback)) End of file in string.")
			}
			if (stream.match("\"")) break
			if (stream.peek.bytes.count == 0) {
				Fiber.abort("[JSON decoder] (%(stream.traceback)) JSON does not allow invalid Unicode sequences.")
			}
			if (stream.peek.bytes[0] < 32) {
				if ((stream.peek.bytes[0] == 10) || (stream.peek.bytes[0] == 13)) {
					Fiber.abort("[JSON decoder] (%(stream.traceback)) JSON does not allow newlines in strings.")
				} else {
					Fiber.abort("[JSON decoder] (%(stream.traceback)) JSON does not allow raw control characters in strings.")
				}
			}
			if (stream.match("\\")) {
				if (stream.match("u")) {
					var h = 0
					for (i in 1..4) {
						if (stream.peek && "0123456789abcdefABCDEF".contains(stream.peek)) {
							var digit = stream.next().bytes[0]
							h = h << 4
							if (digit >= 97) {
								h = h | (digit - 87)
							} else if (digit >= 65) {
								h = h | (digit - 55)
							} else {
								h = h | (digit - 48)
							}
						} else {
							Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected a 4-digit hexadecimal Unicode codepoint.")
						}
					}
					//System.print("## %(h)")
					result.push(h)
				} else {
					var expansion = REVERSE_STRING_ESCAPES[stream.next()]
					if (expansion) {
						result.push(expansion)
					} else {
						Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected a control sequence.")
					}
				}
			} else {
				result.push(stream.next())
			}
		}
		return result.toString
	}

	static decodeNumber(stream) {
		var negative = false
		if (stream.match("-")) negative = true

		var integral = ""
		while (stream.peek && "0123456789".contains(stream.peek)) {
			var c = stream.next()
			if (integral == "0") {
				Fiber.abort("[JSON decoder] (%(stream.traceback)) JSON does not allow leading zeroes.")
			}
			integral = integral + c
		}

		if (integral.bytes.count == 0) {
			Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected digits.")
		}

		var decimal = null
		if (stream.match(".")) {
			decimal = ""
			while (stream.peek && "0123456789".contains(stream.peek)) {
				decimal = decimal + stream.next()
			}

			if (decimal.bytes.count == 0) {
				Fiber.abort("[JSON decoder] (%(stream.traceback)) JSON does not allow a trailing radix point in numbers.")
			}
		}

		var exponent = null
		if (stream.match("e") || stream.match("E")) {
			exponent = ""
			var exponentSign = ""
			if (stream.match("+")) {
				exponentSign = "+"
			} else if (stream.match("-")) {
				exponentSign = "-"
			}
			
			while (stream.peek && "0123456789".contains(stream.peek)) {
				exponent = exponent + stream.next()
			}

			if (exponent.bytes.count == 0) {
				Fiber.abort("[JSON decoder] (%(stream.traceback)) Empty exponent.")
			}

			exponent = exponentSign + exponent
		}

		var numString = (negative ? "-" : "") + (integral) + (decimal ? "."+decimal : "") + (exponent ? "e"+exponent : "")

		var result = Fiber.new{ Num.fromString(numString) }.try()
		if (result is Num) return result
		Fiber.abort("[JSON decoder] Error while parsing %(numString): %(result)")
	}

	static decodeValue(stream) {
		if (stream.match("true")) return true
		if (stream.match("false")) return false
		if (stream.match("null")) return null

		if (stream.peek == null) {
			Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected value, but found EOF instead.")
		}

		if ("0123456789-".contains(stream.peek)) {
			return Json.decodeNumber(stream)
		}

		if (stream.peek == "\"") {
			return Json.decodeString(stream)
		}

		if (stream.match("[")) {
			var result = []
			var continuation = false
			while (true) {
				stream.eatWhitespace()
				if (stream.match("]")) break
				if (continuation) {
					if (!stream.match(",")) {
						Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected comma (`,`).")
					}
				}
				stream.eatWhitespace()
				result.add(Json.decodeValue(stream))
				continuation = true
			}
			return result
		}

		if (stream.match("{")) {
			var result = {}
			var continuation = false
			while (true) {
				stream.eatWhitespace()
				if (stream.match("}")) break
				if (continuation) {
					if (!stream.match(",")) {
						Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected comma (`,`).")
					}
				}
				stream.eatWhitespace()
				var key = Json.decodeString(stream)
				stream.eatWhitespace()
				if (!stream.match(":")) Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected colon (`:`).")
				stream.eatWhitespace()
				var value = Json.decodeValue(stream)
				result[key] = value
				continuation = true
			}
			return result
		}

		Fiber.abort("[JSON decoder] (%(stream.traceback)) Expected value.")
	}
}
