import SwiftUI

@main
struct MyFirstAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("我的第一个 App")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("欢迎来到我的第一个 iOS 应用！")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("点我一下") {
                count += 1
            }
            .buttonStyle(.borderedProminent)

            Text("你点了 \(count) 次")
                .font(.title2)

            Text(Date(), style: .date)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
