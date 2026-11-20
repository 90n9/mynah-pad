import Foundation

// Checks for Store.merge, the three-way merge that folds another process's
// write to notes.json into the app's in-memory state. Run: scripts/test.sh

struct Item: Identifiable, Equatable {
    let id: String
    var v = 0
}

var failures = 0

func check(_ name: String, _ got: [Item], _ want: [Item]) {
    let ok = got == want
    if !ok { failures += 1 }
    func show(_ a: [Item]) -> String { a.map { $0.v == 0 ? $0.id : "\($0.id)\($0.v)" }.joined(separator: " ") }
    print(ok ? "PASS" : "FAIL", name, ok ? "" : "— got [\(show(got))], want [\(show(want))]")
}

func items(_ ids: String) -> [Item] { ids.map { Item(id: String($0)) } }

let base = items("abc")

check("their block added on top, our delete kept",
      Store.merge(ours: items("ac"), base: base, theirs: items("xyzabc")), items("xyzac"))
check("their add at bottom, our add on top",
      Store.merge(ours: items("nabc"), base: base, theirs: items("abcw")), items("nabcw"))
check("their delete wins over our edit",
      Store.merge(ours: [Item(id: "a"), Item(id: "b"), Item(id: "c", v: 9)], base: base, theirs: items("ab")),
      items("ab"))
check("their insert in the middle keeps its place",
      Store.merge(ours: base, base: base, theirs: items("abqc")), items("abqc"))
check("their edit is taken when ours is unchanged",
      Store.merge(ours: base, base: base, theirs: [Item(id: "a", v: 2), Item(id: "b"), Item(id: "c")]),
      [Item(id: "a", v: 2), Item(id: "b"), Item(id: "c")])
check("our edit wins when both sides edit",
      Store.merge(ours: [Item(id: "a", v: 1)], base: items("a"), theirs: [Item(id: "a", v: 2)]),
      [Item(id: "a", v: 1)])
check("our delete wins over their edit",
      Store.merge(ours: items("bc"), base: base, theirs: [Item(id: "a", v: 2), Item(id: "b"), Item(id: "c")]),
      items("bc"))
check("no base (first sync) keeps both sides",
      Store.merge(ours: items("a"), base: [], theirs: items("b")), items("ba"))

print(failures == 0 ? "All merge checks passed" : "\(failures) merge check(s) failed")
exit(failures == 0 ? 0 : 1)
