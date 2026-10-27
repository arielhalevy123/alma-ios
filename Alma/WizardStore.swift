import Foundation
import Observation
import SwiftUI

/// Cross-step state for the four-step redesign wizard: photo → room → mark & tell →
/// palette, the same flow as the website (`frontend/components/wizard/`).
///
/// Holds the payload the backend expects at `POST /design`:
/// `{ image, marked_image, room_hint, palette_hint, prompt }`. Every answer after the
/// photo is an optional hint; the backend falls back to a full redesign without it.
@Observable
@MainActor
final class WizardStore {

    /// The chosen photo, already encoded as JPEG for upload.
    var photoData: Data?
    var photoImage: Image?
    /// The upload-sized photo, kept so the marks can be flattened onto it at submit.
    var photoUIImage: UIImage?

    /// Strokes from the mark step, in the photo's pixel space.
    var strokes: [MarkStroke] = []

    var room: RoomHint?
    var palette: PaletteHint?
    var prompt: String = ""
    /// Stores to take products from; empty means all of them.
    var retailers: Set<String> = []
    /// Set when the server refuses with 402, so the UI can show the paywall.
    var isOutOfDesigns = false

    var designID: String?
    var result: DesignResult?

    /// Set while `POST /design` is in flight so the review step can show progress and
    /// refuse a second submission.
    var isSubmitting = false
    /// The result on screen is already in My designs (just saved, or opened from
    /// there), so leaving it needs no "not saved" warning.
    var resultIsSaved = false
    var errorMessage: String?

    var hasPhoto: Bool { photoData != nil }

    /// The photo is the only required input; room, marks and palette are hints.
    var canSubmit: Bool { hasPhoto && !isSubmitting }

    func setPhoto(data: Data, image: Image, uiImage: UIImage? = nil) {
        photoData = data
        photoImage = image
        photoUIImage = uiImage
        // Marks are drawn on one specific photo and mean nothing on another.
        strokes = []
        // A new photo invalidates any previous result; leaving it would show the user
        // last run's redesign next to this run's input.
        designID = nil
        result = nil
        resultIsSaved = false
        errorMessage = nil
    }

    /// Full reset — "start over" from the result screen.
    func reset() {
        photoData = nil
        photoImage = nil
        photoUIImage = nil
        strokes = []
        room = nil
        palette = nil
        prompt = ""
        retailers = []
        designID = nil
        result = nil
        resultIsSaved = false
        isSubmitting = false
        errorMessage = nil
    }

    /// Keeps the photo, room and prompt, drops the marks and palette: "try another
    /// look" returns to the mark step, as on the website.
    func resetForNewStyle() {
        strokes = []
        palette = nil
        designID = nil
        result = nil
        resultIsSaved = false
        errorMessage = nil
    }

    /// Submits the design. Returns true on success so the caller can navigate.
    /// `auth` is nil for guests: `POST /design` does not require an account.
    func submit(auth: String?) async -> Bool {
        guard let photoData, !isSubmitting else { return false }
        isSubmitting = true
        errorMessage = nil
        isOutOfDesigns = false
        defer { isSubmitting = false }

        do {
            let marked = photoUIImage.flatMap { MarkStroke.flatten(strokes, onto: $0) }
            let design = try await AlmaAPI.startDesign(
                imageData: photoData,
                markedImageData: marked,
                room: room,
                palette: palette,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                retailers: retailers.sorted(),
                auth: auth
            )
            result = design
            resultIsSaved = false
            if design.status == .error {
                errorMessage = design.error ?? "The redesign failed."
                return false
            }
            return true
        } catch AlmaAPI.APIError.quotaExceeded {
            isOutOfDesigns = true
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
