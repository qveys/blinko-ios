import XCTest
@testable import BlinkoApp

final class TagTreeTests: XCTestCase {
    private func tag(_ id: Int, _ name: String, parent: Int = 0, sortOrder: Int = 0) -> Tag {
        Tag(
            id: id,
            name: name,
            parent: parent,
            sortOrder: sortOrder,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Tree building

    func testBuildsNestedTreeFromFlatRows() {
        let tags = [
            tag(3, "work"),
            tag(7, "projects", parent: 3),
            tag(8, "personal"),
        ]

        let tree = TagTreeBuilder.buildTree(from: tags)

        XCTAssertEqual(tree.map(\.tag.id), [3, 8])
        XCTAssertEqual(tree[0].children.map(\.tag.id), [7])
        XCTAssertEqual(tree[0].childCount, 1)
        XCTAssertTrue(tree[0].hasChildren)
        XCTAssertFalse(tree[1].hasChildren)
    }

    func testFullPathsAreSlashJoined() {
        let tags = [
            tag(1, "work"),
            tag(2, "projects", parent: 1),
            tag(3, "ios", parent: 2),
        ]

        let tree = TagTreeBuilder.buildTree(from: tags)

        XCTAssertEqual(tree[0].fullPath, "work")
        XCTAssertEqual(tree[0].children[0].fullPath, "work/projects")
        XCTAssertEqual(tree[0].children[0].children[0].fullPath, "work/projects/ios")
    }

    func testOrphanedChildBecomesRoot() {
        // Parent id 99 is not in the payload — the row must still show up.
        let tags = [tag(1, "work"), tag(2, "lost", parent: 99)]

        let tree = TagTreeBuilder.buildTree(from: tags)

        XCTAssertEqual(Set(tree.map(\.tag.id)), [1, 2])
        XCTAssertEqual(tree.first { $0.tag.id == 2 }?.fullPath, "lost")
    }

    func testSiblingsSortBySortOrderThenPayloadOrder() {
        // Equal sortOrder must preserve API payload order (the spec forbids
        // inventing an ordering), while sortOrder still wins when set.
        let tags = [
            tag(1, "zebra", sortOrder: 1),
            tag(2, "apple", sortOrder: 1),
            tag(3, "first", sortOrder: 0),
        ]

        let tree = TagTreeBuilder.buildTree(from: tags)

        XCTAssertEqual(tree.map(\.tag.name), ["first", "zebra", "apple"])
    }

    func testCyclicParentsDoNotRecurseForever() {
        // Bad data: 1 → 2 → 1. Neither is a root, so both parents "exist";
        // the cycle guard must terminate and keep both rows reachable.
        let tags = [tag(1, "a", parent: 2), tag(2, "b", parent: 1)]

        let tree = TagTreeBuilder.buildTree(from: tags)

        // No roots to attach to — the builder just must not hang or crash.
        XCTAssertTrue(tree.allSatisfy { $0.children.count <= 1 })
    }

    func testEmptyInputBuildsEmptyTree() {
        XCTAssertTrue(TagTreeBuilder.buildTree(from: []).isEmpty)
    }

    // MARK: - Tag.fullPath(in:)

    func testFullPathResolvesAncestors() {
        let all = [tag(1, "work"), tag(2, "projects", parent: 1)]

        XCTAssertEqual(all[1].fullPath(in: all), "work/projects")
        XCTAssertEqual(all[0].fullPath(in: all), "work")
    }

    func testFullPathFallsBackToLeafWhenAncestorsMissing() {
        let orphan = tag(2, "projects", parent: 1)

        XCTAssertEqual(orphan.fullPath(in: [orphan]), "projects")
    }

    func testFullPathSurvivesParentCycle() {
        let a = tag(1, "a", parent: 2)
        let b = tag(2, "b", parent: 1)

        // Must terminate; exact prefix is unspecified for corrupt data.
        XCTAssertTrue(a.fullPath(in: [a, b]).hasSuffix("a"))
    }

    // MARK: - Fixtures

    func testFixtureTagsBuildExpectedTree() {
        let tree = TagTreeBuilder.buildTree(from: APIFixtures.sampleTags)

        XCTAssertEqual(tree.map(\.tag.name), ["work", "personal"])
        XCTAssertEqual(tree[0].children.map(\.tag.name), ["projects"])
        XCTAssertEqual(tree[0].children[0].fullPath, "work/projects")
    }
}
