import SwiftUI

/// The trailing swipe for a row whose deletion asks first. A destructive role would remove the
/// row before the answer, and leave it gone after Cancel, so the button is only tinted.
struct SwipeDeleteButton: View {
    var title = "Delete"
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .tint(.red)
    }
}
