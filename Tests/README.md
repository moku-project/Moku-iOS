# Tests

- `Features/<Feature>`: feature unit tests (Swift Testing and existing XCTest cases).
- `Shared/<Area>`: shared store, cache, media, and backend unit tests.
- `Support`: unit-test helpers.
- `Fixtures`: fixture guidance.
- `UI`: XCTest UI automation, compiled only into the `UITests` target.

The unit-test target is still named `Tests`; the UI-test target is still `UITests`.
The shared parent folder does not combine their execution environments.

Run `./moku-ios test unit` or `./moku-ios test ui`. Live backend/device checks remain
explicitly opt-in through the environment variables documented in their tests.
