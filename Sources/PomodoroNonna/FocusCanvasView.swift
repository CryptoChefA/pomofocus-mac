import AppKit
import ImageIO
import SwiftUI

struct FocusCanvasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOTES & REFERENCES")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    model.pasteImageFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(CanvasToolButtonStyle())
                .help("Paste the image currently copied to your clipboard")

                Button {
                    model.chooseImages()
                } label: {
                    Label("Add", systemImage: "photo.badge.plus")
                }
                .buttonStyle(CanvasToolButtonStyle())

                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if model.note.isEmpty {
                    Text("Write anything you want to remember…")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk.opacity(0.58))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Bindable(model).note)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 86, maxHeight: 110)
            }
            .background(NonnaTheme.sunken.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(NonnaTheme.line.opacity(0.7))
            }

            if model.noteImages.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Paste or drop images here, then caption and resize them.")
                }
                .font(.system(size: 10, design: .default))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(NonnaTheme.raisedPaper.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(NonnaTheme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(model.noteImages.enumerated()), id: \.element.id) { index, attachment in
                            SessionImageEditor(
                                attachment: attachment,
                                index: index,
                                total: model.noteImages.count
                            )
                            .environment(model)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 350)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importImageFiles(urls)
            return !urls.isEmpty
        }
    }
}

private struct SessionImageEditor: View {
    @Environment(AppModel.self) private var model
    let attachment: SessionImageAttachment
    let index: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                StoredAttachmentImage(fileName: attachment.fileName)
                    .frame(maxWidth: attachment.displayWidth)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(NonnaTheme.line)
                    }
                    .frame(maxWidth: .infinity)

                Menu {
                    Button("Open image") { model.openImage(attachment) }
                    Divider()
                    Button("Move up") { model.moveImage(attachment.id, by: -1) }
                        .disabled(index == 0)
                    Button("Move down") { model.moveImage(attachment.id, by: 1) }
                        .disabled(index == total - 1)
                    Divider()
                    Button("Remove image", role: .destructive) { model.removeImage(attachment.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.66), in: Circle())
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(8)
            }

            TextField("Write a caption under this image…", text: Binding(
                get: { model.noteImages.first(where: { $0.id == attachment.id })?.caption ?? "" },
                set: { model.updateImageCaption($0, for: attachment.id) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .default))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(NonnaTheme.cream.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(NonnaTheme.line) }

            HStack(spacing: 9) {
                Image(systemName: "photo")
                    .font(.system(size: 9))
                Slider(value: Binding(
                    get: { model.noteImages.first(where: { $0.id == attachment.id })?.displayWidth ?? attachment.displayWidth },
                    set: { model.updateImageWidth($0, for: attachment.id) }
                ), in: 140...360)
                .tint(NonnaTheme.terracotta)
                Image(systemName: "photo.fill")
                    .font(.system(size: 13))
                Text("Resize")
                    .font(.system(size: 9, weight: .medium, design: .default))
            }
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(11)
        .background(NonnaTheme.raisedPaper.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(NonnaTheme.line) }
    }
}

struct StoredAttachmentImage: View {
    let fileName: String

    var body: some View {
        if let image = AttachmentThumbnails.image(named: fileName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                NonnaTheme.cream
                VStack(spacing: 7) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("Image unavailable")
                        .font(.system(size: 9, design: .default))
                }
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .frame(height: 110)
        }
    }
}

private struct CanvasToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .default))
            .foregroundStyle(NonnaTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(configuration.isPressed ? NonnaTheme.line : NonnaTheme.raisedPaper)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}

/// Decoded, display-sized copies of canvas images. Attachments are stored at up to
/// 2400 px; they are shown at most 360 pt wide, so a 2x-retina thumbnail (840 px) is
/// all a view ever needs. Decoding once and caching also means a redraw never goes
/// back to disk.
@MainActor
enum AttachmentThumbnails {
    private static let maxPixelSize = 840
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        return cache
    }()

    static func image(named fileName: String) -> NSImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = LocalStore.attachmentURL(for: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Point size of half the pixels, so it renders crisp at 2x like the original.
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width / 2, height: thumbnail.height / 2))
        cache.setObject(image, forKey: key)
        return image
    }
}
