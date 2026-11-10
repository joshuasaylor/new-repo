import Foundation

/// Hands Safari the compiled rule list that the app wrote into the App Group.
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        // Empty rule list if the app has not written one yet.
        let attachment = NSItemProvider(contentsOf: BlocklistStore.safariRulesURL)
            ?? NSItemProvider(item: Data("[]".utf8) as NSData, typeIdentifier: "public.json")

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
