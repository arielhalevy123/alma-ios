import XCTest
import SwiftUI
@testable import Alma

/// Wizard state transitions. These are the rules that stop the result screen showing
/// one run's redesign next to another run's photo.
@MainActor
final class WizardStoreTests: XCTestCase {

    private func makeStore() -> WizardStore { WizardStore() }

    private let dummyData = Data([0xFF, 0xD8, 0xFF])          // JPEG magic bytes
    private let dummyImage = Image(systemName: "photo")

    func testStartsEmpty() {
        let store = makeStore()
        XCTAssertFalse(store.hasPhoto)
        XCTAssertFalse(store.canSubmit)
        XCTAssertNil(store.room)
        XCTAssertNil(store.result)
    }

    /// The photo is the only required input; the room is a hint the backend can detect.
    func testSubmitRequiresOnlyThePhoto() {
        let store = makeStore()

        store.room = .bedroom
        XCTAssertFalse(store.canSubmit, "a room with no photo is not submittable")

        store.room = nil
        store.setPhoto(data: dummyData, image: dummyImage)
        XCTAssertTrue(store.canSubmit, "a photo with no room is submittable")
    }

    /// Marks belong to one photo; a new photo must not inherit them.
    func testNewPhotoClearsMarks() {
        let store = makeStore()
        store.setPhoto(data: dummyData, image: dummyImage)
        store.strokes = [MarkStroke(points: [.zero], width: 20)]

        store.setPhoto(data: Data([0x01]), image: dummyImage)

        XCTAssertTrue(store.strokes.isEmpty)
    }

    func testFlattenWithNoMarksSendsNothing() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        XCTAssertNil(MarkStroke.flatten([], onto: photo), "no marks means a full redesign")
        XCTAssertNotNil(MarkStroke.flatten([MarkStroke(points: [.zero], width: 4)], onto: photo))
    }

    func testSubmitBlockedWhileAlreadySubmitting() {
        let store = makeStore()
        store.setPhoto(data: dummyData, image: dummyImage)
        store.room = .kitchen
        XCTAssertTrue(store.canSubmit)

        store.isSubmitting = true
        XCTAssertFalse(store.canSubmit, "a second submission must not start mid-flight")
    }

    /// Choosing a new photo has to drop the previous redesign. Without this the
    /// result screen pairs the new input with the old output.
    func testNewPhotoClearsPreviousResult() {
        let store = makeStore()
        store.setPhoto(data: dummyData, image: dummyImage)
        store.designID = "job-1"
        store.result = DesignResult(status: .done, imageURL: "https://x.co/old.jpg")
        store.errorMessage = "stale error"

        store.setPhoto(data: Data([0x01]), image: dummyImage)

        XCTAssertNil(store.result)
        XCTAssertNil(store.designID)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.hasPhoto)
    }

    /// "Try another look" keeps the photo — that is the whole point of it being a
    /// separate operation from "start over".
    func testResetForNewStyleKeepsPhotoRoomAndNote() {
        let store = makeStore()
        store.setPhoto(data: dummyData, image: dummyImage)
        store.room = .livingRoom
        store.palette = .boldAccents
        store.prompt = "keep the plants"
        store.strokes = [MarkStroke(points: [.zero], width: 20)]
        store.result = DesignResult(status: .done)

        store.resetForNewStyle()

        XCTAssertTrue(store.hasPhoto, "the photo survives a style change")
        XCTAssertEqual(store.room, .livingRoom, "so does the room")
        XCTAssertEqual(store.prompt, "keep the plants", "and the note, as on the website")
        XCTAssertTrue(store.strokes.isEmpty, "the marks are redrawn")
        XCTAssertNil(store.palette, "the palette is what is being reconsidered")
        XCTAssertNil(store.result)
    }

    func testResetClearsEverything() {
        let store = makeStore()
        store.setPhoto(data: dummyData, image: dummyImage)
        store.room = .bathroom
        store.palette = .lightAiry
        store.prompt = "something"
        store.result = DesignResult(status: .done)
        store.isSubmitting = true

        store.reset()

        XCTAssertFalse(store.hasPhoto)
        XCTAssertNil(store.room)
        XCTAssertNil(store.palette)
        XCTAssertEqual(store.prompt, "")
        XCTAssertNil(store.result)
        XCTAssertFalse(store.isSubmitting)
    }

    func testSubmitWithoutPhotoReturnsFalseAndDoesNotHang() async {
        let store = makeStore()
        store.room = .kitchen

        let ok = await store.submit(auth: "irrelevant")

        XCTAssertFalse(ok)
        XCTAssertFalse(store.isSubmitting, "the guard must not leave the flag set")
    }

    /// Guests have no token; the store must accept nil rather than refuse.
    func testGuestSubmitWithoutPhotoStillGuards() async {
        let store = makeStore()
        store.room = .kitchen
        let ok = await store.submit(auth: nil)
        XCTAssertFalse(ok)
        XCTAssertFalse(store.isSubmitting)
    }
}

final class DesignProgressTests: XCTestCase {
    func testStagesFollowTheWebsiteTimings() {
        XCTAssertEqual(DesignProgress.stage(forElapsed: 0), 0)
        XCTAssertEqual(DesignProgress.stage(forElapsed: 11.9), 0)
        XCTAssertEqual(DesignProgress.stage(forElapsed: 12), 1)
        XCTAssertEqual(DesignProgress.stage(forElapsed: 29), 1)
        XCTAssertEqual(DesignProgress.stage(forElapsed: 90), 2)
    }
}
