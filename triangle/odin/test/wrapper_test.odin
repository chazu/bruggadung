#+feature dynamic-literals
// The Odin wrapper's checks: objc/test_objc.m's, for the Odin face.
//   odin test triangle/odin/test
package triangle_test

import "core:strings"
import "core:testing"
import tri "../triangle"

@(test)
wrapper :: proc(t: ^testing.T) {
	src := map[string]string {
		"base.tri" = "#Material: \"steel\" | \"brass\"\n" +
		             "// Something to hold.\n#Tool: { @component(Tool)\n size: length @field(content)\n" +
		             " material: #Material @field(content)\n wear: *0 | >=0 & <=1000 @field(saved)\n}\n" +
		             "w: #Tool & { size: 19mm }\n" +
		             "#Roles: { target: #Tool }\n" +
		             "grab: #Roles & { target: { size: 19mm } } @family(operations)\n",
	}
	defer delete(src)
	c, err := tri.load_sources(src)
	defer tri.content_free(c)
	testing.expect(t, c != nil && err == "", err)

	testing.expect_value(t, tri.documentation(c, "#Tool"), "Something to hold.")
	testing.expect(t, tri.spec(c, "w") != nil)

	paths := tri.variation_paths(c, "w", context.temp_allocator)
	testing.expect(t, len(paths) == 1 && paths[0] == "material")
	testing.expect(t, strings.contains(tri.inspection(c, "w", context.temp_allocator), "wear: 0  <- default from #Tool"))

	a := tri.arena_new()
	defer tri.arena_free(a)
	made := tri.construct(c, "w", 3, a)
	testing.expect(t, made != nil && strings.has_prefix(tri.describe(c, tri.at(c, made, "material"), context.temp_allocator), "\""))

	d := tri.value(c, "#Roles & { target: { size: >=10mm & <=20mm } }", a, nil, 0)
	m, res := tri.match_with_residuals(c, "grab", d, context.temp_allocator)
	testing.expect_value(t, m, tri.Match.Unknown)
	testing.expect(t, len(res) == 1 && res[0] == "target.size")
	testing.expect(t, tri.family_index(c, "operations") != nil)

	bad_src := map[string]string{"bad.tri" = "#A: #Nope\n"}
	defer delete(bad_src)
	bad, bad_err := tri.load_sources(bad_src)
	defer delete(bad_err)
	testing.expect(t, bad == nil && strings.contains(bad_err, "#Nope"), bad_err)
}
