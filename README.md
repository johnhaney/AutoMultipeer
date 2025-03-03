# AutoMultipeer

Provides a simple interface for establishing MultipeerConnectivity between iOS, visionOS, macOS, and/or tvOS devices for connecting and sending messages between devices on the same local network.

Example sending messages,
```
struct MyMessageType: MultipeerMessagable {}
message = MyMessageType()
manager.send(message, mode: .unreliable)
```

Sending raw data (pack your own messages):
```
manager.send(data, mode: .unreliable)
```

Example receiving messages,
```
for await message in manager.messages() {
  // do something with each message
}
```

Receiving data:
```
for await data in manager.data() {
  // do something with each data
}
```

example usage simple chat app (in this repo, look in DeviceChat folder):
```
import SwiftUI
import AutoMultipeer

struct ContentView: View {
    @State var chatMessages: [String] = []
    @State var message: String = ""
    @State var manager = MultipeerManager(serviceName: "devicechat")
    var body: some View {
        VStack {
            List {
                ForEach(chatMessages, id: \.self) { message in
                    Text(message)
                }
            }
            .padding()
            TextField("Send…", text: $message)
                .onSubmit {
                    do {
                        let message = self.message
                        try manager.send(message, mode: .reliable)
                        self.message = ""
                        chatMessages.append(message)
                    } catch {}
                }
        }
        .task {
            let messages: AsyncStream<String> = manager.messages()
            for await message in messages {
                chatMessages.append(message)
            }
        }
    }
}

extension String: MultipeerMessagable {}
```

**Important: Xcode Project settings required:**

For all platforms, add Bonjour support to your app's Info section with your protocol (DeviceChat example below):
```
	<key>NSBonjourServices</key>
	<array>
		<string>_devicechat._tcp</string>
		<string>_devicechat._udp</string>
	</array>
```

When you create the MultipeerManager() pass the protocol part (for DeviceChat, that's `devicechat`).

```
manager = MultipeerManager(serviceName: "devicechat")
```

For macOS apps, add either client, server, or both under your app's Signing & Capabilities.
