import Foundation

enum BlockedTarget: Identifiable, Codable, Hashable {
    case app(bundleID: String, name: String, path: String)
    case website(domain: String, label: String)

    var id: String {
        switch self {
        case .app(let id, _, _): return "app-\(id)"
        case .website(let domain, _): return "web-\(domain)"
        }
    }

    var displayName: String {
        switch self {
        case .app(_, let name, _): return name
        case .website(_, let label): return label
        }
    }

    var isStrict: Bool {
        get { category == .strict }
        set { category = newValue ? .strict : .regular }
    }

    enum Category: String, Codable {
        case strict
        case regular
    }

    var category: Category = .regular

    // For serialization
    enum CodingKeys: String, CodingKey {
        case type, bundleID, name, path, domain, label, category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let cat = try c.decodeIfPresent(Category.self, forKey: .category) ?? .regular
        switch type {
        case "app":
            self = .app(
                bundleID: try c.decode(String.self, forKey: .bundleID),
                name: try c.decode(String.self, forKey: .name),
                path: try c.decode(String.self, forKey: .path)
            )
        default:
            self = .website(
                domain: try c.decode(String.self, forKey: .domain),
                label: try c.decode(String.self, forKey: .label)
            )
        }
        self.category = cat
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(category, forKey: .category)
        switch self {
        case .app(let id, let name, let path):
            try c.encode("app", forKey: .type)
            try c.encode(id, forKey: .bundleID)
            try c.encode(name, forKey: .name)
            try c.encode(path, forKey: .path)
        case .website(let domain, let label):
            try c.encode("web", forKey: .type)
            try c.encode(domain, forKey: .domain)
            try c.encode(label, forKey: .label)
        }
    }
}
