import DiskbloomKit
import Testing

struct ShellTests {
    @Test func argumentsAreNotInterpretedByAShell() async {
        let result = await Shell.run("/bin/echo", ["$HOME; echo injected"])
        #expect(result.succeeded)
        #expect(result.output == "$HOME; echo injected\n")
    }

    @Test func missingExecutableFails() async {
        let result = await Shell.run("/nonexistent/tool", [])
        #expect(!result.succeeded)
    }
}
