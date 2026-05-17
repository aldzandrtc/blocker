import Foundation

enum BlockedTargetKind: Codable, Hashable {
    case app(bundleID: String, name: String, path: String)
    case website(domain: String, label: String)
}

struct BlockedTarget: Identifiable, Codable, Hashable {
    let kind: BlockedTargetKind
    var category: Category = .regular

    var id: String {
        switch kind {
        case .app(let bundleID, _, _): return "app-\(bundleID)"
        case .website(let domain, _):  return "web-\(domain)"
        }
    }

    var displayName: String {
        switch kind {
        case .app(_, let name, _):   return name
        case .website(_, let label): return label
        }
    }

    enum Category: String, Codable {
        case strict
        case regular
    }
}
