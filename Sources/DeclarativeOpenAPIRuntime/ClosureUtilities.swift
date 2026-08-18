/// Makes a closure of any shape that traps, naming the operation it stands for.
///
/// Arity comes from the call site through the parameter pack, so a generated
/// client binds one per operation without spelling any signature out — the
/// same shape as `ClientBuilder`'s helpers, minus the seam. Reaching one is a
/// programmer error by construction: `wired` fills every field, so only a
/// hand-built client can be missing one. Hence a trap rather than a thrown
/// error — it cannot be swallowed by a `catch` in the code under test.
public enum ClosureUtilities {
    public static func unimplemented<each Input, Output>(
        _ operation: String
    ) -> @Sendable (repeat each Input) async throws -> Output {
        { (_: repeat each Input) in
            fatalError("\(operation) is unimplemented")
        }
    }
}
