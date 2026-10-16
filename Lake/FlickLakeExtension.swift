import DynamicLakeKit
import ExtensionFoundation
import SwiftUI

/// DynamicLake 가 띄우는 UI. 로직은 전부 Flick.app 에 있고 여기선 그리기만 한다.
@main
struct FlickLakeExtension: DynamicLakeExtension {
    // AppExtensionPoint.Identifier 는 StaticString 만 받아서 DynamicLakeExtensionPoint 의
    // String 상수를 못 쓴다. 값이 어긋나면 DynamicLake 가 확장을 못 찾으므로 assert 로 묶어 둔다.
    @available(macOS 26.2, *)
    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(
            host: "com.aviorrok.DynamicLakePro.DynamicLakePro",
            name: "extension"
        )
    }

    init() {
        assert(DynamicLakeExtensionPoint.identifier
               == "com.aviorrok.DynamicLakePro.DynamicLakePro.extension",
               "확장 포인트가 바뀌었다 — Info.plist 와 boundExtensionPoint 를 같이 고칠 것")
    }

    var body: some DynamicLakeExtensionScene {
        DynamicLakeLiveActivity {
            LakeCompactView()
                .allowsHitTesting(false)   // 노치 클릭은 DynamicLake 가 가져간다
        }

        // 펼친 화면은 버튼을 노출하므로 hit testing 을 살려 둔다.
        DynamicLakeSneakPeek {
            LakeSneakPeekView()
        }
    }
}
