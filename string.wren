class Buffer {
	construct new() {
		_data = ""
	}

	construct new(data) {
		_data = data
	}

	push(data) {
		if (data is String) {
			_data = _data + data
		} else if (data is Num) {
			_data = _data + String.fromCodePoint(data)
		} else {
			Fiber.abort("You may only push a String or a Num to a Buffer.")
		}
	}

	pushByte(byte) {
		_data = _data + String.fromByte(byte)
	}

	codepointCount { _data.codePoints.count }

	size { _data.bytes.count }
	capacity { _data.bytes.count }
	
	toString { _data }
}

class Stream {
	static new(source) { Stream.new(source, null) }
	construct new(source, name) {
		_source = source
		_name = name
		_index = 0

		_line = 1
		_column = 1
		
		_inMultiCharNewline = false
	}

	copyInfo_ { [ _index, _source, _inMultiCharNewline ] }

	copy() { Stream.copy(this) }

	index { _index }

	advanceTo(other) {
		while (this.index < other.index) this.next()
	}

	construct copy(stream) {
		var info = stream.copyInfo_
		
		_source = info[1]
		_name = stream.name
		_index = info[0]

		_line = stream.line
		_column = stream.column

		_inMultiCharNewline = info[2]
	}

	match(sequence) {
		// If `sequence` is next in the stream, consume it and return true.
		// Otherwise, do not advance the stream (even if there is a partial match) and return false.
		
		var doppelganger = Stream.copy(this)
		for (char in sequence) {
			if (doppelganger.next() != char) return false
		}

		for (char in sequence) this.next()
		return true
	}

	eatWhitespace() {
		while (true) {
			if (match(" ")) continue
			if (match("\t")) continue
			if (match("\n")) continue
			if (match("\r")) continue
			return
		}
	}

	harvestSameLineWhitespace() {
		var buf = Buffer.new()
		while (true) {
			if (match(" ")) {
				buf.push(" ")
				continue
			}
			if (match("\t")) {
				buf.push("\t")
				continue
			}
			break
		}
		return buf.toString
	}

	harvestNewline() {
		var result = null
		if (match("\r")) {
			if (match("\n")) {
				result = "\r\n"
			} else {
				result = "\r"
			}
		} else if (match("\n")) {
			result = "\n"
		}

		return result
	}

	peek {
		if (_index < _source.bytes.count) {
			return _source[_index]
		} else {
			return null
		}
	}

	next() {
		var c = this.peek
		if (c) _index = _index + c.bytes.count

		var doNewline = false

		if (c == "\r") {
			if (_inMultiCharNewline) {
				doNewline = true
				_inMultiCharNewline = false
			} else if (this.peek == "\n") {
				_inMultiCharNewline = true
			} else {
				doNewline = true
			}
		} else if (c == "\n") {
			if (_inMultiCharNewline) {
				doNewline = true
				_inMultiCharNewline = false
			} else if (this.peek == "\r") {
				_inMultiCharNewline = true
			} else {
				doNewline = true
			}
		} else {
			if (_inMultiCharNewline) Fiber.abort("Assertion failed (byte_stream_001)")
			_column = _column + 1
		}

		if (doNewline) {
			_line = _line + 1
			_column = 1
			_lastChar
		}

		return c
	}

	traceback {
		if (_name) {
			return "%(_name), line %(_line), column %(_column)"
		} else {
			return "line %(_line), column %(_column)"
		}
	}
	
	name { _name }
	line { _line }
	column { _column }
}

class Format {
	static hex(h) { Format.hex(h, null) }
	static hex(h, d) {
		// Format non-negative hexadecimal number N to D digits. If
		// D is null, the hex value will not be formatted to
		// any particular width.
		var result = ""
		var hexAlphabet = "0123456789abcdef"
		while (h > 0) {
			result = hexAlphabet[h & 0xf] + result
			h = h >> 4
		}

		if (d) return Format.rjust(result, d, "0")
		return result
	}

	static decimal(n, d) {
		// Justify number N to D decimal points.
		// Additional digits are truncated, not rounded.
		// 
		// If the number is in e-notation only the mantissa is formatted; the
		// exponent is left unchanged.
		// 
		// If d is 0 and n is a safe integer[1], the effect is the same
		// as calling n.floor.toString. 
		// 
		// [1] https://wren.io/modules/core/num.html#num.maxsafeinteger 

		var base = n.toString
		
		var suffix = ""

		if (base.contains("e")) {
			var parts = base.split("e") 
			base = parts[0]
			suffix = parts[1]
		}
		if (base.contains("E")) {
			var parts = base.split("E") 
			base = parts[0]
			suffix = parts[1]
		}

		if (!base.contains(".")) {
			base = base + "."	
		}

		var numDecimals = base.split(".")[1].bytes.count

		if (d == 0) {
			return base.split(".")[0] + suffix
		} else if (d < numDecimals) {
			return base[0...(base.bytes.count + d - numDecimals)] + suffix
		} else if (d > numDecimals) {
			return base + ("0" * (d - numDecimals)) + suffix
		} else {
			return base + suffix
		}
	}

	static count(n) {
		// Prettify a count of something.
		var prefixes = " kMBT"
		var p
		var q
		for (prefix in prefixes) {
			if (n < 1000) {
				if ((n < 10) && (prefix != " ")) {
					n = Format.dec(n, 1)
				} else {
					n = n.floor.toString
				}
				return n + prefix.trim()
			} else {
				p = n
				q = prefix
				n = n / 1000
			}
		}
		return p.floor.toString + q
	}

	static base2Count(n) {
		// Prettify a count using base-2 prefixes ("mega", "giga", etc)
		var prefixes = " kMGT"
		var p
		var q
		for (prefix in prefixes) {
			if (n < 1024) {
				if ((n < 10) && (prefix != " ")) {
					n = Format.dec(n, 1)
				} else {
					n = n.floor.toString
				}
				return n + prefix.trim()
			} else {
				p = n
				q = prefix
				n = n / 1024
			}
		}
		return p.floor.toString + q
	}

	static ljust(text, width) { Format.ljust(text, width, " ") }
	static ljust(text, width, space) {
		var spaceToFill = width - text.count
		if (spaceToFill > 0) {
			return text + space*spaceToFill
		} else {
			return text
		}
	}

	static rjust(text, width) { Format.rjust(text, width, " ") }
	static rjust(text, width, space) {
		var spaceToFill = width - text.count
		if (spaceToFill > 0) {
			return space*spaceToFill + text
		} else {
			return text
		}
	}

	static center(text, width) { Format.center(text, width, " ") }
	static center(text, width, space) {
		var spaceToFill = width - text.count
		if (spaceToFill > 0) {
			var leftSide = (spaceToFill / 2).floor
			return space*leftSide + text + space*(spaceToFill-leftSide)
		} else {
			return text
		}
	}

	static ellipsis(text, width) {
		var size = text.count
		if (size > width) {
			return text[0...(width-3)] + "..."
		}
		return text
	}

	static escapeC(text) {
		var output = Buffer.new()

		for (c in text.bytes) {
			if (c == 13) {
				output.push("\\r")
			} else if (c == 10) {
				output.push("\\n")
			} else if (c == 34) {
				output.push("\\\"")
			} else if (c == 92) {
				output.push("\\\\")
			} else if (c < 32) {
				output.push("\\x" + Format.hex(c,2))
			} else if (c > 126) {
				output.push("\\x" + Format.hex(c,2))
			} else {
				output.push(c)
			}
		}
		return output.toString
	}

	static escapeHtml(text) {
		var output = Buffer.new()
	
		for (c in text.codePoints) {
			if (c == 38) {
				output.push("&amp;")
			} else if (c == 34) {
				output.push("&quot;")
			} else if (c == 39) {
				output.push("&apos;")
			} else if (c == 60) {
				output.push("&lt;")
			} else if (c == 62) {
				output.push("&gt;")
			} else if ((c < 32) || (c > 126)) {
				output.push("&#%(c);")
			} else {
				output.push(c)
			}
		}
		return output.toString
	}

	static escapeUri(text) {
		var output = Buffer.new()
		for (c in text.bytes) {
			if ((c >= 65) && (c <= 90)) {
				output.push(c)
			} else if ((c >= 97) && (c <= 122)) {
				output.push(c)
			} else if ((c == 126) || (c == 95) || (c == 45) || (c == 46)) {
				output.push(c)
			} else {
				output.push("\%" + asciiUpper(hex(c,2)))
			}
		}
		return output.toString
	}
}
