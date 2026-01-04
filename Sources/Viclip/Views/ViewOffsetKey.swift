
import SwiftUI

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: Set<Int> = []
    static func reduce(value: inout Set<Int>, nextValue: () -> Set<Int>) {
        value.formUnion(nextValue())
    }
}
