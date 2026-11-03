package lab

// What the lab used of Foundation whose behaviour Odin's core library doesn't
// give exactly: a port that changes these changes the output. NSString's
// other methods map straight to core:strings. Results
// are in the temporary allocator unless an allocator is given.

import "core:strings"

// -longLongValue: leading spaces and tabs skipped, an optional sign, the
// digits that follow; 0 if there are none; LLONG_MAX or LLONG_MIN past the
// range.
ns_long_long_value :: proc(s: string) -> i64 {
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r' || s[i] == '\v' || s[i] == '\f') do i += 1
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i += 1
	}
	v: u64 = 0
	over := false
	for i < len(s) && s[i] >= '0' && s[i] <= '9' {
		d := u64(s[i] - '0')
		if v > (max(u64) - d) / 10 do over = true
		else do v = v * 10 + d
		i += 1
	}
	if neg {
		if over || v > u64(max(i64)) + 1 do return min(i64)
		return -i64(v) if v != u64(max(i64)) + 1 else min(i64)
	}
	if over || v > u64(max(i64)) do return max(i64)
	return i64(v)
}

// -intValue: the same, INT_MAX or INT_MIN past an int's range.
ns_int_value :: proc(s: string) -> i32 {
	v := ns_long_long_value(s)
	return i32(clamp(v, i64(min(i32)), i64(max(i32))))
}

// -unsignedLongLongValue: as strtoull: a minus sign negates (modulo 2^64),
// ULLONG_MAX past the range.
ns_unsigned_long_long_value :: proc(s: string) -> u64 {
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r' || s[i] == '\v' || s[i] == '\f') do i += 1
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i += 1
	}
	v: u64 = 0
	for i < len(s) && s[i] >= '0' && s[i] <= '9' {
		d := u64(s[i] - '0')
		if v > (max(u64) - d) / 10 do return max(u64)
		v = v * 10 + d
		i += 1
	}
	return -v if neg else v
}

// -componentsSeparatedByString: every piece between separators, empty ones
// too; the whole string, alone, if the separator isn't in it (an empty
// string gives one empty piece).
ns_components_separated :: proc(s, sep: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	if sep == "" {
		append(&out, s)
		return out[:]
	}
	rest := s
	for {
		i := strings.index(rest, sep)
		if i < 0 {
			append(&out, rest)
			break
		}
		append(&out, rest[:i])
		rest = rest[i + len(sep):]
	}
	return out[:]
}

// -hasPrefix: and -hasSuffix:, which say NO for an empty affix.
ns_has_prefix :: proc(s, prefix: string) -> bool {
	return prefix != "" && strings.has_prefix(s, prefix)
}

ns_has_suffix :: proc(s, suffix: string) -> bool {
	return suffix != "" && strings.has_suffix(s, suffix)
}

// -rangeOfString:'s location: where `sub` first is, or NOT_FOUND (an empty
// `sub` is never found).
ns_range_of :: proc(s, sub: string) -> uint {
	if sub == "" do return NOT_FOUND
	i := strings.index(s, sub)
	return NOT_FOUND if i < 0 else uint(i)
}

// Whether -rangeOfString: finds it.
ns_contains :: proc(s, sub: string) -> bool {
	return sub != "" && strings.contains(s, sub)
}

// -stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]:
// spaces and tabs off both ends (not newlines).
ns_trim_whitespace :: proc(s: string) -> string {
	return strings.trim(s, " \t")
}

// -stringByReplacingOccurrencesOfString:withString:.
ns_replace :: proc(s, old, new: string, allocator := context.temp_allocator) -> string {
	if old == "" do return s
	r, _ := strings.replace_all(s, old, new, allocator)
	return r
}

// -compare: for the lab's strings, which are ASCII: byte order.
ns_compare :: proc(a, b: string) -> int {
	return strings.compare(a, b)
}

// [NSString stringWithUTF8String:] of a C string: nil gives "".
ns_string :: proc(s: cstring) -> string {
	return string(s) if s != nil else ""
}

// -UTF8String: a C string of an Odin one, in the temporary allocator.
ns_utf8 :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}
