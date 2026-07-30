import Foundation
import ServiceManagement

public final class LaunchAtLoginService {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return isEnabled
    }
}
