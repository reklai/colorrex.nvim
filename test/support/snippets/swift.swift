enum ParseError: Error { case empty }
func parse(_ text: String?) throws -> Int {
    guard let t = text else { throw ParseError.empty }
    do { return try convert(t) } catch let err { fatalError("\(err)") }
    return t == nil ? 3 : 0
}
func size(a: String?) -> Int { return a?.count ?? a!.count }
